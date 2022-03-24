from config import conf
import aiohttp
import asyncio
from pathlib import Path

FILE = Path()
INFO = conf.config(filename=f"{FILE}/config/api.ini", section="TDAMERITRADE")

async def obtain_instrument(symbol):
    # Obtiene el cusip, símbolo, descripción, mercado y tipo de valor de un instrumento.
    async with aiohttp.ClientSession() as session:
        url = f"https://api.tdameritrade.com/v1/instruments"
        query = {
            "apikey": INFO["costumer_key"],
            "symbol": symbol,
            "projection": "symbol-search",
        }
        async with session.get(url, params=query) as response:
            if response.status != 200:
                raise Exception(f"No hay respuesta - {response.status}")
            resp = await response.json()
            content = list(resp)
            row = tuple((resp[content[0]]).values())
            return row
