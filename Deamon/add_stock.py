from db import Connection
from db.manage import INSTRUMENT

if __name__ == "__main__":
    conn = Connection()
    db = INSTRUMENT(conn)
    from os import getcwd
    path = getcwd()
    db.insert_into_instruments(f'{path}/S&P500.csv')