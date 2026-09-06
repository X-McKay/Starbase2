use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, Path, State},
    http::StatusCode,
    routing::{get, post},
};
use serde_json::{Value, json};
use starbase_core::{
    Store,
    model::{Contract, MissionInput, Submission, Transition},
};
use std::sync::{Arc, Mutex};
type App = Arc<Mutex<Store>>;
type ApiResult<T> = Result<Json<T>, (StatusCode, Json<Value>)>;
fn err(e: String) -> (StatusCode, Json<Value>) {
    (StatusCode::CONFLICT, Json(json!({"error":e})))
}
#[tokio::main]
async fn main() {
    if std::env::args().any(|s| s == "--schema") {
        println!(
            "{}",
            serde_json::to_string_pretty(&schemars::schema_for!(Contract)).unwrap()
        );
        return;
    }
    if std::env::args().any(|s| s == "--schema-v4") {
        println!(
            "{}",
            serde_json::to_string_pretty(&schemars::schema_for!(
                starbase_core::field::FieldContract
            ))
            .unwrap()
        );
        return;
    }
    if std::env::args().any(|s| s == "--schema-v3") {
        println!(
            "{}",
            serde_json::to_string_pretty(&schemars::schema_for!(
                starbase_core::repair::RepairContract
            ))
            .unwrap()
        );
        return;
    }
    if std::env::args().any(|s| s == "--schema-v2") {
        println!(
            "{}",
            serde_json::to_string_pretty(&schemars::schema_for!(
                starbase_core::operations::OperationsContract
            ))
            .unwrap()
        );
        return;
    }
    if std::env::args().any(|s| s == "--healthcheck") {
        use std::io::{Read, Write};
        let port = std::env::var("STARBASE_PORT").unwrap_or("8787".into());
        let mut socket =
            std::net::TcpStream::connect(format!("127.0.0.1:{port}")).expect("core socket");
        socket
            .set_read_timeout(Some(std::time::Duration::from_secs(12)))
            .unwrap();
        socket
            .write_all(b"GET /v2/snapshot HTTP/1.0\r\nHost: localhost\r\n\r\n")
            .unwrap();
        let mut result = String::new();
        socket.read_to_string(&mut result).unwrap();
        if !result.starts_with("HTTP/1.0 200") && !result.starts_with("HTTP/1.1 200") {
            std::process::exit(1);
        }
        return;
    }
    let migrate = std::env::args().any(|s| s == "--migrate");
    let db = std::env::var("STARBASE_DB").unwrap_or(".local/starbase.sqlite".into());
    let port = std::env::var("STARBASE_PORT").unwrap_or("8787".into());
    let pg = std::env::var("STARBASE_DATABASE_URL_FILE").ok();
    let production = std::env::var("STARBASE_ENV").is_ok_and(|v| v == "production");
    if production && (pg.is_none() || std::env::var("STARBASE_TOKEN_FILE").is_err()) {
        panic!("production requires PostgreSQL and a worker token file");
    }
    let store = if let Some(path) = pg {
        let url = std::fs::read_to_string(path).expect("database connection file");
        Store::open_postgres(url.trim(), migrate).expect("open PostgreSQL store")
    } else {
        assert!(!migrate, "--migrate requires PostgreSQL");
        Store::open(&db).expect("open local store")
    };
    if migrate {
        println!("PostgreSQL schema verified");
        return;
    }
    let store = Arc::new(Mutex::new(store));
    let mut app = Router::new().merge(starbase_core::operations_api::router(
        starbase_core::operations_api::Access {
            worker: std::env::var("STARBASE_TOKEN_FILE")
                .ok()
                .and_then(|p| std::fs::read_to_string(p).ok())
                .unwrap_or_default()
                .trim()
                .into(),
            session: {
                use std::io::Read;
                let mut bytes = [0u8; 32];
                std::fs::File::open("/dev/urandom")
                    .expect("OS randomness")
                    .read_exact(&mut bytes)
                    .expect("OS randomness");
                bytes.iter().map(|b| format!("{b:02x}")).collect()
            },
            origin: format!("http://127.0.0.1:{port}"),
        },
    ));
    if std::env::var("STARBASE_LEGACY_ENABLED")
        .ok()
        .is_none_or(|v| v != "false")
    {
        app = app
            .route("/v1/snapshot", get(snapshot))
            .route("/v1/missions", post(create))
            .route("/v1/missions/{id}", get(mission))
            .route("/v1/missions/{id}/transition", post(transition))
            .route("/v1/missions/{id}/cancel", post(cancel))
            .route("/v1/missions/{id}/evidence", post(submit));
    }
    let app = app
        .with_state(store)
        .layer(DefaultBodyLimit::max(2 * 1024 * 1024));
    let listener = tokio::net::TcpListener::bind(format!("127.0.0.1:{port}"))
        .await
        .expect("bind loopback");
    println!("Starbase2 local core: http://127.0.0.1:{port}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}
async fn shutdown_signal() {
    #[cfg(unix)]
    {
        let mut terminate =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
                .expect("install SIGTERM handler");
        tokio::select! {
            _ = terminate.recv() => {},
            result = tokio::signal::ctrl_c() => result.expect("SIGINT handler"),
        }
    }
    #[cfg(not(unix))]
    tokio::signal::ctrl_c().await.expect("shutdown handler");
}
async fn snapshot(State(app): State<App>) -> ApiResult<starbase_core::model::Snapshot> {
    app.lock().unwrap().snapshot().map(Json).map_err(err)
}
async fn mission(
    State(app): State<App>,
    Path(id): Path<String>,
) -> ApiResult<starbase_core::model::Mission> {
    app.lock().unwrap().get(&id).map(Json).map_err(err)
}
async fn create(State(app): State<App>, Json(input): Json<MissionInput>) -> ApiResult<Value> {
    app.lock().unwrap().create(&input).map_err(err)?;
    Ok(Json(json!({"id":input.id})))
}
async fn transition(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(command): Json<Transition>,
) -> ApiResult<Value> {
    app.lock().unwrap().transition(&id, &command).map_err(err)?;
    Ok(Json(json!({"id":id})))
}
async fn cancel(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(_): Json<Value>,
) -> ApiResult<Value> {
    app.lock()
        .unwrap()
        .transition(
            &id,
            &Transition {
                state: "cancel_requested".into(),
                detail: "Stop requested; worker acknowledgement pending".into(),
            },
        )
        .map_err(err)?;
    Ok(Json(json!({"id":id,"state":"cancel_requested"})))
}
async fn submit(
    State(app): State<App>,
    Path(id): Path<String>,
    Json(body): Json<Submission>,
) -> ApiResult<Value> {
    app.lock()
        .unwrap()
        .submit(&id, &body)
        .map(Json)
        .map_err(err)
}
