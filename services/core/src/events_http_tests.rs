//! Real loopback HTTP checks for `GET /v8/events` and the internal activity route.
use crate::{
    Store,
    events::EventHub,
    now,
    operations_api::{Access, router},
    sdlc::{SdlcEvent, SdlcInput, SdlcPolicy},
};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

#[derive(Debug, Clone, PartialEq)]
struct Frame {
    id: Option<String>,
    event: String,
    data: Value,
}

struct Client {
    socket: TcpStream,
    buffer: String,
    offset: usize,
}

impl Client {
    async fn get(addr: &str, path: &str, headers: &[(&str, &str)]) -> Self {
        let mut socket = TcpStream::connect(addr).await.unwrap();
        let mut request = format!("GET {path} HTTP/1.0\r\nHost: localhost\r\n");
        for (name, value) in headers {
            request.push_str(&format!("{name}: {value}\r\n"));
        }
        request.push_str("\r\n");
        socket.write_all(request.as_bytes()).await.unwrap();
        Self {
            socket,
            buffer: String::new(),
            offset: 0,
        }
    }
    /// Read until `n` more complete SSE frames are available (headers skipped).
    async fn frames(&mut self, n: usize) -> Vec<Frame> {
        let mut out = vec![];
        tokio::time::timeout(Duration::from_secs(9), async {
            loop {
                if self.offset == 0
                    && let Some(end) = self.buffer.find("\r\n\r\n")
                {
                    self.offset = end + 4;
                }
                while self.offset > 0 && out.len() < n {
                    let Some(end) = self.buffer[self.offset..].find("\n\n") else {
                        break;
                    };
                    let raw = self.buffer[self.offset..self.offset + end].to_owned();
                    self.offset += end + 2;
                    let mut frame = Frame {
                        id: None,
                        event: "message".into(),
                        data: Value::Null,
                    };
                    for line in raw.lines() {
                        if let Some(v) = line.strip_prefix("id: ") {
                            frame.id = Some(v.into());
                        } else if let Some(v) = line.strip_prefix("event: ") {
                            frame.event = v.into();
                        } else if let Some(v) = line.strip_prefix("data: ") {
                            frame.data = serde_json::from_str(v).unwrap();
                        }
                    }
                    out.push(frame);
                }
                if out.len() == n {
                    return;
                }
                let mut chunk = [0u8; 4096];
                let read = self.socket.read(&mut chunk).await.unwrap();
                assert!(read > 0, "stream ended early: {}", self.buffer);
                self.buffer
                    .push_str(std::str::from_utf8(&chunk[..read]).unwrap());
            }
        })
        .await
        .unwrap_or_else(|_| panic!("timed out; received {}", self.buffer));
        out
    }
    fn head(&self) -> &str {
        &self.buffer[..self.offset]
    }
}

async fn post(addr: &str, path: &str, body: Value, token: Option<&str>) -> (u16, Value) {
    let mut socket = TcpStream::connect(addr).await.unwrap();
    let body = body.to_string();
    let auth = token.map_or(String::new(), |t| format!("Authorization: Bearer {t}\r\n"));
    socket
        .write_all(
            format!(
                "POST {path} HTTP/1.0\r\nHost: localhost\r\nContent-Type: application/json\r\n{auth}Content-Length: {}\r\n\r\n{body}",
                body.len()
            )
            .as_bytes(),
        )
        .await
        .unwrap();
    let mut response = String::new();
    socket.read_to_string(&mut response).await.unwrap();
    let status = response[9..12].parse().unwrap();
    let body = response
        .split_once("\r\n\r\n")
        .map_or(Value::Null, |(_, b)| {
            serde_json::from_str(b).unwrap_or(Value::Null)
        });
    (status, body)
}

fn store(hub: EventHub) -> Store {
    let mut s = Store::open(":memory:").unwrap();
    s.events = Arc::new(hub);
    s.sdlc_set_policy_at(
        &SdlcPolicy {
            repository: "X-McKay/algent".into(),
            enabled: true,
            publish: true,
            generation: 0,
            max_missions: 3,
            expires_at: now() + 3600.0,
        },
        true,
    )
    .unwrap();
    s.sdlc_admit_at(
        &SdlcInput {
            id: "m1".into(),
            repository: "X-McKay/algent".into(),
            revision: "a".repeat(40),
            opportunity: "persistence-history".into(),
            build: json!({"digest":"b".repeat(64)}),
            capability_digest: None,
        },
        true,
    )
    .unwrap();
    s
}

fn stage(app: &Arc<Mutex<Store>>, key: &str, stage: &str) {
    app.lock()
        .unwrap()
        .sdlc_event(
            "m1",
            &SdlcEvent {
                key: key.into(),
                stage: stage.into(),
                data: json!({"role":"lead"}),
            },
        )
        .unwrap();
}

async fn serve(store: Store) -> (String, Arc<Mutex<Store>>) {
    let app = Arc::new(Mutex::new(store));
    let routes = router(Access {
        worker: "worker-token".into(),
        session: "session".into(),
        origin: "http://127.0.0.1".into(),
    })
    .with_state(app.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    tokio::spawn(async move { axum::serve(listener, routes).await.unwrap() });
    (addr, app)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn stream_format_ordering_resume_live_and_heartbeat() {
    let (addr, app) = serve(store(EventHub::with_epoch("ep1".into(), 100))).await;
    // seq 1 policy.changed, seq 2 mission.admitted
    stage(&app, "inv", "investigating"); // seq 3
    let mut replay = Client::get(&addr, "/v8/events?after=ep1-1", &[]).await;
    let frames = replay.frames(3).await;
    assert!(replay.head().starts_with("HTTP/1.0 200"));
    assert!(replay.head().contains("content-type: text/event-stream"));
    assert_eq!(frames[0].id.as_deref(), Some("ep1-2"));
    assert_eq!(frames[0].event, "record");
    assert_eq!(frames[0].data["type"], "mission.admitted");
    assert_eq!(frames[0].data["family"], "v7_mission");
    assert_eq!(frames[0].data["record_id"], "m1");
    assert_eq!(frames[1].data["type"], "mission.stage");
    assert_eq!(frames[1].data["payload"]["stage"], "investigating");
    assert_eq!(frames[1].data["payload"]["role"], "lead");
    assert_eq!(frames[1].data["seq"], 3);
    assert_eq!(frames[2].event, "ready");
    assert_eq!(
        frames[2].id.as_deref(),
        Some("ep1-3"),
        "ready carries the cursor"
    );
    assert_eq!(frames[2].data["replayed"], 2);
    assert_eq!(frames[2].data["epoch"], "ep1");

    // Last-Event-ID wins over ?after= (browsers resend it on reconnect).
    let mut header = Client::get(
        &addr,
        "/v8/events?after=ep1-0",
        &[("Last-Event-ID", "ep1-2")],
    )
    .await;
    let frames = header.frames(2).await;
    assert_eq!(frames[0].id.as_deref(), Some("ep1-3"));
    assert_eq!(frames[1].event, "ready");

    // A fresh client gets only `ready`, then live events in order.
    let mut live = Client::get(&addr, "/v8/events", &[]).await;
    assert_eq!(live.frames(1).await[0].data["replayed"], 0);
    stage(&app, "lead", "implementing");
    app.lock().unwrap().sdlc_cancel("m1").unwrap();
    let frames = live.frames(2).await;
    assert_eq!(frames[0].id.as_deref(), Some("ep1-4"));
    assert_eq!(frames[1].id.as_deref(), Some("ep1-5"));
    assert_eq!(frames[1].data["type"], "mission.cancel_requested");
    // The earlier replay connection receives the same live events too.
    let ids: Vec<_> = replay.frames(2).await.into_iter().map(|f| f.id).collect();
    assert_eq!(ids, [Some("ep1-4".into()), Some("ep1-5".into())]);
    // Idle connections get a heartbeat within the advertised period.
    let beat = live.frames(1).await;
    assert_eq!(beat[0].event, "heartbeat");
    assert_eq!(beat[0].id, None, "heartbeats do not move the resume cursor");
    assert_eq!(beat[0].data["cursor"], "ep1-5");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn stream_resets_when_buffer_exceeded_or_epoch_changed() {
    let (addr, app) = serve(store(EventHub::with_epoch("ep2".into(), 2))).await;
    stage(&app, "inv", "investigating"); // seq 3; seq 1 has been evicted
    let mut stale = Client::get(&addr, "/v8/events?after=ep2-0", &[]).await;
    let frames = stale.frames(2).await;
    assert_eq!(frames[0].event, "reset");
    assert_eq!(frames[0].data["reason"], "buffer_exceeded");
    assert_eq!(frames[0].id.as_deref(), Some("ep2-3"));
    assert_eq!(frames[1].event, "ready");
    let mut restarted = Client::get(&addr, "/v8/events", &[("Last-Event-ID", "ep1-9")]).await;
    let frames = restarted.frames(1).await;
    assert_eq!(frames[0].data["reason"], "epoch_changed");
    let mut current = Client::get(&addr, "/v8/events?after=ep2-1", &[]).await;
    let frames = current.frames(3).await;
    assert_eq!(frames[0].id.as_deref(), Some("ep2-2"));
    assert_eq!(frames[2].event, "ready");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn activity_notes_require_worker_auth_and_stay_out_of_mission_events() {
    let (addr, app) = serve(store(EventHub::with_epoch("ep3".into(), 100))).await;
    stage(&app, "inv", "investigating");
    let mut live = Client::get(&addr, "/v8/events", &[]).await;
    live.frames(1).await;
    let path = "/internal/v7/missions/m1/activity";
    let note = json!({"kind":"model_request_finished","role":"lead","request":1,"ok":true,
        "input_tokens":1200,"output_tokens":300,"elapsed_ms":4100});
    assert_eq!(post(&addr, path, note.clone(), None).await.0, 403);
    assert_eq!(post(&addr, path, note.clone(), Some("wrong")).await.0, 403);
    let (status, body) = post(&addr, path, note.clone(), Some("worker-token")).await;
    assert_eq!((status, body), (200, json!({"broadcast":true})));
    let frame = &live.frames(1).await[0];
    assert_eq!(frame.data["type"], "mission.activity");
    assert_eq!(frame.data["retained"], false);
    assert_eq!(frame.data["payload"]["kind"], "model_request_finished");
    assert_eq!(frame.data["payload"]["output_tokens"], 300);
    assert_eq!(frame.data["payload"]["state"], "investigating");
    let mission = app.lock().unwrap().sdlc_mission("m1").unwrap();
    assert_eq!(mission["events"].as_array().unwrap().len(), 1);
    let unknown = "/internal/v7/missions/missing/activity";
    assert_eq!(
        post(&addr, unknown, note.clone(), Some("worker-token"))
            .await
            .0,
        409
    );
    let invalid = json!({"kind":"grade_self","ok":true});
    assert_eq!(
        post(&addr, path, invalid, Some("worker-token")).await.0,
        422
    );
    // Transient notes are not replayed to a resuming client.
    let mut resumed = Client::get(&addr, "/v8/events?after=ep3-0", &[]).await;
    let frames = resumed.frames(4).await;
    let kinds: Vec<_> = frames.iter().map(|f| f.data["type"].clone()).collect();
    assert_eq!(
        kinds,
        [
            json!("policy.changed"),
            json!("mission.admitted"),
            json!("mission.stage"),
            json!("ready")
        ]
    );
    assert_eq!(frames[0].data["family"], "v7_policy");
    assert_eq!(frames[0].data["payload"]["generation"], 1);
    app.lock().unwrap().sdlc_cancel("m1").unwrap();
    stage(&app, "stop", "cancelled");
    let (status, _) = post(&addr, path, note, Some("worker-token")).await;
    assert_eq!(status, 409, "a stopped mission accepts no activity notes");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn closing_the_hub_ends_open_streams() {
    let (addr, app) = serve(store(EventHub::with_epoch("ep4".into(), 100))).await;
    let mut live = Client::get(&addr, "/v8/events", &[]).await;
    live.frames(1).await;
    app.lock().unwrap().events.close();
    let mut rest = String::new();
    tokio::time::timeout(
        Duration::from_secs(3),
        live.socket.read_to_string(&mut rest),
    )
    .await
    .expect("stream ends promptly after close")
    .unwrap();
}
