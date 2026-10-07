use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use crate::db::chat_db::{
    clean_phone, get_canned_responses, get_conversations, get_messages, save_simple_message,
};
use crate::db::AppState;
use crate::routes::settings::get_settings_map;
use crate::services::scheduler::trigger_reminders_check;
use crate::services::waha::{
    get_api_key, get_default_templates, get_session_name, get_working_waha_url,
    render_whatsapp_template, send_whatsapp_text,
    sync_waha_messages_for_chat,
};

#[derive(Debug, Deserialize)]
pub struct ChatMessagesQuery {
    pub phone: Option<String>,
    #[serde(rename = "chatId")]
    pub chat_id: Option<String>,
    pub client_name: Option<String>,
    pub limit: Option<i64>,
    pub sync: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChatSendReq {
    pub phone: Option<String>,
    #[serde(rename = "chatId")]
    pub chat_id: Option<String>,
    pub text: Option<String>,
    pub message: Option<String>,
    pub client_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SyncReq {
    pub phone: Option<String>,
    #[allow(dead_code)]
    pub client_name: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SendNotificationReq {
    pub phone: Option<String>,
    pub client_name: Option<String>,
    pub service: Option<String>,
    pub date: Option<String>,
    pub time: Option<String>,
    pub price: Option<f32>,
    pub message: Option<String>,
    pub template: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct TestSendReq {
    pub phone: Option<String>,
    pub text: Option<String>,
    pub message: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct WebhookConfigReq {
    pub url: Option<String>,
    pub events: Option<Vec<String>>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/status", get(get_whatsapp_status))
        .route("/qr", get(get_whatsapp_qr))
        .route("/refresh-qr", post(refresh_whatsapp_qr))
        .route("/screenshot", get(get_whatsapp_screenshot))
        .route("/start", post(start_whatsapp_session))
        .route("/logout", post(logout_whatsapp_session))
        .route("/integration", delete(disconnect_whatsapp))
        .route("/disconnect", post(disconnect_whatsapp).delete(disconnect_whatsapp))
        .route("/webhook/config", get(get_webhook_config).post(set_webhook_config))
        .route("/webhook/test", post(test_webhook_forward))
        .route("/send-notification", post(send_notification))
        .route("/test", post(test_send_message))
        .route("/settings", get(get_whatsapp_settings).post(save_whatsapp_settings))
        .route("/send-pending-reminders", post(send_pending_reminders))
        .route("/chat/messages", get(get_chat_messages))
        .route("/chat/send", post(chat_send))
        .route("/chat/sync", post(chat_sync))
        .route("/chat/canned-responses", get(get_chat_canned_responses))
        .route("/canned-responses", get(get_chat_canned_responses))
        .route("/chat/conversations", get(get_chat_conversations))
        .route("/conversations", get(get_chat_conversations))
        .route("/webhook", post(receive_webhook))
}

async fn get_whatsapp_status(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;

    let is_integrated: bool = if settings.get("whatsapp_integrated").map(|v| v == "true").unwrap_or(false) {
        true
    } else {
        sqlx::query_scalar::<_, i32>(
            "SELECT id FROM integrations WHERE type IN ('whatsapp', 'waha') LIMIT 1"
        )
        .fetch_optional(&state.pg_pool)
        .await
        .ok()
        .flatten()
        .is_some()
    };

    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => {
            return Ok(Json(json!({
                "installed": false,
                "is_integrated": is_integrated,
                "connected": false,
                "status": "NOT_INSTALLED",
                "session": "default",
                "session_name": "default",
                "error": "WAHA offline ou inacessível. Inicie o container WAHA.",
                "waha_url": null,
                "me": null,
                "n8n_webhook_url": settings.get("n8n_whatsapp_webhook_url").cloned().unwrap_or_default(),
                "n8n_webhook_events": settings.get("n8n_whatsapp_webhook_events").cloned().unwrap_or_else(|| "message,message.any".to_string()),
            })));
        }
    };

    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let resp = state
        .http_client
        .get(format!("{}/api/sessions", waha_url))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(3))
        .send()
        .await;

    let mut session_status = "STOPPED".to_string();
    let mut me = json!(null);
    let mut is_connected = false;

    if let Ok(r) = resp {
        if let Ok(sessions) = r.json::<Vec<Value>>().await {
            for s in &sessions {
                let name = s.get("name").and_then(|v| v.as_str()).unwrap_or("");
                if name == session || session == "default" {
                    let st = s.get("status").and_then(|v| v.as_str()).unwrap_or("STOPPED");
                    session_status = st.to_string();
                    if st == "WORKING" {
                        is_connected = true;
                    }
                    if let Some(m) = s.get("me") {
                        me = m.clone();
                    }
                    break;
                }
            }
        }
    }

    let empresa = settings
        .get("company_name")
        .or_else(|| settings.get("studio_name"))
        .cloned()
        .unwrap_or_else(|| "BeautyFlow".to_string());

    let default_templates = get_default_templates();

    Ok(Json(json!({
        "installed": true,
        "is_integrated": is_integrated,
        "connected": is_connected,
        "status": session_status,
        "session": session,
        "session_name": session,
        "me": me,
        "waha_url": waha_url,
        "error": null,
        "n8n_webhook_url": settings.get("n8n_whatsapp_webhook_url").cloned().unwrap_or_default(),
        "n8n_webhook_events": settings.get("n8n_whatsapp_webhook_events").cloned().unwrap_or_else(|| "message,message.any".to_string()),
        "settings": {
            "notify_on_create": settings.get("whatsapp_auto_notify_created").map(|v| v == "true").unwrap_or(true),
            "notify_on_cancel": settings.get("whatsapp_auto_notify_cancelled").map(|v| v == "true").unwrap_or(true),
            "notify_on_reminder": settings.get("whatsapp_auto_notify_reminder").map(|v| v == "true").unwrap_or(true),
            "notify_on_return": settings.get("whatsapp_auto_notify_return").map(|v| v == "true").unwrap_or(false),
            "notify_on_thanks": settings.get("whatsapp_auto_notify_thanks").map(|v| v == "true").unwrap_or(false),
            "auto_notify_created": settings.get("whatsapp_auto_notify_created").map(|v| v == "true").unwrap_or(true),
            "auto_notify_reminder": settings.get("whatsapp_auto_notify_reminder").map(|v| v == "true").unwrap_or(true),
            "auto_notify_cancelled": settings.get("whatsapp_auto_notify_cancelled").map(|v| v == "true").unwrap_or(true),
            "auto_notify_return": settings.get("whatsapp_auto_notify_return").map(|v| v == "true").unwrap_or(false),
            "auto_notify_thanks": settings.get("whatsapp_auto_notify_thanks").map(|v| v == "true").unwrap_or(false),
            "reminder_timing": settings.get("whatsapp_reminder_timing").cloned().unwrap_or_else(|| "1_day".to_string()),
            "reminder_time": settings.get("whatsapp_reminder_time").cloned().unwrap_or_else(|| "09:00".to_string()),
            "return_interval_days": settings.get("whatsapp_return_interval_days").cloned().unwrap_or_else(|| "20".to_string()),
            "return_time": settings.get("whatsapp_return_time").cloned().unwrap_or_else(|| "10:00".to_string()),
            "thanks_delay": settings.get("whatsapp_thanks_delay").cloned().unwrap_or_else(|| "immediate".to_string()),
            "waha_api_url": settings.get("waha_api_url").cloned().unwrap_or_default(),
            "waha_api_key": settings.get("waha_api_key").cloned().unwrap_or_default(),
            "waha_session_name": settings.get("waha_session_name").cloned().unwrap_or_default(),
            "country_code": settings.get("whatsapp_country_code").cloned().unwrap_or_else(|| "55".to_string()),
            "company_name": empresa,
            "template_created": settings.get("whatsapp_template_created").cloned().unwrap_or_else(|| default_templates["whatsapp_template_created"].to_string()),
            "template_reminder": settings.get("whatsapp_template_reminder").cloned().unwrap_or_else(|| default_templates["whatsapp_template_reminder"].to_string()),
            "template_cancelled": settings.get("whatsapp_template_cancelled").cloned().unwrap_or_else(|| default_templates["whatsapp_template_cancelled"].to_string()),
            "template_return": settings.get("whatsapp_template_return").cloned().unwrap_or_else(|| default_templates["whatsapp_template_return"].to_string()),
            "template_thanks": settings.get("whatsapp_template_thanks").cloned().unwrap_or_else(|| default_templates["whatsapp_template_thanks"].to_string()),
        }
    })))
}

async fn ensure_session_started(
    client: &reqwest::Client,
    waha_url: &str,
    api_key: &str,
    session: &str,
) {
    let check_resp = client
        .get(format!("{}/api/sessions/{}", waha_url, session))
        .header("X-Api-Key", api_key)
        .timeout(Duration::from_secs(3))
        .send()
        .await;

    let mut needs_create = true;
    let mut needs_start = false;

    if let Ok(r) = check_resp {
        if r.status().as_u16() == 200 {
            needs_create = false;
            if let Ok(sess_data) = r.json::<Value>().await {
                if sess_data.get("status").and_then(|v| v.as_str()) == Some("STOPPED") {
                    needs_start = true;
                }
            }
        }
    }

    if needs_create {
        let _ = client
            .post(format!("{}/api/sessions", waha_url))
            .header("X-Api-Key", api_key)
            .json(&json!({ "name": session, "start": true }))
            .timeout(Duration::from_secs(5))
            .send()
            .await;
    } else if needs_start {
        let _ = client
            .post(format!("{}/api/sessions/{}/start", waha_url, session))
            .header("X-Api-Key", api_key)
            .timeout(Duration::from_secs(5))
            .send()
            .await;
    }
}

async fn get_whatsapp_qr(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => {
            return Err((StatusCode::SERVICE_UNAVAILABLE, Json(json!({ "error": "WAHA offline" }))));
        }
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    // Check status first
    let sess_check = state
        .http_client
        .get(format!("{}/api/sessions/{}", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(3))
        .send()
        .await;

    if let Ok(r) = sess_check {
        if r.status().as_u16() == 200 {
            if let Ok(data) = r.json::<Value>().await {
                if data.get("status").and_then(|v| v.as_str()) == Some("WORKING") {
                    return Ok(Json(json!({
                        "status": "WORKING",
                        "message": "WhatsApp já está conectado.",
                        "me": data.get("me"),
                        "session": session
                    })));
                } else if data.get("status").and_then(|v| v.as_str()) == Some("STOPPED") {
                    let _ = state
                        .http_client
                        .post(format!("{}/api/sessions/{}/start", waha_url, session))
                        .header("X-Api-Key", &api_key)
                        .timeout(Duration::from_secs(4))
                        .send()
                        .await;
                }
            }
        } else if r.status().as_u16() == 404 || r.status().as_u16() == 422 {
            let _ = state
                .http_client
                .post(format!("{}/api/sessions", waha_url))
                .header("X-Api-Key", &api_key)
                .json(&json!({ "name": session, "start": true }))
                .timeout(Duration::from_secs(4))
                .send()
                .await;
        }
    } else {
        ensure_session_started(&state.http_client, &waha_url, &api_key, &session).await;
    }

    // Try to fetch QR
    let qr_url = format!("{}/api/{}/auth/qr", waha_url, session);
    for _ in 0..2 {
        let resp = state
            .http_client
            .get(&qr_url)
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(5))
            .send()
            .await;

        if let Ok(r) = resp {
            if r.status().is_success() {
                let bytes = r.bytes().await.unwrap_or_default();
                if bytes.len() > 100 {
                    use base64::Engine;
                    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                    let data_url = format!("data:image/png;base64,{}", b64);
                    return Ok(Json(json!({
                        "status": "SCAN_QR_CODE",
                        "qr": data_url,
                        "qr_image": data_url,
                        "session": session,
                        "expires_in": 35
                    })));
                }
            }
        }
        tokio::time::sleep(Duration::from_millis(600)).await;
    }

    Ok(Json(json!({
        "status": "STARTING",
        "qr": null,
        "qr_image": null,
        "message": "Aguardando o WAHA gerar o QR Code...",
        "session": session
    })))
}

async fn refresh_whatsapp_qr(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Err((StatusCode::SERVICE_UNAVAILABLE, Json(json!({ "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    // Check if already WORKING
    let r_sess = state
        .http_client
        .get(format!("{}/api/sessions/{}", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(3))
        .send()
        .await;

    if let Ok(r) = r_sess {
        if r.status().is_success() {
            if let Ok(sess_data) = r.json::<Value>().await {
                if sess_data.get("status").and_then(|v| v.as_str()) == Some("WORKING") {
                    return Ok(Json(json!({
                        "status": "WORKING",
                        "message": "WhatsApp já está conectado.",
                        "session": session
                    })));
                }
            }
        }
    }

    // Restart or start session
    let restart_res = state
        .http_client
        .post(format!("{}/api/sessions/{}/restart", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(6))
        .send()
        .await;

    if restart_res.is_err() || !restart_res.unwrap().status().is_success() {
        let _ = state
            .http_client
            .post(format!("{}/api/sessions/{}/start", waha_url, session))
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(4))
            .send()
            .await;
    }

    let qr_url = format!("{}/api/{}/auth/qr", waha_url, session);
    for _ in 0..4 {
        tokio::time::sleep(Duration::from_millis(1200)).await;
        let r_qr = state
            .http_client
            .get(&qr_url)
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(5))
            .send()
            .await;

        if let Ok(r) = r_qr {
            if r.status().is_success() {
                let bytes = r.bytes().await.unwrap_or_default();
                if bytes.len() > 100 {
                    use base64::Engine;
                    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                    let data_url = format!("data:image/png;base64,{}", b64);
                    return Ok(Json(json!({
                        "status": "SCAN_QR_CODE",
                        "qr": data_url,
                        "qr_image": data_url,
                        "session": session,
                        "expires_in": 35
                    })));
                }
            }
        }
    }

    Ok(Json(json!({
        "status": "STARTING",
        "qr": null,
        "qr_image": null,
        "message": "Sessão reiniciada. O QR Code está sendo processado...",
        "session": session
    })))
}

async fn get_whatsapp_screenshot(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Ok((StatusCode::OK, Json(json!({ "success": false, "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let resp = state
        .http_client
        .get(format!("{}/api/screenshot?session={}", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(10))
        .send()
        .await;

    if let Ok(r) = resp {
        if r.status().is_success() {
            let ct = r.headers().get("content-type").and_then(|v| v.to_str().ok()).unwrap_or("image/jpeg").to_string();
            let bytes = r.bytes().await.unwrap_or_default();
            if bytes.len() > 100 {
                use base64::Engine;
                let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
                let data_url = format!("data:{};base64,{}", ct, b64);
                let now_str = chrono::Local::now().format("%d/%m/%Y às %H:%M:%S").to_string();
                return Ok((StatusCode::OK, Json(json!({
                    "success": true,
                    "screenshot": data_url,
                    "session": session,
                    "timestamp": now_str
                }))));
            }
        }
    }

    Ok((StatusCode::OK, Json(json!({
        "success": false,
        "error": "Não foi possível obter a captura do WhatsApp Web."
    }))))
}

async fn start_whatsapp_session(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Ok((StatusCode::OK, Json(json!({ "success": false, "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let res = state
        .http_client
        .post(format!("{}/api/sessions/{}/start", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(5))
        .send()
        .await;

    let need_create = match &res {
        Ok(r) => r.status().as_u16() == 404 || r.status().as_u16() == 422,
        Err(_) => true,
    };

    if need_create {
        let _ = state
            .http_client
            .post(format!("{}/api/sessions", waha_url))
            .header("X-Api-Key", &api_key)
            .json(&json!({ "name": session, "start": true }))
            .timeout(Duration::from_secs(5))
            .send()
            .await;
    }

    Ok((StatusCode::OK, Json(json!({ "success": true, "status": "ok", "message": "Sessão iniciada." }))))
}

async fn logout_whatsapp_session(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Ok((StatusCode::OK, Json(json!({ "success": false, "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let _ = state
        .http_client
        .post(format!("{}/api/sessions/{}/logout", waha_url, session))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(5))
        .send()
        .await;

    Ok((StatusCode::OK, Json(json!({ "success": true, "status": "ok", "message": "WhatsApp desconectado." }))))
}

async fn disconnect_whatsapp(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    if let Some(waha_url) = get_working_waha_url(&state, &settings).await {
        let api_key = get_api_key(&state, &settings);
        let session = get_session_name(&state, &waha_url, &settings).await;
        let _ = state
            .http_client
            .post(format!("{}/api/sessions/{}/logout", waha_url, session))
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(5))
            .send()
            .await;
    }

    let _ = sqlx::query("DELETE FROM public.integrations WHERE type IN ('whatsapp', 'waha')")
        .execute(&state.pg)
        .await;

    let _ = sqlx::query(
        "UPDATE public.settings SET value = 'false' WHERE key IN \
         ('whatsapp_integrated', 'whatsapp_auto_notify_created', 'whatsapp_auto_notify_cancelled', 'whatsapp_auto_notify_reminder')"
    )
    .execute(&state.pg)
    .await;

    let _ = sqlx::query("UPDATE public.settings SET value = '' WHERE key = 'n8n_whatsapp_webhook_url'")
        .execute(&state.pg)
        .await;

    Ok(Json(json!({ "status": "ok", "message": "WhatsApp desconectado com sucesso" })))
}


async fn get_webhook_config(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    Ok(Json(json!({
        "url": settings.get("n8n_whatsapp_webhook_url").cloned().unwrap_or_default(),
        "events": settings.get("n8n_whatsapp_webhook_events").cloned().unwrap_or_else(|| "message,message.any".to_string()).split(',').map(|s| s.trim().to_string()).collect::<Vec<_>>(),
    })))
}

async fn set_webhook_config(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<WebhookConfigReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let url = payload.url.unwrap_or_default().trim().to_string();
    let events = payload.events.unwrap_or_else(|| vec!["message".to_string(), "message.any".to_string()]).join(",");

    let _ = sqlx::query(
        "INSERT INTO public.settings (key, value) VALUES ('n8n_whatsapp_webhook_url', $1) \
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
    )
    .bind(&url)
    .execute(&state.pg)
    .await;

    let _ = sqlx::query(
        "INSERT INTO public.settings (key, value) VALUES ('n8n_whatsapp_webhook_events', $1) \
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
    )
    .bind(&events)
    .execute(&state.pg)
    .await;

    Ok(Json(json!({
        "status": "ok",
        "url": url,
        "events": events,
        "message": if !url.is_empty() { "Webhook salvo com sucesso!" } else { "Webhook desativado." }
    })))
}

async fn test_webhook_forward(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let url = settings.get("n8n_whatsapp_webhook_url").cloned().unwrap_or_default();
    if url.trim().is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Nenhuma URL de webhook configurada para o n8n." }))));
    }

    let payload = json!({
        "event": "message",
        "session": "default",
        "me": { "id": "5511999990000@c.us" },
        "payload": {
            "id": "TEST_WEBHOOK_MSG_001",
            "timestamp": chrono::Utc::now().timestamp(),
            "from": "5511988887777@c.us",
            "fromMe": false,
            "body": "Olá! Este é um teste de integração de WhatsApp disparado pelo BeautyFlow para o n8n 🌸",
            "_data": {
                "notifyName": "Cliente Teste",
                "flow": "n8n_incoming_test"
            }
        }
    });

    let resp = state
        .http_client
        .post(&url)
        .json(&payload)
        .timeout(Duration::from_secs(8))
        .send()
        .await;

    match resp {
        Ok(r) if r.status().is_success() => {
            Ok(Json(json!({ "status": "ok", "message": format!("Disparo de teste recebido com status HTTP {}!", r.status().as_u16()) })))
        }
        Ok(r) => {
            let code = r.status().as_u16();
            Err((StatusCode::BAD_GATEWAY, Json(json!({ "error": format!("O n8n respondeu com erro HTTP {}.", code) }))))
        }
        Err(e) if e.is_timeout() => {
            Err((StatusCode::GATEWAY_TIMEOUT, Json(json!({ "error": "Tempo limite de 8s excedido ao tentar conectar ao webhook." }))))
        }
        Err(e) => {
            Err((StatusCode::BAD_GATEWAY, Json(json!({ "error": format!("Falha de conexão: {}", e) }))))
        }
    }
}

async fn send_notification(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SendNotificationReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let phone = payload.phone.as_deref().unwrap_or("").trim();
    if phone.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Telefone é obrigatório" }))));
    }

    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Err((StatusCode::SERVICE_UNAVAILABLE, Json(json!({ "error": "WAHA offline ou não configurado" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let mut text_to_send = payload.message.clone().unwrap_or_default();
    if text_to_send.trim().is_empty() {
        if let Some(ref tpl_name) = payload.template {
            let def_templates = get_default_templates();
            let raw_tpl = settings.get(tpl_name).map(|s| s.as_str()).unwrap_or_else(|| def_templates.get(tpl_name.as_str()).copied().unwrap_or(""));

            let mut ctx = HashMap::new();
            ctx.insert("nome", payload.client_name.clone().unwrap_or_else(|| "Cliente".to_string()));
            ctx.insert("servico", payload.service.clone().unwrap_or_default());
            ctx.insert("data", payload.date.clone().unwrap_or_default());
            ctx.insert("horario", payload.time.clone().unwrap_or_default());
            ctx.insert("valor", format!("{:.2}", payload.price.unwrap_or(0.0)));
            ctx.insert("empresa", settings.get("company_name").cloned().unwrap_or_else(|| "BeautyFlow".to_string()));

            text_to_send = render_whatsapp_template(raw_tpl, &ctx);
        }
    }

    if text_to_send.trim().is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Mensagem ou template é obrigatório" }))));
    }

    let msg_id = send_whatsapp_text(&state, &waha_url, &api_key, &session, phone, &text_to_send)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, Json(json!({ "error": e }))))?;

    let clean_p = clean_phone(phone);
    let _ = save_simple_message(
        &state.sqlite,
        &clean_p,
        msg_id.as_deref(),
        true,
        Some(&text_to_send),
        Some(chrono::Utc::now().timestamp()),
        Some("sent"),
        None,
        payload.client_name.as_deref(),
    )
    .await;

    Ok(Json(json!({ "status": "ok", "message_id": msg_id, "sent": true })))
}

async fn test_send_message(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<TestSendReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let phone = payload.phone.as_deref().unwrap_or("").trim();
    let text = payload.text.as_deref().or(payload.message.as_deref()).unwrap_or("").trim();

    if phone.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Telefone é obrigatório" }))));
    }
    let msg = if text.is_empty() {
        "Olá! Esta é uma mensagem de teste do BeautyFlow via WhatsApp 💅✨"
    } else {
        text
    };

    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Err((StatusCode::SERVICE_UNAVAILABLE, Json(json!({ "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let res = send_whatsapp_text(&state, &waha_url, &api_key, &session, phone, msg).await;

    match res {
        Ok(msg_id) => {
            let clean_p = clean_phone(phone);
            let _ = save_simple_message(
                &state.sqlite,
                &clean_p,
                msg_id.as_deref(),
                true,
                Some(msg),
                Some(chrono::Utc::now().timestamp()),
                Some("sent"),
                None,
                None,
            )
            .await;
            Ok(Json(json!({ "status": "ok", "message": "Mensagem enviada com sucesso!", "message_id": msg_id })))
        }
        Err(e) => Err((StatusCode::BAD_GATEWAY, Json(json!({ "error": e })))),
    }
}

async fn get_whatsapp_settings(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let settings = get_settings_map(&state.pg).await;
    let def_tpl = get_default_templates();

    let mut result = serde_json::Map::new();
    for (k, v) in def_tpl {
        let val = settings.get(k).cloned().unwrap_or_else(|| v.to_string());
        result.insert(k.to_string(), Value::String(val));
    }

    result.insert("whatsapp_auto_notify_created".to_string(), Value::String(settings.get("whatsapp_auto_notify_created").cloned().unwrap_or_else(|| "true".to_string())));
    result.insert("whatsapp_auto_notify_cancelled".to_string(), Value::String(settings.get("whatsapp_auto_notify_cancelled").cloned().unwrap_or_else(|| "true".to_string())));
    result.insert("whatsapp_auto_notify_reminder".to_string(), Value::String(settings.get("whatsapp_auto_notify_reminder").cloned().unwrap_or_else(|| "true".to_string())));
    result.insert("whatsapp_reminder_hours_before".to_string(), Value::String(settings.get("whatsapp_reminder_hours_before").cloned().unwrap_or_else(|| "24".to_string())));

    Ok(Json(Value::Object(result)))
}

async fn save_whatsapp_settings(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<HashMap<String, Value>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    for (key, val) in payload {
        let val_str = match val {
            Value::String(s) => s,
            Value::Bool(b) => b.to_string(),
            Value::Number(n) => n.to_string(),
            _ => val.to_string(),
        };

        let _ = sqlx::query(
            "INSERT INTO public.settings (key, value) VALUES ($1, $2) \
             ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
        )
        .bind(&key)
        .bind(&val_str)
        .execute(&state.pg)
        .await;
    }

    Ok(Json(json!({ "status": "ok", "message": "Configurações salvas com sucesso!" })))
}

async fn send_pending_reminders(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let count = trigger_reminders_check(state.clone()).await;
    Ok(Json(json!({ "status": "ok", "sent_count": count })))
}

async fn get_chat_messages(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ChatMessagesQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let raw_phone = query
        .phone
        .as_deref()
        .or(query.chat_id.as_deref())
        .unwrap_or("")
        .trim();
    if raw_phone.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Telefone é obrigatório" }))));
    }

    let clean_p = clean_phone(raw_phone);
    if clean_p.len() < 10 {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Número de telefone inválido" }))));
    }

    let client_name = query.client_name.as_deref().unwrap_or("").to_string();
    let limit = query.limit.unwrap_or(150).clamp(1, 250);

    let settings = get_settings_map(&state.pg).await;
    let mut waha_connected = false;
    let mut session = "default".to_string();

    if let Some(waha_url) = get_working_waha_url(&state, &settings).await {
        let api_key = get_api_key(&state, &settings);
        session = get_session_name(&state, &waha_url, &settings).await;

        let check_res = state
            .http_client
            .get(format!("{}/api/sessions/{}", waha_url, session))
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(3))
            .send()
            .await;

        if let Ok(r) = check_res {
            if r.status().is_success() {
                if let Ok(sess_data) = r.json::<Value>().await {
                    if sess_data.get("status").and_then(|v| v.as_str()) == Some("WORKING") {
                        waha_connected = true;
                    }
                }
            }
        }
    }

    let do_sync = query
        .sync
        .as_deref()
        .map(|s| s == "true" || s == "1" || s == "yes")
        .unwrap_or(true);

    if do_sync && waha_connected {
        let state_clone = state.clone();
        let phone_clone = clean_p.clone();
        tokio::spawn(async move {
            sync_waha_messages_for_chat(&state_clone, &phone_clone, None, 40).await;
        });
    }

    let msgs = get_messages(&state.sqlite, &clean_p, limit, 0).await;
    let chat_id = crate::db::chat_db::to_chat_id(&clean_p);

    Ok(Json(json!({
        "chat_id": chat_id,
        "phone": clean_p,
        "client_name": client_name,
        "messages": msgs,
        "waha_connected": waha_connected,
        "waha_session": session
    })))
}

async fn chat_send(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<ChatSendReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let raw_phone = payload
        .phone
        .as_deref()
        .or(payload.chat_id.as_deref())
        .unwrap_or("")
        .trim();
    let text = payload.text.as_deref().or(payload.message.as_deref()).unwrap_or("").trim();
    let client_name = payload.client_name.as_deref().unwrap_or("").trim();

    if raw_phone.is_empty() || text.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Telefone e mensagem são obrigatórios" }))));
    }

    let clean_p = clean_phone(raw_phone);
    if clean_p.len() < 10 {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Número de telefone inválido" }))));
    }

    let settings = get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return Err((StatusCode::SERVICE_UNAVAILABLE, Json(json!({ "error": "WAHA offline" })))),
    };
    let api_key = get_api_key(&state, &settings);
    let session = get_session_name(&state, &waha_url, &settings).await;

    let msg_id = send_whatsapp_text(&state, &waha_url, &api_key, &session, &clean_p, text)
        .await
        .map_err(|e| (StatusCode::BAD_GATEWAY, Json(json!({ "error": e }))))?;

    let now_ts = chrono::Utc::now().timestamp();
    let saved = save_simple_message(
        &state.sqlite,
        &clean_p,
        msg_id.as_deref(),
        true,
        Some(text),
        Some(now_ts),
        Some("sent"),
        None,
        if client_name.is_empty() { None } else { Some(client_name) },
    )
    .await;

    let chat_id = crate::db::chat_db::to_chat_id(&clean_p);
    let msg_obj = json!({
        "id": saved.as_ref().map(|s| s.id).unwrap_or(0),
        "chat_id": chat_id,
        "phone": clean_p,
        "content": text,
        "from_me": true,
        "message_type": "outgoing",
        "sender_type": "agent",
        "waha_message_id": msg_id,
        "status": "sent",
        "timestamp": now_ts,
    });

    let _ = state.io.emit("whatsapp:new_message", &msg_obj).await;
    let _ = state.io.emit("whatsapp:message", &msg_obj).await;

    Ok(Json(json!({
        "success": true,
        "status": "ok",
        "message": msg_obj
    })))
}

async fn chat_sync(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<SyncReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let raw_phone = payload.phone.as_deref().unwrap_or("").trim();
    if raw_phone.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({ "error": "Telefone é obrigatório" }))));
    }

    let clean_p = clean_phone(raw_phone);
    let synced = sync_waha_messages_for_chat(&state, &clean_p, None, 50).await;
    Ok(Json(json!({ "success": true, "status": "ok", "synced_count": synced })))
}


async fn get_chat_canned_responses(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let responses = get_canned_responses(&state.sqlite).await;
    Ok(Json(json!(responses)))
}

async fn get_chat_conversations(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let convs = get_conversations(&state.sqlite, 50).await;
    Ok(Json(json!(convs)))
}

async fn receive_webhook(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let event = payload.get("event").and_then(|v| v.as_str()).unwrap_or("");

    if event == "message" || payload.get("payload").is_some() || payload.get("data").is_some() {
        let data = payload.get("payload").or_else(|| payload.get("data")).unwrap_or(&payload);

        let from_raw = data.get("from").and_then(|v| v.as_str()).unwrap_or("");
        let body = data.get("body").and_then(|v| v.as_str()).unwrap_or("");
        let from_me = data.get("fromMe").and_then(|v| v.as_bool()).unwrap_or(false);
        let msg_id = data.get("id").and_then(|v| {
            if let Some(s) = v.as_str() {
                Some(s.to_string())
            } else if let Some(ser) = v.get("_serialized").and_then(|x| x.as_str()) {
                Some(ser.to_string())
            } else {
                v.get("id").and_then(|x| x.as_str()).map(|s| s.to_string())
            }
        }).unwrap_or_default();

        let ts = data.get("timestamp").and_then(|v| v.as_i64()).unwrap_or_else(|| chrono::Utc::now().timestamp());
        let sender_name = data.get("_data").and_then(|d| d.get("notifyName")).and_then(|v| v.as_str());

        if !from_raw.is_empty() && !body.is_empty() {
            let clean_p = clean_phone(from_raw);
            let saved = save_simple_message(
                &state.sqlite,
                &clean_p,
                if msg_id.is_empty() { None } else { Some(&msg_id) },
                from_me,
                Some(body),
                Some(ts),
                Some("received"),
                None,
                sender_name,
            )
            .await;

            let emit_obj = json!({
                "id": saved.as_ref().map(|s| s.id).unwrap_or(0),
                "phone": clean_p,
                "message_id": msg_id,
                "from_me": from_me,
                "text": body,
                "timestamp": ts,
                "sender_name": sender_name,
            });

            let _ = state.io.emit("whatsapp:new_message", &emit_obj).await;
            let _ = state.io.emit("whatsapp:message", &emit_obj).await;
        }

        // Forward to n8n if n8n webhook URL is configured
        let settings = get_settings_map(&state.pg).await;
        let n8n_url = settings.get("n8n_whatsapp_webhook_url").cloned().unwrap_or_default();
        if !n8n_url.trim().is_empty() {
            let client = state.http_client.clone();
            let payload_clone = payload.clone();
            tokio::spawn(async move {
                let _ = client
                    .post(&n8n_url)
                    .json(&payload_clone)
                    .timeout(Duration::from_secs(5))
                    .send()
                    .await;
            });
        }
    } else if event == "session.status" {
        let _ = state.io.emit("whatsapp:status", &payload).await;
    }

    Ok(Json(json!({ "status": "ok" })))
}
