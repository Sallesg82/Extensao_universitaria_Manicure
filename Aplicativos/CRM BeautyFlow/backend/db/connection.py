import os
from dotenv import load_dotenv
from psycopg_pool import ConnectionPool

load_dotenv()

raw_url = os.environ.get("DATABASE_URL", "postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow")
if '@postgres:' in raw_url:
    try:
        import socket
        socket.gethostbyname('postgres')
    except Exception:
        raw_url = raw_url.replace('@postgres:', '@localhost:')

DATABASE_URL = raw_url
_pool = None


def get_pool():
    global _pool
    if _pool is None or getattr(_pool, 'closed', False):
        _pool = ConnectionPool(conninfo=DATABASE_URL, min_size=1, max_size=5, open=True)
    return _pool


def get_conn():
    return get_pool().connection()
