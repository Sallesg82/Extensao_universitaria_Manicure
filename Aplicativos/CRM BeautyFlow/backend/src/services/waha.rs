use crate::db::chat_db::{clean_phone, save_message, to_chat_id};
use crate::db::SharedState;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::time::Duration;

pub const DEFAULT_API_KEY: &str = "218c0effefb845238a1ae3651c8ced5b";

pub fn get_default_templates() -> HashMap<&'static str, &'static str> {
    let mut m = HashMap::new();
    m.insert(
        "whatsapp_template_created",
        "Olá, *{nome}*! 🌸\n\nSeu agendamento de *{servico}* foi confirmado com sucesso!\n📅 *Data:* {data}\n⏰ *Horário:* {horario}\n💰 *Valor:* R$ {valor}\n\nEsperamos por você no *{empresa}*! Caso precise reagendar, por favor nos avise.",
    );
    m.insert(
        "whatsapp_template_reminder",
        "Olá, *{nome}*! 💅 Passando para lembrar do seu horário agendado de *{servico}* amanhã ({data}) às *{horario}* no *{empresa}*.\n\nQualquer imprevisto ou dúvida, por favor nos responda por aqui!",
    );
    m.insert(
        "whatsapp_template_cancelled",
        "Olá, *{nome}*.\n\nInformamos que seu agendamento de *{servico}* marcado para *{data} às {horario}* foi cancelado.\n\nFicamos à disposição para um novo agendamento quando desejar!",
    );
    m.insert(
        "whatsapp_template_return",
        "Olá, *{nome}*! ✨ Sentimos sua falta por aqui no *{empresa}*! Que tal agendarmos uma manutenção para manter suas unhas lindas e impecáveis? Responda para escolhermos o melhor horário!",
    );
    m.insert(
        "whatsapp_template_thanks",
        "Olá, *{nome}*! 💖 Muito obrigado pela sua visita ao *{empresa}* hoje! Foi um enorme prazer atender você. Esperamos vê-la novamente em breve!",
    );
    m
}

pub fn render_whatsapp_template(template: &str, context: &HashMap<&str, String>) -> String {
    let mut result = template.to_string();
    for (key, val) in context {
        let tag = format!("{{{}}}", key);
        result = result.replace(&tag, val);
    }
    result
}

pub fn candidate_urls(state: &SharedState, settings: &HashMap<String, String>) -> Vec<String> {
    let mut candidates = Vec::new();
    if let Some(custom) = settings.get("waha_api_url") {
        let trimmed = custom.trim().trim_end_matches('/').to_string();
        if !trimmed.is_empty() && !candidates.contains(&trimmed) {
            candidates.push(trimmed);
        }
    }

    let env_url = state.config.waha_api_url.trim().trim_end_matches('/').to_string();
    if !env_url.is_empty() && !candidates.contains(&env_url) {
        candidates.push(env_url);
    }

    for def in &["http://waha:3000", "http://beautyflow-waha:3000", "http://localhost:3000", "http://127.0.0.1:3000"] {
        let s = def.to_string();
        if !candidates.contains(&s) {
            candidates.push(s);
        }
    }
    candidates
}

pub fn get_api_key(state: &SharedState, settings: &HashMap<String, String>) -> String {
    if let Some(key) = settings.get("waha_api_key") {
        let trimmed = key.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    if !state.config.waha_api_key.trim().is_empty() {
        return state.config.waha_api_key.trim().to_string();
    }
    DEFAULT_API_KEY.to_string()
}

pub async fn get_working_waha_url(
    state: &SharedState,
    settings: &HashMap<String, String>,
) -> Option<String> {
    let candidates = candidate_urls(state, settings);
    let api_key = get_api_key(state, settings);

    for url in candidates {
        let req = state
            .http_client
            .get(format!("{}/ping", url))
            .header("X-Api-Key", &api_key)
            .timeout(Duration::from_secs(2))
            .send()
            .await;

        if let Ok(resp) = req {
            let status = resp.status().as_u16();
            if status == 200 || status == 401 {
                return Some(url);
            }
        }
    }
    None
}

pub async fn get_session_name(
    state: &SharedState,
    waha_url: &str,
    settings: &HashMap<String, String>,
) -> String {
    if let Some(s) = settings.get("waha_session_name") {
        let trimmed = s.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    if !state.config.waha_session.trim().is_empty() {
        return state.config.waha_session.trim().to_string();
    }

    let api_key = get_api_key(state, settings);
    let req = state
        .http_client
        .get(format!("{}/api/sessions", waha_url))
        .header("X-Api-Key", &api_key)
        .timeout(Duration::from_secs(3))
        .send()
        .await;

    if let Ok(resp) = req {
        if let Ok(sessions) = resp.json::<Vec<Value>>().await {
            for s in &sessions {
                if s.get("status").and_then(|v| v.as_str()) == Some("WORKING") {
                    if let Some(name) = s.get("name").and_then(|v| v.as_str()) {
                        return name.to_string();
                    }
                }
            }
            if let Some(first) = sessions.first() {
                if let Some(name) = first.get("name").and_then(|v| v.as_str()) {
                    return name.to_string();
                }
            }
        }
    }

    "default".to_string()
}

#[allow(dead_code)]
pub fn resolve_url_for_docker(url: &str) -> String {
    if url.contains("localhost") || url.contains("127.0.0.1") {
        if let Ok(content) = std::fs::read_to_string("/proc/net/route") {
            for line in content.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 3 && parts[1] == "00000000" {
                    if let Ok(hex_ip) = u32::from_str_radix(parts[2], 16) {
                        let ip = std::net::Ipv4Addr::from(hex_ip.to_be());
                        let gateway = ip.to_string();
                        return url
                            .replace("localhost", &gateway)
                            .replace("127.0.0.1", &gateway);
                    }
                }
            }
        }
        return url
            .replace("localhost", "172.23.0.1")
            .replace("127.0.0.1", "172.23.0.1");
    }
    url.to_string()
}

pub async fn send_whatsapp_text(
    state: &SharedState,
    waha_url: &str,
    api_key: &str,
    session_name: &str,
    phone: &str,
    text: &str,
) -> Result<Option<String>, String> {
    let clean_p = clean_phone(phone);
    if clean_p.len() < 10 {
        return Err(format!("Número de telefone inválido: {}", phone));
    }
    let chat_id = to_chat_id(&clean_p);

    let payload = json!({
        "session": session_name,
        "chatId": chat_id,
        "text": text
    });

    let resp = state
        .http_client
        .post(format!("{}/api/sendText", waha_url))
        .header("Content-Type", "application/json")
        .header("X-Api-Key", api_key)
        .json(&payload)
        .timeout(Duration::from_secs(12))
        .send()
        .await
        .map_err(|e| format!("Falha de conexão com WAHA: {}", e))?;

    let status = resp.status().as_u16();
    if status == 200 || status == 201 {
        let body: Value = resp.json().await.unwrap_or(json!({}));
        let msg_id = body.get("id").and_then(|v| {
            if let Some(s) = v.as_str() {
                Some(s.to_string())
            } else if let Some(ser) = v.get("_serialized").and_then(|x| x.as_str()) {
                Some(ser.to_string())
            } else {
                v.get("id").and_then(|x| x.as_str()).map(|s| s.to_string())
            }
        });
        Ok(msg_id)
    } else {
        let err_text = resp.text().await.unwrap_or_default();
        Err(format!("WAHA retornou erro HTTP {}: {}", status, err_text))
    }
}

pub async fn sync_waha_messages_for_chat(
    state: &SharedState,
    phone_or_chat_id: &str,
    client_name: Option<&str>,
    limit: i64,
) -> i64 {
    let settings = crate::routes::settings::get_settings_map(&state.pg).await;
    let waha_url = match get_working_waha_url(state, &settings).await {
        Some(u) => u,
        None => return 0,
    };
    let clean_p = clean_phone(phone_or_chat_id);
    let chat_id = to_chat_id(&clean_p);
    if chat_id.is_empty() {
        return 0;
    }

    let session = get_session_name(state, &waha_url, &settings).await;
    let api_key = get_api_key(state, &settings);

    let mut chat_ids_to_try = vec![chat_id.clone()];
    for p in crate::db::chat_db::get_phone_variants(&clean_p) {
        let cid = to_chat_id(&p);
        if !cid.is_empty() && !chat_ids_to_try.contains(&cid) {
            chat_ids_to_try.push(cid);
        }
    }

    let mut raw_messages: Vec<Value> = Vec::new();
    for c_id in &chat_ids_to_try {
        let endpoints = [
            format!("{}/api/{}/chats/{}/messages?limit={}&downloadMedia=false", waha_url, session, c_id, limit),
            format!("{}/api/messages?session={}&chatId={}&limit={}", waha_url, session, c_id, limit),
            format!("{}/api/{}/messages?chatId={}&limit={}", waha_url, session, c_id, limit),
            format!("{}/api/chats/{}/messages?session={}&limit={}", waha_url, session, c_id, limit),
        ];

        for ep in endpoints {
            let res = state
                .http_client
                .get(&ep)
                .header("X-Api-Key", &api_key)
                .timeout(Duration::from_secs(4))
                .send()
                .await;

            if let Ok(r) = res {
                if r.status().is_success() {
                    if let Ok(msgs) = r.json::<Vec<Value>>().await {
                        if !msgs.is_empty() {
                            raw_messages = msgs;
                            break;
                        }
                    }
                }
            }
        }
        if !raw_messages.is_empty() {
            break;
        }
    }

    let mut count = 0;
    for m in raw_messages {
        let m_id = m.get("id").and_then(|v| {
            if let Some(s) = v.as_str() {
                Some(s.to_string())
            } else if let Some(ser) = v.get("_serialized").and_then(|x| x.as_str()) {
                Some(ser.to_string())
            } else {
                v.get("id").and_then(|x| x.as_str()).map(|s| s.to_string())
            }
        });

        let mut body = m.get("body")
            .or_else(|| m.get("text"))
            .or_else(|| m.get("caption"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .trim()
            .to_string();

        let from_me = m.get("fromMe").and_then(|v| v.as_bool()).unwrap_or_else(|| {
            m.get("id").and_then(|id| id.get("fromMe")).and_then(|v| v.as_bool()).unwrap_or(false)
        });

        let ts = m.get("timestamp").and_then(|v| v.as_i64());
        let ack = m.get("ack").and_then(|v| v.as_i64()).unwrap_or(1);
        let status = if ack == 3 { "read" } else if ack == 2 { "delivered" } else { "sent" };

        let has_media = m.get("hasMedia").and_then(|v| v.as_bool()).unwrap_or(false)
            || m.get("media").is_some();
        let media_url = m.get("mediaUrl").and_then(|v| v.as_str())
            .or_else(|| m.get("media").and_then(|x| x.get("url")).and_then(|v| v.as_str()));
        let media_type = m.get("type").and_then(|v| v.as_str());
        let m_type = media_type.unwrap_or("").to_lowercase();

        if body.is_empty() && !has_media && matches!(m_type.as_str(), "e2e_notification" | "notification_template" | "protocol" | "gp2" | "revoked") {
            continue;
        }

        if body.is_empty() && has_media {
            if m_type.contains("image") {
                body = "[Imagem]".to_string();
            } else if m_type.contains("video") {
                body = "[Vídeo]".to_string();
            } else if m_type.contains("audio") || m_type.contains("ptt") {
                body = "[Áudio]".to_string();
            } else if m_type.contains("sticker") {
                body = "[Figurinha]".to_string();
            } else if m_type.contains("document") {
                body = "[Documento]".to_string();
            } else {
                body = "[Mídia]".to_string();
            }
        }

        if body.is_empty() && !has_media {
            continue;
        }

        let saved = save_message(
            &state.sqlite,
            &chat_id,
            Some(&body),
            from_me,
            m_id.as_deref(),
            ts,
            Some(status),
            media_url,
            media_type,
            Some(if from_me { "agent" } else { "client" }),
            Some(if from_me { "outgoing" } else { "incoming" }),
            client_name,
            None,
        ).await;

        if let Some(s) = saved {
            if s._is_new.unwrap_or(false) {
                count += 1;
            }
        }
    }

    count
}
