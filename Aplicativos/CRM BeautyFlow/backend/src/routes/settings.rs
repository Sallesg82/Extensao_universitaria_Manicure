use crate::db::SharedState;
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::Datelike;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashMap;

pub async fn get_settings_map(pool: &sqlx::PgPool) -> HashMap<String, String> {
    let rows = sqlx::query("SELECT key, value FROM settings")
        .fetch_all(pool)
        .await
        .unwrap_or_default();

    let mut map = HashMap::new();
    for r in rows {
        let k: String = r.get("key");
        let v: String = r.get("value");
        map.insert(k, v);
    }
    map
}

pub async fn handle_get_settings(State(state): State<SharedState>) -> impl IntoResponse {
    let map = get_settings_map(&state.pg).await;
    let mut json_obj = serde_json::Map::new();

    for (k, v) in map {
        if k == "meta_mensal" {
            let num: f64 = v.parse().unwrap_or(7000.0);
            json_obj.insert(k, json!(num));
        } else {
            json_obj.insert(k, json!(v));
        }
    }

    if !json_obj.contains_key("meta_mensal") {
        json_obj.insert("meta_mensal".to_string(), json!(7000.0));
    }

    Json(Value::Object(json_obj))
}

pub async fn handle_put_settings(
    State(state): State<SharedState>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    if let Value::Object(map) = &body {
        for (k, v) in map {
            let str_val = match v {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                Value::Bool(b) => b.to_string(),
                _ => v.to_string(),
            };

            if k == "meta_mensal" {
                let now = chrono::Local::now();
                let mes = map
                    .get("mes")
                    .and_then(|m| m.as_str())
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| format!("{:04}-{:02}", now.year(), now.month()));

                if let Ok(meta_val) = str_val.parse::<f64>() {
                    let _ = sqlx::query(
                        r#"
                        INSERT INTO public.metas (mes, meta, updated_at)
                        VALUES ($1, $2, now())
                        ON CONFLICT (mes) DO UPDATE SET meta = EXCLUDED.meta, updated_at = now()
                        "#
                    )
                    .bind(&mes)
                    .bind(meta_val)
                    .execute(&state.pg)
                    .await;
                }
            }

            let _ = sqlx::query(
                r#"
                INSERT INTO settings (key, value)
                VALUES ($1, $2)
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
                "#
            )
            .bind(k)
            .bind(&str_val)
            .execute(&state.pg)
            .await;
        }

        let _ = state.io.emit("data:changed", &json!({"type": "setting", "action": "updated"}));
    }

    Ok(handle_get_settings(State(state)).await)
}

pub async fn list_expense_categories(State(state): State<SharedState>) -> impl IntoResponse {
    let settings = get_settings_map(&state.pg).await;
    let raw = settings.get("expense_categories").cloned().unwrap_or_else(|| "[]".to_string());
    let list: Value = serde_json::from_str(&raw).unwrap_or_else(|_| json!([]));
    Json(list)
}

pub async fn create_expense_category(
    State(state): State<SharedState>,
    Json(body): Json<Value>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    let name = body
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .trim()
        .to_string();

    if name.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(json!({"error": "Nome da categoria é obrigatório"}))));
    }

    let settings = get_settings_map(&state.pg).await;
    let raw = settings.get("expense_categories").cloned().unwrap_or_else(|| "[]".to_string());
    let mut list: Vec<Value> = serde_json::from_str(&raw).unwrap_or_default();

    for item in &list {
        if let Some(item_name) = item.get("name").and_then(|n| n.as_str()) {
            if item_name.eq_ignore_ascii_case(&name) {
                return Err((StatusCode::CONFLICT, Json(json!({"error": "Categoria já existe"}))));
            }
        }
    }

    let new_cat = json!({
        "name": name,
        "id": (list.len() + 1).to_string()
    });
    list.push(new_cat.clone());

    let updated_json = serde_json::to_string(&list).unwrap_or_else(|_| "[]".to_string());
    let _ = sqlx::query(
        "INSERT INTO settings (key, value) VALUES ('expense_categories', $1) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value"
    )
    .bind(&updated_json)
    .execute(&state.pg)
    .await;

    Ok((StatusCode::CREATED, Json(new_cat)))
}

pub fn router() -> Router<SharedState> {
    Router::new()
        .route("/settings", get(handle_get_settings).put(handle_put_settings))
        .route("/settings/", get(handle_get_settings).put(handle_put_settings))
        .route("/settings/expense-categories", get(list_expense_categories).post(create_expense_category))
        .route("/expense-categories", get(list_expense_categories).post(create_expense_category))
}
