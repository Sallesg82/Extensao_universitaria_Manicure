use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use chrono::{Duration, Local};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration as StdDuration;

use crate::db::AppState;
use crate::routes::settings::get_settings_map;
use crate::services::n8n::{compute_iso_datetimes, N8N_FALLBACK};

#[derive(Debug, Deserialize)]
pub struct TestReq {
    pub webhook_url: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SyncCalendarReq {
    pub action: Option<String>,
    pub appointment_id: Option<i32>,
    pub appointment_date: Option<String>,
    pub appointment_time: Option<String>,
    pub duration_minutes: Option<i32>,
    pub client_name: Option<String>,
    pub client_phone: Option<String>,
    pub service: Option<String>,
    pub price: Option<f32>,
    pub status: Option<String>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/config", get(get_n8n_config).put(update_n8n_config))
        .route("/test", post(test_n8n))
        .route("/sync-calendar", post(sync_calendar))
        .route("/status", get(get_n8n_status))
}

async fn get_n8n_config(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let fallback_url = if !state.config.n8n_webhook_url.trim().is_empty() {
        state.config.n8n_webhook_url.clone()
    } else {
        N8N_FALLBACK.to_string()
    };

    Ok(Json(serde_json::json!({
        "n8n_enabled": settings.get("n8n_enabled").cloned().unwrap_or_else(|| "true".to_string()),
        "n8n_webhook_url": settings.get("n8n_webhook_url").cloned().unwrap_or(fallback_url),
        "n8n_events": settings.get("n8n_events").cloned().unwrap_or_else(|| "create,update,delete".to_string()),
        "n8n_timeout": settings.get("n8n_timeout").cloned().unwrap_or_else(|| "8".to_string()),
        "n8n_header_name": settings.get("n8n_header_name").cloned().unwrap_or_default(),
        "n8n_header_value": settings.get("n8n_header_value").cloned().unwrap_or_default(),
    })))
}

async fn update_n8n_config(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<HashMap<String, serde_json::Value>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let keys = [
        "n8n_enabled",
        "n8n_webhook_url",
        "n8n_events",
        "n8n_timeout",
        "n8n_header_name",
        "n8n_header_value",
    ];

    for key in keys {
        if let Some(val) = payload.get(key) {
            let val_str = match val {
                serde_json::Value::String(s) => s.clone(),
                serde_json::Value::Bool(b) => b.to_string(),
                serde_json::Value::Number(n) => n.to_string(),
                _ => val.to_string(),
            };

            let _ = sqlx::query(
                "INSERT INTO public.settings (key, value) VALUES ($1, $2) \
                 ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
            )
            .bind(key)
            .bind(&val_str)
            .execute(&state.pg)
            .await;
        }
    }

    Ok(Json(serde_json::json!({ "status": "ok" })))
}

async fn test_n8n(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<TestReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let url = payload.webhook_url.and_then(|u| {
        let trimmed = u.trim().to_string();
        if trimmed.is_empty() { None } else { Some(trimmed) }
    }).unwrap_or_else(|| {
        settings.get("n8n_webhook_url").cloned().filter(|u| !u.trim().is_empty()).unwrap_or_else(|| {
            if !state.config.n8n_webhook_url.trim().is_empty() {
                state.config.n8n_webhook_url.clone()
            } else {
                N8N_FALLBACK.to_string()
            }
        })
    });

    if url.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nenhuma URL de webhook configurada." }))));
    }

    let now = Local::now();
    let start_dt = now.format("%Y-%m-%dT%H:%M:%S-03:00").to_string();
    let end_dt = (now + Duration::hours(1)).format("%Y-%m-%dT%H:%M:%S-03:00").to_string();

    let test_body = serde_json::json!({
        "action": "test",
        "appointment_id": 0,
        "client_name": "Teste BeautyFlow",
        "client_phone": "(11) 99999-0000",
        "service": "Teste de Integração",
        "price": 0,
        "status": "test",
        "start_datetime": start_dt,
        "end_datetime": end_dt,
    });

    let timeout_secs: u64 = settings.get("n8n_timeout").and_then(|v| v.parse().ok()).unwrap_or(8);

    let mut req = state.http_client
        .post(&url)
        .json(&test_body)
        .timeout(StdDuration::from_secs(timeout_secs));

    if let (Some(h_name), Some(h_val)) = (settings.get("n8n_header_name"), settings.get("n8n_header_value")) {
        let n = h_name.trim();
        let v = h_val.trim();
        if !n.is_empty() && !v.is_empty() {
            req = req.header(n, v);
        }
    }

    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            let snippet = if text.len() > 500 { &text[..500] } else { &text };

            if status.is_success() {
                Ok(Json(serde_json::json!({
                    "status": "ok",
                    "message": "Webhook enviado com sucesso!",
                    "n8n_status": status.as_u16(),
                    "n8n_response": snippet,
                })))
            } else {
                Err((
                    StatusCode::BAD_GATEWAY,
                    Json(serde_json::json!({
                        "error": format!("n8n retornou erro HTTP {}", status.as_u16()),
                        "n8n_status": status.as_u16(),
                        "n8n_response": snippet,
                    })),
                ))
            }
        }
        Err(e) if e.is_timeout() => {
            Err((
                StatusCode::GATEWAY_TIMEOUT,
                Json(serde_json::json!({
                    "error": format!("Timeout — n8n não respondeu em {} segundos.", timeout_secs)
                })),
            ))
        }
        Err(e) if e.is_connect() => {
            Err((
                StatusCode::BAD_GATEWAY,
                Json(serde_json::json!({
                    "error": "Conexão recusada — verifique a URL do webhook."
                })),
            ))
        }
        Err(e) => {
            Err((
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(serde_json::json!({
                    "error": format!("Erro inesperado: {}", e)
                })),
            ))
        }
    }
}

async fn sync_calendar(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SyncCalendarReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let appt_id = match payload.appointment_id {
        Some(id) => id,
        None => return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Campos obrigatórios ausentes: appointment_id" })))),
    };
    let appt_date = match payload.appointment_date {
        Some(d) if !d.trim().is_empty() => d,
        _ => return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Campos obrigatórios ausentes: appointment_date" })))),
    };
    let appt_time = match payload.appointment_time {
        Some(t) if !t.trim().is_empty() => t,
        _ => return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Campos obrigatórios ausentes: appointment_time" })))),
    };

    let action = payload.action.unwrap_or_else(|| "create".to_string());
    let duration = payload.duration_minutes.unwrap_or(60);
    let (start_iso, end_iso) = compute_iso_datetimes(&appt_date, &appt_time, duration);

    let body = serde_json::json!({
        "action": action,
        "appointment_id": appt_id,
        "client_name": payload.client_name.unwrap_or_else(|| "Cliente".to_string()),
        "client_phone": payload.client_phone.unwrap_or_default(),
        "service": payload.service.unwrap_or_else(|| "Serviço".to_string()),
        "price": payload.price.unwrap_or(0.0),
        "status": payload.status.unwrap_or_else(|| "pending".to_string()),
        "start_datetime": start_iso,
        "end_datetime": end_iso,
    });

    let settings = get_settings_map(&state.pg).await;
    let enabled = settings.get("n8n_enabled").map(|v| v.as_str()).unwrap_or("true") == "true";
    if !enabled {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Integração n8n desabilitada." }))));
    }

    let custom_url = settings.get("n8n_webhook_url").map(|v| v.trim()).unwrap_or("");
    let url = if !custom_url.is_empty() {
        custom_url
    } else if !state.config.n8n_webhook_url.trim().is_empty() {
        &state.config.n8n_webhook_url
    } else {
        N8N_FALLBACK
    };

    let timeout_secs: u64 = settings.get("n8n_timeout").and_then(|v| v.parse().ok()).unwrap_or(8);

    let mut req = state.http_client
        .post(url)
        .json(&body)
        .timeout(StdDuration::from_secs(timeout_secs));

    if let (Some(h_name), Some(h_val)) = (settings.get("n8n_header_name"), settings.get("n8n_header_value")) {
        let n = h_name.trim();
        let v = h_val.trim();
        if !n.is_empty() && !v.is_empty() {
            req = req.header(n, v);
        }
    }

    match req.send().await {
        Ok(resp) => {
            let status = resp.status();
            Ok(Json(serde_json::json!({
                "status": "ok",
                "message": "Sincronização enviada ao n8n com sucesso",
                "n8n_status": status.as_u16(),
                "payload_enviado": body,
            })))
        }
        Err(e) if e.is_timeout() => {
            Err((StatusCode::GATEWAY_TIMEOUT, Json(serde_json::json!({ "error": "Timeout ao conectar com o n8n." }))))
        }
        Err(e) if e.is_connect() => {
            Err((StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "error": "Não foi possível conectar ao n8n. Verifique a URL do webhook." }))))
        }
        Err(e) => {
            Err((StatusCode::BAD_GATEWAY, Json(serde_json::json!({ "error": format!("n8n retornou erro: {}", e) }))))
        }
    }
}

async fn get_n8n_status(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let custom_url = settings.get("n8n_webhook_url").map(|v| v.trim()).unwrap_or("");
    let url = if !custom_url.is_empty() {
        custom_url.to_string()
    } else if !state.config.n8n_webhook_url.trim().is_empty() {
        state.config.n8n_webhook_url.clone()
    } else {
        N8N_FALLBACK.to_string()
    };

    let enabled = settings.get("n8n_enabled").map(|v| v.as_str()).unwrap_or("true") == "true";
    let events = settings.get("n8n_events").cloned().unwrap_or_else(|| "create,update,delete".to_string());
    let timeout: i64 = settings.get("n8n_timeout").and_then(|v| v.parse().ok()).unwrap_or(8);

    let (online, http_code) = match state.http_client.get(&url).timeout(StdDuration::from_secs(5)).send().await {
        Ok(resp) => (true, Some(resp.status().as_u16())),
        Err(_) => (false, None),
    };

    Ok(Json(serde_json::json!({
        "n8n_enabled": enabled,
        "n8n_webhook_url": url,
        "n8n_events": events,
        "n8n_timeout": timeout,
        "n8n_reachable": online,
        "n8n_http_code": http_code,
    })))
}
