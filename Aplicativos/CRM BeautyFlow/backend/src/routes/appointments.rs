use crate::db::schema::sync_appointment_income;
use crate::db::SharedState;
use crate::routes::business_hours::validate_appointment_hours;
use crate::services::n8n::fire_n8n_appointment;
use crate::services::waha::{
    get_api_key, get_default_templates, get_session_name, get_working_waha_url,
    render_whatsapp_template, send_whatsapp_text,
};
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::{NaiveDate, NaiveTime, Timelike};
use regex::Regex;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashMap;

#[derive(Deserialize)]
pub struct ListAppointmentsQuery {
    pub date: Option<String>,
    pub client_id: Option<i32>,
    pub status: Option<String>,
    pub date_from: Option<String>,
    pub date_to: Option<String>,
}

fn fmt_time(t: NaiveTime) -> String {
    t.format("%H:%M").to_string()
}

pub async fn list_appointments(
    State(state): State<SharedState>,
    Query(params): Query<ListAppointmentsQuery>,
) -> impl IntoResponse {
    let mut sql = String::from(
        r#"
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a
        LEFT JOIN clients c ON c.id = a.client_id
        WHERE 1=1
        "#,
    );

    let mut conditions = Vec::new();
    let mut binds: Vec<String> = Vec::new();

    if let Some(d) = &params.date {
        binds.push(d.clone());
        conditions.push(format!("a.appointment_date = ${}", binds.len()));
    }
    if let Some(df) = &params.date_from {
        binds.push(df.clone());
        conditions.push(format!("a.appointment_date >= ${}", binds.len()));
    }
    if let Some(dt) = &params.date_to {
        binds.push(dt.clone());
        conditions.push(format!("a.appointment_date <= ${}", binds.len()));
    }
    if let Some(cid) = params.client_id {
        binds.push(cid.to_string());
        conditions.push(format!("a.client_id = ${}", binds.len()));
    }
    if let Some(st) = &params.status {
        binds.push(st.clone());
        conditions.push(format!("a.status = ${}", binds.len()));
    }

    if !conditions.is_empty() {
        sql.push_str(" AND ");
        sql.push_str(&conditions.join(" AND "));
    }
    sql.push_str(" ORDER BY a.appointment_date, a.appointment_time");

    let mut q = sqlx::query(sqlx::AssertSqlSafe(sql.as_str()));
    for b in &binds {
        if let Ok(num) = b.parse::<i32>() {
            q = q.bind(num);
        } else if let Ok(nd) = NaiveDate::parse_from_str(b, "%Y-%m-%d") {
            q = q.bind(nd);
        } else {
            q = q.bind(b);
        }
    }

    let rows = q.fetch_all(&state.pg).await.unwrap_or_default();
    let mut list = Vec::new();

    for r in rows {
        let id: i32 = r.get("id");
        let client_id: Option<i32> = r.get("client_id");
        let client_name = match r.get::<Option<String>, _>("client_name") {
            Some(n) => n,
            None if client_id.is_none() => "(Cliente removido)".to_string(),
            None => "".to_string(),
        };
        let client_phone = r.get::<Option<String>, _>("client_phone").unwrap_or_default();
        let service: String = r.get("service");
        let appt_date: NaiveDate = r.get("appointment_date");
        let appt_time: NaiveTime = r.get("appointment_time");
        let status: String = r.get("status");
        let payment_status: String = r.get::<Option<String>, _>("payment_status").unwrap_or_else(|| "unpaid".to_string());
        let price: f32 = r.get("price");
        let duration: i32 = r.get::<Option<i32>, _>("duration").unwrap_or(60);
        let notes: String = r.get::<Option<String>, _>("notes").unwrap_or_default();
        let created_at: Option<chrono::DateTime<chrono::Utc>> = r.get("created_at");
        let updated_at: Option<chrono::DateTime<chrono::Utc>> = r.get("updated_at");

        list.push(json!({
            "id": id,
            "client_id": client_id,
            "client_name": client_name,
            "client_phone": client_phone,
            "service": service,
            "appointment_date": appt_date.to_string(),
            "appointment_time": fmt_time(appt_time),
            "status": status,
            "payment_status": payment_status,
            "price": price,
            "duration": duration,
            "notes": notes,
            "created_at": created_at.map(|t| t.to_rfc3339()),
            "updated_at": updated_at.map(|t| t.to_rfc3339()),
        }));
    }

    Json(list)
}

pub async fn fetch_appointment_value(pool: &sqlx::PgPool, appt_id: i32) -> Option<Value> {
    let row = sqlx::query(
        r#"
        SELECT a.*, c.name as client_name, c.phone as client_phone
        FROM appointments a
        LEFT JOIN clients c ON c.id = a.client_id
        WHERE a.id = $1
        "#,
    )
    .bind(appt_id)
    .fetch_optional(pool)
    .await
    .unwrap_or(None)?;

    let client_id: Option<i32> = row.get("client_id");
    let client_name = match row.get::<Option<String>, _>("client_name") {
        Some(n) => n,
        None if client_id.is_none() => "(Cliente removido)".to_string(),
        None => "".to_string(),
    };
    let appt_date: NaiveDate = row.get("appointment_date");
    let appt_time: NaiveTime = row.get("appointment_time");

    Some(json!({
        "id": appt_id,
        "client_id": client_id,
        "client_name": client_name,
        "client_phone": row.get::<Option<String>, _>("client_phone").unwrap_or_default(),
        "service": row.get::<String, _>("service"),
        "appointment_date": appt_date.to_string(),
        "appointment_time": fmt_time(appt_time),
        "status": row.get::<String, _>("status"),
        "payment_status": row.get::<Option<String>, _>("payment_status").unwrap_or_else(|| "unpaid".to_string()),
        "price": row.get::<f32, _>("price"),
        "duration": row.get::<Option<i32>, _>("duration").unwrap_or(60),
        "notes": row.get::<Option<String>, _>("notes").unwrap_or_default(),
        "created_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
        "updated_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at").map(|t| t.to_rfc3339()),
    }))
}

pub async fn get_appointment_by_id(
    State(state): State<SharedState>,
    Path(appt_id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    match fetch_appointment_value(&state.pg, appt_id).await {
        Some(v) => Ok(Json(v)),
        None => Err((StatusCode::NOT_FOUND, Json(json!({"error": "Agendamento não encontrado"})))),
    }
}

pub async fn create_appointment(
    State(state): State<SharedState>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let mut errors = Vec::new();
    let client_id = body.get("client_id").and_then(|v| v.as_i64()).map(|v| v as i32);
    if client_id.is_none() {
        errors.push("ID do cliente é obrigatório");
    }

    let service = body.get("service").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    if service.len() < 2 {
        errors.push("Nome do serviço é obrigatório");
    }

    let date_str = body.get("appointment_date").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let re_date = Regex::new(r"^\d{4}-\d{2}-\d{2}$").unwrap();
    if !re_date.is_match(&date_str) {
        errors.push("Data deve estar no formato YYYY-MM-DD");
    }

    let time_str = body.get("appointment_time").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let re_time = Regex::new(r"^\d{2}:\d{2}$").unwrap();
    if !re_time.is_match(&time_str) {
        errors.push("Hora deve estar no formato HH:MM");
    }

    let price_val = body.get("price").and_then(|v| {
        if let Some(f) = v.as_f64() {
            Some(f as f32)
        } else if let Some(s) = v.as_str() {
            s.parse::<f32>().ok()
        } else {
            None
        }
    });

    if let Some(p) = price_val {
        if p < 0.0 {
            errors.push("Preço deve ser positivo");
        }
    } else {
        errors.push("Preço é obrigatório");
    }

    if !errors.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "Dados inválidos", "details": errors})),
        ));
    }

    let client_id = client_id.unwrap();
    let client_row = sqlx::query("SELECT name, phone FROM clients WHERE id = $1")
        .bind(client_id)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    let (client_name, client_phone) = match client_row {
        Some(r) => (r.get::<String, _>("name"), r.get::<String, _>("phone")),
        None => return Err((StatusCode::BAD_REQUEST, Json(json!({"error": "Cliente não encontrado"})))),
    };

    let duration: i32 = body.get("duration").and_then(|v| v.as_i64()).unwrap_or(60) as i32;
    let svc_buf_row = sqlx::query("SELECT buffer FROM services WHERE name = $1")
        .bind(&service)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);
    let svc_buffer = svc_buf_row.map(|r| r.get::<i32, _>("buffer")).unwrap_or(0);

    if let Some(hours_err) = validate_appointment_hours(&state.pg, &date_str, &time_str, duration, svc_buffer).await {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({"error": format!("Horário fora do funcionamento: {}", hours_err)})),
        ));
    }

    let parsed_date = NaiveDate::parse_from_str(&date_str, "%Y-%m-%d").unwrap();
    let parsed_time = NaiveTime::parse_from_str(&time_str, "%H:%M").unwrap();

    let new_start = (parsed_time.hour() as i32) * 60 + (parsed_time.minute() as i32);
    let new_end = new_start + duration + svc_buffer;

    let existing_appts = sqlx::query(
        "SELECT a.appointment_time, a.duration, a.service, s.buffer FROM appointments a LEFT JOIN services s ON s.name = a.service WHERE a.appointment_date = $1 AND a.status != 'cancelled'",
    )
    .bind(parsed_date)
    .fetch_all(&state.pg)
    .await
    .unwrap_or_default();

    for ea in existing_appts {
        let ea_t: NaiveTime = ea.get("appointment_time");
        let ea_start = (ea_t.hour() as i32) * 60 + (ea_t.minute() as i32);
        let ea_dur: i32 = ea.get::<Option<i32>, _>("duration").unwrap_or(60);
        let ea_buf: i32 = ea.get::<Option<i32>, _>("buffer").unwrap_or(0);
        let ea_end = ea_start + ea_dur + ea_buf;

        if new_start < ea_end && new_end > ea_start {
            return Err((
                StatusCode::CONFLICT,
                Json(json!({
                    "error": "Este horário já está reservado por outro cliente. Por favor, escolha outro horário."
                })),
            ));
        }
    }

    let status = body.get("status").and_then(|v| v.as_str()).unwrap_or("pending").to_string();
    let payment_status = body.get("payment_status").and_then(|v| v.as_str()).unwrap_or("unpaid").to_string();
    let price = price_val.unwrap();
    let notes = body.get("notes").and_then(|v| v.as_str()).unwrap_or("").to_string();

    let row = sqlx::query(
        r#"
        INSERT INTO appointments (client_id, service, appointment_date, appointment_time, status, payment_status, price, duration, notes, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now(), now())
        RETURNING *
        "#,
    )
    .bind(client_id)
    .bind(&service)
    .bind(parsed_date)
    .bind(parsed_time)
    .bind(&status)
    .bind(&payment_status)
    .bind(price)
    .bind(duration)
    .bind(&notes)
    .fetch_one(&state.pg)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    let appt_id: i32 = row.get("id");
    let result = json!({
        "id": appt_id,
        "client_id": client_id,
        "client_name": client_name,
        "client_phone": client_phone,
        "service": service,
        "appointment_date": date_str,
        "appointment_time": time_str,
        "status": status,
        "payment_status": payment_status,
        "price": price,
        "duration": duration,
        "notes": notes,
        "created_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
        "updated_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at").map(|t| t.to_rfc3339()),
    });

    // Fire n8n
    fire_n8n_appointment(
        state.clone(),
        appt_id,
        &client_name,
        &client_phone,
        &service,
        price,
        &status,
        &date_str,
        &time_str,
        duration,
        "create",
    );

    // Send WhatsApp notification
    let state_wa = state.clone();
    let wa_phone = client_phone.clone();
    let wa_name = client_name.clone();
    let wa_svc = service.clone();
    let wa_date = date_str.clone();
    let wa_time = time_str.clone();
    tokio::spawn(async move {
        let settings = crate::routes::settings::get_settings_map(&state_wa.pg).await;
        if settings.get("whatsapp_auto_notify_created").map(|s| s.as_str()).unwrap_or("true") == "true" {
            if let Some(waha_url) = get_working_waha_url(&state_wa, &settings).await {
                let session = get_session_name(&state_wa, &waha_url, &settings).await;
                let api_key = get_api_key(&state_wa, &settings);
                let empresa = settings.get("company_name").or_else(|| settings.get("studio_name")).cloned().unwrap_or_else(|| "BeautyFlow".to_string());
                let first_name = wa_name.split_whitespace().next().unwrap_or("Cliente").to_string();
                let parts: Vec<&str> = wa_date.split('-').collect();
                let date_fmt = if parts.len() == 3 { format!("{}/{}/{}", parts[2], parts[1], parts[0]) } else { wa_date.clone() };

                let def_tmpls = get_default_templates();
                let tmpl = settings.get("whatsapp_template_created").map(|s| s.as_str()).unwrap_or_else(|| def_tmpls.get("whatsapp_template_created").unwrap());

                let mut ctx = HashMap::new();
                ctx.insert("nome", wa_name.clone());
                ctx.insert("primeiro_nome", first_name);
                ctx.insert("servico", wa_svc.clone());
                ctx.insert("data", date_fmt);
                ctx.insert("horario", wa_time);
                ctx.insert("valor", format!("{:.2}", price).replace('.', ","));
                ctx.insert("empresa", empresa);

                let text = render_whatsapp_template(tmpl, &ctx);
                let _ = send_whatsapp_text(&state_wa, &waha_url, &api_key, &session, &wa_phone, &text).await;
            }
        }

        let notif_enabled = settings.get("notify_confirmacao_de_agendamento").map(|s| s.as_str()).unwrap_or("false") == "true";
        if notif_enabled {
            let notif_msg = format!("{} - {} em {} às {}", wa_name, wa_svc, wa_date, time_str);
            let _ = sqlx::query(
                "INSERT INTO notifications (type, title, message, related_id, related_type, read) VALUES ('appointment_created', 'Novo Agendamento', $1, $2, 'appointment', false)"
            )
            .bind(&notif_msg)
            .bind(appt_id)
            .execute(&state_wa.pg)
            .await;
        }
    });

    let _ = state.io.emit("appointment:created", &result);
    let _ = state.io.emit("data:changed", &json!({"type": "appointment", "action": "created"}));

    Ok((StatusCode::CREATED, Json(result)))
}

pub async fn update_appointment(
    State(state): State<SharedState>,
    Path(appt_id): Path<i32>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let existing_opt = sqlx::query("SELECT * FROM appointments WHERE id = $1")
        .bind(appt_id)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    let existing = match existing_opt {
        Some(e) => e,
        None => return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Agendamento não encontrado"})))),
    };

    if let Some(ps) = body.get("payment_status").and_then(|v| v.as_str()) {
        if ps != "paid" && ps != "unpaid" {
            return Err((StatusCode::BAD_REQUEST, Json(json!({"error": "Status de pagamento inválido"}))));
        }
    }

    let cur_date: NaiveDate = existing.get("appointment_date");
    let cur_time: NaiveTime = existing.get("appointment_time");
    let cur_dur: i32 = existing.get::<Option<i32>, _>("duration").unwrap_or(60);
    let cur_svc: String = existing.get("service");

    let check_date = body.get("appointment_date").and_then(|v| v.as_str()).unwrap_or(&cur_date.to_string()).to_string();
    let check_time = body.get("appointment_time").and_then(|v| v.as_str()).unwrap_or(&fmt_time(cur_time)).to_string();
    let check_dur = body.get("duration").and_then(|v| v.as_i64()).map(|d| d as i32).unwrap_or(cur_dur);
    let check_svc = body.get("service").and_then(|v| v.as_str()).unwrap_or(&cur_svc).to_string();

    let svc_buf_row = sqlx::query("SELECT buffer FROM services WHERE name = $1")
        .bind(&check_svc)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);
    let svc_buf = svc_buf_row.map(|r| r.get::<i32, _>("buffer")).unwrap_or(0);

    if let Some(err) = validate_appointment_hours(&state.pg, &check_date, &check_time, check_dur, svc_buf).await {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({"error": format!("Horário fora do funcionamento: {}", err)})),
        ));
    }

    if let Value::Object(map) = &body {
        for (k, v) in map {
            match k.as_str() {
                "client_id" => {
                    if let Some(cid) = v.as_i64() {
                        let _ = sqlx::query("UPDATE appointments SET client_id = $1, updated_at = now() WHERE id = $2")
                            .bind(cid as i32).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "service" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE appointments SET service = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "appointment_date" => {
                    if let Some(s) = v.as_str() {
                        if let Ok(d) = NaiveDate::parse_from_str(s, "%Y-%m-%d") {
                            let _ = sqlx::query("UPDATE appointments SET appointment_date = $1, updated_at = now() WHERE id = $2")
                                .bind(d).bind(appt_id).execute(&state.pg).await;
                        }
                    }
                }
                "appointment_time" => {
                    if let Some(s) = v.as_str() {
                        if let Ok(t) = NaiveTime::parse_from_str(s, "%H:%M") {
                            let _ = sqlx::query("UPDATE appointments SET appointment_time = $1, updated_at = now() WHERE id = $2")
                                .bind(t).bind(appt_id).execute(&state.pg).await;
                        }
                    }
                }
                "status" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE appointments SET status = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "payment_status" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE appointments SET payment_status = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "price" => {
                    let p = if let Some(f) = v.as_f64() { Some(f as f32) } else if let Some(s) = v.as_str() { s.parse::<f32>().ok() } else { None };
                    if let Some(val) = p {
                        let _ = sqlx::query("UPDATE appointments SET price = $1, updated_at = now() WHERE id = $2")
                            .bind(val).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "duration" => {
                    if let Some(d) = v.as_i64() {
                        let _ = sqlx::query("UPDATE appointments SET duration = $1, updated_at = now() WHERE id = $2")
                            .bind(d as i32).bind(appt_id).execute(&state.pg).await;
                    }
                }
                "notes" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE appointments SET notes = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(appt_id).execute(&state.pg).await;
                    }
                }
                _ => {}
            }
        }
    }

    let _ = sync_appointment_income(&state.pg, appt_id).await;

    let updated_val = fetch_appointment_value(&state.pg, appt_id).await.unwrap_or_else(|| json!({}));

    let status = body.get("status").and_then(|v| v.as_str()).unwrap_or("");
    let is_cancelled = status == "cancelled";

    let state_n8n = state.clone();
    let client_name = updated_val.get("client_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let client_phone = updated_val.get("client_phone").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let service = updated_val.get("service").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let price = updated_val.get("price").and_then(|v| v.as_f64()).unwrap_or(0.0) as f32;
    let date = updated_val.get("appointment_date").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let time = updated_val.get("appointment_time").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let dur = updated_val.get("duration").and_then(|v| v.as_i64()).unwrap_or(60) as i32;

    if is_cancelled {
        fire_n8n_appointment(
            state_n8n.clone(),
            appt_id,
            &client_name,
            &client_phone,
            &service,
            price,
            "cancelled",
            &date,
            &time,
            dur,
            "delete",
        );

        tokio::spawn(async move {
            let settings = crate::routes::settings::get_settings_map(&state_n8n.pg).await;
            if settings.get("whatsapp_auto_notify_cancelled").map(|s| s.as_str()).unwrap_or("true") == "true" {
                if let Some(waha_url) = get_working_waha_url(&state_n8n, &settings).await {
                    let session = get_session_name(&state_n8n, &waha_url, &settings).await;
                    let api_key = get_api_key(&state_n8n, &settings);
                    let def_tmpls = get_default_templates();
                    let tmpl = settings.get("whatsapp_template_cancelled").map(|s| s.as_str()).unwrap_or_else(|| def_tmpls.get("whatsapp_template_cancelled").unwrap());
                    let mut ctx = HashMap::new();
                    ctx.insert("nome", client_name.clone());
                    ctx.insert("servico", service.clone());
                    ctx.insert("data", date.clone());
                    ctx.insert("horario", time.clone());
                    let text = render_whatsapp_template(tmpl, &ctx);
                    let _ = send_whatsapp_text(&state_n8n, &waha_url, &api_key, &session, &client_phone, &text).await;
                }
            }

            if settings.get("notify_confirmacao_de_agendamento").map(|s| s.as_str()).unwrap_or("false") == "true" {
                let notif_msg = format!("{} - {} em {} foi cancelado", client_name, service, date);
                let _ = sqlx::query(
                    "INSERT INTO notifications (type, title, message, related_id, related_type, read) VALUES ('appointment_cancelled', 'Agendamento Cancelado', $1, $2, 'appointment', false)"
                )
                .bind(&notif_msg)
                .bind(appt_id)
                .execute(&state_n8n.pg)
                .await;
            }
        });
    } else {
        fire_n8n_appointment(
            state_n8n,
            appt_id,
            &client_name,
            &client_phone,
            &service,
            price,
            &status,
            &date,
            &time,
            dur,
            "update",
        );
    }

    let _ = state.io.emit("appointment:updated", &json!({"id": appt_id}));
    let _ = state.io.emit("data:changed", &json!({"type": "appointment", "action": "updated"}));

    get_appointment_by_id(State(state), Path(appt_id)).await
}

pub async fn delete_appointment(
    State(state): State<SharedState>,
    Path(appt_id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let appt_val = match fetch_appointment_value(&state.pg, appt_id).await {
        Some(v) => v,
        None => return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Agendamento não encontrado"})))),
    };

    let client_name = appt_val.get("client_name").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let service = appt_val.get("service").and_then(|v| v.as_str()).unwrap_or("").to_string();
    let date = appt_val.get("appointment_date").and_then(|v| v.as_str()).unwrap_or("").to_string();

    fire_n8n_appointment(
        state.clone(),
        appt_id,
        &client_name,
        "",
        &service,
        0.0,
        "cancelled",
        &date,
        "12:00",
        60,
        "delete",
    );

    let state_notif = state.clone();
    let c_name = client_name.clone();
    let s_name = service.clone();
    let d_name = date.clone();
    tokio::spawn(async move {
        let settings = crate::routes::settings::get_settings_map(&state_notif.pg).await;
        if settings.get("notify_confirmacao_de_agendamento").map(|s| s.as_str()).unwrap_or("false") == "true" {
            let notif_msg = format!("{} - {} em {} foi removido", c_name, s_name, d_name);
            let _ = sqlx::query(
                "INSERT INTO notifications (type, title, message, related_id, related_type, read) VALUES ('appointment_cancelled', 'Agendamento Removido', $1, $2, 'appointment', false)"
            )
            .bind(&notif_msg)
            .bind(appt_id)
            .execute(&state_notif.pg)
            .await;
        }
    });

    let _ = sqlx::query("DELETE FROM appointments WHERE id = $1")
        .bind(appt_id)
        .execute(&state.pg)
        .await;

    let _ = state.io.emit("appointment:deleted", &json!({"id": appt_id}));
    let _ = state.io.emit("data:changed", &json!({"type": "appointment", "action": "deleted"}));

    Ok(Json(json!({"message": "Agendamento removido", "id": appt_id})))
}

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/appointments", get(list_appointments).post(create_appointment))
        .route("/appointments/", get(list_appointments).post(create_appointment))
        .route(
            "/appointments/{id}",
            get(get_appointment_by_id)
                .put(update_appointment)
                .delete(delete_appointment),
        )
}
