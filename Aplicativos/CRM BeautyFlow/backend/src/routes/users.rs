use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;

use crate::db::AppState;
use crate::services::auth::{hash_password, verify_password};

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserDto {
    pub id: i32,
    pub name: String,
    pub email: String,
    pub phone: Option<String>,
    pub role: String,
    pub created_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Debug, Deserialize)]
pub struct CreateUserReq {
    pub name: String,
    pub email: String,
    pub password: String,
    pub phone: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateUserReq {
    pub name: Option<String>,
    pub email: Option<String>,
    pub password: Option<String>,
    pub phone: Option<String>,
    pub role: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ChangePasswordReq {
    pub password: String,
}

#[derive(Debug, Deserialize)]
pub struct LoginReq {
    pub email: Option<String>,
    pub username: Option<String>,
    pub password: Option<String>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new()
        .route("/", get(list_users).post(create_user))
        .route("/exists", get(users_exist))
        .route("/login", post(login))
        .route("/{id}", get(get_user).put(update_user).delete(delete_user))
        .route("/{id}/password", put(change_password))
}

async fn list_users(State(state): State<Arc<AppState>>) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let rows = sqlx::query_as::<_, UserDto>(
        "SELECT id, name, email, phone, role, created_at FROM public.users ORDER BY name ASC"
    )
    .fetch_all(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to fetch users: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    Ok(Json(rows))
}

async fn users_exist(State(state): State<Arc<AppState>>) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM public.users")
        .fetch_one(&state.pg_pool)
        .await
        .unwrap_or(0);

    Ok(Json(serde_json::json!({ "exists": count > 0 })))
}

async fn get_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let user = sqlx::query_as::<_, UserDto>(
        "SELECT id, name, email, phone, role, created_at FROM public.users WHERE id = $1 LIMIT 1"
    )
    .bind(id)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| {
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    match user {
        Some(u) => Ok(Json(u)),
        None => Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Usuário não encontrado" })))),
    }
}

async fn create_user(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateUserReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let name = payload.name.trim();
    let email = payload.email.trim();
    if name.is_empty() || email.is_empty() || payload.password.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Nome, email e senha são obrigatórios" }))));
    }

    let existing: Option<i32> = sqlx::query_scalar("SELECT id FROM public.users WHERE email = $1 LIMIT 1")
        .bind(email)
        .fetch_optional(&state.pg_pool)
        .await
        .unwrap_or(None);

    if existing.is_some() {
        return Err((StatusCode::CONFLICT, Json(serde_json::json!({ "error": "Email já cadastrado" }))));
    }

    let pw_hash = hash_password(&payload.password);
    let role = payload.role.unwrap_or_else(|| "admin".to_string());
    let phone = payload.phone.unwrap_or_default();

    let user = sqlx::query_as::<_, UserDto>(
        "INSERT INTO public.users (name, email, password_hash, phone, role) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, name, email, phone, role, created_at"
    )
    .bind(name)
    .bind(email)
    .bind(&pw_hash)
    .bind(&phone)
    .bind(&role)
    .fetch_one(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Failed to create user: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao criar usuário" })))
    })?;

    Ok((StatusCode::CREATED, Json(user)))
}

async fn update_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<UpdateUserReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let existing = sqlx::query("SELECT id, email FROM public.users WHERE id = $1 LIMIT 1")
        .bind(id)
        .fetch_optional(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    let existing = match existing {
        Some(e) => e,
        None => return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Usuário não encontrado" })))),
    };
    let current_email: String = existing.get("email");

    if let Some(ref new_email) = payload.email {
        let trimmed_email = new_email.trim();
        if trimmed_email != current_email {
            let email_exists: Option<i32> = sqlx::query_scalar("SELECT id FROM public.users WHERE email = $1 AND id != $2 LIMIT 1")
                .bind(trimmed_email)
                .bind(id)
                .fetch_optional(&state.pg_pool)
                .await
                .unwrap_or(None);

            if email_exists.is_some() {
                return Err((StatusCode::CONFLICT, Json(serde_json::json!({ "error": "Email já cadastrado" }))));
            }
        }
    }

    let mut set_clauses = Vec::new();
    let mut param_index = 2; // $1 is id

    if payload.name.is_some() {
        set_clauses.push(format!("name = ${}", param_index));
        param_index += 1;
    }
    if payload.email.is_some() {
        set_clauses.push(format!("email = ${}", param_index));
        param_index += 1;
    }
    if payload.phone.is_some() {
        set_clauses.push(format!("phone = ${}", param_index));
        param_index += 1;
    }
    if payload.role.is_some() {
        set_clauses.push(format!("role = ${}", param_index));
        param_index += 1;
    }
    if let Some(ref pwd) = payload.password {
        if !pwd.is_empty() {
            set_clauses.push(format!("password_hash = ${}", param_index));
        }
    }

    if set_clauses.is_empty() {
        let u = sqlx::query_as::<_, UserDto>(
            "SELECT id, name, email, phone, role, created_at FROM public.users WHERE id = $1"
        )
        .bind(id)
        .fetch_one(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;
        return Ok(Json(u));
    }

    let query_str = format!(
        "UPDATE public.users SET {} WHERE id = $1 RETURNING id, name, email, phone, role, created_at",
        set_clauses.join(", ")
    );

    let mut query = sqlx::query_as::<_, UserDto>(sqlx::AssertSqlSafe(query_str.as_str())).bind(id);

    if let Some(name) = payload.name {
        query = query.bind(name);
    }
    if let Some(email) = payload.email {
        query = query.bind(email);
    }
    if let Some(phone) = payload.phone {
        query = query.bind(phone);
    }
    if let Some(role) = payload.role {
        query = query.bind(role);
    }
    if let Some(pwd) = payload.password {
        if !pwd.is_empty() {
            let hash = hash_password(&pwd);
            query = query.bind(hash);
        }
    }

    let updated = query.fetch_one(&state.pg_pool).await.map_err(|e| {
        tracing::error!("Failed to update user: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": "Erro ao atualizar usuário" })))
    })?;

    Ok(Json(updated))
}

async fn delete_user(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let res = sqlx::query("DELETE FROM public.users WHERE id = $1")
        .bind(id)
        .execute(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Usuário não encontrado" }))));
    }

    Ok(Json(serde_json::json!({ "message": "Usuário removido", "id": id })))
}

async fn change_password(
    State(state): State<Arc<AppState>>,
    Path(id): Path<i32>,
    Json(payload): Json<ChangePasswordReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    if payload.password.trim().len() < 4 {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Senha deve ter no mínimo 4 caracteres" }))));
    }

    let pw_hash = hash_password(&payload.password);
    let res = sqlx::query("UPDATE public.users SET password_hash = $1 WHERE id = $2")
        .bind(pw_hash)
        .bind(id)
        .execute(&state.pg_pool)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() }))))?;

    if res.rows_affected() == 0 {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({ "error": "Usuário não encontrado" }))));
    }

    Ok(Json(serde_json::json!({ "message": "Senha alterada com sucesso" })))
}

async fn login(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginReq>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let raw_identifier = payload
        .email
        .or(payload.username)
        .unwrap_or_default();
    let identifier = raw_identifier.trim();
    let password = payload.password.as_deref().unwrap_or("");

    if identifier.is_empty() || password.is_empty() {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({ "error": "Email e senha são obrigatórios" }))));
    }

    tracing::info!("Tentando login com identificador: '{}'", identifier);

    let user_row = sqlx::query(
        "SELECT id, name, email, phone, role, password_hash, created_at \
         FROM public.users \
         WHERE LOWER(email) = LOWER($1) OR LOWER(name) = LOWER($1) \
         LIMIT 1"
    )
    .bind(identifier)
    .fetch_optional(&state.pg_pool)
    .await
    .map_err(|e| {
        tracing::error!("Erro de DB no login: {}", e);
        (StatusCode::INTERNAL_SERVER_ERROR, Json(serde_json::json!({ "error": e.to_string() })))
    })?;

    let row = match user_row {
        Some(r) => r,
        None => {
            tracing::warn!("Usuário não encontrado para: '{}'", identifier);
            return Err((StatusCode::UNAUTHORIZED, Json(serde_json::json!({ "error": "Email ou senha inválidos" }))));
        }
    };

    let stored_hash: String = row.get("password_hash");
    let is_valid = verify_password(&stored_hash, password);
    tracing::info!("Verificação de senha para '{}': valid={}", identifier, is_valid);
    if !is_valid {
        return Err((StatusCode::UNAUTHORIZED, Json(serde_json::json!({ "error": "Email ou senha inválidos" }))));
    }

    let user = UserDto {
        id: row.get("id"),
        name: row.get("name"),
        email: row.get("email"),
        phone: row.get("phone"),
        role: row.get("role"),
        created_at: row.get("created_at"),
    };

    Ok(Json(user))
}
