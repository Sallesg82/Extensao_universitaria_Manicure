use serde_json::{json, Value};
use socketioxide::SocketIo;
use sqlx::postgres::PgListener;
use std::collections::HashMap;
use std::time::Duration;
use tracing::{error, info, warn};

pub async fn start_postgres_listener(database_url: String, io: SocketIo) {
    let mut table_event_map = HashMap::new();
    table_event_map.insert("appointments", "appointment");
    table_event_map.insert("transactions", "transaction");
    table_event_map.insert("clients", "client");
    table_event_map.insert("services", "service");
    table_event_map.insert("settings", "setting");
    table_event_map.insert("business_hours", "business_hours");
    table_event_map.insert("notifications", "notification");
    table_event_map.insert("users", "user");
    table_event_map.insert("products", "product");
    table_event_map.insert("metas", "meta");

    tokio::spawn(async move {
        loop {
            match PgListener::connect(&database_url).await {
                Ok(mut listener) => {
                    if let Err(e) = listener.listen("pgevents").await {
                        error!("[Realtime PG] Erro ao registrar LISTEN pgevents: {}", e);
                        tokio::time::sleep(Duration::from_secs(3)).await;
                        continue;
                    }
                    info!("[Realtime PG] Escutando notificações no canal 'pgevents'...");

                    loop {
                        match listener.recv().await {
                            Ok(notification) => {
                                let payload_str = notification.payload();
                                if let Ok(val) = serde_json::from_str::<Value>(payload_str) {
                                    let table = val.get("table").and_then(|v| v.as_str()).unwrap_or("");
                                    let action = val
                                        .get("action")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or("")
                                        .to_lowercase();
                                    let rec_id = val.get("id").cloned();

                                    let ev_type = table_event_map.get(table).copied().unwrap_or(table);

                                    let changed_payload = json!({
                                        "type": ev_type,
                                        "action": action,
                                        "id": rec_id
                                    });

                                    let _ = io.emit("data:changed", &changed_payload);

                                    if !ev_type.is_empty() && !action.is_empty() {
                                        let specific_ev = format!("{}:{}", ev_type, action);
                                        let specific_payload = json!({ "id": rec_id });
                                        let _ = io.emit(&specific_ev, &specific_payload);
                                    }
                                }
                            }
                            Err(e) => {
                                warn!(
                                    "[Realtime PG] Conexão listener interrompida (reconectando em 3s): {}",
                                    e
                                );
                                break;
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!(
                        "[Realtime PG] Falha ao conectar listener no Postgres (tentando em 3s): {}",
                        e
                    );
                }
            }
            tokio::time::sleep(Duration::from_secs(3)).await;
        }
    });
}

pub fn start_pg_listener(state: crate::db::SharedState) {
    let db_url = state.config.database_url.clone();
    let io = state.io.clone();
    tokio::spawn(async move {
        start_postgres_listener(db_url, io).await;
    });
}

