from db import Connection
from db.manage import INSTRUMENT
from app.news_scrapper import NEW, content_extractor
from ML import analyse
import asyncio
from threading import Thread, Event
import random
from datetime import datetime
from time import time, sleep

class MyThread(Thread):
    '''
    Clase para crear un thread que ejecuta un evento de forma concurrente en ciclos de manera permanente hasta la interrupción con  las teclas |CTRL| + |C|

    [Argumentos]
    *Requeire de un objeto de la clase Event del módulo threading.
    *Un método a ejecutarlo ciclicamente.
    *Un entero que represente el tiempo de espera en segundos para reaudar el ciclo terminado.
    '''
    def __init__(self, event, method, wait_time):
        Thread.__init__(self)
        self.stopped = event
        self.method = method
        self.wait_time = wait_time

    def run(self):
        '''Da inicio a la ejecución multithreading del evento'''
        self.method()
        while not self.stopped.wait(self.wait_time):
            self.method()
            print()
            print("{:*^40}".format("*Waiting for the next analysis*"))
            print()


class DISPATCHER():
    '''
    Clase que recibe el symbolo de una acción para obtener su información(código único, descripción de la empresa, 
    tipo de acción y moneda de cambio en que se cotiza) de un broker. Posteriormente se usará el news scrapper para conseguir 
    articulos recientes, limpiarlos, analizarlos y almanenarlos.
    '''
    def __init__(self, symbol: str, cusip: str, running_time: float, time_per_process: float, current_process:int):
        self.symbol = symbol
        self.cusip = cusip
        self.new = NEW(self.symbol)
        self.running_time = running_time
        self.time_per_process = time_per_process
        self.current_process = current_process

    def get_news(self, conn):
        if self.running_time < (self.current_process * self.time_per_process):
            sleep(self.time_per_process)
        if news := (self.new.filter_news(conn)):
            articles = [
                (article[0][0], article[0][1], str(article[0][2]), self.cusip, article[1])
                for article in news
            ]
            return articles
        else:
            return None

    def run(self):
        conn = Connection()
        db_manager = INSTRUMENT(conn)
        news = self.get_news(conn)
        if news:
            for new in news:
                try:
                    article = asyncio.run(content_extractor(new[1]))
                    if article:
                        score = analyse([article])
                        date = datetime.fromtimestamp(int(new[2]))
                        values = (new[0], article, date, new[3], int(score))
                        # Inserting news
                        news_query = INSTRUMENT(conn)
                        returned = news_query.insert_into_news(values)
                        download_time = str(returned['download_time'])
                        # Updating news reference
                        reference_table = INSTRUMENT(conn, self.symbol)
                        reference_table.insert_news_reference(new[4], download_time)

                        db_manager.commit_changes()

                        print(f"News of {self.symbol} succesfully added")
                except Exception as e:
                    print("")
                    print('{:-^40}'.format("An error occurred"))
                    print("Message : {e}")
                    print("")

        else:
            return None 

def update_news():
    get_db_instruments = INSTRUMENT(Connection)
    instruments = get_db_instruments.select_symbols()
    random.shuffle(instruments)

    time_spend_by_process = 1
    start = time()

    for n_process, instrument in enumerate(instruments):
        end = time()
        current_time = round(end - start)
        process = DISPATCHER(symbol=instrument[0], cusip=instrument[1], running_time=current_time, time_per_process=time_spend_by_process, current_process=n_process)
        process.run()
    

def main():
    event = Event()
    update_news_constantly = MyThread(event, update_news, wait_time=1080)
    update_news_constantly.start()
    update_news_constantly.join()
    

if __name__ == "__main__":
    main()