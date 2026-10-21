use crate::db::SharedState;
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::Row;

pub async fn list_services(State(state): State<SharedState>) -> impl IntoResponse {
    let rows = sqlx::query("SELECT * FROM services ORDER BY name")
        .fetch_all(&state.pg)
        .await
        .unwrap_or_default();

    let list: Vec<Value> = rows
        .into_iter()
        .map(|r| {
            json!({
                "id": r.get::<i32, _>("id"),
                "name": r.get::<String, _>("name"),
                "duration": r.get::<i32, _>("duration"),
                "buffer": r.get::<i32, _>("buffer"),
                "price": r.get::<f32, _>("price"),
                "color": r.get::<Option<String>, _>("color").unwrap_or_else(|| "#4a90d9".to_string()),
                "created_at": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
            })
        })
        .collect();

    Json(list)
}

pub async fn create_service(
    State(state): State<SharedState>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let name = body.get("name").and_then(|v| v.as_str()).unwrap_or("").trim().to_string();
    let duration = body.get("duration").and_then(|v| v.as_i64()).map(|d| d as i32);
    let price = body.get("price").and_then(|v| {
        if let Some(f) = v.as_f64() { Some(f as f32) } else if let Some(s) = v.as_str() { s.parse::<f32>().ok() } else { None }
    });

    if name.is_empty() || duration.is_none() || price.is_none() {
        return Err((
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "Nome, duração e preço são obrigatórios"})),
        ));
    }

    let existing = sqlx::query("SELECT * FROM services WHERE name = $1")
        .bind(&name)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    if let Some(r) = existing {
        return Ok((
            StatusCode::OK,
            Json(json!({
                "id": r.get::<i32, _>("id"),
                "name": r.get::<String, _>("name"),
                "duration": r.get::<i32, _>("duration"),
                "buffer": r.get::<i32, _>("buffer"),
                "price": r.get::<f32, _>("price"),
                "color": r.get::<Option<String>, _>("color").unwrap_or_else(|| "#4a90d9".to_string()),
                "created_at": r.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
            })),
        ));
    }

    let buffer = body.get("buffer").and_then(|v| v.as_i64()).unwrap_or(15) as i32;
    let color = body.get("color").and_then(|v| v.as_str()).unwrap_or("#4a90d9").to_string();

    let row = sqlx::query(
        "INSERT INTO services (name, duration, buffer, price, color) VALUES ($1, $2, $3, $4, $5) RETURNING *"
    )
    .bind(&name)
    .bind(duration.unwrap())
    .bind(buffer)
    .bind(price.unwrap())
    .bind(&color)
    .fetch_one(&state.pg)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    let svc = json!({
        "id": row.get::<i32, _>("id"),
        "name": name,
        "duration": duration.unwrap(),
        "buffer": buffer,
        "price": price.unwrap(),
        "color": color,
        "created_at": row.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
    });

    let _ = state.io.emit("service:changed", &json!({"action": "created", "service": &svc}));
    let _ = state.io.emit("data:changed", &json!({"type": "service", "action": "created"}));

    Ok((StatusCode::CREATED, Json(svc)))
}

pub async fn update_service(
    State(state): State<SharedState>,
    Path(svc_id): Path<i32>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let existing = sqlx::query("SELECT * FROM services WHERE id = $1")
        .bind(svc_id)
        .fetch_optional(&state.pg)
        .await
        .unwrap_or(None);

    if existing.is_none() {
        return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Serviço não encontrado"}))));
    }

    if let Value::Object(map) = body {
        for (k, v) in map {
            match k.as_str() {
                "name" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE services SET name = $1 WHERE id = $2")
                            .bind(s).bind(svc_id).execute(&state.pg).await;
                    }
                }
                "color" => {
                    if let Some(s) = v.as_str() {
                        let _ = sqlx::query("UPDATE services SET color = $1 WHERE id = $2")
                            .bind(s).bind(svc_id).execute(&state.pg).await;
                    }
                }
                "duration" => {
                    if let Some(d) = v.as_i64() {
                        let _ = sqlx::query("UPDATE services SET duration = $1 WHERE id = $2")
                            .bind(d as i32).bind(svc_id).execute(&state.pg).await;
                    }
                }
                "buffer" => {
                    if let Some(b) = v.as_i64() {
                        let _ = sqlx::query("UPDATE services SET buffer = $1 WHERE id = $2")
                            .bind(b as i32).bind(svc_id).execute(&state.pg).await;
                    }
                }
                "price" => {
                    let p = if let Some(f) = v.as_f64() { Some(f as f32) } else if let Some(s) = v.as_str() { s.parse::<f32>().ok() } else { None };
                    if let Some(val) = p {
                        let _ = sqlx::query("UPDATE services SET price = $1 WHERE id = $2")
                            .bind(val).bind(svc_id).execute(&state.pg).await;
                    }
                }
                _ => {}
            }
        }
    }

    let updated = sqlx::query("SELECT * FROM services WHERE id = $1")
        .bind(svc_id)
        .fetch_one(&state.pg)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    let res = json!({
        "id": svc_id,
        "name": updated.get::<String, _>("name"),
        "duration": updated.get::<i32, _>("duration"),
        "buffer": updated.get::<i32, _>("buffer"),
        "price": updated.get::<f32, _>("price"),
        "color": updated.get::<Option<String>, _>("color").unwrap_or_else(|| "#4a90d9".to_string()),
        "created_at": updated.get::<Option<chrono::DateTime<chrono::Utc>>, _>("created_at").map(|t| t.to_rfc3339()),
    });

    let _ = state.io.emit("service:changed", &json!({"action": "updated", "service": &res}));
    let _ = state.io.emit("data:changed", &json!({"type": "service", "action": "updated"}));

    Ok(Json(res))
}

pub async fn delete_service(
    State(state): State<SharedState>,
    Path(svc_id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let res = sqlx::query("DELETE FROM services WHERE id = $1")
        .bind(svc_id)
        .execute(&state.pg)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error": e.to_string()}))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(json!({"error": "Serviço não encontrado"}))));
    }

    let _ = state.io.emit("service:changed", &json!({"action": "deleted", "id": svc_id}));
    let _ = state.io.emit("data:changed", &json!({"type": "service", "action": "deleted"}));

    Ok(Json(json!({"message": "Serviço removido", "id": svc_id})))
}

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/services", get(list_services).post(create_service))
        .route("/services/", get(list_services).post(create_service))
        .route("/services/{id}", get(update_service).put(update_service).delete(delete_service))
}
