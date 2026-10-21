use regex::Regex;
use serde::{Deserialize, Serialize};
use sqlx::{Row, SqlitePool};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation {
    pub id: i64,
    pub chat_id: String,
    pub phone: String,
    pub contact_name: Option<String>,
    pub client_id: Option<i64>,
    pub unread_count: i64,
    pub last_message: Option<String>,
    pub last_message_at: Option<String>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: i64,
    pub conversation_id: Option<i64>,
    pub waha_message_id: Option<String>,
    pub chat_id: String,
    pub sender_type: String,
    pub message_type: String,
    pub content: Option<String>,
    pub media_url: Option<String>,
    pub media_type: Option<String>,
    pub status: String,
    pub from_me: i64,
    pub timestamp: i64,
    pub created_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub _is_new: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CannedResponse {
    pub id: i64,
    pub short_code: String,
    pub title: String,
    pub content: String,
    pub category: String,
}

pub fn clean_phone(raw_phone: &str) -> String {
    if raw_phone.is_empty() {
        return String::new();
    }
    let cleaned = raw_phone.split('@').next().unwrap_or("");
    let re = Regex::new(r"\D").unwrap();
    let digits = re.replace_all(cleaned, "").to_string();
    if digits.is_empty() {
        return String::new();
    }
    if digits.starts_with("55") && (digits.len() == 12 || digits.len() == 13) {
        return digits;
    }
    if digits.len() == 10 || digits.len() == 11 {
        return format!("55{}", digits);
    }
    digits
}

pub fn to_chat_id(phone_or_chat_id: &str) -> String {
    let s = phone_or_chat_id.trim();
    if s.is_empty() {
        return String::new();
    }
    if s.contains("@c.us") || s.contains("@g.us") || s.contains("@lid") {
        return s.to_string();
    }
    let p = clean_phone(s);
    if p.is_empty() {
        String::new()
    } else {
        format!("{}@c.us", p)
    }
}

pub fn get_phone_variants(phone_or_chat_id: &str) -> Vec<String> {
    let phone = clean_phone(phone_or_chat_id);
    if phone.is_empty() {
        return Vec::new();
    }
    let mut variants = vec![phone.clone()];
    if phone.starts_with("55") && phone.len() == 13 && phone.chars().nth(4) == Some('9') {
        variants.push(format!("{}{}", &phone[..4], &phone[5..]));
    } else if phone.starts_with("55") && phone.len() == 12 {
        variants.push(format!("{}9{}", &phone[..4], &phone[4..]));
    }
    variants
}

pub fn get_chat_id_variants(phone_or_chat_id: &str) -> Vec<String> {
    let mut variants = Vec::new();
    let base_cid = to_chat_id(phone_or_chat_id);
    if !base_cid.is_empty() {
        variants.push(base_cid);
    }
    for p in get_phone_variants(phone_or_chat_id) {
        let cid = to_chat_id(&p);
        if !cid.is_empty() && !variants.contains(&cid) {
            variants.push(cid);
        }
    }
    variants
}

pub async fn init_chat_db(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS whatsapp_conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chat_id TEXT UNIQUE NOT NULL,
            phone TEXT NOT NULL,
            contact_name TEXT,
            client_id INTEGER,
            unread_count INTEGER DEFAULT 0,
            last_message TEXT,
            last_message_at DATETIME,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS whatsapp_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER,
            waha_message_id TEXT UNIQUE,
            chat_id TEXT NOT NULL,
            sender_type TEXT DEFAULT 'client',
            message_type TEXT DEFAULT 'incoming',
            content TEXT,
            media_url TEXT,
            media_type TEXT,
            status TEXT DEFAULT 'sent',
            from_me INTEGER DEFAULT 0,
            timestamp INTEGER NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (conversation_id) REFERENCES whatsapp_conversations(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS whatsapp_canned_responses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            short_code TEXT UNIQUE NOT NULL,
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            category TEXT DEFAULT 'geral'
        );
        CREATE INDEX IF NOT EXISTS idx_wa_conv_chat_id ON whatsapp_conversations(chat_id);
        CREATE INDEX IF NOT EXISTS idx_wa_conv_phone ON whatsapp_conversations(phone);
        CREATE INDEX IF NOT EXISTS idx_wa_msg_chat_id ON whatsapp_messages(chat_id);
        CREATE INDEX IF NOT EXISTS idx_wa_msg_waha_id ON whatsapp_messages(waha_message_id);
        CREATE INDEX IF NOT EXISTS idx_wa_msg_timestamp ON whatsapp_messages(timestamp);
        CREATE INDEX IF NOT EXISTS idx_wa_msg_conv_id ON whatsapp_messages(conversation_id);
        "#,
    )
    .execute(pool)
    .await?;

    let count_row = sqlx::query("SELECT COUNT(*) as cnt FROM whatsapp_canned_responses")
        .fetch_one(pool)
        .await?;
    let cnt: i64 = count_row.get("cnt");
    if cnt == 0 {
        let defaults = [
            ("/confirmar", "Confirmar Agendamento", "Olá, {nome}! 🌸 Passando para confirmar seu horário de {servico} em {data} às {horario}. Esperamos por você!", "agendamento"),
            ("/lembrete", "Lembrete de Horário", "Olá, {nome}! 💅 Lembrando do seu horário de {servico} amanhã às {horario} no estúdio. Qualquer dúvida estamos à disposição!", "agendamento"),
            ("/obrigado", "Agradecimento pós-visita", "Olá, {nome}! 💖 Muito obrigado pela sua visita hoje! Foi um prazer atender você. Esperamos vê-la novamente em breve!", "relacionamento"),
            ("/retorno", "Convite para Retorno / Manutenção", "Olá, {nome}! ✨ Passando para saber como estão suas unhas! Que tal agendarmos sua manutenção para mantê-las impecáveis?", "retencao"),
            ("/atraso", "Aviso de Atraso / Tolerância", "Olá, {nome}! Informamos que temos uma tolerância de até 10 minutos para início do atendimento. Caso ocorra algum imprevisto, nos avise!", "geral"),
        ];
        for (code, title, content, cat) in defaults {
            let _ = sqlx::query(
                "INSERT OR IGNORE INTO whatsapp_canned_responses (short_code, title, content, category) VALUES (?, ?, ?, ?)"
            )
            .bind(code)
            .bind(title)
            .bind(content)
            .bind(cat)
            .execute(pool)
            .await;
        }
    }

    Ok(())
}

pub async fn get_or_create_conversation(
    pool: &SqlitePool,
    phone_or_chat_id: &str,
    contact_name: Option<&str>,
    client_id: Option<i64>,
) -> Option<Conversation> {
    let chat_id = to_chat_id(phone_or_chat_id);
    let phone = clean_phone(phone_or_chat_id);
    if chat_id.is_empty() || phone.is_empty() {
        return None;
    }

    let p_vars = get_phone_variants(phone_or_chat_id);
    let c_vars = get_chat_id_variants(phone_or_chat_id);

    let mut query_builder = String::from("SELECT * FROM whatsapp_conversations WHERE ");
    let mut conds = Vec::new();
    for _ in &c_vars {
        conds.push("chat_id = ?");
    }
    for _ in &p_vars {
        conds.push("phone = ?");
    }
    if conds.is_empty() {
        return None;
    }
    query_builder.push_str(&conds.join(" OR "));
    query_builder.push_str(" LIMIT 1");

    let mut q = sqlx::query(sqlx::AssertSqlSafe(query_builder.as_str()));
    for c in &c_vars {
        q = q.bind(c);
    }
    for p in &p_vars {
        q = q.bind(p);
    }

    let existing = q.fetch_optional(pool).await.ok().flatten();
    let now_str = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();

    if let Some(row) = existing {
        let conv_id: i64 = row.get("id");
        let curr_name: Option<String> = row.get("contact_name");
        let curr_cid: Option<i64> = row.get("client_id");

        let mut update_needed = false;
        let mut new_name = curr_name.clone();
        let mut new_client_id = curr_cid;

        if let Some(name) = contact_name {
            if curr_name.as_deref().unwrap_or("").is_empty() || curr_name.as_deref() == Some("Cliente") {
                new_name = Some(name.to_string());
                update_needed = true;
            }
        }
        if client_id.is_some() && curr_cid.is_none() {
            new_client_id = client_id;
            update_needed = true;
        }

        if update_needed {
            let _ = sqlx::query(
                "UPDATE whatsapp_conversations SET contact_name = ?, client_id = ?, updated_at = ? WHERE id = ?"
            )
            .bind(&new_name)
            .bind(new_client_id)
            .bind(&now_str)
            .bind(conv_id)
            .execute(pool)
            .await;
        }

        return Some(Conversation {
            id: conv_id,
            chat_id: row.get("chat_id"),
            phone: row.get("phone"),
            contact_name: new_name,
            client_id: new_client_id,
            unread_count: row.get("unread_count"),
            last_message: row.get("last_message"),
            last_message_at: row.get("last_message_at"),
            created_at: row.get("created_at"),
            updated_at: Some(now_str),
        });
    }

    // Insert new conversation
    let res = sqlx::query(
        "INSERT INTO whatsapp_conversations (chat_id, phone, contact_name, client_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)"
    )
    .bind(&chat_id)
    .bind(&phone)
    .bind(contact_name.unwrap_or("Cliente"))
    .bind(client_id)
    .bind(&now_str)
    .bind(&now_str)
    .execute(pool)
    .await;

    if let Ok(r) = res {
        let id = r.last_insert_rowid();
        Some(Conversation {
            id,
            chat_id,
            phone,
            contact_name: Some(contact_name.unwrap_or("Cliente").to_string()),
            client_id,
            unread_count: 0,
            last_message: None,
            last_message_at: None,
            created_at: Some(now_str.clone()),
            updated_at: Some(now_str),
        })
    } else {
        None
    }
}

pub async fn save_message(
    pool: &SqlitePool,
    chat_id_or_phone: &str,
    content: Option<&str>,
    from_me: bool,
    waha_message_id: Option<&str>,
    timestamp: Option<i64>,
    status: Option<&str>,
    media_url: Option<&str>,
    media_type: Option<&str>,
    sender_type: Option<&str>,
    message_type: Option<&str>,
    contact_name: Option<&str>,
    client_id: Option<i64>,
) -> Option<ChatMessage> {
    let chat_id = to_chat_id(chat_id_or_phone);
    if chat_id.is_empty() {
        return None;
    }

    let conv = get_or_create_conversation(pool, &chat_id, contact_name, client_id).await;
    let conv_id = conv.as_ref().map(|c| c.id);

    let from_me_int: i64 = if from_me { 1 } else { 0 };
    let stype = sender_type.unwrap_or(if from_me { "agent" } else { "client" });
    let mtype = message_type.unwrap_or(if from_me { "outgoing" } else { "incoming" });
    let stat = status.unwrap_or(if from_me { "sent" } else { "delivered" });

    let ts = timestamp.unwrap_or_else(|| {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64
    });
    let ts_norm = if ts > 10_000_000_000 { ts / 1000 } else { ts };
    let now_dt = chrono::DateTime::from_timestamp(ts_norm, 0)
        .map(|d| d.naive_local().format("%Y-%m-%d %H:%M:%S").to_string())
        .unwrap_or_else(|| chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string());

    if let Some(waha_id) = waha_message_id {
        if let Ok(Some(existing)) = sqlx::query("SELECT * FROM whatsapp_messages WHERE waha_message_id = ?")
            .bind(waha_id)
            .fetch_optional(pool)
            .await
        {
            let id: i64 = existing.get("id");
            let _ = sqlx::query(
                "UPDATE whatsapp_messages SET status = COALESCE(?, status), content = COALESCE(?, content), media_url = COALESCE(?, media_url) WHERE id = ?"
            )
            .bind(status)
            .bind(content)
            .bind(media_url)
            .bind(id)
            .execute(pool)
            .await;

            return Some(ChatMessage {
                id,
                conversation_id: existing.get("conversation_id"),
                waha_message_id: Some(waha_id.to_string()),
                chat_id: existing.get("chat_id"),
                sender_type: existing.get("sender_type"),
                message_type: existing.get("message_type"),
                content: content.map(|s| s.to_string()).or_else(|| existing.get("content")),
                media_url: media_url.map(|s| s.to_string()).or_else(|| existing.get("media_url")),
                media_type: existing.get("media_type"),
                status: status.map(|s| s.to_string()).unwrap_or_else(|| existing.get("status")),
                from_me: existing.get("from_me"),
                timestamp: existing.get("timestamp"),
                created_at: existing.get("created_at"),
                _is_new: Some(false),
            });
        }
    }

    let insert_res = sqlx::query(
        r#"
        INSERT INTO whatsapp_messages (
            conversation_id, waha_message_id, chat_id, sender_type,
            message_type, content, media_url, media_type, status,
            from_me, timestamp, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(conv_id)
    .bind(waha_message_id)
    .bind(&chat_id)
    .bind(stype)
    .bind(mtype)
    .bind(content)
    .bind(media_url)
    .bind(media_type)
    .bind(stat)
    .bind(from_me_int)
    .bind(ts_norm)
    .bind(&now_dt)
    .execute(pool)
    .await;

    if let Ok(res) = insert_res {
        let msg_id = res.last_insert_rowid();

        if let Some(cid) = conv_id {
            let unread_inc = if from_me { 0 } else { 1 };
            let last_txt = content.unwrap_or("[Mídia]");
            let _ = sqlx::query(
                r#"
                UPDATE whatsapp_conversations
                SET last_message = ?,
                    last_message_at = ?,
                    unread_count = unread_count + ?,
                    updated_at = ?
                WHERE id = ?
                "#,
            )
            .bind(last_txt)
            .bind(&now_dt)
            .bind(unread_inc)
            .bind(&now_dt)
            .bind(cid)
            .execute(pool)
            .await;
        }

        Some(ChatMessage {
            id: msg_id,
            conversation_id: conv_id,
            waha_message_id: waha_message_id.map(|s| s.to_string()),
            chat_id,
            sender_type: stype.to_string(),
            message_type: mtype.to_string(),
            content: content.map(|s| s.to_string()),
            media_url: media_url.map(|s| s.to_string()),
            media_type: media_type.map(|s| s.to_string()),
            status: stat.to_string(),
            from_me: from_me_int,
            timestamp: ts_norm,
            created_at: Some(now_dt),
            _is_new: Some(true),
        })
    } else {
        None
    }
}

pub async fn get_conversation_messages(
    pool: &SqlitePool,
    phone_or_chat_id: &str,
    limit: i64,
    offset: i64,
) -> Vec<ChatMessage> {
    let p_vars = get_phone_variants(phone_or_chat_id);
    let c_vars = get_chat_id_variants(phone_or_chat_id);
    if p_vars.is_empty() && c_vars.is_empty() {
        return Vec::new();
    }

    let mut query = String::from(
        r#"
        SELECT m.*
        FROM whatsapp_messages m
        LEFT JOIN whatsapp_conversations c ON m.conversation_id = c.id
        WHERE 
        "#,
    );

    let mut conds = Vec::new();
    for _ in &c_vars {
        conds.push("m.chat_id = ?");
    }
    for _ in &p_vars {
        conds.push("c.phone = ?");
    }
    query.push_str(&format!("({}) ORDER BY m.timestamp ASC, m.id ASC LIMIT ? OFFSET ?", conds.join(" OR ")));

    let mut q = sqlx::query(sqlx::AssertSqlSafe(query.as_str()));
    for c in &c_vars {
        q = q.bind(c);
    }
    for p in &p_vars {
        q = q.bind(p);
    }
    q = q.bind(limit).bind(offset);

    let rows = q.fetch_all(pool).await.unwrap_or_default();
    rows.into_iter()
        .map(|r| ChatMessage {
            id: r.get("id"),
            conversation_id: r.get("conversation_id"),
            waha_message_id: r.get("waha_message_id"),
            chat_id: r.get("chat_id"),
            sender_type: r.get("sender_type"),
            message_type: r.get("message_type"),
            content: r.get("content"),
            media_url: r.get("media_url"),
            media_type: r.get("media_type"),
            status: r.get("status"),
            from_me: r.get("from_me"),
            timestamp: r.get("timestamp"),
            created_at: r.get("created_at"),
            _is_new: None,
        })
        .collect()
}

#[allow(dead_code)]
pub async fn mark_conversation_as_read(pool: &SqlitePool, phone_or_chat_id: &str) {
    let chat_id = to_chat_id(phone_or_chat_id);
    let phone = clean_phone(phone_or_chat_id);
    if chat_id.is_empty() {
        return;
    }

    let _ = sqlx::query(
        "UPDATE whatsapp_conversations SET unread_count = 0 WHERE chat_id = ? OR phone = ?"
    )
    .bind(&chat_id)
    .bind(&phone)
    .execute(pool)
    .await;

    let _ = sqlx::query(
        r#"
        UPDATE whatsapp_messages
        SET status = 'read'
        WHERE (chat_id = ? OR conversation_id IN (SELECT id FROM whatsapp_conversations WHERE phone = ?))
          AND from_me = 0 AND status != 'read'
        "#
    )
    .bind(&chat_id)
    .bind(&phone)
    .execute(pool)
    .await;
}

pub async fn get_canned_responses(pool: &SqlitePool) -> Vec<CannedResponse> {
    let rows = sqlx::query("SELECT * FROM whatsapp_canned_responses ORDER BY category, title")
        .fetch_all(pool)
        .await
        .unwrap_or_default();

    rows.into_iter()
        .map(|r| CannedResponse {
            id: r.get("id"),
            short_code: r.get("short_code"),
            title: r.get("title"),
            content: r.get("content"),
            category: r.get("category"),
        })
        .collect()
}

pub async fn get_recent_conversations(pool: &SqlitePool, limit: i64) -> Vec<Conversation> {
    let rows = sqlx::query(
        "SELECT * FROM whatsapp_conversations ORDER BY last_message_at DESC, updated_at DESC LIMIT ?"
    )
    .bind(limit)
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    rows.into_iter()
        .map(|r| Conversation {
            id: r.get("id"),
            chat_id: r.get("chat_id"),
            phone: r.get("phone"),
            contact_name: r.get("contact_name"),
            client_id: r.get("client_id"),
            unread_count: r.get("unread_count"),
            last_message: r.get("last_message"),
            last_message_at: r.get("last_message_at"),
            created_at: r.get("created_at"),
            updated_at: r.get("updated_at"),
        })
        .collect()
}

pub async fn save_simple_message(
    pool: &SqlitePool,
    chat_id_or_phone: &str,
    waha_message_id: Option<&str>,
    from_me: bool,
    content: Option<&str>,
    timestamp: Option<i64>,
    status: Option<&str>,
    media_url: Option<&str>,
    contact_name: Option<&str>,
) -> Option<ChatMessage> {
    save_message(
        pool,
        chat_id_or_phone,
        content,
        from_me,
        waha_message_id,
        timestamp,
        status,
        media_url,
        None,
        Some(if from_me { "agent" } else { "client" }),
        Some("text"),
        contact_name,
        None,
    )
    .await
}

pub use get_conversation_messages as get_messages;
pub use get_recent_conversations as get_conversations;
pub use init_chat_db as init_sqlite_schema;
