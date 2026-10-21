use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, patch},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::db::AppState;

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct ProductDto {
    pub id: i32,
    pub name: String,
    pub category: String,
    pub qty: i32,
    pub price: f32,
    pub min_qty: i32,
    pub missing: bool,
    pub created_at: Option<chrono::DateTime<chrono::Utc>>,
    pub updated_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct ProductQuery {
    pub search: Option<String>,
    pub category: Option<String>,
    pub situation: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateProductReq {
    pub name: String,
    pub category: Option<String>,
    pub qty: Option<i32>,
    pub price: Option<f32>,
    pub min_qty: Option<i32>,
    pub missing: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateProductReq {
    pub name: Option<String>,
    pub category: Option<String>,
    pub qty: Option<i32>,
    pub price: Option<f32>,
    pub min_qty: Option<i32>,
    pub missing: Option<bool>,
}

#[derive(Debug, Deserialize)]
pub struct StockPatchReq {
    pub delta: Option<i32>,
    pub qty: Option<i32>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_products).post(create_product))
        .route("/stats", get(get_products_stats))
        .route("/{id}", get(get_product).put(update_product).delete(delete_product))
        .route("/{id}/stock", patch(adjust_stock))
}

fn normalize_category(cat: Option<&str>) -> String {
    let c = cat.unwrap_or("esmaltes").trim().to_lowercase();
    match c.as_str() {
        "pink" => "esmaltes".to_string(),
        "amber" => "cuidados".to_string(),
        "blue" => "descartaveis".to_string(),
        "purple" => "quimicos".to_string(),
        "" => "esmaltes".to_string(),
        other => other.to_string(),
    }
}

async fn list_products(
    State(state): State<Arc<AppState>>,
    Query(query): Query<ProductQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let mut sql = "SELECT id, name, category, qty, price, min_qty, missing, created_at, updated_at FROM public.products WHERE 1=1".to_string();
    let mut conditions = Vec::new();
    let mut param_index = 1;

    let search_clean = query.search.as_ref().map(|s| s.trim()).filter(|s| !s.is_empty());
    let category_clean = query.category.as_ref().map(|c| c.trim()).filter(|c| !c.is_empty() && *c != "todos");
    let situation = query.situation.as_deref().unwrap_or("todos");

    if search_clean.is_some() {
        conditions.push(format!("name ILIKE ${}", param_index));
        param_index += 1;
    }

    if category_clean.is_some() {
        conditions.push(format!("category = ${}", param_index));
    }

    match situation {
        "falta" => conditions.push("(missing = true OR qty = 0)".to_string()),
        "baixo" => conditions.push("(missing = false AND qty > 0 AND qty <= min_qty)".to_string()),
        "ok" => conditions.push("(missing = false AND qty > min_qty)".to_string()),
        _ => {}
    }

    if !conditions.is_empty() {
        sql.push_str(" AND ");
        sql.push_str(&conditions.join(" AND "));
    }

    sql.push_str(" ORDER BY missing DESC, (qty <= min_qty) DESC, id ASC");

    let mut q = sqlx::query_as::<_, ProductDto>(sqlx::AssertSqlSafe(sql.as_str()));

    if let Some(s) = search_clean {
        q = q.bind(format!("%{}%", s));
    }
    if let Some(c) = category_clean {
        q = q.bind(normalize_category(Some(c)));
    }

    let rows = q.fetch_all(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to fetch products: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    Ok(Json(rows))
}

async fn get_products_stats(
    State(state): State<Arc<AppState>>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let row = sqlx::query(
        r#"
        SELECT 
            COUNT(*) as total_products,
            COALESCE(SUM(qty), 0) as total_units,
            COALESCE(SUM(qty * price), 0.0) as total_value,
            COALESCE(SUM(CASE WHEN (missing = true OR qty = 0) THEN 1 ELSE 0 END), 0) as out_of_stock_count,
            COALESCE(SUM(CASE WHEN (missing = false AND qty > 0 AND qty <= min_qty) THEN 1 ELSE 0 END), 0) as low_stock_count,
            COALESCE(SUM(CASE WHEN (missing = false AND qty > min_qty) THEN 1 ELSE 0 END), 0) as in_stock_count
        FROM public.products
        "#
    )
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch products stats: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    let total_products: i64 = row.get("total_products");
    let total_units: i64 = row.get("total_units");
    let total_value: f64 = row
        .try_get::<f64, _>("total_value")
        .or_else(|_| row.try_get::<f32, _>("total_value").map(|v| v as f64))
        .unwrap_or(0.0);
    let out_of_stock_count: i64 = row.get("out_of_stock_count");
    let low_stock_count: i64 = row.get("low_stock_count");
    let in_stock_count: i64 = row.get("in_stock_count");

    Ok(Json(serde_json::json!({
        "total_products": total_products,
        "total_units": total_units,
        "total_value": (total_value * 100.0).round() / 100.0,
        "out_of_stock_count": out_of_stock_count,
        "low_stock_count": low_stock_count,
        "in_stock_count": in_stock_count,
    })))
}

async fn get_product(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let prod = sqlx::query_as::<_, ProductDto>(
        "SELECT id, name, category, qty, price, min_qty, missing, created_at, updated_at \
         FROM public.products WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    match prod {
        Some(p) => Ok(Json(p)),
        None => Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Produto não encontrado" })))),
    }
}

async fn create_product(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateProductReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let name = payload.name.trim().to_string();
    if name.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nome do produto é obrigatório" }))));
    }

    let missing = payload.missing.unwrap_or(false);
    let qty = if missing { 0 } else { payload.qty.unwrap_or(0).max(0) };
    let price = payload.price.unwrap_or(0.0).max(0.0);
    let min_qty = payload.min_qty.unwrap_or(5).max(0);
    let category = normalize_category(payload.category.as_deref());

    let prod = sqlx::query_as::<_, ProductDto>(
        "INSERT INTO public.products (name, category, qty, price, min_qty, missing) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id, name, category, qty, price, min_qty, missing, created_at, updated_at"
    )
    .bind(&name)
    .bind(&category)
    .bind(qty)
    .bind(price)
    .bind(min_qty)
    .bind(missing)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to create product: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao criar produto" })))
    })?;

    let _ = state.io.emit("product:changed", &serde_json::json!({
        "action": "created",
        "product": &prod
    })).await;

    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "product",
        "action": "created",
        "id": prod.id
    })).await;

    Ok((StatusCode::CREATED, Json(prod)))
}

async fn update_product(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateProductReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let existing = sqlx::query_as::<_, ProductDto>(
        "SELECT id, name, category, qty, price, min_qty, missing, created_at, updated_at \
         FROM public.products WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    let existing = match existing {
        Some(p) => p,
        None => return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Produto não encontrado" })))),
    };

    let mut set_clauses = Vec::new();
    let mut param_index = 2;

    if let Some(ref name) = payload.name {
        if name.trim().is_empty() {
            return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nome do produto não pode ser vazio" }))));
        }
        set_clauses.push(format!("name = ${}", param_index));
        param_index += 1;
    }

    if payload.category.is_some() {
        set_clauses.push(format!("category = ${}", param_index));
        param_index += 1;
    }

    if payload.price.is_some() {
        set_clauses.push(format!("price = ${}", param_index));
        param_index += 1;
    }

    if payload.min_qty.is_some() {
        set_clauses.push(format!("min_qty = ${}", param_index));
        param_index += 1;
    }

    let mut final_missing = payload.missing.unwrap_or(existing.missing);
    let mut final_qty = payload.qty.unwrap_or(existing.qty).max(0);

    if let Some(m) = payload.missing {
        if m {
            final_qty = 0;
            final_missing = true;
        }
    }
    if let Some(q) = payload.qty {
        if q > 0 && payload.missing.is_none() {
            final_missing = false;
        }
    }

    set_clauses.push(format!("qty = ${}", param_index));
    param_index += 1;
    set_clauses.push(format!("missing = ${}", param_index));
    set_clauses.push("updated_at = now()".to_string());

    let sql = format!(
        "UPDATE public.products SET {} WHERE id = $1 RETURNING id, name, category, qty, price, min_qty, missing, created_at, updated_at",
        set_clauses.join(", ")
    );

    let mut q = sqlx::query_as::<_, ProductDto>(sqlx::AssertSqlSafe(sql.as_str())).bind(id);

    if let Some(ref name) = payload.name {
        q = q.bind(name.trim().to_string());
    }
    if let Some(ref cat) = payload.category {
        q = q.bind(normalize_category(Some(cat)));
    }
    if let Some(price) = payload.price {
        q = q.bind(price.max(0.0));
    }
    if let Some(min_qty) = payload.min_qty {
        q = q.bind(min_qty.max(0));
    }
    q = q.bind(final_qty);
    q = q.bind(final_missing);

    let updated = q.fetch_one(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to update product: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao atualizar produto" })))
    })?;

    let _ = state.io.emit("product:changed", &serde_json::json!({
        "action": "updated",
        "product": &updated
    })).await;

    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "product",
        "action": "updated",
        "id": id
    })).await;

    Ok(Json(updated))
}

async fn adjust_stock(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<StockPatchReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let existing = sqlx::query_as::<_, ProductDto>(
        "SELECT id, name, category, qty, price, min_qty, missing, created_at, updated_at \
         FROM public.products WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    let existing = match existing {
        Some(p) => p,
        None => return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Produto não encontrado" })))),
    };

    let new_qty = if let Some(delta) = payload.delta {
        (existing.qty + delta).max(0)
    } else if let Some(qty) = payload.qty {
        qty.max(0)
    } else {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Parâmetro delta ou qty é obrigatório" }))));
    };

    let new_missing = new_qty == 0;

    let updated = sqlx::query_as::<_, ProductDto>(
        "UPDATE public.products SET qty = $1, missing = $2, updated_at = now() WHERE id = $3 \
         RETURNING id, name, category, qty, price, min_qty, missing, created_at, updated_at"
    )
    .bind(new_qty)
    .bind(new_missing)
    .bind(id)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to adjust stock: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao atualizar estoque" })))
    })?;

    let _ = state.io.emit("product:changed", &serde_json::json!({
        "action": "updated",
        "product": &updated
    })).await;

    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "product",
        "action": "updated",
        "id": id
    })).await;

    Ok(Json(updated))
}

async fn delete_product(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let res = sqlx::query("DELETE FROM public.products WHERE id = $1")
        .bind(id)
        .execute(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Produto não encontrado" }))));
    }

    let _ = state.io.emit("product:changed", &serde_json::json!({
        "action": "deleted",
        "id": id
    })).await;

    let _ = state.io.emit("data:changed", &serde_json::json!({
        "type": "product",
        "action": "deleted",
        "id": id
    })).await;

    Ok(Json(serde_json::json!({ "message": "Produto removido com sucesso", "id": id })))
}
