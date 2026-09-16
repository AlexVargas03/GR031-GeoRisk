"""
GeoRisk - Prepara el payload de datos que consume el prototipo de dashboard.

Lee las salidas de data/out/ y escribe un JSON compacto con lo que el
dashboard necesita: scoring por zona, top factores y atributos de contexto.

Uso:
    python data/generar_dataset.py
    python data/validar_modelo.py
    python prototipo/preparar_datos.py
"""

from __future__ import annotations

import csv
import json
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
OUT = RAIZ / "data" / "out"
DESTINO = Path(__file__).parent / "datos.json"

# Mismos coeficientes que V_GEORISK_MATRIZ en sql/03_vistas_analiticas.sql
LEY_MIN, LEY_MAX = 0.20, 2.00
TON_MIN, TON_MAX = 10.0, 1000.0


def atractivo(ley: float, tonelaje: float) -> float:
    """Atractivo geologico 0-100 (100 = mejor). Espejo de V_GEORISK_MATRIZ."""
    l = (min(max(ley, LEY_MIN), LEY_MAX) - LEY_MIN) / (LEY_MAX - LEY_MIN)
    t = (min(max(tonelaje, TON_MIN), TON_MAX) - TON_MIN) / (TON_MAX - TON_MIN)
    return round(100.0 * (0.60 * l + 0.40 * t), 2)


def cuadrante(riesgo: float, atr: float) -> str:
    if riesgo < 50 and atr >= 50:
        return "Prioritaria"
    if riesgo < 50:
        return "Viable"
    if atr >= 50:
        return "Requiere mitigacion"
    return "Descartable"


def main() -> None:
    scoring = json.loads((OUT / "georisk_scoring.json").read_text(encoding="utf-8"))
    zonas = {r["zona_id"]: r for r in csv.DictReader(
        (OUT / "georisk_zonas.csv").open(encoding="utf-8"))}

    salida = []
    for s in scoring:
        z = zonas[s["zona_id"]]
        ley = float(z["ley_mineral_pct"])
        ton = float(z["tonelaje_estimado_mt"])
        atr = atractivo(ley, ton)

        salida.append({
            "id": s["zona_id"],
            "nombre": s["nombre_zona"],
            "region": s["region"],
            "provincia": z["provincia"],
            "mineral": z["mineral_principal"],
            "fase": z["fase_proyecto"],
            "rank": s["ranking_riesgo"],
            "global": s["riesgo_global"],
            "base": s["riesgo_base"],
            "agravante": s["agravante"],
            "geo": s["riesgo_geologico"],
            "amb": s["riesgo_ambiental"],
            "soc": s["riesgo_social"],
            "nivel": s["nivel_riesgo"],
            "factor": s["factor_critico"],
            "factorScore": s["factor_critico_score"],
            "lat": float(z["latitud"]),
            "lon": float(z["longitud"]),
            "altitud": int(z["altitud_msnm"]),
            "poblacion": int(z["poblacion_afectada"]),
            "comunidades": int(z["comunidades_influencia_n"]),
            "inversion": float(z["inversion_acumulada_musd"]),
            "ley": ley,
            "tonelaje": ton,
            "atractivo": atr,
            "cuadrante": cuadrante(s["riesgo_global"], atr),
            "subindices": s["subindices"],
            # Solo los 6 factores de mayor aporte: es lo que muestra el panel
            "factores": [
                {
                    "desc": c["descripcion"],
                    "dim": c["dimension"],
                    "valor": c["valor_original"],
                    "unidad": c["unidad"],
                    "norm": c["valor_norm"],
                    "pts": c["contribucion_pp"],
                }
                for c in s["contribuciones"][:6]
            ],
        })

    payload = json.dumps(salida, ensure_ascii=False, separators=(",", ":"))
    DESTINO.write_text(payload, encoding="utf-8")
    print(f"Escrito {DESTINO.name}  ({len(salida)} zonas, {len(payload)/1024:.1f} KB)")

    # Ensamblar el dashboard autocontenido a partir de la plantilla
    plantilla = Path(__file__).parent / "dashboard.template.html"
    if not plantilla.exists():
        print(f"AVISO: no se encontro {plantilla.name}; no se genero el dashboard")
        return

    # El marcador incluye el "[]" para que se sustituya entero. Si solo se
    # reemplazara el comentario, quedaria "const DATOS = [...][];" -> el
    # "[]" sobrante es un error de sintaxis y ningun grafico se dibuja.
    marca = "/*__DATOS__*/[]"
    html = plantilla.read_text(encoding="utf-8")
    if marca not in html:
        raise SystemExit(f"La plantilla no contiene el marcador {marca}")

    destino_html = Path(__file__).parent / "dashboard.html"
    generado = html.replace(marca, payload)
    destino_html.write_text(generado, encoding="utf-8")

    # Comprobacion: la sentencia de datos debe cerrar limpiamente
    if "}][];" in generado or "const DATOS = [];" in generado:
        raise SystemExit("ERROR: los datos no quedaron bien insertados en el HTML")

    print(f"Escrito {destino_html.name} ({destino_html.stat().st_size/1024:.1f} KB)")


if __name__ == "__main__":
    main()
