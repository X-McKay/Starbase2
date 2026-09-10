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
    response::{Html, IntoResponse, Response},
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
        .route("/v4/snapshot", get(field_snapshot))
        .route("/v4/runs", post(field_create))
        .route("/v4/runs/{id}", get(field_detail))
        .route("/v4/runs/{id}/cancel", post(field_cancel))
        .route("/v4/duties", post(field_duty))
        .route("/v4/repositories", get(repositories).post(repository_set))
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
