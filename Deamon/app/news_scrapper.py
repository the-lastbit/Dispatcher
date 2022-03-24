import aiohttp
import asyncio
import yfinance as yf
from bs4 import BeautifulSoup
import warnings
from db.manage import INSTRUMENT


class NEW:
    def __init__(self, symbol: str) -> None:
        self.symbol = symbol

    def get_news(self) -> dict:        
        json = None
        try:
            data = yf.Ticker(self.symbol)
            json = data.news
        except Exception as e:
            print("")
            print("{:-^40}!".format("An error ocurred"))
            print(f"Message : {e}")
            print("")

        return json

    def get_id_news(self, conn):
        response = self.get_news()
        ids_response = set()
        if response:
            for id_ in response:
                ids_response.add(id_["uuid"])

            references = INSTRUMENT(conn, self.symbol)
            db_references = set(references.return_news_reference())

            if len(db_references) == 0:
                return response
            else:
                return ids_response, response, db_references

    def filter_news(self, conn) -> None:
        ids = self.get_id_news(conn)
        
        try:
            ids_response, response, stored_ids = ids
            unique_ids_ = ids_response.difference(stored_ids)
            if len(unique_ids_) > 0:
                print("{:-<40} has news".format(self.symbol))
                # Primer caso, ya se habia registrado el simbolo
                resultant_ids = [id_ for id_ in unique_ids_]
                unique_news = [
                    (new["title"],new["link"],new["providerPublishTime"])
                    for new in response
                    if new["uuid"] in resultant_ids
                ]
                return [*zip(unique_news, unique_ids_)]
            else:
                print("{:-<40} has no news".format(self.symbol))
                # O no hay
                return None
        except Exception:
            pass

        response_ = ids
        if response_:
            # Segundo caso, primera vez registrando noticias de este instrumento o hay registro y no hay noticas nuevas
            print("{:-<40} first time to accuire news".format(self.symbol))
            ids_ = set()
            unique_news = [(new["title"],new["link"],new["providerPublishTime"]) for new in response_]
            for id_ in response_:
                ids_.add(id_["uuid"])
            return [*zip(unique_news, ids_)]
        else:
            # O no hay
            print("{:-<40} is registered but never has had news".format(self.symbol))
            return None
        


async def content_extractor(news_uri:str())->str:
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(news_uri, timeout=20) as response:
                if response.status != 200:
                    raise Exception(response.status)
                resp = await response.text()
                soup = BeautifulSoup(resp, features='lxml',parser='lxml')
                news_uri = soup.find("div", class_="caas-body").find_all('p')
                article =''

                for paragraf in news_uri:
                        warnings.filterwarnings("ignore")
                        for content in (BeautifulSoup(str(paragraf),features='lxml',parser='lxml').p.contents):
                            try:
                                article += BeautifulSoup(str(content),features='lxml',parser='lxml').string
                            except Exception:
                                pass
                return article
    except Exception as e:
        print("")
        print("{:-^40}!".format("A problem occurred"))
        print(f'SKIPPED - {news_uri}')
        print(f"Message : {e}")
        print("")
