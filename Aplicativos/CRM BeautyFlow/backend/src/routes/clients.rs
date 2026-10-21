use crate::db::SharedState;
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use regex::Regex;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashMap;

#[derive(Deserialize)]
pub struct ListClientsQuery {
    pub search: Option<String>,
    pub status: Option<String>,
}

fn compute_initials(name: &str) -> String {
    let parts: Vec<&str> = name.split_whitespace().collect();
    if parts.is_empty() {
        return "??".to_string();
    }
    if parts.len() == 1 {
        return parts[0].chars().take(2).collect::<String>().to_uppercase();
    }
    format!(
        "{}{}",
        parts[0].chars().next().unwrap_or('?'),
        parts[1].chars().next().unwrap_or('?')
    )
    .to_uppercase()
}

pub async fn list_clients(
    State(state): State<SharedState>,
    Query(query): Query<ListClientsQuery>,
) -> impl IntoResponse {
    let sql = r#"
        SELECT c.*,
            COUNT(a.id) FILTER (WHERE a.status != 'cancelled') AS visits,
            COALESCE(SUM(a.price) FILTER (WHERE a.status = 'done' OR a.payment_status = 'paid'), 0) AS total_spent,
            MAX(a.appointment_date) FILTER (WHERE a.status != 'cancelled') AS last_visit
        FROM clients c
        LEFT JOIN appointments a ON a.client_id = c.id
        GROUP BY c.id
        ORDER BY c.name
    "#;

    let rows = sqlx::query(sql).fetch_all(&state.pg).await.unwrap_or_default();
    let search_clean = query
        .search
        .as_deref()
        .map(|s| Regex::new(r"\D").unwrap().replace_all(s, "").to_string())
        .unwrap_or_default();
    let search_lower = query.search.as_deref().unwrap_or("").trim().to_lowercase();
    let status_filter = query.status.as_deref().unwrap_or("").trim().to_lowercase();

    let mut results = Vec::new();
    for r in rows {
        let name: String = r.get("name");
        let phone: String = r.get("phone");
        let status: String = r.get::<Option<String>, _>("status").unwrap_or_else(|| "regular".to_string());

        if !status_filter.is_empty() && status.to_lowercase() != status_filter {
            continue;
        }

        if !search_lower.is_empty() {
            let phone_clean = Regex::new(r"\D").unwrap().replace_all(&phone, "").to_string();
            let matches_name = name.to_lowercase().contains(&search_lower);
            let matches_phone = !search_clean.is_empty() && phone_clean.contains(&search_clean);
            if !matches_name && !matches_phone {
                continue;
            }
        }

        let id: i32 = r.get("id");
        let email: String = r.get::<Option<String>, _>("email").unwrap_or_default();
        let cpf: String = r.get::<Option<String>, _>("cpf").unwrap_or_default();
        let avatar_initials: String = r.get::<Option<String>, _>("avatar_initials").unwrap_or_else(|| compute_initials(&name));
        let avatar_bg: String = r.get::<Option<String>, _>("avatar_bg").unwrap_or_else(|| "#daeaf8".to_string());
        let avatar_color: String = r.get::<Option<String>, _>("avatar_color").unwrap_or_else(|| "#1a5fab".to_string());
        let notes: String = r.get::<Option<String>, _>("notes").unwrap_or_default();
        let visits: i64 = r.get("visits");
        let total_spent: f32 = r.get("total_spent");
        let last_visit: Option<chrono::NaiveDate> = r.get("last_visit");
        let created_at: Option<chrono::DateTime<chrono::Utc>> = r.get("created_at");
        let updated_at: Option<chrono::DateTime<chrono::Utc>> = r.get("updated_at");

        results.push(json!({
            "id": id,
            "name": name,
            "phone": phone,
            "email": email,
            "cpf": cpf,
            "avatar_initials": avatar_initials,
            "avatar_bg": avatar_bg,
            "avatar_color": avatar_color,
            "notes": notes,
            "status": status,
            "visits": visits,
            "total_spent": total_spent,
            "last_visit": last_visit.map(|d| d.to_string()),
            "created_at": created_at.map(|t| t.to_rfc3339()),
            "updated_at": updated_at.map(|t| t.to_rfc3339()),
        }));
    }

    Json(results)
}

pub async fn get_client_by_id(
    State(state): State<SharedState>,
    Path(client_id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let row = sqlx::query("SELECT * FROM clients WHERE id = $1")
        .bind(client_id)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    let c = match row {
        Some(r) => r,
        None => return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Cliente não encontrado"})))),
    };

    let appt_rows = sqlx::query(
        "SELECT * FROM appointments WHERE client_id = $1 ORDER BY appointment_date DESC, appointment_time DESC",
    )
    .bind(client_id)
    .fetch_all(&state.pg)
    .await
    .unwrap_or_default();

    let mut visits = 0;
    let mut total_spent = 0.0f32;
    let mut last_visit: Option<String> = None;
    let mut appointments = Vec::new();
    let mut svc_counts: HashMap<String, i32> = HashMap::new();

    for a in appt_rows {
        let status: String = a.get("status");
        let payment_status: String = a.get::<Option<String>, _>("payment_status").unwrap_or_else(|| "unpaid".to_string());
        let price: f32 = a.get("price");
        let d: chrono::NaiveDate = a.get("appointment_date");
        let t: chrono::NaiveTime = a.get("appointment_time");
        let time_str = t.format("%H:%M").to_string();

        if status != "cancelled" {
            visits += 1;
            if last_visit.is_none() {
                last_visit = Some(d.to_string());
            }
        }
        if status == "done" || payment_status == "paid" {
            total_spent += price;
        }

        let svc: String = a.get("service");
        if status == "done" || status == "confirmed" {
            let s_name = if svc.trim().is_empty() { "Outros".to_string() } else { svc.clone() };
            *svc_counts.entry(s_name).or_insert(0) += 1;
        }

        appointments.push(json!({
            "id": a.get::<i32, _>("id"),
            "client_id": client_id,
            "service": svc,
            "appointment_date": d.to_string(),
            "appointment_time": time_str,
            "status": status,
            "payment_status": payment_status,
            "price": price,
            "duration": a.get::<Option<i32>, _>("duration").unwrap_or(60),
            "notes": a.get::<Option<String>, _>("notes").unwrap_or_default(),
            "created_at": a.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
            "updated_at": a.get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at").map(|t| t.to_rfc3339()),
        }));
    }

    let mut service_usage: Vec<Value> = svc_counts
        .into_iter()
        .map(|(service, count)| json!({"service": service, "count": count}))
        .collect();
    service_usage.sort_by(|a, b| {
        let ca = a.get("count").and_then(|v| v.as_i64()).unwrap_or(0);
        let cb = b.get("count").and_then(|v| v.as_i64()).unwrap_or(0);
        cb.cmp(&ca)
    });

    let name: String = c.get("name");
    Ok(Json(json!({
        "id": client_id,
        "name": name,
        "phone": c.get::<String, _>("phone"),
        "email": c.get::<Option<String>, _>("email").unwrap_or_default(),
        "cpf": c.get::<Option<String>, _>("cpf").unwrap_or_default(),
        "avatar_initials": c.get::<Option<String>, _>("avatar_initials").unwrap_or_else(|| compute_initials(&name)),
        "avatar_bg": c.get::<Option<String>, _>("avatar_bg").unwrap_or_else(|| "#daeaf8".to_string()),
        "avatar_color": c.get::<Option<String>, _>("avatar_color").unwrap_or_else(|| "#1a5fab".to_string()),
        "notes": c.get::<Option<String>, _>("notes").unwrap_or_default(),
        "status": c.get::<Option<String>, _>("status").unwrap_or_else(|| "regular".to_string()),
        "visits": visits,
        "total_spent": total_spent,
        "last_visit": last_visit,
        "appointments": appointments,
        "service_usage": service_usage,
        "created_at": c.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
        "updated_at": c.get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at").map(|t| t.to_rfc3339()),
    })))
}

pub async fn create_client_route(
    State(state): State<SharedState>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let name = body.get("name").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let phone = body.get("phone").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let email = body.get("email").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let cpf = body.get("cpf").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let avatar_bg = body.get("avatar_bg").and_then(|v| v.as_str()).unwrap_or("#daeaf8").to_string();
    let avatar_color = body.get("avatar_color").and_then(|v| v.as_str()).unwrap_or("#1a5fab").to_string();
    let notes = body.get("notes").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let status = body.get("status").and_then(|v| v.as_str()).unwrap_or("regular").to_string();

    let mut errors = Vec::new();
    if name.len() < 2 {
        errors.push("Nome deve ter pelo menos 2 caracteres");
    }
    if phone.len() < 8 {
        errors.push("Telefone inválido");
    }
    if !errors.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "Dados inválidos", "details": errors})),
        ));
    }

    let initials = body
        .get("avatar_initials")
        .and_then(|v| v.as_str())
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.to_string())
        .unwrap_or_else(|| compute_initials(&name));

    let row = sqlx::query(
        r#"
        INSERT INTO clients (name, phone, email, cpf, avatar_initials, avatar_bg, avatar_color, notes, status, created_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now(), now())
        RETURNING *
        "#,
    )
    .bind(&name)
    .bind(&phone)
    .bind(&email)
    .bind(&cpf)
    .bind(&initials)
    .bind(&avatar_bg)
    .bind(&avatar_color)
    .bind(&notes)
    .bind(&status)
    .fetch_one(&state.pg)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    let id: i32 = row.get("id");
    let result = json!({
        "id": id,
        "name": name,
        "phone": phone,
        "email": email,
        "cpf": cpf,
        "avatar_initials": initials,
        "avatar_bg": avatar_bg,
        "avatar_color": avatar_color,
        "notes": notes,
        "status": status,
        "visits": 0,
        "total_spent": 0.0,
        "last_visit": null,
        "created_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
        "updated_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("updated_at").map(|t| t.to_rfc3339()),
    });

    let _ = state.io.emit("client:created", &result);
    let _ = state.io.emit("data:changed", &json!({"type": "client", "action": "created"}));

    Ok((StatusCode::CREATED, Json(result)))
}

pub async fn update_client_route(
    State(state): State<SharedState>,
    Path(client_id): Path<i32>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let exists = sqlx::query("SELECT id FROM clients WHERE id = $1")
        .bind(client_id)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    if exists.is_none() {
        return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Cliente não encontrado"}))));
    }

    if let Value::Object(map) = body {
        for (k, v) in map {
            match k.as_str() {
                "name" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET name = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "phone" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET phone = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "email" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET email = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "cpf" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET cpf = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "avatar_initials" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET avatar_initials = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "avatar_bg" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET avatar_bg = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "avatar_color" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET avatar_color = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "notes" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET notes = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                "status" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE clients SET status = $1, updated_at = now() WHERE id = $2")
                            .bind(s).bind(client_id).execute(&state.pg).await;
                    }
                }
                _ => {}
            }
        }
    }

    let updated_res = get_client_by_id(State(state.clone()), Path(client_id)).await?;
    let updated_json = updated_res.into_response();

    let _ = state.io.emit("client:updated", &json!({"id": client_id}));
    let _ = state.io.emit("data:changed", &json!({"type": "client", "action": "updated"}));

    Ok(updated_json)
}

pub async fn delete_client_route(
    State(state): State<SharedState>,
    Path(client_id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let res = sqlx::query("DELETE FROM clients WHERE id = $1")
        .bind(client_id)
        .execute(&state.pg)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Cliente não encontrado"}))));
    }

    let _ = state.io.emit("client:deleted", &json!({"id": client_id}));
    let _ = state.io.emit("data:changed", &json!({"type": "client", "action": "deleted"}));

    Ok(Json(json!({"message": "Cliente removido", "id": client_id})))
}

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/clients", get(list_clients).post(create_client_route))
        .route("/clients/", get(list_clients).post(create_client_route))
        .route(
            "/clients/{id}",
            get(get_client_by_id)
                .put(update_client_route)
                .delete(delete_client_route),
        )
}
