use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use regex::Regex;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::db::AppState;

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct MetaDto {
    pub id: i32,
    pub mes: String,
    pub meta: f32,
    pub created_at: Option<chrono::DateTime<chrono::Utc>>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct MetaQuery {
    pub mes: Option<String>,
    pub month: Option<i32>,
    pub year: Option<i32>,
}

#[derive(Debug, Deserialize)]
pub struct SaveMetaReq {
    pub mes: Option<String>,
    pub month: Option<i32>,
    pub year: Option<i32>,
    pub meta: Option<f32>,
    pub meta_mensal: Option<f32>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_or_get_meta).post(save_meta_root).put(save_meta_root))
        .route("/{mes}", get(get_single_meta).post(save_meta_param).put(save_meta_param))
}

pub async fn get_meta_value(pool: &sqlx::PgPool, mes: &str) -> f32 {
    if let Ok(Some(row)) = sqlx::query("SELECT meta FROM public.metas WHERE mes = $1 LIMIT 1")
        .bind(mes)
        .fetch_optional(pool)
        .await
    {
        return row.get::<f32, _>("meta");
    }

    if let Ok(Some(prev)) = sqlx::query("SELECT meta FROM public.metas WHERE mes < $1 ORDER BY mes DESC LIMIT 1")
        .bind(mes)
        .fetch_optional(pool)
        .await
    {
        return prev.get::<f32, _>("meta");
    }

    if let Ok(Some(s_row)) = sqlx::query("SELECT value FROM public.settings WHERE key = 'meta_mensal' LIMIT 1")
        .fetch_optional(pool)
        .await
    {
        let val_str: String = s_row.get("value");
        if let Ok(v) = val_str.parse::<f32>() {
            return v;
        }
    }

    7000.0
}

fn validate_mes(mes: &str) -> bool {
    let re = Regex::new(r"^\d{4}-(0[1-9]|1[0-2])$").unwrap();
    re.is_match(mes)
}

fn resolve_mes(req: &SaveMetaReq, param_mes: Option<&str>) -> String {
    if let Some(p) = param_mes {
        if validate_mes(p) {
            return p.to_string();
        }
    }
    if let Some(ref m) = req.mes {
        let trimmed = m.trim();
        if validate_mes(trimmed) {
            return trimmed.to_string();
        }
    }
    if let (Some(m), Some(y)) = (req.month, req.year) {
        if (1..=12).contains(&m) && (2000..=2100).contains(&y) {
            return format!("{:04}-{:02}", y, m);
        }
    }
    let now = chrono::Local::now();
    format!("{:04}-{:02}", now.format("%Y"), now.format("%m"))
}

async fn list_or_get_meta(
    State(state): State<Arc<AppState>>,
    Query(query): Query<MetaQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    if let Some(ref m) = query.mes {
        if validate_mes(m) {
            let meta_val = get_meta_value(&state.pg_pool, m).await;
            return Ok(Json(serde_json::json!({
                "mes": m,
                "meta": meta_val
            })));
        }
    }

    if let (Some(month), Some(year)) = (query.month, query.year) {
        if (1..=12).contains(&month) {
            let formatted = format!("{:04}-{:02}", year, month);
            let meta_val = get_meta_value(&state.pg_pool, &formatted).await;
            return Ok(Json(serde_json::json!({
                "mes": formatted,
                "meta": meta_val
            })));
        }
    }

    let rows = sqlx::query_as::<_, MetaDto>(
        "SELECT id, mes, meta, created_at, updated_at FROM public.metas ORDER BY mes DESC"
    )
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    Ok(Json(serde_json::to_value(rows).unwrap()))
}

async fn get_single_meta(
    State(state): State<Arc<AppState>>,
    Path(mes): Path<String>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    if !validate_mes(&mes) {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Formato de mês inválido. Use YYYY-MM" }))));
    }

    let meta_val = get_meta_value(&state.pg_pool, &mes).await;
    Ok(Json(serde_json::json!({
        "mes": mes,
        "meta": meta_val
    })))
}

async fn save_meta_root(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SaveMetaReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    save_meta_internal(state, payload, None).await
}

async fn save_meta_param(
    State(state): State<Arc<AppState>>,
    Path(mes): Path<String>,
    Json(payload): Json<SaveMetaReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    save_meta_internal(state, payload, Some(&mes)).await
}

async fn save_meta_internal(
    state: Arc<AppState>,
    payload: SaveMetaReq,
    param_mes: Option<&str>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let mes_target = resolve_mes(&payload, param_mes);
    let raw_val = payload.meta.or(payload.meta_mensal);

    let val = match raw_val {
        Some(v) if v > 0.0 => v,
        Some(_) => return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "A meta deve ser maior que zero" })))),
        None => return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Valor da meta é obrigatório" })))),
    };

    let saved = sqlx::query_as::<_, MetaDto>(
        "INSERT INTO public.metas (mes, meta, updated_at) \
         VALUES ($1, $2, now()) \
         ON CONFLICT (mes) DO UPDATE \
         SET meta = EXCLUDED.meta, updated_at = now() \
         RETURNING id, mes, meta, created_at, updated_at"
    )
    .bind(&mes_target)
    .bind(val)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to save meta: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao salvar meta" })))
    })?;

    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "meta",
        "mes": &mes_target,
        "meta": val
    })).await;

    Ok(Json(serde_json::json!({
        "success": true,
        "mes": mes_target,
        "meta": val,
        "data": saved
    })))
}
