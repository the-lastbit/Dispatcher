import psycopg2.extras
from config import conf


class Connection:
    params = conf.config()
    conn = psycopg2.connect(**params)
    con = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)

    def __new__(cls):
        return cls

    @classmethod
    def connect(cls):
        return cls.con

    @classmethod
    def commit(cls):
        cls.conn.commit()

    @classmethod
    def close(cls):
        cls.conn.close()
        
    @classmethod
    def rollback(cls):
        cls.conn.rollback()