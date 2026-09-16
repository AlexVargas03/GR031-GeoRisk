"""
GeoRisk - Validacion del modelo de scoring.

Ejecuta cuatro controles y produce las salidas que consume el prototipo:

  1. Coherencia de pesos: cada nivel de la jerarquia debe sumar 1.0
  2. Paridad SQL <-> Python: los INSERT de sql/01_ddl_tablas.sql deben
     coincidir con los parametros de motor_scoring.py (evita que el modelo
     de HANA y el de referencia se separen sin que nadie lo note)
  3. Rango de resultados: todo score debe caer en 0-100
  4. Reconstruccion: la suma de contribuciones debe reproducir el global

Salidas en data/out/:
  - georisk_scoring.csv          resultado por zona (comparable con HANA)
  - georisk_contribuciones.csv   detalle variable a variable
  - georisk_scoring.json         insumo del prototipo HTML

Uso:
    python data/validar_modelo.py
"""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from motor_scoring import (  # noqa: E402
    AGRAVANTE_FACTOR,
    AGRAVANTE_UMBRAL,
    CATEGORIAS,
    DIMENSIONES,
    SUBINDICES,
    VARIABLES,
    calcular_dataset,
    verificar_pesos,
)

RAIZ = Path(__file__).resolve().parent.parent
CSV_ENTRADA = RAIZ / "data" / "out" / "georisk_zonas.csv"
SQL_DDL = RAIZ / "sql" / "01_ddl_tablas.sql"
DIR_SALIDA = RAIZ / "data" / "out"

TOLERANCIA = 1e-6


# --------------------------------------------------------------------------
# Control 2: paridad entre el SQL y el motor Python
# --------------------------------------------------------------------------

RE_VARIABLE = re.compile(
    r"INSERT\s+INTO\s+GEORISK_PARAM_VARIABLE\s+VALUES\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)
RE_DIMENSION = re.compile(
    r"INSERT\s+INTO\s+GEORISK_PARAM_DIMENSION\s+VALUES\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)
RE_SUBINDICE = re.compile(
    r"INSERT\s+INTO\s+GEORISK_PARAM_SUBINDICE\s+VALUES\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)
RE_CATEGORIA = re.compile(
    r"INSERT\s+INTO\s+GEORISK_PARAM_CATEGORIA\s+VALUES\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)
RE_MODELO = re.compile(
    r"INSERT\s+INTO\s+GEORISK_PARAM_MODELO\s+VALUES\s*\((.*?)\);",
    re.IGNORECASE | re.DOTALL,
)


def _partir_valores(bloque: str) -> list[str]:
    """Divide la lista de VALUES respetando las comillas simples."""
    partes, actual, en_texto = [], [], False
    for char in bloque:
        if char == "'":
            en_texto = not en_texto
            continue
        if char == "," and not en_texto:
            partes.append("".join(actual).strip())
            actual = []
            continue
        actual.append(char)
    partes.append("".join(actual).strip())
    return partes


def comparar_sql_python() -> list[str]:
    """Compara los parametros declarados en el DDL con los del motor Python."""
    if not SQL_DDL.exists():
        return [f"No se encontro {SQL_DDL}"]

    sql = SQL_DDL.read_text(encoding="utf-8")
    errores: list[str] = []

    # --- Dimensiones: (cod, desc, peso, activo) ---
    dim_sql = {}
    for bloque in RE_DIMENSION.findall(sql):
        campos = _partir_valores(bloque)
        dim_sql[campos[0]] = float(campos[2])
    for cod, (_desc, peso) in DIMENSIONES.items():
        if cod not in dim_sql:
            errores.append(f"Dimension {cod} existe en Python pero no en el SQL")
        elif abs(dim_sql[cod] - peso) > TOLERANCIA:
            errores.append(
                f"Dimension {cod}: peso SQL={dim_sql[cod]} vs Python={peso}"
            )
    for cod in dim_sql.keys() - DIMENSIONES.keys():
        errores.append(f"Dimension {cod} existe en el SQL pero no en Python")

    # --- Subindices: (cod, dimension, desc, peso) ---
    sub_sql = {}
    for bloque in RE_SUBINDICE.findall(sql):
        campos = _partir_valores(bloque)
        sub_sql[campos[0]] = (campos[1], float(campos[3]))
    for cod, (dim, _desc, peso) in SUBINDICES.items():
        if cod not in sub_sql:
            errores.append(f"Subindice {cod} existe en Python pero no en el SQL")
            continue
        dim_s, peso_s = sub_sql[cod]
        if dim_s != dim:
            errores.append(f"Subindice {cod}: dimension SQL={dim_s} vs Python={dim}")
        if abs(peso_s - peso) > TOLERANCIA:
            errores.append(f"Subindice {cod}: peso SQL={peso_s} vs Python={peso}")
    for cod in sub_sql.keys() - SUBINDICES.keys():
        errores.append(f"Subindice {cod} existe en el SQL pero no en Python")

    # --- Variables: (cod, subindice, desc, unidad, min, max, sentido, peso) ---
    var_sql = {}
    for bloque in RE_VARIABLE.findall(sql):
        campos = _partir_valores(bloque)
        var_sql[campos[0]] = {
            "subindice": campos[1],
            "min_ref": float(campos[4]),
            "max_ref": float(campos[5]),
            "sentido": campos[6],
            "peso": float(campos[7]),
        }
    for cod, p in VARIABLES.items():
        if cod not in var_sql:
            errores.append(f"Variable {cod} existe en Python pero no en el SQL")
            continue
        s = var_sql[cod]
        if s["subindice"] != p.subindice:
            errores.append(
                f"Variable {cod}: subindice SQL={s['subindice']} vs Python={p.subindice}"
            )
        if abs(s["min_ref"] - p.min_ref) > TOLERANCIA:
            errores.append(f"Variable {cod}: min SQL={s['min_ref']} vs Python={p.min_ref}")
        if abs(s["max_ref"] - p.max_ref) > TOLERANCIA:
            errores.append(f"Variable {cod}: max SQL={s['max_ref']} vs Python={p.max_ref}")
        if s["sentido"] != p.sentido:
            errores.append(
                f"Variable {cod}: sentido SQL={s['sentido']} vs Python={p.sentido}"
            )
        if abs(s["peso"] - p.peso) > TOLERANCIA:
            errores.append(f"Variable {cod}: peso SQL={s['peso']} vs Python={p.peso}")
    for cod in var_sql.keys() - VARIABLES.keys():
        errores.append(f"Variable {cod} existe en el SQL pero no en Python")

    # --- Categorias: (variable, valor, score) ---
    cat_sql: dict[str, dict[str, float]] = {}
    for bloque in RE_CATEGORIA.findall(sql):
        campos = _partir_valores(bloque)
        cat_sql.setdefault(campos[0], {})[campos[1]] = float(campos[2])
    for var, mapa in CATEGORIAS.items():
        if var not in cat_sql:
            errores.append(f"Categoria {var} existe en Python pero no en el SQL")
            continue
        for valor, score in mapa.items():
            if valor not in cat_sql[var]:
                errores.append(f"Categoria {var}='{valor}' falta en el SQL")
            elif abs(cat_sql[var][valor] - score) > TOLERANCIA:
                errores.append(
                    f"Categoria {var}='{valor}': SQL={cat_sql[var][valor]} vs Python={score}"
                )

    # --- Parametros generales: (cod, desc, valor) ---
    mod_sql = {}
    for bloque in RE_MODELO.findall(sql):
        campos = _partir_valores(bloque)
        mod_sql[campos[0]] = float(campos[2])
    esperados = {
        "AGRAVANTE_UMBRAL": AGRAVANTE_UMBRAL,
        "AGRAVANTE_FACTOR": AGRAVANTE_FACTOR,
    }
    for cod, valor in esperados.items():
        if cod not in mod_sql:
            errores.append(f"Parametro {cod} existe en Python pero no en el SQL")
        elif abs(mod_sql[cod] - valor) > TOLERANCIA:
            errores.append(f"Parametro {cod}: SQL={mod_sql[cod]} vs Python={valor}")

    return errores


# --------------------------------------------------------------------------
# Controles 3 y 4: rangos y reconstruccion del score
# --------------------------------------------------------------------------


def verificar_resultados(resultados: list[dict]) -> list[str]:
    errores: list[str] = []
    campos_score = (
        "riesgo_global", "riesgo_base",
        "riesgo_geologico", "riesgo_ambiental", "riesgo_social",
    )

    for r in resultados:
        for campo in campos_score:
            valor = r[campo]
            if not (0.0 <= valor <= 100.0):
                errores.append(f"{r['zona_id']}: {campo}={valor} fuera de 0-100")

        # La suma de contribuciones debe reconstruir el RIESGO BASE (el
        # agravante es un componente aparte, no atribuible a una variable).
        suma = sum(c["contribucion_pp"] for c in r["contribuciones"])
        if abs(suma - r["riesgo_base"]) > 0.05:
            errores.append(
                f"{r['zona_id']}: contribuciones suman {suma:.3f} "
                f"pero el riesgo base es {r['riesgo_base']}"
            )

        # El global debe ser exactamente base + agravante (salvo tope en 100).
        esperado = min(100.0, r["riesgo_base"] + r["agravante"])
        if abs(esperado - r["riesgo_global"]) > 0.05:
            errores.append(
                f"{r['zona_id']}: base {r['riesgo_base']} + agravante "
                f"{r['agravante']} = {esperado:.2f}, pero el global es {r['riesgo_global']}"
            )

    return errores


# --------------------------------------------------------------------------
# Carga y salidas
# --------------------------------------------------------------------------


def cargar_zonas() -> list[dict[str, object]]:
    if not CSV_ENTRADA.exists():
        raise SystemExit(
            f"No existe {CSV_ENTRADA}\nEjecuta primero: python data/generar_dataset.py"
        )
    with CSV_ENTRADA.open(encoding="utf-8") as fh:
        # El motor espera nombres de columna en mayusculas, como en HANA.
        return [{k.upper(): v for k, v in fila.items()} for fila in csv.DictReader(fh)]


def exportar(resultados: list[dict]) -> None:
    DIR_SALIDA.mkdir(parents=True, exist_ok=True)

    columnas = [
        "ranking_riesgo", "zona_id", "nombre_zona", "region",
        "riesgo_global", "riesgo_base", "agravante", "peor_dimension",
        "riesgo_geologico", "riesgo_ambiental", "riesgo_social",
        "nivel_riesgo", "factor_critico", "factor_critico_score",
    ]
    with (DIR_SALIDA / "georisk_scoring.csv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=columnas, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(resultados)

    with (DIR_SALIDA / "georisk_contribuciones.csv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh)
        writer.writerow([
            "zona_id", "nombre_zona", "dimension", "subindice", "variable",
            "descripcion", "valor_original", "unidad", "valor_norm",
            "peso_efectivo", "contribucion_pp",
        ])
        for r in resultados:
            for c in r["contribuciones"]:
                writer.writerow([
                    r["zona_id"], r["nombre_zona"], c["dimension"], c["subindice"],
                    c["variable"], c["descripcion"], c["valor_original"], c["unidad"],
                    c["valor_norm"], c["peso_efectivo"], c["contribucion_pp"],
                ])

    with (DIR_SALIDA / "georisk_scoring.json").open("w", encoding="utf-8") as fh:
        json.dump(resultados, fh, ensure_ascii=False, indent=1)


def resumen(resultados: list[dict]) -> None:
    n = len(resultados)
    globales = [r["riesgo_global"] for r in resultados]
    print(f"\n  Zonas evaluadas : {n}")
    print(f"  Riesgo global   : min {min(globales):.2f} | "
          f"prom {sum(globales) / n:.2f} | max {max(globales):.2f}")

    print("\n  Distribucion por nivel de riesgo")
    for nivel in ("BAJO", "MODERADO", "ALTO", "CRITICO"):
        cant = sum(1 for r in resultados if r["nivel_riesgo"] == nivel)
        barra = "#" * cant
        print(f"    {nivel:<9} {cant:>3}  {barra}")

    print("\n  Top 5 zonas de mayor riesgo")
    print(f"    {'#':<3} {'Zona':<22} {'Region':<13} {'Global':>7}  Factor critico")
    for r in resultados[:5]:
        print(f"    {r['ranking_riesgo']:<3} {str(r['nombre_zona'])[:21]:<22} "
              f"{str(r['region'])[:12]:<13} {r['riesgo_global']:>7.2f}  {r['factor_critico']}")

    print("\n  Menor riesgo")
    r = resultados[-1]
    print(f"    {r['ranking_riesgo']:<3} {str(r['nombre_zona'])[:21]:<22} "
          f"{str(r['region'])[:12]:<13} {r['riesgo_global']:>7.2f}  {r['factor_critico']}")


def main() -> None:
    print("=" * 72)
    print("GeoRisk :: validacion del modelo de scoring")
    print("=" * 72)

    fallos = 0

    print("\n[1/4] Coherencia de pesos del modelo")
    errores = verificar_pesos()
    if errores:
        fallos += len(errores)
        for e in errores:
            print(f"      FALLO  {e}")
    else:
        print("      OK  los pesos suman 1.0 en dimension, subindice y variable")

    print("\n[2/4] Paridad entre sql/01_ddl_tablas.sql y motor_scoring.py")
    errores = comparar_sql_python()
    if errores:
        fallos += len(errores)
        for e in errores:
            print(f"      FALLO  {e}")
    else:
        print(f"      OK  {len(VARIABLES)} variables, {len(SUBINDICES)} subindices "
              f"y {len(DIMENSIONES)} dimensiones coinciden")

    print("\n[3/4] Calculo del scoring sobre el dataset")
    zonas = cargar_zonas()
    resultados = calcular_dataset(zonas)
    print(f"      OK  {len(resultados)} zonas procesadas")

    print("\n[4/4] Rango de scores y reconstruccion del riesgo global")
    errores = verificar_resultados(resultados)
    if errores:
        fallos += len(errores)
        for e in errores[:10]:
            print(f"      FALLO  {e}")
    else:
        print("      OK  scores en 0-100 y contribuciones consistentes")

    exportar(resultados)
    resumen(resultados)

    print("\n" + "=" * 72)
    if fallos:
        print(f"RESULTADO: {fallos} problema(s) detectado(s)")
        raise SystemExit(1)
    print("RESULTADO: modelo valido. Archivos escritos en data/out/")
    print("=" * 72)


if __name__ == "__main__":
    main()
