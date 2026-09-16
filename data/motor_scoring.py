"""
GeoRisk - Motor de scoring de referencia (implementacion Python).

Replica exactamente la logica de sql/02_vistas_scoring.sql. Cumple dos fines:

  1. Permite desarrollar y validar el modelo SIN acceso a SAP HANA Cloud.
  2. Actua como implementacion de referencia: validar_modelo.py comprueba que
     los parametros aqui definidos coinciden con los INSERT del SQL, de modo
     que una divergencia entre ambos mundos se detecta automaticamente.

Formulas (identicas al SQL):
    norm_directo = 100 * (clamp(x, min, max) - min) / (max - min)
    norm_inverso = 100 - norm_directo
    subindice    = sum(norm_i * peso_i) / sum(peso_i)
    dimension    = sum(subindice_j * peso_j) / sum(peso_j)
    global       = sum(dimension_k * peso_k) / sum(peso_k)
"""

from __future__ import annotations

from dataclasses import dataclass

# ==========================================================================
# Parametros del modelo (espejo de GEORISK_PARAM_* en 01_ddl_tablas.sql)
# ==========================================================================

# codigo -> (descripcion, peso)
DIMENSIONES: dict[str, tuple[str, float]] = {
    "GEO": ("Riesgo geologico", 0.40),
    "AMB": ("Riesgo ambiental", 0.35),
    "SOC": ("Riesgo social", 0.25),
}

# codigo -> (dimension, descripcion, peso dentro de la dimension)
SUBINDICES: dict[str, tuple[str, str, float]] = {
    "GEO_ESTAB": ("GEO", "Estabilidad estructural", 0.40),
    "GEO_DEPOS": ("GEO", "Caracteristicas del deposito", 0.35),
    "GEO_HIDRO": ("GEO", "Hidrogeologia y drenaje acido", 0.25),
    "AMB_AGUA":  ("AMB", "Recurso hidrico", 0.40),
    "AMB_BIO":   ("AMB", "Biodiversidad y areas naturales", 0.35),
    "AMB_RESID": ("AMB", "Pasivos, emisiones y residuos", 0.25),
    "SOC_ACEPT": ("SOC", "Aceptacion comunitaria", 0.40),
    "SOC_LEGAL": ("SOC", "Contexto legal y permisos", 0.35),
    "SOC_TERR":  ("SOC", "Contexto territorial", 0.25),
}


@dataclass(frozen=True)
class ParamVariable:
    subindice: str
    desc: str
    unidad: str
    min_ref: float
    max_ref: float
    sentido: str  # 'D' directo (mas = peor) | 'I' inverso (mas = mejor)
    peso: float   # dentro de su subindice


VARIABLES: dict[str, ParamVariable] = {
    # --- GEOLOGICAS ---
    "DENSIDAD_FALLAS_KM2":      ParamVariable("GEO_ESTAB", "Densidad de fallas geologicas",         "fallas/km2", 0.0,   5.0,    "D", 0.35),
    "INDICE_ESTABILIDAD_TALUD": ParamVariable("GEO_ESTAB", "Indice de estabilidad de taludes",      "0-10",       0.0,   10.0,   "I", 0.35),
    "SISMICIDAD_PGA_G":         ParamVariable("GEO_ESTAB", "Sismicidad (aceleracion pico)",         "g",          0.10,  0.60,   "D", 0.30),
    "LEY_MINERAL_PCT":          ParamVariable("GEO_DEPOS", "Ley mineral equivalente",               "%",          0.20,  2.00,   "I", 0.40),
    "PROFUNDIDAD_DEPOSITO_M":   ParamVariable("GEO_DEPOS", "Profundidad del deposito",              "m",          50.0,  800.0,  "D", 0.35),
    "TONELAJE_ESTIMADO_MT":     ParamVariable("GEO_DEPOS", "Tonelaje estimado",                     "Mt",         10.0,  1000.0, "I", 0.25),
    "PERMEABILIDAD_MD":         ParamVariable("GEO_HIDRO", "Permeabilidad de la roca",              "mD",         0.10,  500.0,  "D", 0.40),
    "POTENCIAL_DAM_NPAP":       ParamVariable("GEO_HIDRO", "Potencial de drenaje acido (NP/AP)",    "ratio",      0.20,  3.00,   "I", 0.60),
    # --- AMBIENTALES ---
    "DIST_FUENTE_AGUA_KM":      ParamVariable("AMB_AGUA",  "Distancia a fuente de agua",            "km",         0.0,   10.0,   "I", 0.35),
    "CALIDAD_AGUA_ICA":         ParamVariable("AMB_AGUA",  "Indice de calidad de agua",             "0-100",      0.0,   100.0,  "I", 0.35),
    "ESTRES_HIDRICO_IDX":       ParamVariable("AMB_AGUA",  "Indice de estres hidrico",              "0-100",      0.0,   100.0,  "D", 0.30),
    "DIST_AREA_PROTEGIDA_KM":   ParamVariable("AMB_BIO",   "Distancia a area natural protegida",    "km",         0.0,   50.0,   "I", 0.35),
    "INDICE_BIODIVERSIDAD":     ParamVariable("AMB_BIO",   "Indice de biodiversidad local",         "0-100",      0.0,   100.0,  "D", 0.35),
    "ESPECIES_AMENAZADAS_N":    ParamVariable("AMB_BIO",   "Especies amenazadas registradas",       "conteo",     0.0,   25.0,   "D", 0.30),
    "PASIVOS_AMBIENTALES_N":    ParamVariable("AMB_RESID", "Pasivos ambientales preexistentes",     "conteo",     0.0,   15.0,   "D", 0.40),
    "COBERTURA_GLACIAR_PCT":    ParamVariable("AMB_RESID", "Cobertura glaciar en el area",          "%",          0.0,   30.0,   "D", 0.35),
    "PRECIPITACION_ANUAL_MM":   ParamVariable("AMB_RESID", "Precipitacion anual",                   "mm",         200.0, 1600.0, "D", 0.25),
    # --- SOCIALES ---
    "INDICE_ACEPTACION_SOCIAL": ParamVariable("SOC_ACEPT", "Indice de aceptacion social",           "0-100",      0.0,   100.0,  "I", 0.45),
    "CONFLICTOS_HISTORICOS_N":  ParamVariable("SOC_ACEPT", "Conflictos sociales historicos",        "conteo",     0.0,   12.0,   "D", 0.35),
    "COMUNIDADES_INFLUENCIA_N": ParamVariable("SOC_ACEPT", "Comunidades en area de influencia",     "conteo",     0.0,   15.0,   "D", 0.20),
    "CONSULTA_PREVIA_SCORE":    ParamVariable("SOC_LEGAL", "Estado de la consulta previa",          "score",      0.0,   100.0,  "D", 0.40),
    "ESTADO_LICENCIA_SCORE":    ParamVariable("SOC_LEGAL", "Estado de la licencia social/ambiental","score",      0.0,   100.0,  "D", 0.35),
    "PERMISOS_PENDIENTES_N":    ParamVariable("SOC_LEGAL", "Permisos pendientes",                   "conteo",     0.0,   12.0,   "D", 0.25),
    "DIST_CENTRO_POBLADO_KM":   ParamVariable("SOC_TERR",  "Distancia a centro poblado",            "km",         0.0,   20.0,   "I", 0.35),
    "POBREZA_PCT":              ParamVariable("SOC_TERR",  "Incidencia de pobreza",                 "%",          0.0,   70.0,   "D", 0.35),
    "IDH_DISTRITAL":            ParamVariable("SOC_TERR",  "Indice de desarrollo humano distrital", "0-1",        0.20,  0.70,   "I", 0.30),
}

# Traduccion de variables categoricas a score de riesgo 0-100
CATEGORIAS: dict[str, dict[str, float]] = {
    "CONSULTA_PREVIA_ESTADO": {
        "Concluida": 0.0,
        "No aplica": 15.0,
        "En proceso": 45.0,
        "No iniciada": 85.0,
    },
    "ESTADO_LICENCIA": {
        "Vigente": 0.0,
        "En tramite": 50.0,
        "Observada": 80.0,
        "Sin licencia": 100.0,
    },
}

# Columna categorica de origen -> variable derivada del modelo
DERIVADAS_CATEGORICAS = {
    "CONSULTA_PREVIA_ESTADO": "CONSULTA_PREVIA_SCORE",
    "ESTADO_LICENCIA": "ESTADO_LICENCIA_SCORE",
}

# (codigo, descripcion, limite_inferior, limite_superior, color)
ESCALA: tuple[tuple[str, str, float, float, str], ...] = (
    ("BAJO",     "Riesgo bajo",      0.0,  25.0,   "#2E7D32"),
    ("MODERADO", "Riesgo moderado", 25.0,  50.0,   "#F9A825"),
    ("ALTO",     "Riesgo alto",     50.0,  75.0,   "#EF6C00"),
    ("CRITICO",  "Riesgo critico",  75.0, 100.01,  "#C62828"),
)

# Principio NO COMPENSATORIO (espejo de GEORISK_PARAM_MODELO).
# Una media ponderada pura permitiria que una geologia excelente compense un
# riesgo social critico. En gestion de riesgo eso es incorrecto: un factor
# critico no se compensa. Cuando la peor dimension supera el umbral, su exceso
# se suma al riesgo base.
AGRAVANTE_UMBRAL = 60.0
AGRAVANTE_FACTOR = 0.50


# ==========================================================================
# Motor de calculo
# ==========================================================================


def normalizar(valor: float, p: ParamVariable) -> float:
    """Lleva un valor crudo a escala 0-100 donde 100 = riesgo maximo."""
    recortado = min(max(valor, p.min_ref), p.max_ref)
    directo = 100.0 * (recortado - p.min_ref) / (p.max_ref - p.min_ref)
    return directo if p.sentido == "D" else 100.0 - directo


def clasificar(riesgo_global: float) -> tuple[str, str, str]:
    """Devuelve (codigo, descripcion, color) del nivel de riesgo."""
    for cod, desc, inf, sup, color in ESCALA:
        if inf <= riesgo_global < sup:
            return cod, desc, color
    return ESCALA[-1][0], ESCALA[-1][1], ESCALA[-1][4]


def _valores_modelo(fila: dict[str, object]) -> dict[str, float]:
    """
    Extrae del registro crudo las variables del modelo, resolviendo las
    categoricas mediante CATEGORIAS. Equivale a V_GEORISK_VALORES.
    """
    valores: dict[str, float] = {}

    for col_categorica, var_derivada in DERIVADAS_CATEGORICAS.items():
        bruto = fila.get(col_categorica)
        if bruto is not None:
            score = CATEGORIAS[col_categorica].get(str(bruto))
            if score is not None:
                valores[var_derivada] = score

    for cod in VARIABLES:
        if cod in valores:  # ya resuelta como categorica
            continue
        bruto = fila.get(cod)
        if bruto is None or bruto == "":
            continue
        valores[cod] = float(bruto)

    return valores


def calcular_zona(fila: dict[str, object]) -> dict[str, object]:
    """
    Calcula el scoring completo de una zona.

    `fila` usa nombres de columna en MAYUSCULAS (como en HANA). Devuelve
    scores por dimension, riesgo global, nivel, factor critico y el detalle
    de contribucion de cada variable.
    """
    valores = _valores_modelo(fila)

    # --- Nivel variable: normalizacion ---
    normalizados: dict[str, float] = {
        cod: normalizar(val, VARIABLES[cod]) for cod, val in valores.items()
    }

    # --- Nivel subindice: media ponderada ---
    acum: dict[str, list[float]] = {}
    for cod, norm in normalizados.items():
        p = VARIABLES[cod]
        num, den = acum.setdefault(p.subindice, [0.0, 0.0])
        acum[p.subindice] = [num + norm * p.peso, den + p.peso]

    subindices = {
        sub: (num / den if den else 0.0) for sub, (num, den) in acum.items()
    }

    # --- Nivel dimension: media ponderada de subindices ---
    acum_dim: dict[str, list[float]] = {}
    for sub, score in subindices.items():
        dim, _desc, peso = SUBINDICES[sub]
        num, den = acum_dim.setdefault(dim, [0.0, 0.0])
        acum_dim[dim] = [num + score * peso, den + peso]

    dimensiones = {
        dim: (num / den if den else 0.0) for dim, (num, den) in acum_dim.items()
    }

    # --- Riesgo base: componente compensatorio (media ponderada) ---
    num_g = sum(score * DIMENSIONES[d][1] for d, score in dimensiones.items())
    den_g = sum(DIMENSIONES[d][1] for d in dimensiones)
    riesgo_base = num_g / den_g if den_g else 0.0

    # --- Agravante: componente no compensatorio ---
    peor_dimension = max(dimensiones.values()) if dimensiones else 0.0
    agravante = AGRAVANTE_FACTOR * max(0.0, peor_dimension - AGRAVANTE_UMBRAL)
    riesgo_global = min(100.0, riesgo_base + agravante)

    nivel_cod, nivel_desc, color = clasificar(riesgo_global)

    # --- Explicabilidad: contribucion de cada variable al riesgo global ---
    contribuciones = []
    for cod, norm in normalizados.items():
        p = VARIABLES[cod]
        dim, _sd, peso_sub = SUBINDICES[p.subindice]
        peso_efectivo = p.peso * peso_sub * DIMENSIONES[dim][1]
        contribuciones.append({
            "variable": cod,
            "descripcion": p.desc,
            "dimension": dim,
            "subindice": p.subindice,
            "valor_original": valores[cod],
            "unidad": p.unidad,
            "valor_norm": round(norm, 2),
            "peso_efectivo": round(peso_efectivo, 5),
            "contribucion_pp": round(norm * peso_efectivo, 3),
        })
    contribuciones.sort(key=lambda c: c["contribucion_pp"], reverse=True)

    # --- Factor critico: subindice con mayor aporte ponderado ---
    aporte_sub = {
        sub: score * SUBINDICES[sub][2] * DIMENSIONES[SUBINDICES[sub][0]][1]
        for sub, score in subindices.items()
    }
    sub_critico = max(aporte_sub, key=aporte_sub.get) if aporte_sub else None

    return {
        "zona_id": fila.get("ZONA_ID"),
        "nombre_zona": fila.get("NOMBRE_ZONA"),
        "region": fila.get("REGION"),
        "riesgo_geologico": round(dimensiones.get("GEO", 0.0), 2),
        "riesgo_ambiental": round(dimensiones.get("AMB", 0.0), 2),
        "riesgo_social": round(dimensiones.get("SOC", 0.0), 2),
        # Descomposicion: base compensatoria + agravante no compensatorio
        "riesgo_base": round(riesgo_base, 2),
        "peor_dimension": round(peor_dimension, 2),
        "agravante": round(agravante, 2),
        "riesgo_global": round(riesgo_global, 2),
        "nivel_riesgo": nivel_cod,
        "nivel_riesgo_desc": nivel_desc,
        "nivel_color": color,
        "factor_critico": SUBINDICES[sub_critico][1] if sub_critico else None,
        "factor_critico_score": round(subindices[sub_critico], 2) if sub_critico else None,
        "subindices": {s: round(v, 2) for s, v in subindices.items()},
        "contribuciones": contribuciones,
    }


def calcular_dataset(filas: list[dict[str, object]]) -> list[dict[str, object]]:
    """Calcula el scoring de todas las zonas y asigna el ranking global."""
    resultados = [calcular_zona(f) for f in filas]
    resultados.sort(key=lambda r: r["riesgo_global"], reverse=True)
    for posicion, res in enumerate(resultados, start=1):
        res["ranking_riesgo"] = posicion
    return resultados


# ==========================================================================
# Verificacion de consistencia de los parametros
# ==========================================================================


def verificar_pesos(tolerancia: float = 1e-9) -> list[str]:
    """
    Comprueba que los pesos sumen 1.0 en cada nivel de la jerarquia.
    Devuelve la lista de errores encontrados (vacia si el modelo es valido).
    """
    errores: list[str] = []

    suma_dim = sum(peso for _d, peso in DIMENSIONES.values())
    if abs(suma_dim - 1.0) > tolerancia:
        errores.append(f"Los pesos de dimension suman {suma_dim:.6f}, se esperaba 1.0")

    por_dimension: dict[str, float] = {}
    for _sub, (dim, _desc, peso) in SUBINDICES.items():
        por_dimension[dim] = por_dimension.get(dim, 0.0) + peso
    for dim, suma in sorted(por_dimension.items()):
        if abs(suma - 1.0) > tolerancia:
            errores.append(f"Los subindices de {dim} suman {suma:.6f}, se esperaba 1.0")

    por_subindice: dict[str, float] = {}
    for _cod, p in VARIABLES.items():
        por_subindice[p.subindice] = por_subindice.get(p.subindice, 0.0) + p.peso
    for sub, suma in sorted(por_subindice.items()):
        if abs(suma - 1.0) > tolerancia:
            errores.append(f"Las variables de {sub} suman {suma:.6f}, se esperaba 1.0")

    faltantes = set(SUBINDICES) - set(por_subindice)
    if faltantes:
        errores.append(f"Subindices sin variables asignadas: {sorted(faltantes)}")

    for cod, p in VARIABLES.items():
        if p.sentido not in ("D", "I"):
            errores.append(f"{cod}: sentido invalido '{p.sentido}'")
        if p.max_ref <= p.min_ref:
            errores.append(f"{cod}: rango invalido [{p.min_ref}, {p.max_ref}]")
        if p.subindice not in SUBINDICES:
            errores.append(f"{cod}: subindice desconocido '{p.subindice}'")

    return errores
