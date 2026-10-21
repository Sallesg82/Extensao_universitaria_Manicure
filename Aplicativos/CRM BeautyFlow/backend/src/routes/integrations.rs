use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::db::AppState;

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct IntegrationDto {
    pub id: i32,
    pub name: String,
    pub r#type: String,
    pub config: Option<serde_json::Value>,
    pub enabled: bool,
    pub created_at: Option<chrono::DateTime<chrono::Utc>>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateIntegrationReq {
    pub name: Option<String>,
    pub r#type: Option<String>,
    pub config: Option<serde_json::Value>,
    pub enabled: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateIntegrationReq {
    pub name: Option<String>,
    pub config: Option<serde_json::Value>,
    pub enabled: Option<bool>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_integrations).post(create_integration))
        .route("/{id}", get(get_integration).put(update_integration).delete(delete_integration))
}

async fn list_integrations(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let rows = sqlx::query_as::<_, IntegrationDto>(
        "SELECT id, name, type, config, enabled, created_at, updated_at \
         FROM public.integrations \
         ORDER BY created_at ASC"
    )
    .fetch_all(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch integrations: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    Ok(Json(rows))
}

async fn get_integration(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let integ = sqlx::query_as::<_, IntegrationDto>(
        "SELECT id, name, type, config, enabled, created_at, updated_at \
         FROM public.integrations \
         WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    match integ {
        Some(i) => Ok(Json(i)),
        None => Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Integração não encontrada" })))),
    }
}

async fn create_integration(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateIntegrationReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let name = payload.name.unwrap_or_default().trim().to_string();
    let integ_type = payload.r#type.unwrap_or_default().trim().to_string();

    if name.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nome é obrigatório" }))));
    }

    if !["webhook", "n8n", "whatsapp", "waha"].contains(&integ_type.as_str()) {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Tipo inválido" }))));
    }

    let config = payload.config.unwrap_or_else(|| serde_json::json!({}));
    let enabled = payload.enabled.unwrap_or(true);

    let created = sqlx::query_as::<_, IntegrationDto>(
        "INSERT INTO public.integrations (name, type, config, enabled) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, name, type, config, enabled, created_at, updated_at"
    )
    .bind(&name)
    .bind(&integ_type)
    .bind(&config)
    .bind(enabled)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to create integration: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao criar integração" })))
    })?;

    if integ_type == "whatsapp" || integ_type == "waha" {
        let _ = sqlx::query(
            "INSERT INTO public.settings (key, value) VALUES ('whatsapp_integrated', 'true') \
             ON CONFLICT (key) DO UPDATE SET value = 'true'"
        )
        .execute(&state.pg_pool)
        .await;
    }

    Ok((StatusCode::CREATED, Json(created)))
}

async fn update_integration(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateIntegrationReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let existing: Option<i32> = sqlx::query_scalar("SELECT id FROM public.integrations WHERE id = $1 LIMIT 1")
        .bind(id)
        .fetch_optional(&state.pg_pool)
        .await
        .unwrap_or(None);

    if existing.is_none() {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Integração não encontrada" }))));
    }

    let mut set_clauses = Vec::new();
    let mut param_index = 2;

    if payload.name.is_some() {
        set_clauses.push(format!("name = ${}", param_index));
        param_index += 1;
    }
    if payload.config.is_some() {
        set_clauses.push(format!("config = ${}", param_index));
        param_index += 1;
    }
    if payload.enabled.is_some() {
        set_clauses.push(format!("enabled = ${}", param_index));
    }

    if set_clauses.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nenhum dado para atualizar" }))));
    }

    set_clauses.push("updated_at = now()".to_string());

    let sql = format!(
        "UPDATE public.integrations SET {} WHERE id = $1 RETURNING id, name, type, config, enabled, created_at, updated_at",
        set_clauses.join(", ")
    );

    let mut query = sqlx::query_as::<_, IntegrationDto>(sqlx::AssertSqlSafe(sql.as_str())).bind(id);

    if let Some(name) = payload.name {
        query = query.bind(name.trim().to_string());
    }
    if let Some(config) = payload.config {
        query = query.bind(config);
    }
    if let Some(enabled) = payload.enabled {
        query = query.bind(enabled);
    }

    let updated = query.fetch_one(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to update integration: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao atualizar integração" })))
    })?;

    Ok(Json(updated))
}

async fn delete_integration(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let integ = sqlx::query_as::<_, IntegrationDto>(
        "SELECT id, name, type, config, enabled, created_at, updated_at FROM public.integrations WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    let integ = match integ {
        Some(i) => i,
        None => return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Integração não encontrada" })))),
    };

    let _ = sqlx::query("DELETE FROM public.integrations WHERE id = $1")
        .bind(id)
        .execute(&state.pg_pool)
        .await;

    if integ.r#type == "whatsapp" || integ.r#type == "waha" {
        let remaining_wa: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM public.integrations WHERE type IN ('whatsapp', 'waha')"
        )
        .fetch_one(&state.pg_pool)
        .await
        .unwrap_or(0);

        if remaining_wa == 0 {
            let _ = sqlx::query(
                "UPDATE public.settings SET value = 'false' WHERE key IN \
                 ('whatsapp_integrated', 'whatsapp_auto_notify_created', 'whatsapp_auto_notify_cancelled', 'whatsapp_auto_notify_reminder')"
            )
            .execute(&state.pg_pool)
            .await;
        }
    }

    Ok(Json(serde_json::json!({ "message": "Integração removida", "id": id })))
}
