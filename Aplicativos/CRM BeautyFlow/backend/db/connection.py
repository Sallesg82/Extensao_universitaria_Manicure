import os
from dotenv import load_dotenv
from psycopg_pool import ConnectionPool

load_dotenv()

pool = ConnectionPool(conninfo=os.environ["DATABASE_URL"], min_size=2, max_size=10, open=True)


def get_conn():
    return pool.connection()
