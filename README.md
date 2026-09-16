# GeoRisk

**Evaluacion inteligente de riesgos geologicos y socioambientales en zonas de
exploracion minera.**

Reto HKT-2026-T2 · SAP HANA Cloud + SAP Analytics Cloud + SAP Build Process
Automation + SAP Build Work Zone

---

## Que es

GeoRisk evalua, compara y **explica** el riesgo de zonas de exploracion minera
combinando tres dimensiones — geologica, ambiental y social — en un score
unico y auditable, con un flujo de revision humana y trazabilidad completa de
cada decision.

```
40 zonas · 12 regiones mineras · 41 variables
26 variables en el modelo · 9 subindices · 3 dimensiones
```

---

## Inicio rapido

```bash
# 1. Generar el dataset sintetico (reproducible, semilla fija)
python data/generar_dataset.py

# 2. Validar el modelo y calcular el scoring de referencia
python data/validar_modelo.py
```

La validacion ejecuta cuatro controles y debe terminar con
`RESULTADO: modelo valido`. Genera en `data/out/`:

| Archivo | Contenido |
|---|---|
| `georisk_zonas.csv` | Dataset para cargar en HANA Cloud |
| `georisk_zonas.sql` | Mismos datos como `INSERT` (si el trial no importa CSV) |
| `georisk_scoring.csv` | Scoring de referencia — **comparar contra HANA** |
| `georisk_contribuciones.csv` | Aporte de cada variable al score de cada zona |
| `georisk_scoring.json` | Insumo para prototipos |

---

## Prototipo visual del dashboard

```bash
python prototipo/preparar_datos.py
```

Genera `prototipo/dashboard.html`, un panel autocontenido con los datos reales
del modelo. Cumple dos funciones:

- **Referencia de diseno** para construir el dashboard en SAC — cada widget
  corresponde a una vista de `sql/03_vistas_analiticas.sql`.
- **Plan B de demo** si la conexion SAC ↔ HANA falla el dia del evento.

> No sustituye a SAC: el entregable exige el dashboard construido en SAP
> Analytics Cloud. Este prototipo permite validar el diseno y los numeros antes
> de tener acceso al ambiente.

---

## Despliegue en SAP HANA Cloud

Ejecutar en orden:

```
sql/01_ddl_tablas.sql          tablas + parametros del modelo
sql/02_vistas_scoring.sql      cadena de scoring (6 vistas)
sql/03_vistas_analiticas.sql   vistas para SAC (9 vistas)
sql/04_trazabilidad.sql        procedimientos y vistas para BPA
data/out/georisk_zonas.sql     carga de datos
```

Verificacion:

```sql
SELECT COUNT(*) FROM V_GEORISK_SCORING;   -- 40
SELECT * FROM V_GEORISK_KPI;
```

> **Si la organizacion entrega el dataset comun ya cargado:** no ejecutar la
> creacion de `GEORISK_ZONAS`. Adaptar unicamente la vista
> `V_GEORISK_ZONAS_BASE` (final de `01_ddl_tablas.sql`) al nombre real de tabla
> y columnas. El resto del modelo funciona sin cambios.

---

## Documentacion

| Documento | Para que |
|---|---|
| [00 - Accesos y cuentas](docs/00-accesos-y-cuentas.md) | Que suscripciones SAP hacen falta y como obtenerlas |
| [01 - Arquitectura](docs/01-arquitectura.md) | Capas, decisiones de diseno, modelo de datos |
| [02 - Modelo de scoring](docs/02-modelo-scoring.md) | Variables, ponderaciones, formulas, justificacion |
| [03 - Proceso BPA](docs/03-proceso-bpa.md) | Guia de armado del flujo de revision |
| [04 - Dashboard SAC](docs/04-dashboard-sac.md) | Guia de armado del dashboard |
| [05 - Work Zone](docs/05-work-zone.md) | Estructura del site y experiencia |
| [06 - Joule](docs/06-joule-skills.md) | Skills conversacionales (bonus) |
| [07 - Supuestos y limitaciones](docs/07-supuestos-limitaciones.md) | Honestidad tecnica |
| [08 - Guion de demo](docs/08-guion-demo.md) | Video 3 min + presentacion 10 min |

---

## El modelo en una pagina

```
RIESGO GLOBAL = min(100, RIESGO_BASE + AGRAVANTE)

  RIESGO_BASE = 0.40 × Geologico + 0.35 × Ambiental + 0.25 × Social
  AGRAVANTE   = 0.50 × max(0, peor_dimension − 60)
```

**Cuatro decisiones que lo distinguen de un promedio ponderado:**

1. **Parametros en tablas, no en codigo** — cambiar una ponderacion es un
   `UPDATE`; habilita simulacion "que pasa si" en vivo.
2. **Rangos de referencia fijos** — el score de una zona no cambia cuando se
   agregan zonas nuevas al dataset.
3. **Agregacion no compensatoria** — una geologia excelente no puede tapar un
   riesgo social critico.
4. **Contribucion por variable** — cada score se descompone en los puntos que
   aporta cada variable, y la suma reconstruye el resultado exactamente.

Clasificacion: BAJO 0-25 · MODERADO 25-50 · ALTO 50-75 · CRITICO 75-100

---

## Resultados sobre el dataset de referencia

```
Riesgo global : min 24.16 | promedio 51.05 | max 81.01

BAJO        2  ██
MODERADO   20  ████████████████████
ALTO       13  █████████████
CRITICO     5  █████
```

---

## Estructura del repositorio

```
├── data/
│   ├── generar_dataset.py      generador sintetico (semilla fija)
│   ├── motor_scoring.py        motor de referencia; replica el SQL
│   ├── validar_modelo.py       4 controles de validacion
│   └── out/                    salidas generadas
├── sql/
│   ├── 01_ddl_tablas.sql       tablas y parametros
│   ├── 02_vistas_scoring.sql   cadena de scoring
│   ├── 03_vistas_analiticas.sql vistas para SAC
│   └── 04_trazabilidad.sql     procedimientos para BPA
└── docs/                       documentacion (00 a 08)
```

---

## Validacion automatica

`python data/validar_modelo.py` verifica:

1. **Coherencia de pesos** — suman 1.0 en dimension, subindice y variable.
2. **Paridad SQL ↔ Python** — los parametros del DDL coinciden con los del
   motor de referencia. Si alguien cambia una ponderacion en un solo lado, el
   control falla.
3. **Rango** — todo score cae en 0-100.
4. **Reconstruccion** — las contribuciones suman el riesgo base, y
   `base + agravante = global`.

> El control 2 existe porque el modelo esta implementado dos veces — en SQL
> para HANA y en Python como referencia. Sin esa verificacion, ambos podrian
> divergir sin que nadie lo note hasta la demo.

---

## Estado

| Componente | Estado |
|---|---|
| Dataset sintetico | Completo y validado |
| Modelo de scoring (SQL) | Completo — **pendiente ejecutar en HANA** |
| Motor de referencia (Python) | Completo y validado |
| Vistas analiticas | Completas — pendiente conectar SAC |
| Procedimientos de trazabilidad | Escritos — **pendiente probar en HANA** |
| Dashboard SAC | Especificado, pendiente construir |
| Proceso BPA | Especificado, pendiente construir |
| Work Zone | Especificado, pendiente construir |
| Joule | Especificado (bonus, depende de NTT DATA) |

**Primera accion al obtener acceso a HANA:** desplegar los 4 archivos SQL y
comparar `SELECT * FROM V_GEORISK_SCORING` contra `data/out/georisk_scoring.csv`.
Deben coincidir salvo redondeo (tolerancia 0.05).
