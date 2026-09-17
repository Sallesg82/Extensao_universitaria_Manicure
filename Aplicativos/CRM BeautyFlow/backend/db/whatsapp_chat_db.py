# ==============================================================================
# BeautyFlow Platform — Banco de Dados Dedicado para Chat do WhatsApp
# Arquitetura inspirada no Chatwoot (Models: Conversation, Message, CannedResponses)
# Banco: SQLite 3 dedicado (db/whatsapp_chat.db) — Isolado, autônomo e de alta performance
# ==============================================================================
import os
import re
import sqlite3
import time
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

DB_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(DB_DIR, 'whatsapp_chat.db')


def get_chat_db():
    """Retorna uma conexão thread-safe com o banco SQLite dedicado do WhatsApp."""
    conn = sqlite3.connect(DB_PATH, timeout=25.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def clean_phone(raw_phone):
    """Normaliza o número de telefone para o padrão WhatsApp internacional (ex: 5511999999999)."""
    if not raw_phone:
        return ''
    cleaned = str(raw_phone).split('@')[0]
    digits = re.sub(r'\D', '', cleaned)
    if not digits:
        return ''
    if digits.startswith('55') and len(digits) in (12, 13):
        return digits
    if len(digits) in (10, 11):
        return '55' + digits
    return digits


def to_chat_id(phone_or_chat_id):
    """Garante que o ID do chat termine com @c.us."""
    if not phone_or_chat_id:
        return ''
    s = str(phone_or_chat_id).strip()
    if '@c.us' in s or '@g.us' in s or '@lid' in s:
        return s
    phone = clean_phone(s)
    return f"{phone}@c.us" if phone else ''


def get_phone_variants(phone_or_chat_id):
    """Gera variações comuns do número (com e sem o 9º dígito brasileiro)."""
    phone = clean_phone(phone_or_chat_id)
    if not phone:
        return []
    variants = [phone]
    if phone.startswith('55') and len(phone) == 13 and phone[4] == '9':
        variants.append(phone[:4] + phone[5:])
    elif phone.startswith('55') and len(phone) == 12:
        variants.append(phone[:4] + '9' + phone[4:])
    return variants


def get_chat_id_variants(phone_or_chat_id):
    """Gera variações de chat_id correspondentes."""
    variants = []
    base_cid = to_chat_id(phone_or_chat_id)
    if base_cid:
        variants.append(base_cid)
    for p in get_phone_variants(phone_or_chat_id):
        cid = to_chat_id(p)
        if cid and cid not in variants:
            variants.append(cid)
    return variants


def init_chat_db():
    """Inicializa as tabelas e índices do banco de dados dedicado de mensagens."""
    os.makedirs(DB_DIR, exist_ok=True)
    with get_chat_db() as conn:
        cursor = conn.cursor()

        # 1. Tabela de Conversas (inspirada no model Conversation do Chatwoot)
        cursor.execute("""
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
        """)

        # 2. Tabela de Mensagens (inspirada no model Message do Chatwoot)
        cursor.execute("""
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
        """)

        # 3. Tabela de Respostas Rápidas / Templates (Chatwoot Canned Responses)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS whatsapp_canned_responses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                short_code TEXT UNIQUE NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                category TEXT DEFAULT 'geral'
            );
        """)

        # Índices de Alta Performance
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_conv_chat_id ON whatsapp_conversations(chat_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_conv_phone ON whatsapp_conversations(phone);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_msg_chat_id ON whatsapp_messages(chat_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_msg_waha_id ON whatsapp_messages(waha_message_id);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_msg_timestamp ON whatsapp_messages(timestamp);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_wa_msg_conv_id ON whatsapp_messages(conversation_id);")

        # Inserção de Respostas Rápidas Padrão (se vazia)
        cursor.execute("SELECT COUNT(*) as cnt FROM whatsapp_canned_responses;")
        if cursor.fetchone()['cnt'] == 0:
            default_canned = [
                ('/confirmar', 'Confirmar Agendamento',
                 'Olá, {nome}! 🌸 Passando para confirmar seu horário de {servico} em {data} às {horario}. Esperamos por você!', 'agendamento'),
                ('/lembrete', 'Lembrete de Horário',
                 'Olá, {nome}! 💅 Lembrando do seu horário de {servico} amanhã às {horario} no estúdio. Qualquer dúvida estamos à disposição!', 'agendamento'),
                ('/obrigado', 'Agradecimento pós-visita',
                 'Olá, {nome}! 💖 Muito obrigado pela sua visita hoje! Foi um prazer atender você. Esperamos vê-la novamente em breve!', 'relacionamento'),
                ('/retorno', 'Convite para Retorno / Manutenção',
                 'Olá, {nome}! ✨ Passando para saber como estão suas unhas! Que tal agendarmos sua manutenção para mantê-las impecáveis?', 'retencao'),
                ('/atraso', 'Aviso de Atraso / Tolerância',
                 'Olá, {nome}! Informamos que temos uma tolerância de até 10 minutos para início do atendimento. Caso ocorra algum imprevisto, nos avise!', 'geral'),
            ]
            cursor.executemany("""
                INSERT OR IGNORE INTO whatsapp_canned_responses (short_code, title, content, category)
                VALUES (?, ?, ?, ?);
            """, default_canned)

        conn.commit()
    logger.info(f"[WhatsApp Chat DB] Banco de dados inicializado em {DB_PATH}")
    return True


def get_or_create_conversation(phone_or_chat_id, contact_name=None, client_id=None):
    """Busca ou cria uma conversa para o número informado."""
    init_chat_db()
    chat_id = to_chat_id(phone_or_chat_id)
    phone = clean_phone(phone_or_chat_id)
    if not chat_id or not phone:
        return None

    p_vars = get_phone_variants(phone_or_chat_id)
    c_vars = get_chat_id_variants(phone_or_chat_id)

    with get_chat_db() as conn:
        cursor = conn.cursor()
        c_ph = ','.join(['?'] * len(c_vars))
        p_ph = ','.join(['?'] * len(p_vars))
        cursor.execute(f"SELECT * FROM whatsapp_conversations WHERE chat_id IN ({c_ph}) OR phone IN ({p_ph})", (*c_vars, *p_vars))
        row = cursor.fetchone()

        now_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        if row:
            conv_id = row['id']
            # Atualiza nome ou client_id se fornecido e antes estava vazio
            update_fields = []
            params = []
            if contact_name and (not row['contact_name'] or row['contact_name'] == 'Cliente'):
                update_fields.append("contact_name = ?")
                params.append(contact_name)
            if client_id and not row['client_id']:
                update_fields.append("client_id = ?")
                params.append(client_id)

            if update_fields:
                update_fields.append("updated_at = ?")
                params.append(now_str)
                params.append(conv_id)
                cursor.execute(f"UPDATE whatsapp_conversations SET {', '.join(update_fields)} WHERE id = ?", params)
                conn.commit()
                cursor.execute("SELECT * FROM whatsapp_conversations WHERE id = ?", (conv_id,))
                row = cursor.fetchone()

            return dict(row)

        # Inserção de nova conversa
        cursor.execute("""
            INSERT INTO whatsapp_conversations (chat_id, phone, contact_name, client_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (chat_id, phone, contact_name or 'Cliente', client_id, now_str, now_str))
        conn.commit()
        conv_id = cursor.lastrowid
        cursor.execute("SELECT * FROM whatsapp_conversations WHERE id = ?", (conv_id,))
        return dict(cursor.fetchone())


def save_message(chat_id_or_phone, content, from_me=False, waha_message_id=None,
                 timestamp=None, status=None, media_url=None, media_type=None,
                 sender_type=None, message_type=None, contact_name=None, client_id=None):
    """
    Salva ou atualiza uma mensagem no banco de dados.
    Normaliza status e tipos no padrão Chatwoot.
    """
    init_chat_db()
    chat_id = to_chat_id(chat_id_or_phone)
    if not chat_id:
        return None

    conv = get_or_create_conversation(chat_id, contact_name=contact_name, client_id=client_id)
    conv_id = conv['id'] if conv else None

    # Normalização de tipos (Chatwoot pattern)
    from_me_int = 1 if from_me else 0
    if not sender_type:
        sender_type = 'agent' if from_me else 'client'
    if not message_type:
        message_type = 'outgoing' if from_me else 'incoming'
    if not status:
        status = 'sent' if from_me else 'delivered'

    ts = timestamp
    if not ts:
        ts = int(time.time())
    elif ts > 10000000000: # Se estiver em milissegundos
        ts = int(ts / 1000)

    now_dt = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')

    with get_chat_db() as conn:
        cursor = conn.cursor()

        # Verifica se mensagem já existe pelo waha_message_id
        if waha_message_id:
            cursor.execute("SELECT id, status FROM whatsapp_messages WHERE waha_message_id = ?", (waha_message_id,))
            existing = cursor.fetchone()
            if existing:
                # Atualiza status e timestamp se necessário
                cursor.execute("""
                    UPDATE whatsapp_messages
                    SET status = COALESCE(?, status),
                        content = COALESCE(?, content),
                        media_url = COALESCE(?, media_url)
                    WHERE id = ?
                """, (status, content, media_url, existing['id']))
                conn.commit()
                cursor.execute("SELECT * FROM whatsapp_messages WHERE id = ?", (existing['id'],))
                res = dict(cursor.fetchone())
                res['_is_new'] = False
                return res

        # Inserção de nova mensagem
        cursor.execute("""
            INSERT INTO whatsapp_messages (
                conversation_id, waha_message_id, chat_id, sender_type,
                message_type, content, media_url, media_type, status,
                from_me, timestamp, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            conv_id, waha_message_id, chat_id, sender_type,
            message_type, content, media_url, media_type, status,
            from_me_int, ts, now_dt
        ))
        msg_id = cursor.lastrowid

        # Atualiza a conversa com a última mensagem e contador de não lidas
        if conv_id:
            unread_inc = 0 if from_me else 1
            cursor.execute("""
                UPDATE whatsapp_conversations
                SET last_message = ?,
                    last_message_at = ?,
                    unread_count = unread_count + ?,
                    updated_at = ?
                WHERE id = ?
            """, (content or '[Mídia]', now_dt, unread_inc, now_dt, conv_id))

        conn.commit()
        cursor.execute("SELECT * FROM whatsapp_messages WHERE id = ?", (msg_id,))
        res = dict(cursor.fetchone())
        res['_is_new'] = True
        return res


def get_conversation_messages(phone_or_chat_id, limit=100, offset=0):
    """Retorna o histórico de mensagens ordenado cronologicamente."""
    init_chat_db()

    if isinstance(phone_or_chat_id, int):
        with get_chat_db() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT m.*
                FROM whatsapp_messages m
                WHERE m.conversation_id = ?
                ORDER BY m.timestamp ASC, m.id ASC
                LIMIT ? OFFSET ?
            """, (phone_or_chat_id, limit, offset))
            return [dict(r) for r in cursor.fetchall()]

    p_vars = get_phone_variants(phone_or_chat_id)
    c_vars = get_chat_id_variants(phone_or_chat_id)
    if not p_vars and not c_vars:
        return []

    with get_chat_db() as conn:
        cursor = conn.cursor()
        c_ph = ','.join(['?'] * len(c_vars))
        p_ph = ','.join(['?'] * len(p_vars))
        cursor.execute(f"""
            SELECT m.*
            FROM whatsapp_messages m
            LEFT JOIN whatsapp_conversations c ON m.conversation_id = c.id
            WHERE m.chat_id IN ({c_ph}) OR c.phone IN ({p_ph})
            ORDER BY m.timestamp ASC, m.id ASC
            LIMIT ? OFFSET ?
        """, (*c_vars, *p_vars, limit, offset))
        rows = cursor.fetchall()
        return [dict(r) for r in rows]



def mark_conversation_as_read(phone_or_chat_id):
    """Zera o contador de não lidas e atualiza o status das mensagens recebidas."""
    init_chat_db()
    chat_id = to_chat_id(phone_or_chat_id)
    phone = clean_phone(phone_or_chat_id)
    if not chat_id:
        return

    with get_chat_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE whatsapp_conversations
            SET unread_count = 0
            WHERE chat_id = ? OR phone = ?
        """, (chat_id, phone))
        cursor.execute("""
            UPDATE whatsapp_messages
            SET status = 'read'
            WHERE (chat_id = ? OR conversation_id IN (SELECT id FROM whatsapp_conversations WHERE phone = ?))
              AND from_me = 0 AND status != 'read'
        """, (chat_id, phone))
        conn.commit()


def get_canned_responses():
    """Retorna todas as respostas prontas cadastradas."""
    init_chat_db()
    with get_chat_db() as conn:
        cursor = conn.cursor()
        cursor.execute("SELECT * FROM whatsapp_canned_responses ORDER BY category, title")
        return [dict(r) for r in cursor.fetchall()]


def get_recent_conversations(limit=20):
    """Retorna a lista de conversas mais recentes do WhatsApp."""
    init_chat_db()
    with get_chat_db() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT * FROM whatsapp_conversations
            ORDER BY last_message_at DESC, updated_at DESC
            LIMIT ?
        """, (limit,))
        return [dict(r) for r in cursor.fetchall()]
