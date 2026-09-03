import os
from dotenv import load_dotenv
from psycopg_pool import ConnectionPool

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL", "postgresql://postgres:beautyflow_pass@localhost:5432/beautyflow")
_pool = None


def get_pool():
    global _pool
    if _pool is None:
        _pool = ConnectionPool(conninfo=DATABASE_URL, min_size=1, max_size=5, open=True)
    return _pool


def get_conn():
    return get_pool().connection()
