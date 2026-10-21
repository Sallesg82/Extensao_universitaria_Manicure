pub mod appointments;
pub mod business_hours;
pub mod clients;
pub mod integrations;
pub mod metas;
pub mod migrate;
pub mod n8n;
pub mod notifications;
pub mod products;
pub mod services;
pub mod settings;
pub mod stats;
pub mod transactions;
pub mod users;
pub mod whatsapp;

use axum::Router;
use std::sync::Arc;

use crate::db::AppState;

pub fn create_api_router() -> Router<Arc<AppState>> {
    let api_routes = Router::new()
        // Routers that already define their subpaths (/appointments, /clients, /services, etc.)
        .merge(appointments::router())
        .merge(clients::router())
        .merge(services::router())
        .merge(settings::router())
        .merge(business_hours::router())
        // Routers nested by resource
        .nest("/users", users::router())
        .nest("/notifications", notifications::router())
        .nest("/integrations", integrations::router())
        .nest("/transactions", transactions::router())
        .nest("/products", products::router())
        .nest("/metas", metas::router())
        .nest("/whatsapp", whatsapp::router())
        .nest("/n8n", n8n::router())
        .nest("/stats", stats::router())
        .nest("/migrate", migrate::router());

    Router::new().nest("/api", api_routes)
}
