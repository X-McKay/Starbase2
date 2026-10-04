//! In-memory live change stream (`GET /v8/events`). Records stay authoritative:
//! the stream only tells clients that something changed and when to refetch.
//!
//! Ids are `<epoch>-<seq>`. The epoch is chosen when Core starts, so a restart
//! (which empties the buffer) is detectable. Record events are retained in a
//! bounded ring for resume; transient worker activity notes are broadcast live
//! only and are never replayed or appended to a mission's `events[]`.
use crate::{Result, now};
use axum::response::sse::Event;
use futures_util::stream::{self, Stream};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::VecDeque;
use std::convert::Infallible;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::sync::{broadcast, watch};

pub const RETAINED_EVENTS: usize = 1000;
pub const HEARTBEAT_SECONDS: u64 = 5;
const LIVE_CAPACITY: usize = 256;
const PAYLOAD_LIMIT: usize = 4096;

// One stream record. `type` is fine grained (for example `mission.stage`);
// `family` names the record family whose authoritative route should be refetched.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
pub struct StreamEvent {
    pub id: String,
    pub epoch: String,
    pub seq: u64,
    #[serde(rename = "type")]
    pub kind: String,
    pub family: String,
    pub record_id: String,
    pub at: f64,
    // False for transient activity notes, which are not replayed on resume.
    pub retained: bool,
    pub payload: Value,
}

/// Where a resuming client stands relative to the retained buffer.
#[derive(Debug, Clone, PartialEq)]
pub enum Resume {
    /// Replay these retained events (possibly none), then continue live.
    Replay(Vec<StreamEvent>),
    /// The client cannot be brought up to date from the buffer; refetch snapshots.
    Reset(&'static str),
}

struct Ring {
    next: u64,
    /// Highest sequence number of a retained event that has been evicted.
    evicted_through: u64,
    retained: VecDeque<StreamEvent>,
}

pub struct EventHub {
    epoch: String,
    ring: Mutex<Ring>,
    live: broadcast::Sender<StreamEvent>,
    closed: watch::Sender<bool>,
    capacity: usize,
}

impl Default for EventHub {
    fn default() -> Self {
        Self::new(RETAINED_EVENTS)
    }
}

impl EventHub {
    pub fn new(capacity: usize) -> Self {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos() as u64);
        Self::with_epoch(
            format!("{:016x}", nanos ^ u64::from(std::process::id())),
            capacity,
        )
    }
    pub fn with_epoch(epoch: String, capacity: usize) -> Self {
        Self {
            epoch,
            ring: Mutex::new(Ring {
                next: 1,
                evicted_through: 0,
                retained: VecDeque::new(),
            }),
            live: broadcast::channel(LIVE_CAPACITY).0,
            closed: watch::channel(false).0,
            capacity: capacity.max(1),
        }
    }
    pub fn epoch(&self) -> &str {
        &self.epoch
    }
    fn id(&self, seq: u64) -> String {
        format!("{}-{seq}", self.epoch)
    }
    /// The id of the newest event published in this epoch (`<epoch>-0` when none).
    pub fn cursor(&self) -> String {
        self.id(self.latest_seq())
    }
    pub fn latest_seq(&self) -> u64 {
        self.ring.lock().unwrap().next - 1
    }
    pub fn oldest_retained(&self) -> Option<String> {
        self.ring
            .lock()
            .unwrap()
            .retained
            .front()
            .map(|e| e.id.clone())
    }

    /// Publish a durable record change. Call only after the change is committed.
    pub fn record(&self, kind: &str, family: &str, record_id: &str, payload: Value) {
        self.publish(kind, family, record_id, payload, true);
    }
    /// Broadcast a transient note to current subscribers without retaining it.
    pub fn transient(&self, kind: &str, family: &str, record_id: &str, payload: Value) {
        self.publish(kind, family, record_id, payload, false);
    }
    fn publish(&self, kind: &str, family: &str, record_id: &str, payload: Value, retained: bool) {
        let payload = if payload.to_string().len() > PAYLOAD_LIMIT {
            json!({"truncated":true})
        } else {
            payload
        };
        // Hold the ring lock while sending so subscribe-then-replay sees no gap.
        let mut ring = self.ring.lock().unwrap();
        let seq = ring.next;
        ring.next += 1;
        let event = StreamEvent {
            id: self.id(seq),
            epoch: self.epoch.clone(),
            seq,
            kind: kind.into(),
            family: family.into(),
            record_id: record_id.into(),
            at: now(),
            retained,
            payload,
        };
        if retained {
            ring.retained.push_back(event.clone());
            while ring.retained.len() > self.capacity {
                let evicted = ring.retained.pop_front().unwrap();
                ring.evicted_through = evicted.seq;
            }
        }
        // No receivers is normal; ignore the error.
        let _ = self.live.send(event);
    }

    /// Subscribe first, then compute replay under the same lock as `publish`,
    /// so every later event arrives on the receiver and none is skipped.
    pub fn subscribe(&self, last: Option<&str>) -> (broadcast::Receiver<StreamEvent>, Resume) {
        let ring = self.ring.lock().unwrap();
        let receiver = self.live.subscribe();
        let latest = ring.next - 1;
        let resume = match last.map(|id| self.parse(id)) {
            None => Resume::Replay(vec![]),
            Some(Err(reason)) => Resume::Reset(reason),
            Some(Ok(seq)) if seq > latest => Resume::Reset("unknown_position"),
            Some(Ok(seq)) if seq < ring.evicted_through => Resume::Reset("buffer_exceeded"),
            Some(Ok(seq)) => Resume::Replay(
                ring.retained
                    .iter()
                    .filter(|e| e.seq > seq)
                    .cloned()
                    .collect(),
            ),
        };
        (receiver, resume)
    }
    fn parse(&self, id: &str) -> std::result::Result<u64, &'static str> {
        let (epoch, seq) = id.trim().rsplit_once('-').ok_or("invalid_id")?;
        let seq = seq.parse().map_err(|_| "invalid_id")?;
        if epoch != self.epoch {
            return Err("epoch_changed");
        }
        Ok(seq)
    }
    /// End every open stream (used on graceful shutdown).
    pub fn close(&self) {
        let _ = self.closed.send(true);
    }
    pub fn closed(&self) -> watch::Receiver<bool> {
        self.closed.subscribe()
    }
}

struct Session {
    hub: Arc<EventHub>,
    receiver: broadcast::Receiver<StreamEvent>,
    closed: watch::Receiver<bool>,
    heartbeat: tokio::time::Interval,
    queue: VecDeque<Event>,
    floor: u64,
    done: bool,
}

fn control(hub: &EventHub, kind: &str, extra: Value) -> Event {
    let mut data = json!({"type":kind,"epoch":hub.epoch(),"cursor":hub.cursor(),"at":now()});
    data.as_object_mut()
        .unwrap()
        .extend(extra.as_object().cloned().unwrap_or_default());
    Event::default().event(kind).data(data.to_string())
}
fn record(event: &StreamEvent) -> Event {
    Event::default()
        .id(event.id.clone())
        .event("record")
        .data(serde_json::to_string(event).unwrap_or_default())
}

/// Server-sent events for one client: optional `reset`, replayed records, a
/// `ready` marker carrying the current cursor, then live records and periodic
/// `heartbeat` events. `ready`/`reset` ids are cursors so reconnection resumes.
pub fn sse(
    hub: Arc<EventHub>,
    last: Option<String>,
) -> impl Stream<Item = std::result::Result<Event, Infallible>> {
    let (receiver, resume) = hub.subscribe(last.as_deref());
    let floor = hub.latest_seq();
    let mut queue = VecDeque::new();
    let replayed = match resume {
        Resume::Reset(reason) => {
            queue.push_back(control(&hub, "reset", json!({"reason":reason})).id(hub.id(floor)));
            0
        }
        Resume::Replay(events) => {
            queue.extend(events.iter().map(record));
            events.len()
        }
    };
    queue.push_back(
        control(
            &hub,
            "ready",
            json!({"oldest_retained":hub.oldest_retained(),"replayed":replayed,
                "heartbeat_seconds":HEARTBEAT_SECONDS,"retained_capacity":hub.capacity}),
        )
        .id(hub.id(floor))
        .retry(Duration::from_secs(3)),
    );
    let period = Duration::from_secs(HEARTBEAT_SECONDS);
    let session = Session {
        closed: hub.closed(),
        hub,
        receiver,
        heartbeat: tokio::time::interval_at(tokio::time::Instant::now() + period, period),
        queue,
        floor,
        done: false,
    };
    stream::unfold(session, |mut s| async move {
        loop {
            if let Some(event) = s.queue.pop_front() {
                return Some((Ok(event), s));
            }
            if s.done || *s.closed.borrow() {
                return None;
            }
            tokio::select! {
                changed = s.closed.changed() => {
                    if changed.is_err() || *s.closed.borrow() {
                        s.done = true;
                    }
                }
                _ = s.heartbeat.tick() => {
                    s.queue.push_back(control(&s.hub, "heartbeat", json!({})));
                }
                received = s.receiver.recv() => match received {
                    Ok(event) if event.seq <= s.floor => {}
                    Ok(event) => s.queue.push_back(record(&event)),
                    Err(broadcast::error::RecvError::Lagged(_)) => {
                        // This client fell behind live delivery; it must refetch.
                        s.floor = s.hub.latest_seq();
                        let id = s.hub.id(s.floor);
                        s.queue.push_back(control(&s.hub, "reset", json!({"reason":"lagged"})).id(id));
                    }
                    Err(broadcast::error::RecvError::Closed) => s.done = true,
                },
            }
        }
    })
}

// Small typed worker note; never stored in the mission record.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    ModelRequestStarted,
    ModelRequestFinished,
    ToolStarted,
    ToolFinished,
    SandboxBoot,
    SandboxFinished,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct ActivityNote {
    pub kind: ActivityKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub role: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verification_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub request: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ok: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_tokens: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elapsed_ms: Option<u64>,
}

impl ActivityNote {
    pub fn validate(&self) -> Result<()> {
        let short = |v: &Option<String>| {
            v.as_ref().is_none_or(|s| {
                !s.is_empty()
                    && s.len() <= 80
                    && s.bytes().all(|b| b.is_ascii_graphic() || b == b' ')
            })
        };
        if !short(&self.role)
            || !short(&self.verification_id)
            || !short(&self.tool)
            || !short(&self.label)
            || !short(&self.error)
        {
            return Err("Activity note fields must be short printable text".into());
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(events: &[StreamEvent]) -> Vec<u64> {
        events.iter().map(|e| e.seq).collect()
    }

    #[test]
    fn ids_are_monotonic_and_resume_replays_only_newer_retained_records() {
        let hub = EventHub::with_epoch("e1".into(), 10);
        assert_eq!(hub.cursor(), "e1-0");
        hub.record(
            "mission.stage",
            "v7_mission",
            "m",
            json!({"stage":"testing"}),
        );
        hub.transient("mission.activity", "v7_mission", "m", json!({}));
        hub.record(
            "mission.stage",
            "v7_mission",
            "m",
            json!({"stage":"reviewing"}),
        );
        assert_eq!(hub.cursor(), "e1-3");
        let (_, resume) = hub.subscribe(Some("e1-1"));
        let Resume::Replay(events) = resume else {
            panic!("expected replay")
        };
        assert_eq!(ids(&events), [3], "transient notes are not replayed");
        assert_eq!(events[0].id, "e1-3");
        let Resume::Replay(all) = hub.subscribe(Some("e1-0")).1 else {
            panic!("expected replay")
        };
        assert_eq!(ids(&all), [1, 3]);
        assert_eq!(hub.subscribe(None).1, Resume::Replay(vec![]));
        assert_eq!(hub.subscribe(Some("e1-3")).1, Resume::Replay(vec![]));
    }

    #[test]
    fn reset_when_buffer_exceeded_epoch_changed_or_position_unknown() {
        let hub = EventHub::with_epoch("e2".into(), 3);
        for n in 0..5 {
            hub.record("policy.changed", "v7_policy", "pilot", json!({"n":n}));
        }
        // Events 1 and 2 were evicted; a client at 1 missed 2.
        assert_eq!(
            hub.subscribe(Some("e2-1")).1,
            Resume::Reset("buffer_exceeded")
        );
        let Resume::Replay(events) = hub.subscribe(Some("e2-2")).1 else {
            panic!("seq 2 is the last evicted; 3..5 are retained")
        };
        assert_eq!(ids(&events), [3, 4, 5]);
        assert_eq!(hub.oldest_retained().as_deref(), Some("e2-3"));
        assert_eq!(
            hub.subscribe(Some("old-4")).1,
            Resume::Reset("epoch_changed")
        );
        assert_eq!(
            hub.subscribe(Some("e2-9")).1,
            Resume::Reset("unknown_position")
        );
        assert_eq!(
            hub.subscribe(Some("garbage")).1,
            Resume::Reset("invalid_id")
        );
        // A restarted Core has a new epoch, so every old id resets.
        let restarted = EventHub::new(3);
        assert_ne!(restarted.epoch(), "e2");
        assert_eq!(
            restarted.subscribe(Some("e2-5")).1,
            Resume::Reset("epoch_changed")
        );
    }

    #[test]
    fn subscribers_receive_later_events_in_order_and_payloads_are_bounded() {
        let hub = EventHub::with_epoch("e3".into(), 10);
        let (mut rx, _) = hub.subscribe(None);
        hub.record("a", "v7_mission", "m", json!({"big":"x".repeat(10_000)}));
        hub.transient("b", "v7_mission", "m", json!({}));
        let first = rx.try_recv().unwrap();
        let second = rx.try_recv().unwrap();
        assert_eq!((first.seq, second.seq), (1, 2));
        assert_eq!(first.payload, json!({"truncated":true}));
        assert!(first.retained && !second.retained);
        let encoded = serde_json::to_value(&first).unwrap();
        assert_eq!(encoded["type"], "a");
        assert_eq!(encoded["family"], "v7_mission");
    }

    #[test]
    fn activity_notes_are_typed_and_bounded() {
        let ok: ActivityNote = serde_json::from_value(
            json!({"kind":"tool_finished","tool":"inspect_diff","ok":true,"elapsed_ms":12}),
        )
        .unwrap();
        assert!(ok.validate().is_ok());
        assert!(serde_json::from_value::<ActivityNote>(json!({"kind":"self_certified"})).is_err());
        assert!(
            serde_json::from_value::<ActivityNote>(json!({"kind":"tool_started","extra":1}))
                .is_err()
        );
        let long: ActivityNote =
            serde_json::from_value(json!({"kind":"tool_started","tool":"x".repeat(81)})).unwrap();
        assert!(long.validate().is_err());
        let control: ActivityNote =
            serde_json::from_value(json!({"kind":"tool_started","tool":"a\nb"})).unwrap();
        assert!(control.validate().is_err());
    }
}
