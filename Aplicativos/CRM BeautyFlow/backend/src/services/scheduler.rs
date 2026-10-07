use crate::db::SharedState;
use crate::services::waha::{get_api_key, get_default_templates, get_session_name, get_working_waha_url, render_whatsapp_template, send_whatsapp_text};
use chrono::{Duration, Local, NaiveDateTime, NaiveTime, Timelike};
use sqlx::Row;
use std::collections::HashMap;

pub async fn process_pending_whatsapp_reminders(state: SharedState) -> usize {
    let settings = crate::routes::settings::get_settings_map(&state.pg).await;
    let enabled = settings
        .get("whatsapp_auto_notify_reminder")
        .map(|v| v.as_str())
        .unwrap_or("true")
        == "true";

    if !enabled {
        return 0;
    }

    let waha_url = match get_working_waha_url(&state, &settings).await {
        Some(u) => u,
        None => return 0,
    };

    let timing = settings
        .get("whatsapp_reminder_timing")
        .map(|v| v.as_str())
        .unwrap_or("1_day");

    let now = Local::now();
    let today = now.date_naive();
    let mut target_dates = Vec::new();
    let is_hour_based = matches!(timing, "2_hours" | "4_hours" | "6_hours");

    match timing {
        "1_day" => target_dates.push(today + Duration::days(1)),
        "2_days" => target_dates.push(today + Duration::days(2)),
        "3_days" => target_dates.push(today + Duration::days(3)),
        "same_day" => target_dates.push(today),
        _ if is_hour_based => target_dates.push(today),
        _ => target_dates.push(today + Duration::days(1)),
    }

    let mut sent_count = 0;
    let session_name = get_session_name(&state, &waha_url, &settings).await;
    let api_key = get_api_key(&state, &settings);
    let empresa = settings
        .get("company_name")
        .or_else(|| settings.get("studio_name"))
        .cloned()
        .unwrap_or_else(|| "BeautyFlow".to_string());

    let def_tmpls = get_default_templates();
    let tmpl_str = settings
        .get("whatsapp_template_reminder")
        .map(|s| s.as_str())
        .unwrap_or_else(|| def_tmpls.get("whatsapp_template_reminder").unwrap());

    for t_date in target_dates {
        let appts = sqlx::query(
            r#"
            SELECT a.*, c.name as client_name, c.phone as client_phone
            FROM appointments a
            LEFT JOIN clients c ON c.id = a.client_id
            WHERE a.appointment_date = $1
            "#,
        )
        .bind(t_date)
        .fetch_all(&state.pg)
        .await
        .unwrap_or_default();

        for a in appts {
            let status: String = a.get("status");
            if status == "cancelled" || status == "completed" {
                continue;
            }

            let appt_id: i32 = a.get("id");
            let already = sqlx::query(
                "SELECT id FROM notifications WHERE type = 'whatsapp_reminder' AND related_id = $1 LIMIT 1"
            )
            .bind(appt_id)
            .fetch_optional(&state.pg)
            .await
            .unwrap_or(None);

            if already.is_some() {
                continue;
            }

            let appt_time_val: NaiveTime = a.get("appointment_time");
            let appt_time_str = appt_time_val.format("%H:%M").to_string();

            if is_hour_based {
                let appt_dt = NaiveDateTime::new(t_date, appt_time_val);
                let diff_minutes = (appt_dt.and_utc().timestamp() - now.naive_local().and_utc().timestamp()) / 60;
                match timing {
                    "2_hours" if !(60..=150).contains(&diff_minutes) => continue,
                    "4_hours" if !(180..=270).contains(&diff_minutes) => continue,
                    "6_hours" if !(300..=390).contains(&diff_minutes) => continue,
                    _ => {}
                }
            }

            let client_phone: Option<String> = a.get("client_phone");
            let phone = match client_phone {
                Some(p) if !p.trim().is_empty() => p,
                _ => continue,
            };

            let client_name = a
                .get::<Option<String>, _>("client_name")
                .unwrap_or_else(|| "Cliente".to_string());
            let first_name = client_name
                .split_whitespace()
                .next()
                .unwrap_or("Cliente")
                .to_string();

            let service: String = a.get("service");
            let price: f32 = a.get("price");
            let date_fmt = t_date.format("%d/%m/%Y").to_string();
            let price_val = format!("{:.2}", price).replace('.', ",");

            let mut ctx = HashMap::new();
            ctx.insert("nome", client_name.clone());
            ctx.insert("primeiro_nome", first_name);
            ctx.insert("servico", service.clone());
            ctx.insert("data", date_fmt.clone());
            ctx.insert("horario", appt_time_str.clone());
            ctx.insert("valor", price_val);
            ctx.insert("empresa", empresa.clone());

            let msg = render_whatsapp_template(tmpl_str, &ctx);

            if let Ok(msg_id) = send_whatsapp_text(
                &state,
                &waha_url,
                &api_key,
                &session_name,
                &phone,
                &msg,
            )
            .await
            {
                let _ = crate::db::chat_db::save_message(
                    &state.sqlite,
                    &phone,
                    Some(&msg),
                    true,
                    msg_id.as_deref(),
                    None,
                    Some("sent"),
                    None,
                    None,
                    Some("agent"),
                    Some("template"),
                    Some(&client_name),
                    None,
                )
                .await;

                let notif_msg = format!("Lembrete automático enviado para {} ({} às {})", client_name, date_fmt, appt_time_str);
                let _ = sqlx::query(
                    r#"
                    INSERT INTO notifications (type, title, message, related_id, related_type, read)
                    VALUES ('whatsapp_reminder', 'Lembrete WhatsApp Enviado', $1, $2, 'appointment', false)
                    "#
                )
                .bind(&notif_msg)
                .bind(appt_id)
                .execute(&state.pg)
                .await;

                sent_count += 1;
            }
        }
    }

    sent_count
}

pub fn start_whatsapp_reminder_scheduler(state: SharedState) {
    tokio::spawn(async move {
        tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
        let mut last_minute = String::new();

        loop {
            let now = Local::now();
            let current_min = now.format("%Y-%m-%d %H:%M").to_string();

            if current_min != last_minute {
                last_minute = current_min;
                let settings = crate::routes::settings::get_settings_map(&state.pg).await;
                let timing = settings
                    .get("whatsapp_reminder_timing")
                    .map(|v| v.as_str())
                    .unwrap_or("1_day");
                let pref_time = settings
                    .get("whatsapp_reminder_time")
                    .map(|v| v.as_str())
                    .unwrap_or("09:00");
                let now_time = now.format("%H:%M").to_string();

                if matches!(timing, "2_hours" | "4_hours" | "6_hours") {
                    if now.minute() % 10 == 0 {
                        process_pending_whatsapp_reminders(state.clone()).await;
                    }
                } else if now_time == pref_time {
                    process_pending_whatsapp_reminders(state.clone()).await;
                }
            }

            tokio::time::sleep(tokio::time::Duration::from_secs(25)).await;
        }
    });
}

pub use start_whatsapp_reminder_scheduler as start_scheduler_loop;
pub use process_pending_whatsapp_reminders as trigger_reminders_check;

