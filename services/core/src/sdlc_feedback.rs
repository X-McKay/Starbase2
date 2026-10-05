//! Immutable, bounded PR feedback observations. These records confer no authority.
use crate::{Result, Store, now, operations::hash};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct FeedbackInput {
    pub head: String,
    pub digest: String,
    pub captured: Value,
    pub proposal: Value,
    pub observed_at: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct FeedbackRecord {
    #[serde(flatten)]
    pub input: FeedbackInput,
    pub recorded_at: f64,
}

fn hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn validate(input: &FeedbackInput, parent: &Value) -> Result<()> {
    let output = &input.proposal["output"];
    let state = output["state"].as_str().unwrap_or("");
    if !hex(&input.head, 40)
        || !hex(&input.digest, 64)
        || input.captured["head"] != input.head
        || input.captured["digest"] != input.digest
        || input.captured["coverage"] != "complete"
        || output["head"] != input.head
        || output["feedback_digest"] != input.digest
        || output["advisory"] != true
        || !matches!(
            state,
            "current" | "stale" | "unknown" | "no-change" | "conflicting" | "out-of-scope"
        )
        || serde_json::to_vec(input).map_err(|e| e.to_string())?.len() > 1_000_000
    {
        return Err("Invalid feedback envelope or advisory proposal".into());
    }
    let mut captured = input.captured.clone();
    captured
        .as_object_mut()
        .ok_or("Invalid feedback capture")?
        .remove("digest");
    if hash(&captured) != input.digest {
        return Err("Feedback capture digest mismatch".into());
    }
    let comments = input.captured["comments"]
        .as_array()
        .ok_or("Missing feedback comments")?;
    let references = output["comment_ids"]
        .as_array()
        .ok_or("Missing feedback references")?;
    let paths = output["paths"].as_array().ok_or("Missing feedback paths")?;
    let task = output["task"].as_str().ok_or("Missing feedback task")?;
    let rationale = output["rationale"]
        .as_str()
        .ok_or("Missing feedback rationale")?;
    if comments.len() > 198
        || references.len() > 198
        || paths.len() > 16
        || task.chars().count() > 2000
        || rationale.is_empty()
        || rationale.chars().count() > 2000
        || (!comments.is_empty() && references.is_empty())
    {
        return Err("Feedback proposal exceeds bounded coverage".into());
    }
    let mut ids = std::collections::HashSet::new();
    for comment in comments {
        let id = comment["id"].as_str().ok_or("Invalid feedback ID")?;
        if id.is_empty()
            || id.len() > 80
            || !ids.insert(id)
            || comment["body"]
                .as_str()
                .is_none_or(|body| body.chars().count() > 4000)
        {
            return Err("Invalid or duplicate feedback comment".into());
        }
    }
    let mut seen = std::collections::HashSet::new();
    for reference in references {
        let id = reference.as_str().ok_or("Invalid feedback reference")?;
        if !ids.contains(id) || !seen.insert(id) {
            return Err("Unknown or duplicate feedback reference".into());
        }
        let comment = comments.iter().find(|c| c["id"] == id).unwrap();
        if state == "current"
            && (comment["kind"] != "review"
                || comment["state"] != "current"
                || comment["head"] != input.head
                || !paths.contains(&comment["path"]))
        {
            return Err("Current feedback lacks exact-head review evidence".into());
        }
        if state == "stale" && (comment["state"] != "stale" || comment["head"] == input.head) {
            return Err("Stale feedback lacks old-commit evidence".into());
        }
    }
    if state == "current" {
        let fallback = json!(["src/utils/persistence.py"]);
        let allowed = parent["capability"]["editable_paths"]
            .as_array()
            .or_else(|| fallback.as_array())
            .unwrap();
        if input.captured["lifecycle"] != "open"
            || references.is_empty()
            || paths.is_empty()
            || task.trim().is_empty()
            || paths.iter().any(|path| !allowed.contains(path))
        {
            return Err("Current feedback is outside the retained capability".into());
        }
    } else if !paths.is_empty() || !task.is_empty() || (state == "stale" && references.is_empty()) {
        return Err("Non-current feedback cannot carry executable work".into());
    }
    Ok(())
}

impl Store {
    pub fn sdlc_record_feedback(&self, mid: &str, input: &FeedbackInput) -> Result<FeedbackRecord> {
        let mut parent = self.sdlc_mission(mid)?;
        let entries = parent["feedback"].as_array().cloned().unwrap_or_default();
        if let Some(existing) = entries.iter().find(|entry| entry["digest"] == input.digest) {
            let record: FeedbackRecord =
                serde_json::from_value(existing.clone()).map_err(|e| e.to_string())?;
            return if record.input == *input {
                Ok(record)
            } else {
                Err("Conflicting immutable feedback".into())
            };
        }
        if entries.len() >= 16 {
            return Err("Feedback retention exhausted".into());
        }
        if !input.observed_at.is_finite()
            || (now() - input.observed_at).abs() > 60.0
            || parent["evidence"]["submitted"]["number"]
                .as_u64()
                .is_none_or(|number| number == 0)
            || parent["evidence"]["submitted"]["branch"] != format!("starbase/{mid}")
            || parent["publication"].is_null()
            || parent["input"]["repository"]
                .as_str()
                .unwrap_or("")
                .to_lowercase()
                != "x-mckay/algent"
        {
            return Err("Invalid or stale retained PR feedback observation".into());
        }
        validate(input, &parent)?;
        let record = FeedbackRecord {
            input: input.clone(),
            recorded_at: now(),
        };
        let mut entries = entries;
        entries.push(serde_json::to_value(&record).map_err(|e| e.to_string())?);
        parent["feedback"] = json!(entries);
        self.sdlc_save(&parent)?;
        self.sdlc_emit("mission.feedback", mid, json!({"head":input.head}));
        Ok(record)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parameters as params;

    fn setup() -> Store {
        let store = Store::open(":memory:").unwrap();
        let parent = json!({"id":"test", "input":{"repository":"x-mckay/algent"},
            "state":"awaiting_review", "events":[{"key":"original"}],
            "evidence":{"submitted":{"number":1,"branch":"starbase/test"}},
            "publication":{"revision":"a".repeat(40)}});
        store
            .db
            .execute(
                "INSERT INTO sdlc_missions(id,opportunity,body) VALUES($1,$2,$3)",
                params!["test", "test-opportunity", parent.to_string()],
            )
            .unwrap();
        store
    }
    fn input(sequence: usize) -> FeedbackInput {
        let head = "a".repeat(40);
        let mut captured = json!({"head":head,"lifecycle":"open","coverage":"complete",
            "comments":[{"id":"review:1","body":format!("request {sequence}"),"kind":"review",
            "state":"current","head":head,"path":"src/utils/persistence.py"}]});
        let digest = hash(&captured);
        captured["digest"] = json!(digest);
        FeedbackInput {
            head: head.clone(),
            digest: digest.clone(),
            captured,
            proposal: json!({"role":"feedback","output":{"head":head,"feedback_digest":digest,
                "advisory":true,"state":"current","comment_ids":["review:1"],
                "paths":["src/utils/persistence.py"],"task":"repair","rationale":"evidence"}}),
            observed_at: now(),
        }
    }
    #[test]
    fn immutable_feedback_does_not_change_mission_or_events() {
        let store = setup();
        let before = store.sdlc_mission("test").unwrap();
        let i = input(0);
        store.sdlc_record_feedback("test", &i).unwrap();
        store.sdlc_record_feedback("test", &i).unwrap();
        let after = store.sdlc_mission("test").unwrap();
        assert_eq!(after["state"], before["state"]);
        assert_eq!(after["events"], before["events"]);
        assert_eq!(after["feedback"].as_array().unwrap().len(), 1);
        let mut conflict = i;
        conflict.proposal["output"]["rationale"] = json!("different");
        assert!(
            store
                .sdlc_record_feedback("test", &conflict)
                .unwrap_err()
                .contains("Conflicting")
        );
    }
    #[test]
    fn bounds_and_authority_are_independent() {
        let store = setup();
        for mutation in 0..5 {
            let mut i = input(0);
            match mutation {
                0 => i.observed_at = now() - 61.0,
                1 => i.proposal["output"]["advisory"] = json!(false),
                2 => i.proposal["output"]["paths"] = json!([".github/workflows/ci.yml"]),
                3 => i.captured["comments"][0]["body"] = json!("tampered"),
                _ => i.proposal["output"]["comment_ids"] = json!(["review:unknown"]),
            }
            assert!(store.sdlc_record_feedback("test", &i).is_err());
        }
        for n in 0..16 {
            store.sdlc_record_feedback("test", &input(n)).unwrap();
        }
        assert!(
            store
                .sdlc_record_feedback("test", &input(17))
                .unwrap_err()
                .contains("retention")
        );
    }
}
