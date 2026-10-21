mod config;
mod db;
mod routes;
mod services;

use axum::ServiceExt;
use axum::Router;
use socketioxide::extract::SocketRef;
use socketioxide::SocketIo;
use std::sync::Arc;
use tower::Layer;
use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};
use tracing::info;

use crate::config::AppConfig;
use crate::db::{create_pools, AppState};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. Trace / Logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,beautyflow_crm=debug,tower_http=info".into()),
        )
        .init();

    // 2. Load .env
    dotenvy::dotenv().ok();
    let config = AppConfig::from_env();

    // 3. CLI Args: --healthcheck or --reset-admin
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|a| a == "--healthcheck") {
        info!("Executando healthcheck...");
        let (pg, _) = create_pools(&config).await;
        match sqlx::query("SELECT 1").execute(&pg).await {
            Ok(_) => {
                println!("HEALTHCHECK_OK");
                std::process::exit(0);
            }
            Err(e) => {
                eprintln!("HEALTHCHECK_FAILED: {}", e);
                std::process::exit(1);
            }
        }
    }

    if let Some(pos) = args.iter().position(|a| a == "--reset-admin") {
        if let Some(new_pwd) = args.get(pos + 1) {
            info!("Redefinindo senha de administrador...");
            let (pg, _) = create_pools(&config).await;
            let hash = services::auth::hash_password(new_pwd);
            let res = sqlx::query(
                "UPDATE public.users SET password_hash = $1 WHERE email = 'admin' OR role = 'admin'"
            )
            .bind(&hash)
            .execute(&pg)
            .await;

            match res {
                Ok(r) => {
                    println!("Senha de admin atualizada com sucesso ({} registros afetados)", r.rows_affected());
                    std::process::exit(0);
                }
                Err(e) => {
                    eprintln!("Erro ao redefinir senha: {}", e);
                    std::process::exit(1);
                }
            }
        } else {
            eprintln!("Uso: --reset-admin <nova_senha>");
            std::process::exit(1);
        }
    }

    info!("Iniciando BeautyFlow CRM Backend em Rust...");
    info!("Conectando aos bancos de dados...");
    let (pg_pool, sqlite_pool) = create_pools(&config).await;

    // 4. Initialize schemas
    info!("Inicializando schema do PostgreSQL...");
    db::schema::init_postgres_schema(&pg_pool).await;

    info!("Garantindo usuário admin padrão...");
    db::schema::ensure_admin_user(&pg_pool).await;

    info!("Sincronizando transações de agendamentos concluídos...");
    db::schema::backfill_appointment_income_transactions(&pg_pool).await;

    info!("Inicializando schema do SQLite (WhatsApp Chat)...");
    let _ = db::chat_db::init_sqlite_schema(&sqlite_pool).await;

    // 5. Socket.IO Layer
    let (socketio_layer, io) = SocketIo::new_layer();
    io.ns("/", |socket: SocketRef| async move {
        info!("Cliente Socket.IO conectado: {}", socket.id);
        socket.on_disconnect(|socket: SocketRef| async move {
            info!("Cliente Socket.IO desconectado: {}", socket.id);
        });
    });

    // 6. Build AppState
    let state = Arc::new(AppState {
        pg: pg_pool.clone(),
        pg_pool: pg_pool.clone(),
        sqlite: sqlite_pool,
        io: io.clone(),
        config: config.clone(),
        http_client: reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .build()
            .unwrap_or_default(),
    });

    // 7. Start background workers
    info!("Iniciando listener assíncrono do PostgreSQL (pgevents)...");
    db::listener::start_pg_listener(state.clone());

    info!("Iniciando agendador de lembretes automáticos do WhatsApp...");
    services::scheduler::start_scheduler_loop(state.clone());

    // 8. CORS & Router
    let cors = CorsLayer::permissive();

    let index_file = format!("{}/index.html", config.static_dir.display());
    let serve_dir = ServeDir::new(&config.static_dir)
        .not_found_service(ServeFile::new(&index_file));

    let app = Router::new()
        .merge(routes::create_api_router())
        .fallback_service(serve_dir)
        .layer(socketio_layer)
        .layer(cors)
        .with_state(state.clone());

    let app = tower_http::normalize_path::NormalizePathLayer::trim_trailing_slash().layer(app);

    // 9. Bind & Serve
    let addr = format!("0.0.0.0:{}", config.port);
    info!("🚀 Servidor rodando em http://{}", addr);
    info!("Arquivos estáticos servidos de: {}", config.static_dir.display());

    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(
        listener,
        ServiceExt::<axum::extract::Request>::into_make_service(app),
    )
    .await?;

    Ok(())
}
