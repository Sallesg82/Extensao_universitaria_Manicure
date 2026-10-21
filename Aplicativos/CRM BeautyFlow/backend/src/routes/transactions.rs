use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::NaiveDate;
use serde::Deserialize;
use sqlx::Row;
use std::sync::Arc;

use crate::db::AppState;

#[derive(Debug, Deserialize)]
pub struct TransactionQuery {
    pub date_from: Option<String>,
    pub date_to: Option<String>,
    pub r#type: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize)]
pub struct CreateTransactionReq {
    pub r#type: String,
    pub amount: f32,
    pub date: String,
    pub description: String,
    pub category: Option<String>,
    pub payment_method: Option<String>,
    pub appointment_id: Option<i32>,
    pub client_id: Option<i32>,
    pub client_name: Option<String>,
    pub service: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateTransactionReq {
    pub r#type: Option<String>,
    pub amount: Option<f32>,
    pub date: Option<String>,
    pub description: Option<String>,
    pub category: Option<String>,
    pub payment_method: Option<String>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_transactions).post(create_transaction))
        .route("/{id}", get(get_transaction).put(update_transaction).delete(delete_transaction))
}

fn row_to_json(r: &sqlx::postgres::PgRow) -> serde_json::Value {
    let date_val: Option<NaiveDate> = r.try_get("date").ok();
    let created_at: Option<chrono::DateTime<chrono::Utc>> = r.try_get("created_at").ok();

    serde_json::json!({
        "id": r.get::<i32, _>("id"),
        "type": r.get::<String, _>("type"),
        "description": r.get::<String, _>("description"),
        "amount": r.get::<f32, _>("amount"),
        "category": r.get::<Option<String>, _>("category").unwrap_or_default(),
        "payment_method": r.get::<Option<String>, _>("payment_method").unwrap_or_default(),
        "date": date_val.map(|d| d.to_string()).unwrap_or_default(),
        "appointment_id": r.get::<Option<i32>, _>("appointment_id"),
        "client_id": r.get::<Option<i32>, _>("client_id"),
        "client_name": r.get::<Option<String>, _>("client_name").unwrap_or_default(),
        "service": r.get::<Option<String>, _>("service").unwrap_or_default(),
        "created_at": created_at.map(|t| t.to_rfc3339()),
    })
}

async fn list_transactions(
    State(state): State<Arc<AppState>>,
    Query(query): Query<TransactionQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let mut sql = "SELECT id, type, description, amount, category, payment_method, date, appointment_id, client_id, client_name, service, created_at FROM public.transactions WHERE 1=1".to_string();
    let mut conditions = Vec::new();
    let mut param_index = 1;

    let parsed_date_from = query.date_from.as_ref().and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());
    let parsed_date_to = query.date_to.as_ref().and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok());

    if parsed_date_from.is_some() {
        conditions.push(format!("date >= ${}", param_index));
        param_index += 1;
    }
    if parsed_date_to.is_some() {
        conditions.push(format!("date <= ${}", param_index));
        param_index += 1;
    }
    if query.r#type.as_ref().map(|t| !t.trim().is_empty()).unwrap_or(false) {
        conditions.push(format!("type = ${}", param_index));
        param_index += 1;
    }

    if !conditions.is_empty() {
        sql.push_str(" AND ");
        sql.push_str(&conditions.join(" AND "));
    }

    sql.push_str(" ORDER BY date DESC, id DESC LIMIT $");
    sql.push_str(&param_index.to_string());

    let limit = query.limit.unwrap_or(200).min(1000).max(1);

    let mut q = sqlx::query(sqlx::AssertSqlSafe(sql.as_str()));
    if let Some(d) = parsed_date_from {
        q = q.bind(d);
    }
    if let Some(d) = parsed_date_to {
        q = q.bind(d);
    }
    if let Some(ref t) = query.r#type {
        if !t.trim().is_empty() {
            q = q.bind(t.trim());
        }
    }
    q = q.bind(limit);

    let rows = q.fetch_all(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to fetch transactions: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    let list: Vec<serde_json::Value> = rows.iter().map(row_to_json).collect();
    Ok(Json(list))
}

async fn get_transaction(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let row = sqlx::query(
        "SELECT id, type, description, amount, category, payment_method, date, appointment_id, client_id, client_name, service, created_at \
         FROM public.transactions WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    match row {
        Some(r) => Ok(Json(row_to_json(&r))),
        None => Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Transação não encontrada" })))),
    }
}

async fn create_transaction(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateTransactionReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    if payload.r#type != "income" && payload.r#type != "expense" {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Tipo deve ser income ou expense" }))));
    }

    let parsed_date = NaiveDate::parse_from_str(payload.date.trim(), "%Y-%m-%d").map_err(|_| {
        (StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Formato de data inválido. Use YYYY-MM-DD" })))
    })?;

    let desc = payload.description.trim().to_string();
    if desc.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Descrição é obrigatória" }))));
    }

    let cat = payload.category.unwrap_or_default();
    let pm = payload.payment_method.unwrap_or_default();
    let c_name = payload.client_name.unwrap_or_default();
    let svc = payload.service.unwrap_or_default();

    let row = sqlx::query(
        "INSERT INTO public.transactions (type, amount, date, description, category, payment_method, appointment_id, client_id, client_name, service) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) \
         RETURNING id, type, description, amount, category, payment_method, date, appointment_id, client_id, client_name, service, created_at"
    )
    .bind(&payload.r#type)
    .bind(payload.amount)
    .bind(parsed_date)
    .bind(&desc)
    .bind(&cat)
    .bind(&pm)
    .bind(payload.appointment_id)
    .bind(payload.client_id)
    .bind(&c_name)
    .bind(&svc)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to insert transaction: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao criar transação" })))
    })?;

    let tx_obj = row_to_json(&row);

    let _ = state.io.emit("transaction:created", &tx_obj).await;
    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "transaction",
        "action": "created"
    })).await;

    Ok((StatusCode::CREATED, Json(tx_obj)))
}

async fn update_transaction(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateTransactionReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let existing = sqlx::query("SELECT id FROM public.transactions WHERE id = $1 LIMIT 1")
        .bind(id)
        .fetch_optional(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    if existing.is_none() {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Transação não encontrada" }))));
    }

    let mut set_clauses = Vec::new();
    let mut param_index = 2;

    if payload.r#type.is_some() {
        set_clauses.push(format!("type = ${}", param_index));
        param_index += 1;
    }
    if payload.amount.is_some() {
        set_clauses.push(format!("amount = ${}", param_index));
        param_index += 1;
    }
    if payload.date.is_some() {
        set_clauses.push(format!("date = ${}", param_index));
        param_index += 1;
    }
    if payload.description.is_some() {
        set_clauses.push(format!("description = ${}", param_index));
        param_index += 1;
    }
    if payload.category.is_some() {
        set_clauses.push(format!("category = ${}", param_index));
        param_index += 1;
    }
    if payload.payment_method.is_some() {
        set_clauses.push(format!("payment_method = ${}", param_index));
    }

    if set_clauses.is_empty() {
        let r = sqlx::query(
            "SELECT id, type, description, amount, category, payment_method, date, appointment_id, client_id, client_name, service, created_at \
             FROM public.transactions WHERE id = $1"
        )
        .bind(id)
        .fetch_one(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;
        return Ok(Json(row_to_json(&r)));
    }

    let sql = format!(
        "UPDATE public.transactions SET {} WHERE id = $1 RETURNING id, type, description, amount, category, payment_method, date, appointment_id, client_id, client_name, service, created_at",
        set_clauses.join(", ")
    );

    let mut q = sqlx::query(sqlx::AssertSqlSafe(sql.as_str())).bind(id);

    if let Some(ref t) = payload.r#type {
        q = q.bind(t.trim());
    }
    if let Some(amt) = payload.amount {
        q = q.bind(amt);
    }
    if let Some(ref d_str) = payload.date {
        let d = NaiveDate::parse_from_str(d_str.trim(), "%Y-%m-%d").unwrap_or_else(|_| chrono::Local::now().date_naive());
        q = q.bind(d);
    }
    if let Some(ref desc) = payload.description {
        q = q.bind(desc.trim());
    }
    if let Some(ref cat) = payload.category {
        q = q.bind(cat.trim());
    }
    if let Some(ref pm) = payload.payment_method {
        q = q.bind(pm.trim());
    }

    let updated_row = q.fetch_one(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to update transaction: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao atualizar transação" })))
    })?;

    let tx_obj = row_to_json(&updated_row);

    let _ = state.io.emit("transaction:updated", &tx_obj).await;
    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "transaction",
        "action": "updated"
    })).await;

    Ok(Json(tx_obj))
}

async fn delete_transaction(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let res = sqlx::query("DELETE FROM public.transactions WHERE id = $1")
        .bind(id)
        .execute(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Transação não encontrada" }))));
    }

    let _ = state.io.emit("transaction:deleted", &serde_json::json!({ "id": id })).await;
    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "transaction",
        "action": "deleted"
    })).await;

    Ok(Json(serde_json::json!({ "message": "Transação removida", "id": id })))
}
