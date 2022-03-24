from configparser import ConfigParser
from os import getcwd

FILE = getcwd()
def config(filename=f'{FILE}/config/db.ini', section="postgresql"):
    '''
    Retorna la configuración de requerida para conectarse a la base de datos
    '''
    parser = ConfigParser()
    parser.read(filename)
    db = {}
    if parser.has_section(section):
        params = parser.items(section)
        for param in params:
            db[param[0]] = param[1]
    return db
