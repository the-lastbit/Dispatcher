# from scipy.sparse import save_npz, load_npz
from joblib import load
import numpy as np
from os import getcwd

FILE = getcwd()

def analyse(new):
    '''
    Herramienta de machine learning que analiza los articulos noticieros y entrega un valor numerico que representa una calificación sentimental.

    "Valores"
    
    -positivo : 1
    -negativo : 0
    '''
    model = load(f"{FILE}/ML/SGDClassifierModel.save")
    tfidf = load(f"{FILE}/ML/tfidf.save")
    input_ = tfidf.transform(new)
    analysis = model.predict(input_)
    return np.average(analysis)