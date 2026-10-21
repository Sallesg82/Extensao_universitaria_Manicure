use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::db::AppState;

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct NotificationDto {
    pub id: i32,
    pub r#type: String,
    pub title: String,
    pub message: String,
    pub read: bool,
    pub related_id: Option<i32>,
    pub related_type: Option<String>,
    pub created_at: Option<chrono::DateTime<chrono::Utc>>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_notifications))
        .route("/unread-count", get(unread_count))
        .route("/read/{id}", post(read_one))
        .route("/read-all", post(read_all))
}

async fn list_notifications(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let rows = sqlx::query_as::<_, NotificationDto>(
        "SELECT id, type, title, message, read, related_id, related_type, created_at \
         FROM public.notifications \
         ORDER BY created_at DESC \
         LIMIT 20"
    )
    .fetch_all(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch notifications: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    Ok(Json(rows))
}

async fn unread_count(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM public.notifications WHERE read = false"
    )
    .fetch_one(&state.pg_pool)
    .await
    .unwrap_or(0);

    Ok(Json(serde_json::json!({ "count": count })))
}

async fn read_one(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let _ = sqlx::query("UPDATE public.notifications SET read = true WHERE id = $1")
        .bind(id)
        .execute(&state.pg_pool)
        .await;

    Ok(Json(serde_json::json!({ "status": "ok" })))
}

async fn read_all(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let _ = sqlx::query("UPDATE public.notifications SET read = true WHERE read = false")
        .execute(&state.pg_pool)
        .await;

    Ok(Json(serde_json::json!({ "status": "ok" })))
}
