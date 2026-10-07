pub mod chat_db;
pub mod listener;
pub mod schema;

use crate::config::AppConfig;
use socketioxide::SocketIo;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{PgPool, SqlitePool};
use std::str::FromStr;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub pg: PgPool,
    pub pg_pool: PgPool,
    pub sqlite: SqlitePool,
    pub io: SocketIo,
    pub config: AppConfig,
    pub http_client: reqwest::Client,
}

pub type SharedState = Arc<AppState>;

pub async fn create_pools(config: &AppConfig) -> (PgPool, SqlitePool) {
    let pg_pool = sqlx::PgPool::connect(&config.database_url)
        .await
        .expect("Falha ao conectar no banco PostgreSQL");

    let sqlite_opts = SqliteConnectOptions::from_str(&format!("sqlite://{}", config.sqlite_path))
        .unwrap_or_else(|_| SqliteConnectOptions::default())
        .create_if_missing(true);

    let sqlite_pool = SqlitePoolOptions::new()
        .max_connections(10)
        .connect_with(sqlite_opts)
        .await
        .expect("Falha ao conectar no banco SQLite do WhatsApp");

    (pg_pool, sqlite_pool)
}
