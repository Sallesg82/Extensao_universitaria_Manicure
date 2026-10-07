use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use chrono::{Datelike, Local, NaiveDate};
use serde::Deserialize;
use sqlx::Row;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::Arc;

use crate::db::AppState;
use crate::routes::metas::get_meta_value;

#[derive(Debug, Deserialize)]
pub struct StatsQuery {
    pub period: Option<i32>,
    pub month: Option<i32>,
    pub year: Option<i32>,
}

pub fn router() -> Router<Arc<AppState>> {
    Router::new().route("/", get(get_stats))
}

fn days_in_month(year: i32, month: u32) -> u32 {
    let next_month_date = if month == 12 {
        NaiveDate::from_ymd_opt(year + 1, 1, 1)
    } else {
        NaiveDate::from_ymd_opt(year, month + 1, 1)
    };
    next_month_date
        .and_then(|d| d.pred_opt())
        .map(|d| d.day())
        .unwrap_or(30)
}

fn month_pt(m: u32) -> &'static str {
    match m {
        1 => "Janeiro",
        2 => "Fevereiro",
        3 => "Março",
        4 => "Abril",
        5 => "Maio",
        6 => "Junho",
        7 => "Julho",
        8 => "Agosto",
        9 => "Setembro",
        10 => "Outubro",
        11 => "Novembro",
        12 => "Dezembro",
        _ => "",
    }
}

fn day_pt(d: chrono::Weekday) -> &'static str {
    match d {
        chrono::Weekday::Mon => "Seg",
        chrono::Weekday::Tue => "Ter",
        chrono::Weekday::Wed => "Qua",
        chrono::Weekday::Thu => "Qui",
        chrono::Weekday::Fri => "Sex",
        chrono::Weekday::Sat => "Sáb",
        chrono::Weekday::Sun => "Dom",
    }
}

async fn get_stats(
    State(state): State<Arc<AppState>>,
    Query(q): Query<StatsQuery>,
) -> Result<impl IntoResponse, (StatusCode, Json<serde_json::Value>)> {
    let now = Local::now();
    let today = now.date_naive();
    let today_str = today.to_string();

    let target_month: u32;
    let target_year: i32;
    let month_start: NaiveDate;
    let month_end: NaiveDate;

    if q.month.is_some() || q.year.is_some() {
        target_month = q.month.unwrap_or(now.month() as i32).clamp(1, 12) as u32;
        target_year = q.year.unwrap_or(now.year());
        let last_day = days_in_month(target_year, target_month);
        month_start = NaiveDate::from_ymd_opt(target_year, target_month, 1).unwrap_or(today);
        month_end = NaiveDate::from_ymd_opt(target_year, target_month, last_day).unwrap_or(today);
    } else {
        target_month = now.month();
        target_year = now.year();
        match q.period.unwrap_or(0) {
            7 => {
                let days_from_sun = (now.weekday().num_days_from_sunday()) as i64;
                month_start = today - chrono::Duration::days(days_from_sun);
                month_end = today;
            }
            30 => {
                month_start = NaiveDate::from_ymd_opt(target_year, target_month, 1).unwrap_or(today);
                month_end = today;
            }
            90 => {
                let mut m = target_month as i32 - 3;
                let mut y = target_year;
                while m < 1 {
                    m += 12;
                    y -= 1;
                }
                month_start = NaiveDate::from_ymd_opt(y, m as u32, 1).unwrap_or(today);
                month_end = today;
            }
            365 => {
                month_start = NaiveDate::from_ymd_opt(target_year, 1, 1).unwrap_or(today);
                month_end = today;
            }
            _ => {
                let last_day = days_in_month(target_year, target_month);
                month_start = NaiveDate::from_ymd_opt(target_year, target_month, 1).unwrap_or(today);
                month_end = NaiveDate::from_ymd_opt(target_year, target_month, last_day).unwrap_or(today);
            }
        }
    }

    let (prev_y, prev_m) = if target_month == 1 {
        (target_year - 1, 12)
    } else {
        (target_year, target_month - 1)
    };
    let prev_last_day = days_in_month(prev_y, prev_m);
    let prev_month_start = NaiveDate::from_ymd_opt(prev_y, prev_m, 1).unwrap_or(today);
    let prev_month_last = NaiveDate::from_ymd_opt(prev_y, prev_m, prev_last_day).unwrap_or(today);

    // 1. Agendamentos de hoje
    let today_rows = sqlx::query(
        r#"
        SELECT a.id, a.client_id, a.service, a.price, a.appointment_date, a.appointment_time, a.duration, a.status, a.notes, a.created_at,
               COALESCE(c.name, '(Cliente removido)') AS client_name,
               COALESCE(c.phone, '') AS client_phone
        FROM public.appointments a
        LEFT JOIN public.clients c ON c.id = a.client_id
        WHERE a.appointment_date = $1
        ORDER BY a.appointment_time ASC
        "#
    )
    .bind(today)
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    let mut today_full = Vec::new();
    let mut today_pending = 0;
    for r in &today_rows {
        let status: String = r.get("status");
        if status == "pending" {
            today_pending += 1;
        }
        let time_str: String = r.get::<Option<String>, _>("appointment_time").unwrap_or_default();
        let short_time = if time_str.len() >= 5 { &time_str[..5] } else { &time_str };

        today_full.push(serde_json::json!({
            "id": r.get::<i32, _>("id"),
            "client_id": r.get::<Option<i32>, _>("client_id"),
            "client_name": r.get::<String, _>("client_name"),
            "client_phone": r.get::<String, _>("client_phone"),
            "service": r.get::<String, _>("service"),
            "price": r.get::<f32, _>("price"),
            "appointment_date": today_str,
            "appointment_time": short_time,
            "duration": r.get::<i32, _>("duration"),
            "status": status,
            "notes": r.get::<Option<String>, _>("notes").unwrap_or_default(),
        }));
    }
    let today_count = today_full.len();

    // 2. Agendamentos do mês selecionado
    let month_appts = sqlx::query(
        "SELECT id, client_id, service, price, appointment_date, appointment_time, status \
         FROM public.appointments \
         WHERE appointment_date >= $1 AND appointment_date <= $2"
    )
    .bind(month_start)
    .bind(month_end)
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    let month_appointments_count = month_appts.len();
    let mut month_clients_set = HashSet::new();
    let mut svc_counts: HashMap<String, i32> = HashMap::new();
    let mut month_full = Vec::new();

    for a in &month_appts {
        if let Some(cid) = a.get::<Option<i32>, _>("client_id") {
            month_clients_set.insert(cid);
        }
        let status: String = a.get("status");
        let svc: String = a.get("service");
        let a_date: NaiveDate = a.get("appointment_date");
        let a_time: Option<String> = a.get("appointment_time");
        let short_time = a_time.as_deref().map(|t| if t.len() >= 5 { &t[..5] } else { t }).unwrap_or_default();

        if status == "confirmed" || status == "done" {
            *svc_counts.entry(if svc.is_empty() { "Outros".to_string() } else { svc.clone() }).or_insert(0) += 1;
        }

        month_full.push(serde_json::json!({
            "appointment_date": a_date.to_string(),
            "appointment_time": short_time,
            "status": status,
            "service": svc,
            "price": a.get::<f32, _>("price"),
        }));
    }
    let month_clients_count = month_clients_set.len();

    let total_svc: i32 = svc_counts.values().sum();
    let mut service_breakdown: Vec<serde_json::Value> = svc_counts
        .into_iter()
        .map(|(k, v)| {
            let pct = if total_svc > 0 { ((v as f64 / total_svc as f64) * 1000.0).round() / 10.0 } else { 0.0 };
            serde_json::json!({ "name": k, "count": v, "pct": pct })
        })
        .collect();
    service_breakdown.sort_by(|a, b| b["count"].as_i64().cmp(&a["count"].as_i64()));
    service_breakdown.truncate(5);

    // 3. Receita e Despesas do mês
    let month_txs = sqlx::query(
        "SELECT id, type, amount, date, category, service, payment_method, client_name \
         FROM public.transactions \
         WHERE date >= $1 AND date <= $2"
    )
    .bind(month_start)
    .bind(month_end)
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    let mut month_revenue = 0.0;
    let mut month_expenses = 0.0;
    let mut today_revenue = 0.0;
    let mut svc_revenue: HashMap<String, f64> = HashMap::new();
    let mut weekly_rev: BTreeMap<u32, f64> = BTreeMap::new();
    let mut daily_rev: BTreeMap<String, f64> = BTreeMap::new();
    let mut daily_exp: BTreeMap<String, f64> = BTreeMap::new();
    let mut exp_cat: HashMap<String, f64> = HashMap::new();
    let mut pix_pending = 0;

    for t in &month_txs {
        let t_type: String = t.get("type");
        let amount = t.get::<f32, _>("amount") as f64;
        let d: NaiveDate = t.get("date");
        let d_str = d.to_string();

        if t_type == "income" {
            month_revenue += amount;
            if d == today {
                today_revenue += amount;
            }
            let s_name = t.get::<Option<String>, _>("service").filter(|s| !s.trim().is_empty()).unwrap_or_else(|| "Outros".to_string());
            *svc_revenue.entry(s_name).or_insert(0.0) += amount;

            let week = (d.day() - 1) / 7;
            *weekly_rev.entry(week).or_insert(0.0) += amount;
            *daily_rev.entry(d_str).or_insert(0.0) += amount;

            let pm: Option<String> = t.get("payment_method");
            if pm.as_deref().unwrap_or("").to_lowercase() == "pix" {
                pix_pending += 1;
            }
        } else if t_type == "expense" {
            month_expenses += amount;
            *daily_exp.entry(d_str).or_insert(0.0) += amount;

            let cat = t.get::<Option<String>, _>("category").filter(|c| !c.trim().is_empty()).unwrap_or_else(|| "Outros".to_string());
            *exp_cat.entry(cat).or_insert(0.0) += amount;
        }
    }

    if !(target_year == now.year() && target_month == now.month()) {
        let t_rev_row = sqlx::query_scalar::<_, Option<f32>>(
            "SELECT SUM(amount) FROM public.transactions WHERE type = 'income' AND date = $1"
        )
        .bind(today)
        .fetch_one(&state.pg_pool)
        .await
        .unwrap_or(None);
        today_revenue = t_rev_row.unwrap_or(0.0) as f64;
    }

    // Weekly revenue array
    let max_week = weekly_rev.keys().last().cloned().unwrap_or(0);
    let mut weekly_revenue = Vec::new();
    for w in 0..=max_week {
        weekly_revenue.push(((weekly_rev.get(&w).copied().unwrap_or(0.0) * 100.0).round()) / 100.0);
    }

    // Service revenue breakdown
    let total_svc_rev: f64 = svc_revenue.values().sum();
    let mut service_revenue_breakdown: Vec<serde_json::Value> = svc_revenue
        .into_iter()
        .map(|(k, v)| {
            let pct = if total_svc_rev > 0.0 { ((v / total_svc_rev) * 1000.0).round() / 10.0 } else { 0.0 };
            serde_json::json!({ "name": k, "revenue": (v * 100.0).round() / 100.0, "pct": pct })
        })
        .collect();
    service_revenue_breakdown.sort_by(|a, b| {
        b["revenue"].as_f64().partial_cmp(&a["revenue"].as_f64()).unwrap_or(std::cmp::Ordering::Equal)
    });

    // Daily breakdown
    let mut all_days: Vec<String> = daily_rev.keys().chain(daily_exp.keys()).cloned().collect();
    all_days.sort();
    all_days.dedup();

    let mut daily_breakdown = Vec::new();
    for d_str in all_days {
        let label = NaiveDate::parse_from_str(&d_str, "%Y-%m-%d")
            .map(|d| day_pt(d.weekday()))
            .unwrap_or("Dia");
        daily_breakdown.push(serde_json::json!({
            "day": label,
            "date": d_str,
            "revenue": (daily_rev.get(&d_str).copied().unwrap_or(0.0) * 100.0).round() / 100.0,
            "expense": (daily_exp.get(&d_str).copied().unwrap_or(0.0) * 100.0).round() / 100.0,
        }));
    }

    // Expenses by category
    let total_exp_sum: f64 = exp_cat.values().sum();
    let mut expenses_by_category: Vec<serde_json::Value> = exp_cat
        .into_iter()
        .map(|(cat, val)| {
            let pct = if total_exp_sum > 0.0 { ((val / total_exp_sum) * 1000.0).round() / 10.0 } else { 0.0 };
            serde_json::json!({ "category": cat, "amount": (val * 100.0).round() / 100.0, "pct": pct })
        })
        .collect();
    expenses_by_category.sort_by(|a, b| {
        b["amount"].as_f64().partial_cmp(&a["amount"].as_f64()).unwrap_or(std::cmp::Ordering::Equal)
    });

    // 4. All-time aggregate
    let all_agg = sqlx::query(
        "SELECT COUNT(*) AS cnt, COALESCE(SUM(amount), 0.0) AS total FROM public.transactions WHERE type = 'income'"
    )
    .fetch_one(&state.pg_pool)
    .await;

    let (income_cnt, total_revenue_all): (i64, f64) = match all_agg {
        Ok(r) => {
            let cnt: i64 = r.get("cnt");
            let total = r
                .try_get::<f64, _>("total")
                .or_else(|_| r.try_get::<f32, _>("total").map(|v| v as f64))
                .unwrap_or(0.0);
            (cnt, total)
        }
        Err(_) => (0, 0.0),
    };
    let avg_ticket = if income_cnt > 0 {
        ((total_revenue_all / income_cnt as f64) * 100.0).round() / 100.0
    } else {
        0.0
    };

    // 5. Active clients total
    let active_clients: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM public.clients")
        .fetch_one(&state.pg_pool)
        .await
        .unwrap_or(0);

    // 6. Meta
    let target_mes = format!("{:04}-{:02}", target_year, target_month);
    let meta_mensal = get_meta_value(&state.pg_pool, &target_mes).await as f64;
    let meta_pct = if meta_mensal > 0.0 {
        ((month_revenue / meta_mensal) * 1000.0).round() / 10.0
    } else {
        0.0
    };

    // 7. Top clients
    let top_rows = sqlx::query(
        r#"
        SELECT c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color,
               COUNT(a.id) AS visits,
               COALESCE(SUM(a.price), 0.0) AS total_spent,
               MAX(a.appointment_date) AS last_visit
        FROM public.clients c
        JOIN public.appointments a ON a.client_id = c.id
        WHERE a.status IN ('done', 'confirmed') AND a.appointment_date >= $1 AND a.appointment_date <= $2
        GROUP BY c.id, c.name, c.avatar_initials, c.avatar_bg, c.avatar_color
        ORDER BY total_spent DESC
        LIMIT 5
        "#
    )
    .bind(month_start)
    .bind(month_end)
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    let mut top_clients = Vec::new();
    for r in &top_rows {
        let name: String = r.get("name");
        let initials: String = r.get::<Option<String>, _>("avatar_initials").unwrap_or_else(|| {
            if name.len() >= 2 { name[..2].to_uppercase() } else { "??".to_string() }
        });
        let last_v: Option<NaiveDate> = r.get("last_visit");

        let spent = r
            .try_get::<f64, _>("total_spent")
            .or_else(|_| r.try_get::<f32, _>("total_spent").map(|v| v as f64))
            .unwrap_or(0.0);

        top_clients.push(serde_json::json!({
            "id": r.get::<i32, _>("id"),
            "name": name,
            "avatar_initials": initials,
            "avatar_bg": r.get::<Option<String>, _>("avatar_bg").unwrap_or_else(|| "#e8f2fc".to_string()),
            "avatar_color": r.get::<Option<String>, _>("avatar_color").unwrap_or_else(|| "#1a5fab".to_string()),
            "visits": r.get::<i64, _>("visits"),
            "total_spent": (spent * 100.0).round() / 100.0,
            "last_visit": last_v.map(|d| d.to_string()),
        }));
    }

    // 8. Recent transactions
    let recent_tx_rows = sqlx::query(
        "SELECT id, type, description, amount, category, payment_method, date, client_name, service \
         FROM public.transactions \
         WHERE date >= $1 AND date <= $2 \
         ORDER BY date DESC, id DESC LIMIT 10"
    )
    .bind(month_start)
    .bind(month_end)
    .fetch_all(&state.pg_pool)
    .await
    .unwrap_or_default();

    let mut recent_transactions = Vec::new();
    for r in &recent_tx_rows {
        let d: NaiveDate = r.get("date");
        recent_transactions.push(serde_json::json!({
            "id": r.get::<i32, _>("id"),
            "type": r.get::<String, _>("type"),
            "description": r.get::<String, _>("description"),
            "amount": r.get::<f32, _>("amount"),
            "category": r.get::<Option<String>, _>("category").unwrap_or_default(),
            "payment_method": r.get::<Option<String>, _>("payment_method").unwrap_or_default(),
            "date": d.to_string(),
            "client_name": r.get::<Option<String>, _>("client_name").unwrap_or_default(),
            "service": r.get::<Option<String>, _>("service").unwrap_or_default(),
        }));
    }

    // 9. Previous month revenue
    let prev_inc_sum = sqlx::query_scalar::<_, Option<f32>>(
        "SELECT SUM(amount) FROM public.transactions WHERE type = 'income' AND date >= $1 AND date <= $2"
    )
    .bind(prev_month_start)
    .bind(prev_month_last)
    .fetch_one(&state.pg_pool)
    .await
    .unwrap_or(None);
    let month_revenue_prev = (prev_inc_sum.unwrap_or(0.0) as f64 * 100.0).round() / 100.0;

    // 10. Inactive clients (30+ days since last visit or never visited)
    let thirty_days_ago = today - chrono::Duration::days(30);
    let v_clients = sqlx::query("SELECT total_spent, last_visit FROM public.v_clients")
        .fetch_all(&state.pg_pool)
        .await
        .unwrap_or_default();

    let mut inactive_count = 0;
    let mut inactive_revenue = 0.0;
    for cl in &v_clients {
        let lv: Option<NaiveDate> = cl.get("last_visit");
        let spent = cl.get::<Option<f32>, _>("total_spent").unwrap_or(0.0) as f64;
        match lv {
            None => {
                inactive_count += 1;
                inactive_revenue += spent;
            }
            Some(d) if d < thirty_days_ago => {
                inactive_count += 1;
                inactive_revenue += spent;
            }
            _ => {}
        }
    }

    // 11. Future pending appointments
    let pending_future_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM public.appointments WHERE status = 'pending' AND appointment_date >= $1"
    )
    .bind(today)
    .fetch_one(&state.pg_pool)
    .await
    .unwrap_or(0);

    // 12. Unread notifications
    let mut notifications_unread: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM public.notifications WHERE read = false"
    )
    .fetch_one(&state.pg_pool)
    .await
    .unwrap_or(0);

    // 13. Goal Reached Notification check
    if target_month == now.month() && target_year == now.year() && month_revenue >= meta_mensal && meta_mensal > 0.0 {
        let notify_enabled: Option<String> = sqlx::query_scalar(
            "SELECT value FROM public.settings WHERE key = 'notify_alerta_de_meta_atingida' LIMIT 1"
        )
        .fetch_optional(&state.pg_pool)
        .await
        .unwrap_or(None);

        if notify_enabled.as_deref().unwrap_or("true") == "true" {
            let exists: Option<i32> = sqlx::query_scalar(
                "SELECT id FROM public.notifications WHERE type = 'meta_atingida' LIMIT 1"
            )
            .fetch_optional(&state.pg_pool)
            .await
            .unwrap_or(None);

            if exists.is_none() {
                let msg = format!(
                    "Parabéns! A meta de R$ {:.0} foi alcançada. Entrada atual: R$ {:.2}",
                    meta_mensal, month_revenue
                );
                let _ = sqlx::query(
                    "INSERT INTO public.notifications (type, title, message) VALUES ('meta_atingida', 'Meta Mensal Atingida!', $1)"
                )
                .bind(msg)
                .execute(&state.pg_pool)
                .await;
                notifications_unread += 1;
            }
        }
    }

    Ok(Json(serde_json::json!({
        "today_revenue": (today_revenue * 100.0).round() / 100.0,
        "today_count": today_count,
        "today_pending": today_pending,
        "active_clients": active_clients,
        "avg_ticket": avg_ticket,
        "month_revenue": (month_revenue * 100.0).round() / 100.0,
        "month_expenses": (month_expenses * 100.0).round() / 100.0,
        "month_label": month_pt(target_month),
        "month_year": target_year,
        "selected_month": target_month,
        "selected_year": target_year,
        "month_clients": month_clients_count,
        "weekly_revenue": weekly_revenue,
        "service_breakdown": service_breakdown,
        "service_revenue_breakdown": service_revenue_breakdown,
        "meta_mensal": meta_mensal,
        "meta_pct": meta_pct,
        "pix_pending": pix_pending,
        "total_revenue_all": (total_revenue_all * 100.0).round() / 100.0,
        "month_appointments_count": month_appointments_count,
        "top_clients": top_clients,
        "today_appointments": today_full,
        "daily_breakdown": daily_breakdown,
        "recent_transactions": recent_transactions,
        "expenses_by_category": expenses_by_category,
        "month_revenue_prev": month_revenue_prev,
        "month_appointments": month_full,
        "inactive_clients": inactive_count,
        "inactive_revenue": (inactive_revenue * 100.0).round() / 100.0,
        "pending_future": pending_future_count,
        "notifications_unread": notifications_unread,
    })))
}
