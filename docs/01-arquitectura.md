# 01 - Arquitectura de la solucion

---

## 1. Vista general

```
┌──────────────────────────────────────────────────────────────────────┐
│  EXPERIENCIA          SAP Build Work Zone, standard edition          │
│                       punto unico de acceso                          │
│   ┌────────────┬─────────────────┬──────────────┬────────────────┐   │
│   │ Dashboard  │ Bandeja de      │ Documentacion│  Joule         │   │
│   │ de riesgos │ revision        │ del modelo   │  (opcional)    │   │
│   └─────┬──────┴────────┬────────┴──────────────┴────────┬───────┘   │
└─────────┼───────────────┼─────────────────────────────────┼──────────┘
          │               │                                 │
┌─────────▼───────┐ ┌─────▼──────────────────┐ ┌────────────▼─────────┐
│  ANALITICA      │ │  PROCESO               │ │  IA CONVERSACIONAL   │
│  SAP Analytics  │ │  SAP Build Process     │ │  SAP Joule +         │
│  Cloud          │ │  Automation            │ │  Joule Studio        │
│                 │ │                        │ │                      │
│ · KPIs          │ │ · Formulario revision  │ │ · Consultar riesgo   │
│ · Ranking       │ │ · Aprobar/Observar/    │ │ · Comparar zonas     │
│ · Radar         │ │   Rechazar             │ │ · Explicar scoring   │
│ · Mapa          │ │ · Registro decision    │ │                      │
│ · What-if       │ │ · Bitacora             │ │      (BONUS)         │
└────────┬────────┘ └───────────┬────────────┘ └──────────┬───────────┘
         │                      │                         │
         └──────────────────────┼─────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────────────┐
│  DATOS                    SAP HANA Cloud                             │
│                                                                      │
│  Tablas base          Parametros del modelo      Trazabilidad        │
│  · GEORISK_ZONAS      · PARAM_DIMENSION          · EVALUACION        │
│                       · PARAM_SUBINDICE          · EVAL_LOG          │
│                       · PARAM_VARIABLE                               │
│                       · PARAM_CATEGORIA                              │
│                       · PARAM_ESCALA                                 │
│                       · PARAM_MODELO                                 │
│                                                                      │
│  Cadena de scoring (vistas)                                          │
│  V_ZONAS_BASE → V_VALORES → V_NORM → V_SUBINDICE → V_DIMENSION       │
│                                              → V_SCORING             │
│                                              → V_CONTRIBUCION        │
│                                                                      │
│  Vistas analiticas          Procedimientos                           │
│  · V_KPI      · V_RADAR     · SP_CREAR_EVALUACION                    │
│  · V_RANKING  · V_MAPA      · SP_REGISTRAR_DECISION                  │
│  · V_MATRIZ   · V_TOP_FACTORES                                       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. Decisiones de arquitectura

### 2.1 El scoring vive en HANA, no en SAC

**Decision:** todo el calculo de riesgo se implementa como vistas en HANA
Cloud. SAC solo consume y visualiza.

**Por que:**
- Una sola fuente de verdad. Si el scoring viviera en formulas de SAC, BPA y
  Joule tendrian que reimplementarlo, con riesgo de divergencia.
- BPA necesita el score para congelar la foto de la evaluacion. Solo puede
  obtenerlo si esta en la base.
- El calculo se ejecuta donde estan los datos (mejor rendimiento).

### 2.2 Un unico punto de adaptacion al dataset del evento

`V_GEORISK_ZONAS_BASE` es una vista trivial (`SELECT * FROM GEORISK_ZONAS`)
que existe solo para aislar el resto del modelo del nombre real de la tabla.

**Por que:** el reto indica que el dataset comun estara precargado, pero no se
conoce su esquema ni sus nombres de columna hasta el dia del evento. Cuando se
conozcan, **se modifica esa unica vista** (mapeando nombres con alias) y las 12
vistas y 2 procedimientos siguientes siguen funcionando sin tocarse.

Es la diferencia entre 10 minutos de adaptacion y varias horas de reescritura.

### 2.3 Parametros del modelo en tablas

Ninguna vista contiene un peso ni un rango literal: todo se lee de
`GEORISK_PARAM_*` mediante joins.

**Consecuencias:**
- Simulacion "que pasa si" = un `UPDATE` + refrescar SAC. Sin redeploy.
- El modelo se puede exhibir en el dashboard (`V_GEORISK_MODELO_DOC`): el
  jurado ve las ponderaciones reales, no una lamina.
- Agregar una variable = insertar una fila + una rama en `V_GEORISK_VALORES`.

### 2.4 Formato largo para el scoring

`V_GEORISK_VALORES` convierte la tabla ancha (41 columnas) a formato largo
(`zona_id`, `variable`, `valor`). A partir de ahi todo el calculo es
data-driven: un join con los parametros y una sola expresion de normalizacion
sirve para las 26 variables.

**Alternativa descartada:** normalizar columna por columna habria significado
26 expresiones `CASE` repetidas, imposibles de mantener y de auditar.

### 2.5 El scoring se congela al enviar a revision

`GEORISK_EVALUACION` guarda una copia de los scores en el momento del envio.

**Por que:** si el modelo se recalibra despues, la evaluacion revisada debe
seguir mostrando los numeros sobre los que la persona decidio. Sin esa foto la
trazabilidad no seria auditable. `V_GEORISK_TRAZABILIDAD` compara la foto
contra el scoring vigente y marca las desviaciones (`ALERTA_VIGENCIA`).

---

## 3. Flujo de informacion end-to-end

```
1. Dataset en HANA Cloud
       │
2.     ├─→ Cadena de vistas calcula scoring (26 variables → 3 dimensiones → global)
       │
3.     ├─→ SAC consume V_GEORISK_SCORING y vistas analiticas
       │      · el analista explora ranking, radar, mapa, matriz
       │      · identifica una zona que requiere revision
       │
4.     ├─→ Desde Work Zone se dispara el proceso en SAP BPA
       │      · SP_GEORISK_CREAR_EVALUACION congela el scoring
       │      · se genera la tarea para el especialista
       │
5.     ├─→ El especialista revisa en su bandeja (Work Zone)
       │      · ve scoring, factores criticos y datos de la zona
       │      · decide: Aprobar / Observar / Rechazar + justificacion
       │
6.     ├─→ SP_GEORISK_REGISTRAR_DECISION persiste la decision
       │      · GEORISK_EVALUACION: estado final
       │      · GEORISK_EVAL_LOG: bitacora del evento
       │
7.     └─→ El resultado vuelve a SAC (V_GEORISK_TRAZABILIDAD)
              · KPIs del proceso: ciclo, tasa de aprobacion
              · Joule puede consultar el historial en lenguaje natural
```

---

## 4. Servicios SAP y su rol

| Capa | Servicio | Rol en GeoRisk | Obligatorio |
|---|---|---|---|
| Datos | SAP HANA Cloud | Dataset, modelo de scoring, trazabilidad, procedimientos | Si |
| Analitica | SAP Analytics Cloud | Dashboard, KPIs, ranking, comparacion, what-if | Si |
| Proceso | SAP Build Process Automation | Flujo de revision y registro de decisiones | Si |
| Experiencia | SAP Build Work Zone, std. | Punto de acceso unificado | Si |
| IA | SAP Joule + Joule Studio | Consulta y explicacion en lenguaje natural | No (bonus) |

Ver `docs/00-accesos-y-cuentas.md` para como se obtiene cada uno.

---

## 5. Modelo de datos

### Tablas

| Tabla | Filas aprox. | Proposito |
|---|---|---|
| `GEORISK_ZONAS` | 40 | Dataset base: 41 columnas por zona |
| `GEORISK_PARAM_DIMENSION` | 3 | Pesos de las dimensiones |
| `GEORISK_PARAM_SUBINDICE` | 9 | Pesos de los subindices |
| `GEORISK_PARAM_VARIABLE` | 26 | Rango, sentido y peso de cada variable |
| `GEORISK_PARAM_CATEGORIA` | 8 | Traduccion de categoricas a score |
| `GEORISK_PARAM_ESCALA` | 4 | Umbrales de clasificacion |
| `GEORISK_PARAM_MODELO` | 2 | Umbral y factor del agravante |
| `GEORISK_EVALUACION` | variable | Evaluaciones enviadas a revision |
| `GEORISK_EVAL_LOG` | variable | Bitacora de eventos |

### Vistas por proposito

| Proposito | Vistas |
|---|---|
| Cadena de scoring | `V_GEORISK_ZONAS_BASE`, `V_GEORISK_VALORES`, `V_GEORISK_NORM`, `V_GEORISK_SUBINDICE`, `V_GEORISK_DIMENSION`, `V_GEORISK_SCORING` |
| Explicabilidad | `V_GEORISK_CONTRIBUCION`, `V_GEORISK_TOP_FACTORES`, `V_GEORISK_MODELO_DOC` |
| Analitica (SAC) | `V_GEORISK_KPI`, `V_GEORISK_RANKING`, `V_GEORISK_POR_REGION`, `V_GEORISK_RADAR`, `V_GEORISK_MAPA`, `V_GEORISK_MATRIZ`, `V_GEORISK_DISTRIBUCION` |
| Proceso (BPA) | `V_GEORISK_PENDIENTES`, `V_GEORISK_TRAZABILIDAD`, `V_GEORISK_BITACORA`, `V_GEORISK_KPI_PROCESO` |

---

## 6. Orden de despliegue

```
sql/01_ddl_tablas.sql        tablas + parametros del modelo
sql/01b_dataset_real.sql     adaptacion al dataset real del evento (ver nota)
sql/02_vistas_scoring.sql    cadena de scoring
sql/03_vistas_analiticas.sql vistas para SAC
sql/04_trazabilidad.sql      procedimientos y vistas para BPA
data/out/georisk_zonas.sql   carga de datos (solo si se usa el dataset sintetico propio)
```

> **Nota:** `01b_dataset_real.sql` reemplaza `V_GEORISK_ZONAS_BASE` para
> adaptarla al dataset real del evento (`dataset_tema2_georisk.csv`), que
> resulto ser un historial de evaluaciones (11458 filas / 140 zonas) y no
> una tabla estatica de 40 zonas como se asumio inicialmente. Solo se
> ejecuta si se usa ese dataset; si se usa el dataset sintetico propio
> (`data/generar_dataset.py`), se omite y la vista original de
> `01_ddl_tablas.sql` sigue funcionando tal cual.

Verificacion post-despliegue:

```sql
SELECT COUNT(*) FROM V_GEORISK_SCORING;          -- debe devolver 40
SELECT * FROM V_GEORISK_KPI;                     -- una fila con los KPIs
SELECT * FROM V_GEORISK_RANKING ORDER BY RANKING_RIESGO LIMIT 5;
```

Los resultados deben coincidir con `data/out/georisk_scoring.csv`, generado por
el motor de referencia en Python. Si difieren, hay un problema de tipos o de
redondeo en HANA que hay que investigar antes de seguir.
