"""
GeoRisk - Generador de dataset sintetico de zonas de exploracion minera (Peru).

Genera un dataset reproducible (semilla fija) con variables geologicas,
ambientales, sociales, geograficas e historicas. La salida alimenta:
  - data/out/georisk_zonas.csv   -> carga a SAP HANA Cloud (tabla GEORISK_ZONAS)
  - data/out/georisk_zonas.sql   -> INSERTs por si no hay import de CSV en el trial

Uso:
    python data/generar_dataset.py [--zonas 40] [--seed 2026]

Nota: el reto indica que un dataset comun estara precargado en HANA Cloud.
Este generador produce un equivalente con la misma estructura para poder
avanzar sin acceso al ambiente; ver docs/07-supuestos-limitaciones.md.
"""

from __future__ import annotations

import argparse
import csv
import math
import random
from dataclasses import dataclass, asdict, fields
from datetime import date, timedelta
from pathlib import Path

SEED_POR_DEFECTO = 2026
ZONAS_POR_DEFECTO = 40

# --------------------------------------------------------------------------
# Contexto geografico: regiones mineras del Peru con su perfil caracteristico
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class PerfilRegion:
    region: str
    provincias: tuple[str, ...]
    lat: tuple[float, float]
    lon: tuple[float, float]
    altitud: tuple[int, int]
    precipitacion: tuple[int, int]
    # sesgos del perfil regional (0..1, donde 1 = condicion mas adversa)
    sesgo_social: float
    sesgo_hidrico: float
    mineral: str


REGIONES: tuple[PerfilRegion, ...] = (
    PerfilRegion("Ancash", ("Huari", "Bolognesi", "Recuay"),
                 (-10.4, -9.2), (-77.8, -77.0), (3200, 4700), (600, 1200), 0.55, 0.45, "Cobre"),
    PerfilRegion("Apurimac", ("Cotabambas", "Grau", "Aymaraes"),
                 (-14.4, -13.6), (-72.9, -72.2), (3400, 4600), (500, 1000), 0.85, 0.50, "Cobre"),
    PerfilRegion("Arequipa", ("Caraveli", "Condesuyos", "Castilla"),
                 (-16.6, -15.2), (-73.5, -72.0), (2500, 4300), (150, 500), 0.40, 0.75, "Cobre"),
    PerfilRegion("Cajamarca", ("Hualgayoc", "Celendin", "San Marcos"),
                 (-7.4, -6.5), (-78.8, -78.0), (2800, 4100), (900, 1500), 0.90, 0.35, "Oro"),
    PerfilRegion("Cusco", ("Chumbivilcas", "Espinar", "Paruro"),
                 (-14.9, -14.0), (-72.3, -71.3), (3600, 4700), (700, 1100), 0.75, 0.40, "Cobre"),
    PerfilRegion("Junin", ("Yauli", "Concepcion", "Jauja"),
                 (-12.1, -11.3), (-76.2, -75.4), (3800, 4800), (600, 1000), 0.50, 0.35, "Zinc"),
    PerfilRegion("Moquegua", ("Mariscal Nieto", "General Sanchez Cerro"),
                 (-17.2, -16.3), (-71.0, -70.3), (3000, 4600), (150, 450), 0.60, 0.80, "Cobre"),
    PerfilRegion("Pasco", ("Pasco", "Daniel Alcides Carrion"),
                 (-10.9, -10.2), (-76.5, -76.0), (4000, 4600), (800, 1300), 0.65, 0.30, "Zinc"),
    PerfilRegion("Puno", ("Melgar", "Lampa", "San Antonio de Putina"),
                 (-15.5, -14.3), (-70.8, -69.8), (3900, 4800), (500, 900), 0.80, 0.45, "Plata"),
    PerfilRegion("Tacna", ("Tarata", "Candarave"),
                 (-17.6, -17.0), (-70.4, -69.9), (3300, 4500), (100, 400), 0.55, 0.85, "Cobre"),
    PerfilRegion("La Libertad", ("Santiago de Chuco", "Pataz", "Otuzco"),
                 (-8.4, -7.6), (-78.3, -77.4), (2900, 4200), (700, 1200), 0.60, 0.40, "Oro"),
    PerfilRegion("Ayacucho", ("Lucanas", "Parinacochas", "Huanca Sancos"),
                 (-15.1, -14.0), (-74.6, -73.6), (3500, 4600), (400, 900), 0.70, 0.55, "Plata"),
)

SUFIJOS_ZONA = (
    "Alta", "Norte", "Sur", "Este", "Oeste", "Central", "Baja", "Nueva",
    "Antigua", "Grande", "Chico", "Viejo",
)

NOMBRES_ZONA = (
    "Pumahuasi", "Quillcayhuanca", "Antamarca", "Chalhuane", "Ccarhuayo",
    "Tinyaclla", "Ocoruro", "Yanacocha", "Huayllay", "Corani", "Sillapata",
    "Ticlla", "Ampato", "Chocopata", "Sacsayhuaman", "Ranrahirca",
    "Pachacutec", "Ayapata", "Chumpe", "Colquemarca", "Tantahuatay",
    "Urubamba", "Yanamayo", "Pariacaca", "Huaytara", "Ccochaccasa",
    "Anccara", "Pallcca", "Toquepala", "Quellaveco", "Ilabaya", "Coriwayta",
    "Marcapata", "Sayapullo", "Huanzala", "Pucamarca", "Ccalla", "Antaimarca",
    "Rumichaca", "Vizcachani", "Lloclla", "Suytuccocha", "Yuraccasa",
    "Millpo", "Chungar", "Atacocha", "Racracancha", "Ninabamba",
)

ESTADOS_CONSULTA = ("Concluida", "En proceso", "No iniciada", "No aplica")
ESTADOS_LICENCIA = ("Vigente", "En tramite", "Observada", "Sin licencia")
FASES = ("Prospeccion", "Exploracion inicial", "Exploracion avanzada", "Prefactibilidad")


# --------------------------------------------------------------------------
# Estructura de una zona (orden = orden de columnas en CSV y tabla HANA)
# --------------------------------------------------------------------------


@dataclass
class Zona:
    # --- Identificacion ---
    zona_id: str
    nombre_zona: str
    region: str
    provincia: str
    distrito: str
    mineral_principal: str
    fase_proyecto: str
    # --- Geograficas ---
    latitud: float
    longitud: float
    altitud_msnm: int
    superficie_ha: int
    # --- Geologicas ---
    densidad_fallas_km2: float
    indice_estabilidad_talud: float
    sismicidad_pga_g: float
    ley_mineral_pct: float
    profundidad_deposito_m: int
    tonelaje_estimado_mt: float
    permeabilidad_md: float
    potencial_dam_npap: float
    # --- Ambientales ---
    dist_fuente_agua_km: float
    calidad_agua_ica: float
    estres_hidrico_idx: float
    dist_area_protegida_km: float
    indice_biodiversidad: float
    especies_amenazadas_n: int
    pasivos_ambientales_n: int
    cobertura_glaciar_pct: float
    precipitacion_anual_mm: int
    # --- Sociales ---
    comunidades_influencia_n: int
    poblacion_afectada: int
    indice_aceptacion_social: float
    conflictos_historicos_n: int
    consulta_previa_estado: str
    permisos_pendientes_n: int
    estado_licencia: str
    dist_centro_poblado_km: float
    idh_distrital: float
    pobreza_pct: float
    # --- Historicas ---
    fecha_inicio_exploracion: str
    inversion_acumulada_musd: float
    incidentes_registrados_n: int
    dias_paralizacion_acum: int


# --------------------------------------------------------------------------
# Utilidades de muestreo
# --------------------------------------------------------------------------


def _u(rng: random.Random, a: float, b: float, dec: int = 2) -> float:
    """Uniforme redondeado."""
    return round(rng.uniform(a, b), dec)


def _sesgado(rng: random.Random, a: float, b: float, sesgo: float, dec: int = 2) -> float:
    """
    Muestrea en [a, b] empujando el resultado hacia b cuando `sesgo` -> 1.

    Mezcla una uniforme con el extremo superior; mantiene dispersion pero
    reproduce el perfil regional (p. ej. mas conflictividad en Apurimac).
    """
    base = rng.uniform(a, b)
    valor = base * (1 - sesgo * 0.6) + b * (sesgo * 0.6)
    ruido = rng.gauss(0, (b - a) * 0.08)
    return round(min(b, max(a, valor + ruido)), dec)


def _entero_sesgado(rng: random.Random, a: int, b: int, sesgo: float) -> int:
    return int(round(_sesgado(rng, a, b, sesgo, dec=2)))


def _lat(rng: random.Random, mejor: float, peor: float, fav: float,
         fuerza: float = 0.70, dec: int = 2) -> float:
    """
    Muestrea una variable condicionada al factor latente de favorabilidad.

    `fav` en [0, 1]: 1 = zona favorable (tiende al extremo `mejor`),
    0 = zona problematica (tiende al extremo `peor`). `fuerza` regula cuanto
    pesa el factor latente frente al azar.

    Sin este acoplamiento las 26 variables serian independientes y, al
    promediarlas, todos los scores colapsarian hacia la media (~50): el
    dashboard no discriminaria entre zonas. En la realidad las condiciones
    de una zona estan correlacionadas -- una zona conflictiva suele serlo en
    varios frentes a la vez -- y este factor reproduce esa estructura.
    """
    lo, hi = min(mejor, peor), max(mejor, peor)
    objetivo = mejor + (peor - mejor) * (1.0 - fav)
    base = rng.uniform(lo, hi)
    valor = base * (1.0 - fuerza) + objetivo * fuerza
    valor += rng.gauss(0, (hi - lo) * 0.10)
    return round(min(hi, max(lo, valor)), dec)


def _lat_int(rng: random.Random, mejor: int, peor: int, fav: float,
             fuerza: float = 0.55) -> int:
    return int(round(_lat(rng, mejor, peor, fav, fuerza, dec=2)))


def _categoria(rng: random.Random, opciones: tuple[str, ...], pesos: list[float]) -> str:
    return rng.choices(opciones, weights=pesos, k=1)[0]


# --------------------------------------------------------------------------
# Generacion de una zona
# --------------------------------------------------------------------------


def generar_zona(rng: random.Random, indice: int, perfil: PerfilRegion,
                 nombre: str, fav: float) -> Zona:
    """
    Genera una zona. `fav` es el factor latente de favorabilidad en [0, 1]
    (1 = condiciones favorables, 0 = condiciones adversas) que acopla todas
    las variables; ver `_lat`.
    """
    altitud = rng.randint(*perfil.altitud)
    # A mayor altitud, mas probabilidad de cobertura glaciar y cabecera de cuenca.
    factor_altura = max(0.0, min(1.0, (altitud - 3500) / 1300))

    # El perfil regional modula la favorabilidad en los frentes social e hidrico:
    # una zona intrinsecamente buena en una region conflictiva no lo es tanto.
    fav_social = max(0.0, min(1.0, fav * (1.0 - perfil.sesgo_social * 0.32)))
    fav_hidrico = max(0.0, min(1.0, fav * (1.0 - perfil.sesgo_hidrico * 0.28)))

    # --- Geologia -------------------------------------------------------
    densidad_fallas = _lat(rng, 0.2, 4.8, fav)
    # Zonas con muchas fallas tienden a taludes menos estables.
    estabilidad = round(max(1.0, min(10.0, 9.5 - densidad_fallas * 1.1 + rng.gauss(0, 0.8))), 2)
    # Sismicidad: base regional (sur y costa mas activos) modulada por el latente.
    sismicidad_base = 0.42 + (perfil.lat[0] + 12) * -0.012
    sismicidad = round(max(0.10, min(0.62,
                                     sismicidad_base + (0.5 - fav) * 0.16 + rng.gauss(0, 0.05))), 3)

    ley = round(_lat(rng, 2.00, 0.25, fav, dec=3), 3)
    profundidad = _lat_int(rng, 80, 760, fav)
    # Depositos mas profundos suelen reportar mayor tonelaje potencial.
    tonelaje = round(max(10.0, min(1000.0,
                                   _lat(rng, 900.0, 20.0, fav) * rng.uniform(0.75, 1.25))), 1)
    permeabilidad = round(_lat(rng, 0.5, 450.0, fav, fuerza=0.50), 2)
    # NP/AP: relacion neutralizacion/acidez. <1 indica riesgo alto de drenaje acido.
    potencial_dam = round(_lat(rng, 2.90, 0.25, fav), 2)

    # --- Ambiental ------------------------------------------------------
    dist_agua = round(_lat(rng, 9.5, 0.20, fav_hidrico), 2)
    calidad_agua = _lat(rng, 95.0, 30.0, fav_hidrico)
    estres_hidrico = _lat(rng, 15.0, 92.0, fav_hidrico)
    dist_protegida = round(_lat(rng, 48.0, 0.50, fav), 2)
    # Cerca de areas protegidas, la biodiversidad medida es mas alta.
    biodiv = round(max(10.0, min(98.0, 88 - dist_protegida * 1.1 + rng.gauss(0, 9))), 2)
    especies = int(round(max(0, min(25, biodiv / 5.2 + rng.gauss(0, 2.2)))))
    pasivos = _lat_int(rng, 0, 15, fav)
    glaciar = round(max(0.0, min(30.0,
                                 factor_altura * _lat(rng, 2.0, 28.0, fav) - rng.uniform(0, 3))), 2)
    precipitacion = rng.randint(*perfil.precipitacion)

    # --- Social ---------------------------------------------------------
    comunidades = _lat_int(rng, 0, 14, fav_social)
    poblacion = int(round(max(120, comunidades * rng.uniform(180, 1400) + rng.uniform(0, 900))))
    conflictos = _lat_int(rng, 0, 11, fav_social)
    # La aceptacion cae con la conflictividad historica y el numero de comunidades.
    aceptacion = round(max(5.0, min(97.0,
                                    92 - conflictos * 5.2 - comunidades * 1.4 + rng.gauss(0, 7))), 2)
    # Las zonas favorables tienen mas probabilidad de consulta concluida y licencia vigente.
    consulta = _categoria(rng, ESTADOS_CONSULTA,
                          [0.15 + 0.45 * fav_social, 0.30, 0.40 - 0.32 * fav_social, 0.15])
    licencia = _categoria(rng, ESTADOS_LICENCIA,
                          [0.12 + 0.52 * fav_social, 0.32,
                           0.34 - 0.24 * fav_social, 0.22 - 0.20 * fav_social])
    permisos = _lat_int(rng, 0, 11, fav_social)
    dist_poblado = round(_lat(rng, 19.0, 0.30, fav_social), 2)
    idh = round(_lat(rng, 0.70, 0.22, fav_social, dec=3), 3)
    # La pobreza se mueve en sentido inverso al IDH.
    pobreza = round(max(4.0, min(78.0, 88 - idh * 105 + rng.gauss(0, 6))), 2)

    # --- Historia -------------------------------------------------------
    inicio = date(2016, 1, 1) + timedelta(days=rng.randint(0, 3200))
    anios = (date(2026, 1, 1) - inicio).days / 365.25
    inversion = round(max(0.4, anios * rng.uniform(0.8, 9.5)), 2)
    incidentes = int(round(max(0, min(24, conflictos * rng.uniform(0.4, 1.9) + rng.gauss(0, 1.6)))))
    paralizacion = int(round(max(0, incidentes * rng.uniform(2, 26) + rng.uniform(0, 15))))

    fase = _categoria(rng, FASES, [0.24, 0.30, 0.28, 0.18])

    return Zona(
        zona_id=f"Z{indice:03d}",
        nombre_zona=nombre,
        region=perfil.region,
        provincia=rng.choice(perfil.provincias),
        distrito=f"{rng.choice(perfil.provincias)} {rng.choice(SUFIJOS_ZONA)}",
        mineral_principal=perfil.mineral,
        fase_proyecto=fase,
        latitud=round(rng.uniform(*perfil.lat), 5),
        longitud=round(rng.uniform(*perfil.lon), 5),
        altitud_msnm=altitud,
        superficie_ha=rng.randint(180, 9800),
        densidad_fallas_km2=densidad_fallas,
        indice_estabilidad_talud=estabilidad,
        sismicidad_pga_g=sismicidad,
        ley_mineral_pct=ley,
        profundidad_deposito_m=profundidad,
        tonelaje_estimado_mt=tonelaje,
        permeabilidad_md=permeabilidad,
        potencial_dam_npap=potencial_dam,
        dist_fuente_agua_km=dist_agua,
        calidad_agua_ica=calidad_agua,
        estres_hidrico_idx=estres_hidrico,
        dist_area_protegida_km=dist_protegida,
        indice_biodiversidad=biodiv,
        especies_amenazadas_n=especies,
        pasivos_ambientales_n=pasivos,
        cobertura_glaciar_pct=glaciar,
        precipitacion_anual_mm=precipitacion,
        comunidades_influencia_n=comunidades,
        poblacion_afectada=poblacion,
        indice_aceptacion_social=aceptacion,
        conflictos_historicos_n=conflictos,
        consulta_previa_estado=consulta,
        permisos_pendientes_n=permisos,
        estado_licencia=licencia,
        dist_centro_poblado_km=dist_poblado,
        idh_distrital=idh,
        pobreza_pct=pobreza,
        fecha_inicio_exploracion=inicio.isoformat(),
        inversion_acumulada_musd=inversion,
        incidentes_registrados_n=incidentes,
        dias_paralizacion_acum=paralizacion,
    )


def generar_dataset(n_zonas: int, semilla: int) -> list[Zona]:
    rng = random.Random(semilla)
    nombres = list(NOMBRES_ZONA)
    rng.shuffle(nombres)

    # Factor latente de favorabilidad repartido sobre todo el espectro [0, 1].
    # Se construye de forma estratificada (no por muestreo aleatorio) para
    # garantizar que el dataset contenga zonas en los cuatro niveles de riesgo:
    # con muestreo puro, las zonas extremas podrian no aparecer y el dashboard
    # quedaria sin casos que contrastar en la demo.
    favorabilidades = [
        min(1.0, max(0.0, (i + 0.5) / n_zonas + rng.gauss(0, 0.05)))
        for i in range(n_zonas)
    ]
    rng.shuffle(favorabilidades)

    zonas: list[Zona] = []
    for i in range(n_zonas):
        perfil = REGIONES[i % len(REGIONES)]
        base = nombres[i % len(nombres)]
        # A partir de la segunda vuelta de nombres, se anade sufijo para evitar duplicados.
        nombre = base if i < len(nombres) else f"{base} {SUFIJOS_ZONA[i % len(SUFIJOS_ZONA)]}"
        zonas.append(generar_zona(rng, i + 1, perfil, nombre, favorabilidades[i]))
    return zonas


# --------------------------------------------------------------------------
# Salidas
# --------------------------------------------------------------------------

COLUMNAS = [f.name for f in fields(Zona)]


def escribir_csv(zonas: list[Zona], ruta: Path) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with ruta.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=COLUMNAS)
        writer.writeheader()
        for zona in zonas:
            writer.writerow(asdict(zona))


def _literal_sql(valor: object) -> str:
    if isinstance(valor, str):
        return "'" + valor.replace("'", "''") + "'"
    return str(valor)


def escribir_inserts_sql(zonas: list[Zona], ruta: Path, tabla: str = "GEORISK_ZONAS") -> None:
    """Genera INSERTs por lotes, util si el trial no permite importar CSV."""
    ruta.parent.mkdir(parents=True, exist_ok=True)
    columnas = ", ".join(COLUMNAS)
    lineas = [
        "-- GeoRisk :: carga de datos generada por data/generar_dataset.py",
        "-- Ejecutar despues de sql/01_ddl_tablas.sql",
        "",
        f"DELETE FROM {tabla};",
        "",
    ]
    for zona in zonas:
        datos = asdict(zona)
        valores = ", ".join(_literal_sql(datos[c]) for c in COLUMNAS)
        lineas.append(f"INSERT INTO {tabla} ({columnas}) VALUES ({valores});")
    lineas.append("")
    ruta.write_text("\n".join(lineas), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera el dataset sintetico de GeoRisk.")
    parser.add_argument("--zonas", type=int, default=ZONAS_POR_DEFECTO)
    parser.add_argument("--seed", type=int, default=SEED_POR_DEFECTO)
    parser.add_argument("--out", type=Path, default=Path(__file__).parent / "out")
    args = parser.parse_args()

    zonas = generar_dataset(args.zonas, args.seed)
    escribir_csv(zonas, args.out / "georisk_zonas.csv")
    escribir_inserts_sql(zonas, args.out / "georisk_zonas.sql")

    print(f"Generadas {len(zonas)} zonas (semilla {args.seed})")
    print(f"  CSV : {args.out / 'georisk_zonas.csv'}")
    print(f"  SQL : {args.out / 'georisk_zonas.sql'}")
    regiones = sorted({z.region for z in zonas})
    print(f"  Regiones cubiertas: {len(regiones)} -> {', '.join(regiones)}")


if __name__ == "__main__":
    main()
