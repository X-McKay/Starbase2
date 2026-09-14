//! Isolated browser export fixture: real Core routes and static game on one origin.
//! No worker, provider, persistent database, reverse proxy, or production configuration.
use axum::{
    Router,
    extract::{DefaultBodyLimit, Path},
    http::{HeaderValue, StatusCode, header},
    middleware,
    response::{IntoResponse, Response},
    routing::get,
};
use starbase_core::{Store, operations_api};
use std::{
    collections::BTreeMap,
    io::Read,
    path::PathBuf,
    sync::{Arc, Mutex},
};

fn content_type(name: &str) -> Option<&'static str> {
    match name.rsplit('.').next()? {
        "html" => Some("text/html; charset=utf-8"),
        "js" => Some("application/javascript"),
        "wasm" => Some("application/wasm"),
        "pck" => Some("application/octet-stream"),
        "png" => Some("image/png"),
        "svg" => Some("image/svg+xml"),
        "ico" => Some("image/x-icon"),
        _ => None,
    }
}

fn load_files(root: &std::path::Path) -> BTreeMap<String, (PathBuf, &'static str)> {
    let mut files = BTreeMap::new();
    for entry in std::fs::read_dir(root).expect("read export directory") {
        let entry = entry.expect("export entry");
        let name = entry.file_name().into_string().expect("UTF-8 filename");
        let Some(mime) = content_type(&name) else {
            continue;
        };
        // Only top-level assets; refuse symlinks discovered during startup.
        // The export directory must remain owner-controlled while this fixture runs.
        assert!(
            entry.file_type().unwrap().is_file(),
            "export asset must be regular"
        );
        files.insert(name, (entry.path(), mime));
    }
    assert!(
        files.contains_key("index.html"),
        "missing exported index.html"
    );
    files
}

async fn asset(files: Arc<BTreeMap<String, (PathBuf, &'static str)>>, name: String) -> Response {
    let Some((path, mime)) = files.get(&name) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    // Deliberately a bounded local fixture, not a production static server.
    let path = path.clone();
    let mime = *mime;
    match tokio::task::spawn_blocking(move || std::fs::read(path)).await {
        Ok(Ok(bytes)) => ([(header::CONTENT_TYPE, mime)], bytes).into_response(),
        _ => StatusCode::NOT_FOUND.into_response(),
    }
}

fn retained_fixture_report(store: &mut Store, id: &str) {
    use sha2::{Digest, Sha256};
    use starbase_core::operations::{ReviewReport, RunReport, SourceFile, SourceSnapshot, hash};
    let source = "# Synthetic browser fixture; no repository was inspected.\npass\n";
    let mut snapshot = SourceSnapshot {
        digest: String::new(),
        files: vec![SourceFile {
            path: "synthetic_fixture.py".into(),
            source: source.into(),
            sha256: format!("{:x}", Sha256::digest(source.as_bytes())),
        }],
        skipped: vec![],
        redaction: "literal-and-comment-v1".into(),
    };
    let mut value = serde_json::to_value(&snapshot).unwrap();
    value.as_object_mut().unwrap().remove("digest");
    snapshot.digest = hash(&value);
    store.retain_snapshot(id, &snapshot).unwrap();
    store.retain_report(id, &RunReport { review: Some(ReviewReport {
        snapshot_digest: snapshot.digest, findings: vec![], errors: vec![], files_reviewed: 1,
        elapsed_ms: 0, engine: "ruff-0.16.6".into(), model_calls: 0,
        advisory: Some(serde_json::json!({"fixture":true,"text":"Synthetic retained fixture, not executed analysis"})),
    }), trials: vec![] }).unwrap();
}

#[tokio::main]
async fn main() {
    assert!(
        !std::env::vars_os().any(|(key, _)| key.to_string_lossy().starts_with("STARBASE_")),
        "fixture refuses inherited STARBASE configuration; launch with a clean environment"
    );
    let mut args = std::env::args().skip(1);
    let root = PathBuf::from(
        args.next()
            .expect("usage: web_fixture EXPORT_DIRECTORY [PORT]"),
    )
    .canonicalize()
    .expect("export directory");
    let port: u16 = args
        .next()
        .unwrap_or_else(|| "0".into())
        .parse()
        .expect("port");
    assert!(args.next().is_none(), "unexpected arguments");
    let files = Arc::new(load_files(&root));
    let listener = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, port))
        .await
        .expect("bind isolated loopback fixture");
    let origin = format!("http://{}", listener.local_addr().unwrap());
    let mut random = [0u8; 32];
    std::fs::File::open("/dev/urandom")
        .unwrap()
        .read_exact(&mut random)
        .unwrap();
    let mut store = Store::open(":memory:").expect("isolated fixture store");
    let manifest = serde_json::json!({"profile":"surveyor-v1", "fixture":true});
    store
        .register_build(&serde_json::json!({
            "digest":starbase_core::operations::hash(&manifest), "manifest":manifest
        }))
        .expect("register synthetic build");
    store
        .create_run(&starbase_core::operations::RunInput {
            id: "synthetic-browser-evidence".into(),
            kind: "review".into(),
            target: "sample".into(),
            profile: "surveyor-v1".into(),
            candidate: None,
            inference: false,
        })
        .unwrap();
    store
        .run_transition(
            "synthetic-browser-evidence",
            "running",
            "Synthetic browser fixture; not executed analysis",
        )
        .unwrap();
    retained_fixture_report(&mut store, "synthetic-browser-evidence");
    let store = Arc::new(Mutex::new(store));
    let shell_files = files.clone();
    let redirect_hits = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let landing_hits = redirect_hits.clone();
    let app = operations_api::router(operations_api::Access {
        worker: String::new(),
        session: random.iter().map(|b| format!("{b:02x}")).collect(),
        origin: origin.clone(),
    })
    .route(
        "/__fixture/review",
        get(|| async {
            axum::response::Html(include_str!(
                "../../../fixtures/world-web-probe/review.html"
            ))
        }),
    )
    .route(
        "/__fixture/slow",
        get(|| async {
            tokio::task::spawn_blocking(|| std::thread::sleep(std::time::Duration::from_secs(1)))
                .await
                .unwrap();
            axum::Json(serde_json::json!({"slow":true}))
        }),
    )
    .route("/__fixture/large", get(|| async { "x".repeat(8192) }))
    .route(
        "/__fixture/redirect",
        get(|| async {
            (
                StatusCode::TEMPORARY_REDIRECT,
                [(header::LOCATION, "/__fixture/landing")],
            )
        }),
    )
    .route(
        "/__fixture/landing",
        get(move || {
            landing_hits.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            async { "redirect was followed" }
        }),
    )
    .route(
        "/__fixture/stats",
        get(move || {
            let hits = redirect_hits.load(std::sync::atomic::Ordering::SeqCst);
            async move { axum::Json(serde_json::json!({"redirect_hits":hits})) }
        }),
    )
    .route(
        "/game/",
        get(move || asset(shell_files.clone(), "index.html".into())),
    )
    .route(
        "/game/{name}",
        get(move |Path(name): Path<String>| asset(files.clone(), name)),
    )
    .with_state(store)
    .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
    .layer(middleware::map_response(
        |mut response: Response| async move {
            let headers = response.headers_mut();
            headers.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
            headers.insert(
                header::X_CONTENT_TYPE_OPTIONS,
                HeaderValue::from_static("nosniff"),
            );
            headers.insert(
                header::REFERRER_POLICY,
                HeaderValue::from_static("no-referrer"),
            );
            response
        },
    ));
    let app: Router = app;
    println!("Isolated Godot Web fixture: {origin}/game/ (in-memory Core, no worker)");
    axum::serve(listener, app)
        .with_graceful_shutdown(async { tokio::signal::ctrl_c().await.unwrap() })
        .await
        .unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_export_types_are_served_with_correct_wasm_mime() {
        assert_eq!(content_type("index.wasm"), Some("application/wasm"));
        for name in ["manifest.json", "export.log", "source.gd", ".env"] {
            assert_eq!(content_type(name), None);
        }
    }
}
