use axum::{
    extract::State,
    http::{header, HeaderMap, StatusCode},
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use std::sync::Arc;

use crate::db::AppState;

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(get_migrate_sql))
        .route("/sql", get(get_migrate_sql))
}

async fn get_migrate_sql(
    State(_state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let possible_paths = [
        "db/schema.sql",
        "src/db/schema.sql",
        "backend/db/schema.sql",
        "Aplicativos/CRM BeautyFlow/backend/db/schema.sql",
    ];

    for p in &possible_paths {
        if let Ok(content) = tokio::fs::read_to_string(p).await {
            let mut headers = HeaderMap::new();
            headers.insert(header::CONTENT_TYPE, "text/plain; charset=utf-8".parse().unwrap());
            return Ok((StatusCode::OK, headers, content));
        }
    }

    let default_sql = include_str!("../db/schema.rs");
    let mut headers = HeaderMap::new();
    headers.insert(header::CONTENT_TYPE, "text/plain; charset=utf-8".parse().unwrap());
    Ok((StatusCode::OK, headers, default_sql.to_string()))
}
