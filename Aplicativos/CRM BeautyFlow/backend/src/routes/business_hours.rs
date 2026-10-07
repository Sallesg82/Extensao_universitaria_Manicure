use crate::db::SharedState;
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::{Datelike, NaiveDate, NaiveTime, Timelike};
use chrono_tz::America::Sao_Paulo;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashMap;

pub const DAYS_PT: [&str; 7] = ["segunda", "terca", "quarta", "quinta", "sexta", "sabado", "domingo"];

pub async fn load_business_hours(pool: &sqlx::PgPool) -> HashMap<String, Value> {
    let mut map = HashMap::new();
    let rows = sqlx::query("SELECT day, open, close, closed FROM business_hours")
        .fetch_all(pool)
        .await
        .unwrap_or_default();

    for r in rows {
        let day: String = r.get("day");
        let open: String = r.get("open");
        let close: String = r.get("close");
        let closed: bool = r.get("closed");
        map.insert(
            day,
            json!({
                "open": open,
                "close": close,
                "closed": closed
            }),
        );
    }

    if map.is_empty() {
        let defaults = [
            ("segunda", "08:00", "18:00", false),
            ("terca", "08:00", "18:00", false),
            ("quarta", "08:00", "18:00", false),
            ("quinta", "08:00", "18:00", false),
            ("sexta", "08:00", "18:00", false),
            ("sabado", "08:00", "13:00", false),
            ("domingo", "", "", true),
        ];
        for (d, op, cl, cls) in defaults {
            map.insert(
                d.to_string(),
                json!({
                    "open": op,
                    "close": cl,
                    "closed": cls
                }),
            );
        }
    }
    map
}

pub async fn get_business_hours(State(state): State<SharedState>) -> impl IntoResponse {
    let hours = load_business_hours(&state.pg).await;
    Json(hours)
}

pub async fn put_business_hours(
    State(state): State<SharedState>,
    Json(body): Json<HashMap<String, Value>>,
) -> impl IntoResponse {
    for (day_key, info) in body {
        let open = info.get("open").and_then(|v| v.as_str()).unwrap_or("");
        let close = info.get("close").and_then(|v| v.as_str()).unwrap_or("");
        let closed = info.get("closed").and_then(|v| v.as_bool()).unwrap_or(false);

        let _ = sqlx::query(
            r#"
            INSERT INTO business_hours (day, open, close, closed, updated_at)
            VALUES ($1, $2, $3, $4, now())
            ON CONFLICT (day) DO UPDATE SET
                open = EXCLUDED.open,
                close = EXCLUDED.close,
                closed = EXCLUDED.closed,
                updated_at = now()
            "#,
        )
        .bind(&day_key)
        .bind(open)
        .bind(close)
        .bind(closed)
        .execute(&state.pg)
        .await;
    }

    let _ = state.io.emit("data:changed", &json!({"type": "business_hours", "action": "updated"}));

    Json(json!({"status": "ok"}))
}

pub async fn validate_appointment_hours(
    pool: &sqlx::PgPool,
    appointment_date: &str,
    appointment_time: &str,
    duration: i32,
    buffer: i32,
) -> Option<String> {
    let dt = match NaiveDate::parse_from_str(appointment_date, "%Y-%m-%d") {
        Ok(d) => d,
        Err(_) => return Some("Data inválida".to_string()),
    };

    let parts: Vec<&str> = appointment_time.split(':').collect();
    if parts.len() < 2 {
        return Some("Horário inválido".to_string());
    }
    let h: i32 = match parts[0].parse() {
        Ok(v) => v,
        Err(_) => return Some("Horário inválido".to_string()),
    };
    let m: i32 = match parts[1].parse() {
        Ok(v) => v,
        Err(_) => return Some("Horário inválido".to_string()),
    };
    let appt_min = h * 60 + m;

    let dow = dt.weekday().num_days_from_monday() as usize;
    let day_key = DAYS_PT[dow];

    let hours = load_business_hours(pool).await;
    let day_hours = match hours.get(day_key) {
        Some(v) => v,
        None => return Some("Horário não configurado para este dia".to_string()),
    };

    let closed = day_hours.get("closed").and_then(|v| v.as_bool()).unwrap_or(false);
    if closed {
        return Some("Fechado neste dia".to_string());
    }

    let open_str = day_hours.get("open").and_then(|v| v.as_str()).unwrap_or("08:00");
    let close_str = day_hours.get("close").and_then(|v| v.as_str()).unwrap_or("18:00");

    let open_parts: Vec<&str> = open_str.split(':').collect();
    let close_parts: Vec<&str> = close_str.split(':').collect();
    if open_parts.len() < 2 || close_parts.len() < 2 {
        return Some("Horário de funcionamento inválido".to_string());
    }

    let open_min: i32 = open_parts[0].parse().unwrap_or(0) * 60 + open_parts[1].parse().unwrap_or(0);
    let close_min: i32 = close_parts[0].parse().unwrap_or(0) * 60 + close_parts[1].parse().unwrap_or(0);

    if appt_min < open_min {
        return Some(format!(
            "O horário de funcionamento neste dia é {} às {}. O agendamento deve começar após {}.",
            open_str, close_str, open_str
        ));
    }

    let total = appt_min + duration + buffer;
    if total > close_min {
        return Some(format!(
            "O horário de funcionamento neste dia é {} às {}. O serviço termina após o fechamento.",
            open_str, close_str
        ));
    }

    None
}

#[derive(Deserialize)]
pub struct AvailableSlotsQuery {
    pub date: Option<String>,
    pub duration: Option<i32>,
    pub buffer: Option<i32>,
}

pub async fn get_available_slots(
    State(state): State<SharedState>,
    Query(params): Query<AvailableSlotsQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let date_str = match &params.date {
        Some(d) if !d.is_empty() => d.clone(),
        _ => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "Parâmetro \"date\" é obrigatório (YYYY-MM-DD)"})),
            ))
        }
    };

    let duration = params.duration.unwrap_or(60);
    let buffer = params.buffer.unwrap_or(0);
    let total = duration + buffer;

    let dt = match NaiveDate::parse_from_str(&date_str, "%Y-%m-%d") {
        Ok(d) => d,
        Err(_) => {
            return Err((
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "Formato de data inválido. Use YYYY-MM-DD"})),
            ))
        }
    };

    let dow = dt.weekday().num_days_from_monday() as usize;
    let day_key = DAYS_PT[dow];

    let hours = load_business_hours(&state.pg).await;
    let day_hours = hours.get(day_key).cloned().unwrap_or(json!({}));

    let closed = day_hours.get("closed").and_then(|v| v.as_bool()).unwrap_or(false);
    if closed {
        return Ok(Json(json!({
            "date": date_str,
            "day": day_key,
            "duration": duration,
            "buffer": buffer,
            "closed": true,
            "slots": [],
            "message": "Fechado neste dia"
        })));
    }

    let open_str = day_hours.get("open").and_then(|v| v.as_str()).unwrap_or("08:00");
    let close_str = day_hours.get("close").and_then(|v| v.as_str()).unwrap_or("18:00");

    let open_parts: Vec<&str> = open_str.split(':').collect();
    let close_parts: Vec<&str> = close_str.split(':').collect();
    let open_min = open_parts.first().and_then(|h| h.parse::<i32>().ok()).unwrap_or(8) * 60
        + open_parts.get(1).and_then(|m| m.parse::<i32>().ok()).unwrap_or(0);
    let close_min = close_parts.first().and_then(|h| h.parse::<i32>().ok()).unwrap_or(18) * 60
        + close_parts.get(1).and_then(|m| m.parse::<i32>().ok()).unwrap_or(0);

    // Get services buffers
    let svc_rows = sqlx::query("SELECT name, buffer FROM services")
        .fetch_all(&state.pg)
        .await
        .unwrap_or_default();
    let mut svc_buffers: HashMap<String, i32> = HashMap::new();
    for r in svc_rows {
        let name: String = r.get("name");
        let buf: i32 = r.get("buffer");
        svc_buffers.insert(name, buf);
    }

    // Get existing appointments
    let appt_rows = sqlx::query(
        "SELECT appointment_time, duration, service FROM appointments WHERE appointment_date = $1 AND status != 'cancelled'",
    )
    .bind(dt)
    .fetch_all(&state.pg)
    .await
    .unwrap_or_default();

    struct Occupied {
        start: i32,
        end: i32,
    }
    let mut occupied: Vec<Occupied> = Vec::new();

    for r in appt_rows {
        let t: NaiveTime = r.get("appointment_time");
        let start = (t.hour() as i32) * 60 + (t.minute() as i32);
        let dur: i32 = r.get::<Option<i32>, _>("duration").unwrap_or(60);
        let svc_name: String = r.get::<Option<String>, _>("service").unwrap_or_default();
        let svc_buf = svc_buffers.get(&svc_name).copied().unwrap_or(0);
        occupied.push(Occupied {
            start,
            end: start + dur + svc_buf,
        });
    }

    let now_local = chrono::Utc::now().with_timezone(&Sao_Paulo);
    let today_str = now_local.format("%Y-%m-%d").to_string();
    let current_min = (now_local.hour() as i32) * 60 + (now_local.minute() as i32);

    let slot_step = 30;
    let mut slots = Vec::new();
    let mut slot_start = open_min;

    while slot_start + total <= close_min {
        if date_str == today_str && slot_start <= current_min {
            slot_start += slot_step;
            continue;
        }

        let slot_end = slot_start + total;
        let conflict = occupied.iter().any(|occ| slot_start < occ.end && slot_end > occ.start);

        if !conflict {
            let h = slot_start / 60;
            let m = slot_start % 60;
            slots.push(format!("{:02}:{:02}", h, m));
        }

        slot_start += slot_step;
    }

    Ok(Json(json!({
        "date": date_str,
        "day": day_key,
        "duration": duration,
        "buffer": buffer,
        "closed": false,
        "open": open_str,
        "close": close_str,
        "slots": slots
    })))
}

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/business-hours", get(get_business_hours).put(put_business_hours))
        .route("/available-slots", get(get_available_slots))
}
