//! Loopback operator API. Native writes require operator session cookies;
//! worker writes require a separately configured bearer credential.
use crate::{
    Store,
    model::Transition,
    operations::{Duty, RunInput, RunReport, SourceSnapshot},
};
use axum::{
    Json, Router,
    extract::{Path, Query, Request, State},
    http::{HeaderMap, StatusCode, header},
    middleware::{self, Next},
    response::{Html, IntoResponse, Response, sse::Sse},
    routing::{get, post},
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
type App = Arc<Mutex<Store>>;
type ApiResult = std::result::Result<Json<Value>, (StatusCode, Json<Value>)>;
fn err(e: String) -> (StatusCode, Json<Value>) {
    (StatusCode::CONFLICT, Json(json!({"error":e})))
}
#[derive(Clone)]
pub struct Access {
    pub worker: String,
    pub session: String,
    pub origin: String,
}
async fn guard(State(access): State<Access>, request: Request, next: Next) -> Response {
    let path = request.uri().path();
    if request.method() == axum::http::Method::POST
        && ((path == "/v3/repairs"
            && std::env::var("STARBASE_REPAIRS_ENABLED").is_ok_and(|v| v == "false"))
            || (std::env::var("STARBASE_ACCEPT_WORK").is_ok_and(|v| v == "false")
                && matches!(path, "/v2/runs" | "/v3/repairs" | "/v4/runs")))
    {
        return (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error":"This installation is not accepting this work"})),
        )
            .into_response();
    }
    if request.method() == axum::http::Method::GET
        && !request.uri().path().starts_with("/internal/")
    {
        return next.run(request).await;
    }
    let headers = request.headers();
    let internal = request.uri().path().starts_with("/internal/");
    let permitted = if internal {
        !access.worker.is_empty()
            && headers
                .get(header::AUTHORIZATION)
                .and_then(|v| v.to_str().ok())
                == Some(format!("Bearer {}", access.worker).as_str())
    } else {
        let cookie = headers
            .get(header::COOKIE)
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        let expected = format!("starbase_session={}", access.session);
        !access.session.is_empty()
            && cookie.split(';').any(|s| s.trim() == expected)
            && headers
                .get(header::ORIGIN)
                .and_then(|v| v.to_str().ok())
                .is_none_or(|o| o == access.origin)
            && headers
                .get("sec-fetch-site")
                .and_then(|v| v.to_str().ok())
                .is_none_or(|s| matches!(s, "same-origin" | "none"))
    };
    if permitted {
        next.run(request).await
    } else {
        (
            StatusCode::FORBIDDEN,
            Json(json!({"error":"local operator session or worker credential required"})),
        )
            .into_response()
    }
}
pub fn router(access: Access) -> Router<App> {
    let session = access.session.clone();
    Router::new()
        .route(
            "/",
            get(move || {
                let session = session.clone();
                async move {
                    let mut headers = HeaderMap::new();
                    if !session.is_empty() {
                        headers.insert(
                            header::SET_COOKIE,
                            format!(
                                "starbase_session={session}; HttpOnly; SameSite=Strict; Path=/"
                            )
                            .parse()
                            .unwrap(),
                        );
                    }
                    (headers, Html(include_str!("service.html")))
                }
            }),
        )
        .route("/v3/repairs", get(repair_list).post(repair_create))
        .route("/v3/repairs/{id}", get(repair_detail))
        .route("/v3/repairs/{id}/patch", get(repair_patch))
        .route("/v3/repairs/{id}/cancel", post(repair_cancel))
        .route("/internal/v3/builds", post(repair_build))
        .route(
            "/internal/v3/repairs/{id}/transition",
            post(repair_transition),
        )
        .route("/internal/v3/repairs/{id}/proposal", post(repair_proposal))
        .route(
            "/internal/v3/repairs/{id}/{stage}/authorize",
            post(repair_authorize),
        )
        .route(
            "/internal/v3/repairs/{id}/{stage}/receipt",
            post(repair_receipt),
        )
        .route("/internal/v3/repairs/{id}/finish", post(repair_finish))
        .route("/v7/snapshot", get(sdlc_snapshot))
        .route("/internal/v7/snapshot", get(sdlc_full_snapshot))
        .route("/v8/events", get(event_stream))
        .route("/internal/v7/missions/{id}/activity", post(sdlc_activity))
        .route("/v7/policy", post(sdlc_policy))
        .route("/v7/missions/{id}", get(sdlc_detail))
        .route("/v7/missions/{id}/cancel", post(sdlc_cancel))
        .route("/v7/missions/{id}/retry", post(sdlc_retry))
        .route("/internal/v7/missions", post(sdlc_admit))
        .route("/internal/v7/discoveries", post(sdlc_discover))
        .route(
            "/internal/v7/discoveries/{id}/admit",
            post(sdlc_admit_discovery),
        )
        .route("/internal/v7/missions/{id}/effect", post(sdlc_effect))
        .route("/internal/v7/missions/{id}/event", post(sdlc_event))
        .route(
            "/internal/v7/missions/{id}/feedback",
            post(sdlc_record_feedback),
        )
        .route(
            "/internal/v7/missions/{id}/pr-observation",
            post(sdlc_observe_pr),
        )
        .route(
            "/internal/v7/missions/{id}/publication",
            post(sdlc_publication),
        )
        .route(
            "/internal/v7/missions/{id}/verifications",
            post(sdlc_verification_admit),
        )
        .route(
            "/internal/v7/missions/{id}/verifications/{vid}/event",
            post(sdlc_verification_event),
        )
        .route(
            "/internal/v7/missions/{id}/verifications/{vid}/effect",
            post(sdlc_verification_effect),
        )
        .route(
            "/internal/v7/missions/{id}/verifications/{vid}/authorize",
            post(sdlc_verification_authorize),
        )
        .route(
            "/v7/missions/{id}/verifications/{vid}/cancel",
            post(sdlc_verification_cancel),
        )
        .route("/v6/snapshot", get(learning_snapshot))
        .route("/v6/duty", post(learning_duty))
        .route("/v6/cycles/{id}", get(learning_detail))
        .route("/v6/cycles/{id}/cancel", post(learning_cancel))
        .route("/internal/v6/duty/{generation}/tick", post(learning_tick))
        .route(
            "/internal/v6/cycles/{id}/proposal/claim",
            post(learning_claim),
        )
        .route(
            "/internal/v6/cycles/{id}/proposal/result",
            post(learning_result),
        )
        .route(
            "/internal/v6/cycles/{id}/trials/{slot}/admit",
            post(learning_admit),
        )
        .route("/internal/v6/cycles/{id}/finish", post(learning_finish))
        .route(
            "/internal/v6/cycles/{id}/reconcile-stop",
            post(learning_reconcile_stop),
        )
        .route("/v5/snapshot", get(joint_snapshot))
        .route("/v5/missions", post(joint_create))
        .route("/v5/missions/{id}", get(joint_detail))
        .route("/v5/missions/{id}/cancel", post(joint_cancel))
        .route("/internal/v5/builds", post(joint_build))
        .route("/internal/v5/missions/{id}/reserve", post(joint_reserve))
        .route(
            "/internal/v5/missions/{id}/tasks/{task}/claim",
            post(joint_claim),
        )
        .route(
            "/internal/v5/missions/{id}/tasks/{task}/result",
            post(joint_result),
        )
        .route("/internal/v5/missions/{id}/finish", post(joint_finish))
        .route("/v4/snapshot", get(field_snapshot))
        .route("/v4/runs", post(field_create))
        .route("/v4/runs/{id}", get(field_detail))
        .route("/v4/runs/{id}/cancel", post(field_cancel))
        .route("/v4/duties", post(field_duty))
        .route("/v4/repositories", get(repositories).post(repository_set))
        .route("/v4/repository-discovery", get(repository_discoveries))
        .route(
            "/internal/v4/repository-discovery",
            post(repository_discover),
        )
        .route(
            "/internal/v4/duties/{id}/{generation}/{tick}",
            post(field_tick),
        )
        .route("/v4/memory/review", post(memory_review))
        .route("/internal/v4/builds", post(field_build))
        .route("/internal/v4/runs/{id}/{action}", post(field_update))
        .route("/v2/snapshot", get(snapshot))
        .route("/v2/runs", get(runs).post(create))
        .route("/v2/runs/{id}", get(detail))
        .route("/v2/runs/{id}/cancel", post(cancel))
        .route("/v2/duties", post(duty))
        .route("/internal/v2/builds", post(build))
        .route("/internal/v2/heartbeat", post(heartbeat))
        .route("/internal/v2/duties/{id}/tick/{tick}", post(tick))
        .route("/internal/v2/runs/{id}/transition", post(transition))
        .route("/internal/v2/runs/{id}/snapshot", post(source))
        .route("/internal/v2/runs/{id}/report", post(report))
        .layer(middleware::from_fn_with_state(access, guard))
}
async fn snapshot(State(app): State<App>) -> ApiResult {
    app.lock()
        .unwrap()
        .operations_snapshot()
        .map(Json)
        .map_err(err)
}
#[derive(Deserialize)]
struct Page {
    before: Option<i64>,
    active: Option<bool>,
}
async fn runs(State(app): State<App>, Query(q): Query<Page>) -> ApiResult {
    app.lock()
        .unwrap()
        .runs(q.before.unwrap_or(i64::MAX), q.active.unwrap_or(false))
        .map(|r| Json(json!({"runs":r})))
        .map_err(err)
}
async fn detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock().unwrap().run_detail(&id).map(Json).map_err(err)
}
async fn create(State(app): State<App>, Json(input): Json<RunInput>) -> ApiResult {
    app.lock()
        .unwrap()
        .create_run(&input)
        .map(Json)
        .map_err(err)
}
async fn cancel(State(app): State<App>, Path(id): Path<String>, Json(_): Json<Value>) -> ApiResult {
    app.lock()
        .unwrap()
        .run_transition(
            &id,
            "cancel_requested",
            "Stop requested; awaiting Temporal acknowledgement",
        )
        .map(|()| Json(json!({"id":id})))
        .map_err(err)
}
async fn duty(State(app): State<App>, Json(d): Json<Duty>) -> ApiResult {
    app.lock()
        .unwrap()
        .set_duty(&d)
        .map(|()| Json(json!({"id":d.id})))
        .map_err(err)
}
async fn build(State(app): State<App>, Json(b): Json<Value>) -> ApiResult {
    app.lock()
        .unwrap()
        .register_build(&b)
        .map(|()| Json(json!({"registered":true})))
        .map_err(err)
}
async fn heartbeat(State(app): State<App>, Json(_): Json<Value>) -> ApiResult {
    app.lock()
        .unwrap()
        .heartbeat()
        .map(|()| Json(json!({"ok":true})))
        .map_err(err)
}
async fn tick(
    State(app): State<App>,
    Path((id, tick)): Path<(String, String)>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .duty_tick(&id, &tick)
        .map(Json)
        .map_err(err)
}
async fn transition(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(t): Json<Transition>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .run_transition(&id, &t.state, &t.detail)
        .map(|()| Json(json!({"id":id})))
        .map_err(err)
}
async fn source(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(s): Json<SourceSnapshot>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .retain_snapshot(&id, &s)
        .map(Json)
        .map_err(err)
}
async fn report(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(r): Json<RunReport>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .retain_report(&id, &r)
        .map(Json)
        .map_err(err)
}

async fn repair_list(State(app): State<App>) -> ApiResult {
    let app = app.lock().unwrap();
    Ok(Json(
        json!({"schema_version":3,"repairs":app.repair_list().map_err(err)?,"crew":app.progression().map_err(err)?}),
    ))
}
async fn repair_detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .repair(&id)
        .map(|v| Json(json!(v)))
        .map_err(err)
}
async fn repair_create(
    State(app): State<App>,
    Json(i): Json<crate::repair::RepairInput>,
) -> ApiResult {
    app.lock().unwrap().create_repair(&i).map(Json).map_err(err)
}
async fn repair_cancel(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .repair_transition(
            &id,
            "cancel_requested",
            "Stop requested; existing VM bounded by lifetime, cleanup pending",
        )
        .map(|()| Json(json!({"id":id})))
        .map_err(err)
}
async fn repair_build(State(app): State<App>, Json(b): Json<Value>) -> ApiResult {
    app.lock()
        .unwrap()
        .register_repair_build(&b)
        .map(|()| Json(json!({"ok":true})))
        .map_err(err)
}
async fn repair_transition(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(t): Json<Transition>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .repair_transition(&id, &t.state, &t.detail)
        .map(|()| Json(json!({"ok":true})))
        .map_err(err)
}
async fn repair_proposal(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(p): Json<crate::repair::Proposal>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .repair_proposal(&id, p)
        .map(|()| Json(json!({"ok":true})))
        .map_err(err)
}
async fn repair_authorize(
    State(app): State<App>,
    Path((id, stage)): Path<(String, String)>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .authorize_repair(&id, &stage)
        .map(|v| Json(json!(v)))
        .map_err(err)
}
async fn repair_receipt(
    State(app): State<App>,
    Path((id, stage)): Path<(String, String)>,
    Json(r): Json<crate::repair::Receipt>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .repair_receipt(&id, &stage, r)
        .map(|()| Json(json!({"ok":true})))
        .map_err(err)
}
async fn repair_finish(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .finish_repair(&id)
        .map(Json)
        .map_err(err)
}

async fn repair_patch(State(app): State<App>, Path(id): Path<String>) -> Response {
    let r = match app.lock().unwrap().repair(&id) {
        Ok(r) => r,
        Err(e) => return err(e).into_response(),
    };
    let Some(p) = r.proposal else {
        return err("No proposal retained".into()).into_response();
    };
    let old: Vec<_> = r.baseline.lines().collect();
    let new: Vec<_> = p.source.lines().collect();
    let mut diff = format!(
        "--- a/solution.py\n+++ b/solution.py\n@@ -1,{} +1,{} @@\n",
        old.len(),
        new.len()
    );
    for line in old {
        diff.push_str(&format!("-{line}\n"));
    }
    if !r.baseline.ends_with('\n') {
        diff.push_str("\\ No newline at end of file\n");
    }
    for line in new {
        diff.push_str(&format!("+{line}\n"));
    }
    if !p.source.ends_with('\n') {
        diff.push_str("\\ No newline at end of file\n");
    }
    (
        [
            (header::CONTENT_TYPE, "text/plain; charset=utf-8"),
            (
                header::CONTENT_DISPOSITION,
                "inline; filename=solution.patch",
            ),
        ],
        diff,
    )
        .into_response()
}

async fn field_snapshot(State(app): State<App>) -> ApiResult {
    app.lock().unwrap().field_snapshot().map(Json).map_err(err)
}
async fn field_create(
    State(app): State<App>,
    Json(input): Json<crate::field::FieldInput>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .create_field(&input)
        .map(Json)
        .map_err(err)
}
async fn field_detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock().unwrap().field_run(&id).map(Json).map_err(err)
}
async fn field_build(State(app): State<App>, Json(body): Json<Value>) -> ApiResult {
    app.lock()
        .unwrap()
        .field_build(&body)
        .map(Json)
        .map_err(err)
}
async fn field_cancel(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .field_update(&id, "cancel_requested", json!({}))
        .map(Json)
        .map_err(err)
}
async fn field_update(
    State(app): State<App>,
    Path((id, action)): Path<(String, String)>,
    Json(body): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .field_update(&id, &action, body)
        .map(Json)
        .map_err(err)
}
async fn memory_review(
    State(app): State<App>,
    Json(input): Json<crate::field::MemoryReview>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .review_memory(&input)
        .map(Json)
        .map_err(err)
}

async fn field_duty(State(app): State<App>, Json(d): Json<crate::field::FieldDuty>) -> ApiResult {
    app.lock()
        .unwrap()
        .set_field_duty(&d)
        .map(Json)
        .map_err(err)
}
async fn field_tick(
    State(app): State<App>,
    Path((id, generation, tick)): Path<(String, u32, u64)>,
    Json(_): Json<Value>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .field_tick(&id, generation, tick)
        .map(Json)
        .map_err(err)
}

async fn repositories(State(app): State<App>) -> ApiResult {
    app.lock()
        .unwrap()
        .repositories()
        .map(|r| Json(json!({"repositories":r})))
        .map_err(err)
}
async fn repository_set(
    State(app): State<App>,
    Json(input): Json<crate::repositories::RepositoryWatch>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .set_repository(&input)
        .map(Json)
        .map_err(err)
}

async fn joint_snapshot(State(app): State<App>) -> ApiResult {
    app.lock().unwrap().joint_snapshot().map(Json).map_err(err)
}
async fn joint_detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .joint_mission(&id)
        .map(Json)
        .map_err(err)
}
async fn joint_create(
    State(app): State<App>,
    Json(input): Json<crate::joint::JointInput>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .create_joint(&input)
        .map(Json)
        .map_err(err)
}
async fn joint_cancel(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock().unwrap().cancel_joint(&id).map(Json).map_err(err)
}
async fn joint_build(
    State(app): State<App>,
    Json(body): Json<crate::joint::JointBuild>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .joint_build(&body)
        .map(Json)
        .map_err(err)
}
async fn joint_reserve(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(body): Json<crate::joint::TaskReservation>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .reserve_joint(&id, &body)
        .map(Json)
        .map_err(err)
}
async fn joint_claim(
    State(app): State<App>,
    Path((id, task)): Path<(String, String)>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .claim_joint(&id, &task)
        .map(Json)
        .map_err(err)
}
async fn joint_result(
    State(app): State<App>,
    Path((id, task)): Path<(String, String)>,
    Json(body): Json<crate::joint::TaskResult>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .result_joint(&id, &task, &body)
        .map(Json)
        .map_err(err)
}
async fn joint_finish(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(body): Json<crate::joint::JointFinish>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .finish_joint(&id, &body)
        .map(Json)
        .map_err(err)
}

async fn learning_snapshot(State(app): State<App>) -> ApiResult {
    app.lock()
        .unwrap()
        .learning_snapshot()
        .map(Json)
        .map_err(err)
}
async fn learning_detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .learning_cycle(&id)
        .map(Json)
        .map_err(err)
}
async fn learning_duty(
    State(app): State<App>,
    Json(d): Json<crate::learning::LearningDuty>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .set_learning_duty(&d)
        .map(Json)
        .map_err(err)
}
async fn learning_cancel(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .cancel_learning(&id)
        .map(Json)
        .map_err(err)
}
async fn learning_tick(State(app): State<App>, Path(generation): Path<u32>) -> ApiResult {
    app.lock()
        .unwrap()
        .learning_tick(generation)
        .map(Json)
        .map_err(err)
}
async fn learning_claim(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .claim_learning_proposal(&id)
        .map(Json)
        .map_err(err)
}
async fn learning_result(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(r): Json<crate::learning::ProcedureResult>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .learning_proposal_result(&id, &r)
        .map(Json)
        .map_err(err)
}
async fn learning_admit(
    State(app): State<App>,
    Path((id, slot)): Path<(String, String)>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .admit_learning_trial(&id, &slot)
        .map(Json)
        .map_err(err)
}
async fn learning_reconcile_stop(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .reconcile_learning_stop(&id)
        .map(Json)
        .map_err(err)
}
async fn learning_finish(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .finish_learning(&id)
        .map(Json)
        .map_err(err)
}

async fn repository_discoveries(State(app): State<App>) -> ApiResult {
    app.lock()
        .unwrap()
        .repository_discoveries()
        .map(|v| Json(json!({"discoveries":v})))
        .map_err(err)
}
async fn repository_discover(
    State(app): State<App>,
    Json(input): Json<crate::repository_discovery::RepositoryDiscovery>,
) -> ApiResult {
    let owner = std::env::var("STARBASE_GITHUB_DISCOVERY_OWNER").unwrap_or_default();
    app.lock()
        .unwrap()
        .discover_repositories(&input, &owner)
        .map(Json)
        .map_err(err)
}

#[derive(Deserialize)]
struct SdlcPageQuery {
    limit: Option<usize>,
    before: Option<String>,
}
/// Bounded summaries for polling clients; full records stay on the detail route.
async fn sdlc_snapshot(State(app): State<App>, Query(q): Query<SdlcPageQuery>) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_summary_snapshot(q.limit, q.before.as_deref())
        .map(|s| Json(json!(s)))
        .map_err(|e| (StatusCode::BAD_REQUEST, Json(json!({"error":e}))))
}
#[derive(Deserialize)]
struct StreamQuery {
    after: Option<String>,
}
/// Live change notifications. `Last-Event-ID` (sent by reconnecting clients)
/// takes precedence over `?after=`. Records remain authoritative on their routes.
async fn event_stream(
    State(app): State<App>,
    headers: HeaderMap,
    Query(q): Query<StreamQuery>,
) -> Response {
    let hub = app.lock().unwrap().events.clone();
    let last = headers
        .get("last-event-id")
        .and_then(|v| v.to_str().ok())
        .map(String::from)
        .or(q.after);
    Sse::new(crate::events::sse(hub, last)).into_response()
}
async fn sdlc_activity(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(note): Json<crate::events::ActivityNote>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_activity(&id, &note)
        .map(Json)
        .map_err(err)
}
/// Full retained records for the trusted worker's reconciliation loop.
async fn sdlc_full_snapshot(State(app): State<App>) -> ApiResult {
    app.lock().unwrap().sdlc_snapshot().map(Json).map_err(err)
}
async fn sdlc_policy(State(app): State<App>, Json(p): Json<crate::sdlc::SdlcPolicy>) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_set_policy(&p)
        .map(Json)
        .map_err(err)
}
async fn sdlc_detail(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock().unwrap().sdlc_mission(&id).map(Json).map_err(err)
}
async fn sdlc_cancel(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock().unwrap().sdlc_cancel(&id).map(Json).map_err(err)
}
async fn sdlc_admit(State(app): State<App>, Json(i): Json<crate::sdlc::SdlcInput>) -> ApiResult {
    app.lock().unwrap().sdlc_admit(&i).map(Json).map_err(err)
}
async fn sdlc_event(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(e): Json<crate::sdlc::SdlcEvent>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_event(&id, &e)
        .map(Json)
        .map_err(err)
}
async fn sdlc_publication(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(r): Json<crate::sdlc::SdlcPublication>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_publication(&id, &r)
        .map(Json)
        .map_err(err)
}

async fn sdlc_effect(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(e): Json<crate::sdlc::SdlcEffect>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_effect(&id, &e)
        .map(Json)
        .map_err(err)
}

async fn sdlc_retry(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(r): Json<crate::sdlc::SdlcRetry>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_retry(&id, &r)
        .map(Json)
        .map_err(err)
}

async fn sdlc_verification_admit(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(i): Json<crate::sdlc::SdlcVerificationInput>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_verification_admit(&id, &i)
        .map(Json)
        .map_err(err)
}
async fn sdlc_verification_event(
    State(app): State<App>,
    Path((id, vid)): Path<(String, String)>,
    Json(e): Json<crate::sdlc::SdlcEvent>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_verification_event(&id, &vid, &e)
        .map(Json)
        .map_err(err)
}
async fn sdlc_verification_effect(
    State(app): State<App>,
    Path((id, vid)): Path<(String, String)>,
    Json(e): Json<crate::sdlc::SdlcEffect>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_verification_effect(&id, &vid, &e)
        .map(Json)
        .map_err(err)
}
async fn sdlc_verification_authorize(
    State(app): State<App>,
    Path((id, vid)): Path<(String, String)>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_verification_authorize(&id, &vid)
        .map(Json)
        .map_err(err)
}
async fn sdlc_verification_cancel(
    State(app): State<App>,
    Path((id, vid)): Path<(String, String)>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_verification_cancel(&id, &vid)
        .map(Json)
        .map_err(err)
}

async fn sdlc_observe_pr(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(input): Json<crate::sdlc::SdlcPrObservation>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_observe_pr(&id, &input)
        .map(Json)
        .map_err(err)
}

async fn sdlc_discover(
    State(app): State<App>,
    Json(input): Json<crate::sdlc_discovery::DiscoveryInput>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_discover(&input)
        .map(Json)
        .map_err(err)
}
async fn sdlc_admit_discovery(State(app): State<App>, Path(id): Path<String>) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_admit_discovery(&id)
        .map(Json)
        .map_err(err)
}

async fn sdlc_record_feedback(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(input): Json<crate::sdlc_feedback::FeedbackInput>,
) -> ApiResult {
    app.lock()
        .unwrap()
        .sdlc_record_feedback(&id, &input)
        .map(|record| Json(serde_json::json!(record)))
        .map_err(err)
}
