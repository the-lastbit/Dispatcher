class INSTRUMENT():
    def __init__(self, connector, symbol=None, cusip=None):
        self.connector = connector()
        self.cursor = self.connector.connect()
        self.symbol = symbol
    
    def select_symbols(self):
        query = "SELECT symbol, cusip from db.instruments"
        self.cursor.execute(query)
        instruments = self.cursor.fetchall()
        self.connector.commit()
        return [(instrument[0], instrument[1]) for instrument in instruments]

    def return_news_reference(self):
        import re
        characters = re.compile('[.-]')
        if characters.search(self.symbol) == None:
            query = f'SELECT id_reference FROM db.{self.symbol.lower()}_partition'
            self.cursor.execute(query)
        else:
            query = f'SELECT id_reference FROM db."{self.symbol.lower()}_partition"'
            self.cursor.execute(query)  

        results = self.cursor.fetchall()
        return [result[0] for result in results]

    def insert_news_reference(self, id_reference, date):
        import re
        characters = re.compile('[.-]')
        values = (id_reference, self.symbol.lower(), date)
        if characters.search(self.symbol) == None:
            query = f'INSERT INTO db.{self.symbol.lower()}_partition VALUES(%s,%s,%s)'
            self.cursor.execute(query, values)
        else:
            query = f'INSERT INTO db."{self.symbol.lower()}_partition" VALUES(%s,%s,%s)'
            self.cursor.execute(query, values)            

    def insert_into_news(self, values):
        query = "INSERT INTO news.news (title, description, pubdate, download_time, id_instrument, analysis) VALUES (%s,%s,%s, NOW(),%s,%s) RETURNING download_time"
        self.cursor.execute(query, values)
        returned = self.cursor.fetchone()
        return returned

    def commit_changes(self):
        self.connector.commit()

    def insert_into_instruments(self, file_path:str):
            '''recieves a csv file path that contains the stock symbols'''
            import csv
            import asyncio
            from app.instrument_scrapper import obtain_instrument
            from time import sleep
            import re

            characters = re.compile('[\']')


            with open(file_path, 'r') as file:
                stocks = csv.reader(file)
                next(stocks)
                for stock in stocks:
                    conn = self.connector
                    cursor = conn.connect()
                    if characters.search(stock[2]) == None:
                        name = stock[2]
                    else:
                        name = (stock[2]).replace("'", "`")

                    try:
                        response = asyncio.run(obtain_instrument(stock[1]))
                        sleep(0.3)
                        cusip = response[0]
                        symbol = response[1]
                        try:
                            query = 'INSERT INTO db.instruments (cusip, symbol, description, exchange, assettype) VALUES (%s,%s,%s,%s,%s)'
                            cursor.execute(query, response)
                        except Exception as e:
                            conn.rollback()
                            print("Tabla Instrumentos")
                            print(f"Exception - {e}")
                        try:
                            query2 = f"INSERT INTO db.heatmap (id_instrument, symbol, description, name) VALUES ('{cusip}', '{stock[1]}', '{stock[5]}', '{name}')"
                            cursor.execute(query2)
                        except Exception as e:
                            conn.rollback()
                            print("Tabla Heatmap")
                            print(f"Exception - {e}")
                        try:
                            query3 = f"INSERT INTO db.tops (id_instrument, symbol, description, name) VALUES ('{cusip}', '{stock[1]}', '{stock[5]}', '{name}')"
                            cursor.execute(query3)
                        except Exception as e:
                            conn.rollback()
                            print("Tabla Tops")
                            print(f"Exception - {e}")  
                        try:
                            query4 = f"SELECT db.check_register_symbol('{symbol.lower()}')"
                            cursor.execute(query4)
                        except Exception as e:
                            conn.rollback()
                            print("Tabla check_register_symbol")
                            print(f"Exception - {e}")                                                  
                    except Exception as e:
                        print(f"Exception - {e}")
                        conn.rollback()
                    
                    conn.commit()
                print("Acciones agregadas con éxito")


def erase_all():
    from . import Connection
    import re

    characters = re.compile('[.-]')

    try:
        conn = Connection()
        cursor = conn.connect()
        query1 = "DELETE FROM db.heatmap"
        cursor.execute(query1)
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(e)
    try:
        conn = Connection()
        cursor = conn.connect()
        query2 = "DELETE FROM db.tops;"
        cursor.execute(query2)
    except Exception as e:
        conn.rollback()
        print(e)
    try:
        conn = Connection()
        cursor = conn.connect()
        query3 ="""SELECT c.relname AS child, p.relname AS parent
                    FROM pg_inherits 
                    JOIN pg_class AS c ON (inhrelid=c.oid)
                    JOIN pg_class as p ON (inhparent=p.oid)"""
        cursor.execute(query3)
        results = cursor.fetchall()
        news_partition = [result[0] for result in results if result[1] == 'news']
        references_partition = [result[0] for result in results if result[1] == 'scraped_news_reference']
    except Exception as e:
        conn.rollback()
        print(e)
    
    for news in news_partition:
        conn = Connection()
        cursor = conn.connect()
        try:
            query4= f'DROP TABLE IF EXISTS news."{news}"'
            cursor.execute(query4)
        except Exception as e:
            conn.rollback()
            print(e)
        conn.commit()
    
    for reference in references_partition:
        conn = Connection()
        cursor = conn.connect()
        try:
            if characters.search(reference) == None:
                query5= f'DROP TABLE IF EXISTS db.{reference}'
                cursor.execute(query5)
            else:
                query5= f'DROP TABLE IF EXISTS db."{reference}"'
                cursor.execute(query5)
        except Exception as e:
            conn.rollback()
            print(e)
        conn.commit()

    try:
        conn = Connection()
        cursor = conn.connect()
        query6 = "DELETE FROM news.news;"
        cursor.execute(query6)
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(e)

    try:
        conn = Connection()
        cursor = conn.connect()
        query7 = "DELETE FROM db.instruments;"
        cursor.execute(query7)
        conn.commit()
    except Exception as e:
        conn.rollback()
        print(e)