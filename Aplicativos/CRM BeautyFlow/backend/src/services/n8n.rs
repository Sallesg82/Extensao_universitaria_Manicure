use crate::db::SharedState;
use chrono::{Duration, NaiveDate, NaiveDateTime, NaiveTime};
use serde_json::json;
use tracing::warn;

pub const N8N_FALLBACK: &str = "https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook";

pub fn compute_iso_datetimes(date_str: &str, time_str: &str, duration_mins: i32) -> (String, String) {
    let tz = "-03:00";
    let t_clean = if time_str.len() >= 5 { &time_str[..5] } else { time_str };

    let naive_date = NaiveDate::parse_from_str(date_str, "%Y-%m-%d").unwrap_or_default();
    let naive_time = NaiveTime::parse_from_str(t_clean, "%H:%M").unwrap_or_else(|_| NaiveTime::from_hms_opt(12, 0, 0).unwrap());
    let start_dt = NaiveDateTime::new(naive_date, naive_time);
    let end_dt = start_dt + Duration::minutes(duration_mins as i64);

    let start_iso = format!("{}{}", start_dt.format("%Y-%m-%dT%H:%M:%S"), tz);
    let end_iso = format!("{}{}", end_dt.format("%Y-%m-%dT%H:%M:%S"), tz);
    (start_iso, end_iso)
}

pub fn fire_n8n_appointment(
    state: SharedState,
    appt_id: i32,
    client_name: &str,
    client_phone: &str,
    service: &str,
    price: f32,
    status: &str,
    date: &str,
    time: &str,
    duration: i32,
    action: &str,
) {
    let client = state.http_client.clone();
    let client_name = client_name.to_string();
    let client_phone = client_phone.to_string();
    let service = service.to_string();
    let status = status.to_string();
    let date = date.to_string();
    let time = time.to_string();
    let action = action.to_string();

    tokio::spawn(async move {
        let settings = crate::routes::settings::get_settings_map(&state.pg).await;
        let enabled = settings.get("n8n_enabled").map(|v| v.as_str()).unwrap_or("true") == "true";
        if !enabled {
            return;
        }

        let events_str = settings.get("n8n_events").map(|v| v.as_str()).unwrap_or("create,update,delete");
        let events: Vec<&str> = events_str.split(',').map(|s| s.trim()).collect();
        if !events.contains(&action.as_str()) {
            return;
        }

        let custom_url = settings.get("n8n_webhook_url").map(|v| v.trim()).unwrap_or("");
        let url = if !custom_url.is_empty() {
            custom_url
        } else if !state.config.n8n_webhook_url.trim().is_empty() {
            &state.config.n8n_webhook_url
        } else {
            N8N_FALLBACK
        };

        let timeout_secs: u64 = settings
            .get("n8n_timeout")
            .and_then(|v| v.parse().ok())
            .unwrap_or(8);

        let (start_iso, end_iso) = compute_iso_datetimes(&date, &time, duration);

        let payload = json!({
            "action": action,
            "appointment_id": appt_id,
            "client_name": client_name,
            "client_phone": client_phone,
            "service": service,
            "price": price,
            "status": status,
            "start_datetime": start_iso,
            "end_datetime": end_iso
        });

        let mut req = client.post(url).json(&payload).timeout(std::time::Duration::from_secs(timeout_secs));

        if let (Some(h_name), Some(h_val)) = (settings.get("n8n_header_name"), settings.get("n8n_header_value")) {
            let n = h_name.trim();
            let v = h_val.trim();
            if !n.is_empty() && !v.is_empty() {
                req = req.header(n, v);
            }
        }

        if let Err(e) = req.send().await {
            warn!("[n8n] Falha ao disparar webhook para {}: {}", url, e);
        }
    });
}
