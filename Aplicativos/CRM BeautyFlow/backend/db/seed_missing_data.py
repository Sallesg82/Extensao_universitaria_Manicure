import json
import re
from werkzeug.security import generate_password_hash
from db.database import _run, update_setting, set_meta

def seed_all():
    print("=== 1. DADOS DA EMPRESA E CONFIGURAÇÕES ===")
    empresa_settings = {
        'company_legal_name': 'Beatriz Gomes Studio de Beleza Ltda',
        'company_trade_name': 'Beatriz Gomes Studio',
        'company_cnpj': '48.123.456/0001-89',
        'company_municipal_reg': '123.456-7',
        'company_address': 'Rua das Flores, 142 - Centro, São Paulo - SP, CEP 01001-000',
        'company_phone': '(11) 98765-4321',
        'company_email': 'contato@beatrizgomesstudio.com.br',
        'theme': 'default',
        'color_scheme': 'light',
        'layout_mode': 'vertical',
        'notify_lembrete_24h_antes': 'true',
        'notify_confirmacao_imediata': 'true',
        'notify_alerta_de_meta_atingida': 'true',
        'notify_resumo_semanal': 'true'
    }
    for k, v in empresa_settings.items():
        update_setting(k, v)
    print("Dados da empresa e preferências configuradas com sucesso.")

    print("\n=== 2. CATEGORIAS DE DESPESAS ===")
    expense_cats = [
        {'id': '1', 'name': 'Aluguel e Condomínio'},
        {'id': '2', 'name': 'Produtos e Insumos'},
        {'id': '3', 'name': 'Marketing e Anúncios'},
        {'id': '4', 'name': 'Energia Elétrica e Água'},
        {'id': '5', 'name': 'Internet e Telefonia'},
        {'id': '6', 'name': 'Equipamentos e Manutenção'},
        {'id': '7', 'name': 'Taxas de Cartão / Maquininha'},
        {'id': '8', 'name': 'Limpeza e Higienização'},
        {'id': '9', 'name': 'Cursos e Capacitação'},
        {'id': '10', 'name': 'Outros'}
    ]
    update_setting('expense_categories', json.dumps(expense_cats, ensure_ascii=False))
    print("10 categorias de despesas cadastradas.")

    print("\n=== 3. INTEGRAÇÕES ===")
    integs = [
        ('Google Calendar', 'google_calendar', json.dumps({'calendar_id': 'primary', 'sync_direction': 'two_way', 'status': 'conectado'}), True),
        ('WhatsApp Notificações', 'webhook', json.dumps({'url': 'https://api.whatsapp.com/v1/messages', 'events': ['appointment_created', 'appointment_reminder', 'payment_received']}), True),
        ('Automações n8n', 'n8n', json.dumps({'webhook_url': 'https://n8n.workflow.io/webhook/beautyflow', 'status': 'ativo'}), True)
    ]
    for name, itype, cfg, enabled in integs:
        existing = _run("SELECT id FROM integrations WHERE name = %s", (name,))
        if not existing:
            _run("""
                INSERT INTO integrations (name, type, config, enabled)
                VALUES (%s, %s, %s::jsonb, %s)
            """, (name, itype, cfg, enabled))
    print("Integrações cadastradas.")

    print("\n=== 4. CATÁLOGO DE ESTOQUE (PRODUTOS) ===")
    novos_produtos = [
        {'name': 'Esmalte Vermelho Clássico Risqué', 'category': 'pink', 'qty': 18, 'price': 6.50, 'min_qty': 6, 'missing': False},
        {'name': 'Esmalte Nude Chic Impala', 'category': 'pink', 'qty': 14, 'price': 6.00, 'min_qty': 5, 'missing': False},
        {'name': 'Top Coat Efeito Gel Vult', 'category': 'pink', 'qty': 8, 'price': 18.00, 'min_qty': 4, 'missing': False},
        {'name': 'Base Fortalecedora Dailus', 'category': 'pink', 'qty': 10, 'price': 14.50, 'min_qty': 4, 'missing': False},
        {'name': 'Prep Higienizador Bactericida 120ml', 'category': 'purple', 'qty': 4, 'price': 28.00, 'min_qty': 3, 'missing': False},
        {'name': 'Primer Ácido para Unhas de Gel', 'category': 'purple', 'qty': 3, 'price': 32.00, 'min_qty': 2, 'missing': False},
        {'name': 'Fibra de Vidro em Rolo 2m', 'category': 'amber', 'qty': 6, 'price': 22.00, 'min_qty': 3, 'missing': False},
        {'name': 'Tips Sorriso Transparentes (cx 100un)', 'category': 'amber', 'qty': 5, 'price': 25.00, 'min_qty': 2, 'missing': False},
        {'name': 'Lixa Banana 100/180 (pct 10un)', 'category': 'blue', 'qty': 12, 'price': 16.00, 'min_qty': 5, 'missing': False},
        {'name': 'Broca Tungstênio Cônica', 'category': 'amber', 'qty': 2, 'price': 55.00, 'min_qty': 2, 'missing': False},
        {'name': 'Hidratante para Cutículas e Mãos 200g', 'category': 'amber', 'qty': 5, 'price': 35.00, 'min_qty': 3, 'missing': False},
        {'name': 'Acetona 500ml 100% Pura', 'category': 'purple', 'qty': 7, 'price': 15.00, 'min_qty': 3, 'missing': False},
        {'name': 'Máscara Descartável Tripla (cx 50un)', 'category': 'blue', 'qty': 4, 'price': 19.90, 'min_qty': 2, 'missing': False},
        {'name': 'Toalha Descartável Manicure (pct 50un)', 'category': 'blue', 'qty': 6, 'price': 24.00, 'min_qty': 3, 'missing': False}
    ]
    for p in novos_produtos:
        exists = _run("SELECT id FROM products WHERE name = %s", (p['name'],))
        if not exists:
            _run("""
                INSERT INTO products (name, category, qty, price, min_qty, missing)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (p['name'], p['category'], p['qty'], p['price'], p['min_qty'], p['missing']))
    print("Catálogo de produtos expandido.")

    print("\n=== 5. METAS MENSAIS PARA 2026 ===")
    metas_2026 = {
        '2026-01': 5000.0,
        '2026-02': 5500.0,
        '2026-03': 6000.0,
        '2026-04': 6000.0,
        '2026-05': 6500.0,
        '2026-06': 6500.0,
        '2026-07': 4500.0,
        '2026-08': 5500.0,
        '2026-09': 8500.0,
        '2026-10': 9000.0,
        '2026-11': 9500.0,
        '2026-12': 12000.0
    }
    for mes, val in metas_2026.items():
        set_meta(mes, val)
    print("Metas de Janeiro a Dezembro/2026 configuradas.")

    print("\n=== 6. USUÁRIOS DO SISTEMA ===")
    _run("UPDATE users SET email = %s WHERE email LIKE %s", ('pataquinig12@gmail.com', '%pataquinig12@gmail.com%'))
    beatriz_exists = _run("SELECT id FROM users WHERE email = 'beatriz@beatrizgomesstudio.com.br'")
    if not beatriz_exists:
        pw = generate_password_hash('beatriz123')
        _run("""
            INSERT INTO users (name, email, phone, password_hash, role)
            VALUES (%s, %s, %s, %s, %s)
        """, ('Beatriz Gomes', 'beatriz@beatrizgomesstudio.com.br', '(11) 98765-4321', pw, 'admin'))
        print("Usuária Beatriz Gomes (admin) criada.")

    print("\n=== 7. COMPLEMENTAÇÃO DE CLIENTES ===")
    clients_sem_email = _run("SELECT id, name FROM clients WHERE email IS NULL OR email = ''")
    for cl in clients_sem_email:
        clean_name = re.sub(r'[^a-zA-Z0-9]', '', cl['name'].lower().split()[0])
        email = f"{clean_name}{cl['id']}@gmail.com"
        _run("UPDATE clients SET email = %s WHERE id = %s", (email, cl['id']))
    print(f"{len(clients_sem_email)} clientes atualizados com e-mail válido.")

    print("\n>>> DADOS POPULADOS COM SUCESSO! <<<")

if __name__ == '__main__':
    seed_all()
