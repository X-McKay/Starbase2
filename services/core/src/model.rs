use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Build {
    pub digest: String,
    pub variant: String,
    pub manifest: Value,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct MissionInput {
    pub id: String,
    pub baseline: Build,
    pub candidate: Build,
    pub delay_seconds: u32,
    pub integration: bool,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Finding {
    pub code: String,
    pub file: String,
    pub line: u32,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Trial {
    pub case_id: String,
    pub build_digest: String,
    pub findings: Vec<Finding>,
    pub elapsed_ms: u64,
    pub model: String,
    pub requests: u32,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Submission {
    pub trials: Vec<Trial>,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct Transition {
    pub state: String,
    pub detail: String,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
pub struct Mission {
    pub input: MissionInput,
    pub state: String,
    pub updated_at: f64,
    pub detail: String,
    pub stale: bool,
    pub evidence: Option<Value>,
}
#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema)]
pub struct Snapshot {
    pub schema_version: u32,
    pub observed_at: f64,
    pub simulation: bool,
    pub missions: Vec<Mission>,
}
#[derive(JsonSchema)]
#[allow(dead_code)]
pub struct Contract {
    pub input: MissionInput,
    pub submission: Submission,
    pub transition: Transition,
    pub snapshot: Snapshot,
}
