use std::env;
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct AppConfig {
    pub database_url: String,
    pub sqlite_path: String,
    pub static_dir: PathBuf,
    pub port: u16,
    pub n8n_webhook_url: String,
    #[allow(dead_code)]
    pub install_waha: String,
    pub waha_api_url: String,
    pub waha_api_key: String,
    pub waha_session: String,
}

impl AppConfig {
    pub fn from_env() -> Self {
        Self::load()
    }

    pub fn load() -> Self {
        let _ = dotenvy::dotenv();

        let mut raw_db_url = env::var("DATABASE_URL").unwrap_or_else(|_| {
            "postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow".to_string()
        });

        // If not in docker and pointing to host 'postgres', replace with 'localhost'
        if raw_db_url.contains("@postgres:") {
            if std::net::TcpStream::connect("postgres:5432").is_err() {
                raw_db_url = raw_db_url.replace("@postgres:", "@localhost:");
            }
        }

        let current_dir = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let static_dir = if let Ok(s) = env::var("STATIC_DIR") {
            PathBuf::from(s)
        } else if current_dir.join("Aplicativos/CRM BeautyFlow/src/index.html").exists() {
            current_dir.join("Aplicativos/CRM BeautyFlow/src")
        } else if current_dir.join("src/index.html").exists() {
            current_dir.join("src")
        } else if current_dir.join("../src/index.html").exists() {
            current_dir.join("../src")
        } else if PathBuf::from("/app/src/index.html").exists() {
            PathBuf::from("/app/src")
        } else {
            current_dir.parent().map(|p| p.join("src")).unwrap_or_else(|| PathBuf::from("src"))
        };

        let db_dir = if current_dir.join("Aplicativos/CRM BeautyFlow/backend/db").exists() {
            current_dir.join("Aplicativos/CRM BeautyFlow/backend/db")
        } else if current_dir.join("backend/db").exists() {
            current_dir.join("backend/db")
        } else if current_dir.join("db").exists() {
            current_dir.join("db")
        } else {
            current_dir.join("db")
        };
        let _ = std::fs::create_dir_all(&db_dir);
        let sqlite_path = db_dir.join("whatsapp_chat.db").to_string_lossy().to_string();

        let port: u16 = env::var("PORT")
            .ok()
            .and_then(|p| p.parse().ok())
            .unwrap_or(3001);

        let n8n_webhook_url = env::var("N8N_WEBHOOK_URL").unwrap_or_else(|_| {
            "https://mirianfiorini.app.n8n.cloud/webhook/calendar-webhook".to_string()
        });

        let install_waha = env::var("INSTALL_WAHA").unwrap_or_else(|_| "false".to_string());
        let waha_api_url = env::var("WAHA_API_URL").unwrap_or_else(|_| "http://localhost:3000".to_string());
        let waha_api_key = env::var("WAHA_API_KEY").unwrap_or_else(|_| "218c0effefb845238a1ae3651c8ced5b".to_string());
        let waha_session = env::var("WAHA_SESSION").unwrap_or_else(|_| "beauty".to_string());

        Self {
            database_url: raw_db_url,
            sqlite_path,
            static_dir,
            port,
            n8n_webhook_url,
            install_waha,
            waha_api_url,
            waha_api_key,
            waha_session,
        }
    }
}
