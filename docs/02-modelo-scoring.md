# 02 - Modelo de scoring multidimensional

Documento de referencia del modelo GeoRisk: variables, escalas, ponderaciones,
logica de calculo y justificacion de cada decision.

---

## 1. Principios de diseno

El modelo se construyo sobre cuatro decisiones que lo diferencian de un
promedio ponderado convencional:

| Decision | Que resuelve |
|---|---|
| **Parametros en tablas, no en codigo** | Cambiar una ponderacion es un `UPDATE`, no una edicion de SQL. Habilita simulacion "que pasa si" en vivo. |
| **Rangos de referencia fijos** | El score de una zona no cambia cuando se agregan zonas nuevas al dataset. Un min-max sobre la muestra haria el score inestable. |
| **Agregacion no compensatoria** | Un riesgo social critico no queda diluido por una geologia excelente. |
| **Contribucion por variable** | Cada score se descompone en los puntos que aporta cada variable: el resultado es auditable, no una caja negra. |

---

## 2. Jerarquia del modelo

```
RIESGO GLOBAL
├── Riesgo Geologico ................................ peso 0.40
│   ├── Estabilidad estructural ..................... 0.40
│   │   ├── Densidad de fallas geologicas ........... 0.35  (directo)
│   │   ├── Indice de estabilidad de taludes ........ 0.35  (inverso)
│   │   └── Sismicidad (PGA) ........................ 0.30  (directo)
│   ├── Caracteristicas del deposito ................ 0.35
│   │   ├── Ley mineral equivalente ................. 0.40  (inverso)
│   │   ├── Profundidad del deposito ................ 0.35  (directo)
│   │   └── Tonelaje estimado ....................... 0.25  (inverso)
│   └── Hidrogeologia y drenaje acido ............... 0.25
│       ├── Permeabilidad de la roca ................ 0.40  (directo)
│       └── Potencial de drenaje acido (NP/AP) ...... 0.60  (inverso)
│
├── Riesgo Ambiental ................................ peso 0.35
│   ├── Recurso hidrico ............................. 0.40
│   │   ├── Distancia a fuente de agua .............. 0.35  (inverso)
│   │   ├── Indice de calidad de agua ............... 0.35  (inverso)
│   │   └── Indice de estres hidrico ................ 0.30  (directo)
│   ├── Biodiversidad y areas naturales ............. 0.35
│   │   ├── Distancia a area protegida .............. 0.35  (inverso)
│   │   ├── Indice de biodiversidad local ........... 0.35  (directo)
│   │   └── Especies amenazadas ..................... 0.30  (directo)
│   └── Pasivos, emisiones y residuos ............... 0.25
│       ├── Pasivos ambientales preexistentes ....... 0.40  (directo)
│       ├── Cobertura glaciar ....................... 0.35  (directo)
│       └── Precipitacion anual ..................... 0.25  (directo)
│
└── Riesgo Social ................................... peso 0.25
    ├── Aceptacion comunitaria ...................... 0.40
    │   ├── Indice de aceptacion social ............. 0.45  (inverso)
    │   ├── Conflictos historicos ................... 0.35  (directo)
    │   └── Comunidades en area de influencia ....... 0.20  (directo)
    ├── Contexto legal y permisos ................... 0.35
    │   ├── Estado de consulta previa ............... 0.40  (categorico)
    │   ├── Estado de licencia ...................... 0.35  (categorico)
    │   └── Permisos pendientes ..................... 0.25  (directo)
    └── Contexto territorial ........................ 0.25
        ├── Distancia a centro poblado .............. 0.35  (inverso)
        ├── Incidencia de pobreza ................... 0.35  (directo)
        └── IDH distrital ........................... 0.30  (inverso)
```

**26 variables · 9 subindices · 3 dimensiones.** Los pesos suman 1.0 en cada
nivel (verificado automaticamente por `data/validar_modelo.py`).

---

## 3. Justificacion de las ponderaciones

### Entre dimensiones (40 / 35 / 25)

- **Geologico 40 %** — es la condicion habilitante. Sin un deposito viable y
  estructuralmente manejable, los otros riesgos son irrelevantes porque no hay
  proyecto que evaluar.
- **Ambiental 35 %** — determina la obtencion de permisos y concentra los
  costos de mitigacion; en Peru es la causa mas frecuente de reformulacion de
  proyectos de exploracion.
- **Social 25 %** — menor peso *nominal*, pero es la dimension que mas
  frecuentemente activa el agravante no compensatorio (seccion 5), por lo que
  su impacto efectivo sobre el ranking es mayor que su peso.

> Estas ponderaciones son un **punto de partida documentado y editable**, no
> una verdad tecnica. La tabla `GEORISK_PARAM_DIMENSION` permite al jurado o
> al negocio cambiarlas en vivo y ver el efecto inmediato.

### Casos que merecen explicacion

| Variable | Sentido | Por que |
|---|---|---|
| **Ley mineral** | Inverso | Baja ley = margen estrecho = mayor riesgo de inviabilidad economica ante cualquier sobrecosto. |
| **Tonelaje** | Inverso | Poco tonelaje no amortiza la inversion en mitigacion ambiental y social. |
| **Indice de biodiversidad** | Directo | Mayor biodiversidad = mayor impacto potencial y exigencia regulatoria. No es que la biodiversidad sea mala: es que eleva el riesgo del proyecto. |
| **Potencial DAM (NP/AP)** | Inverso, peso 0.60 | Es la variable individual de mayor peso dentro de su subindice. Un ratio NP/AP < 1 implica drenaje acido, el pasivo ambiental mas costoso y persistente de la mineria. |
| **Precipitacion** | Directo | Mas lluvia acelera la lixiviacion y el transporte de contaminantes. |
| **Distancia a centro poblado** | Inverso | Mayor cercania = mas poblacion expuesta y mayor probabilidad de conflicto. |

### Variables categoricas

Se traducen a score de riesgo 0-100 mediante `GEORISK_PARAM_CATEGORIA`:

| Consulta previa | Score | | Estado de licencia | Score |
|---|---|---|---|---|
| Concluida | 0 | | Vigente | 0 |
| No aplica | 15 | | En tramite | 50 |
| En proceso | 45 | | Observada | 80 |
| No iniciada | 85 | | Sin licencia | 100 |

"No aplica" no es 0 porque la ausencia de obligacion de consulta no elimina
por completo el riesgo relacional con el entorno.

---

## 4. Normalizacion

Cada variable se lleva a una escala **0-100 donde 100 = riesgo maximo**:

```
valor_recortado = min(max(x, MIN_REF), MAX_REF)

directo:  norm = 100 * (valor_recortado - MIN_REF) / (MAX_REF - MIN_REF)
inverso:  norm = 100 - directo
```

**Por que se recorta al rango.** Un outlier (una permeabilidad de 5000 mD en un
dataset cuyo rango tecnico llega a 500) no debe arrastrar la escala ni producir
valores fuera de 0-100. Se satura en el extremo.

**Por que los rangos son fijos y no min-max de la muestra.** Si la escala se
derivara del dataset, agregar una zona nueva cambiaria el score de todas las
demas. Con rangos de referencia tecnica, el score de una zona es una propiedad
de esa zona, no de la muestra en la que se la mire. Esto es indispensable para
que una evaluacion archivada siga siendo comparable meses despues.

---

## 5. Agregacion

### 5.1 Componente compensatorio (riesgo base)

Media ponderada en tres niveles:

```
subindice = SUM(norm_i * peso_i) / SUM(peso_i)
dimension = SUM(subindice_j * peso_j) / SUM(peso_j)
riesgo_base = SUM(dimension_k * peso_k) / SUM(peso_k)
```

Se divide por la suma de pesos *presentes* — no por 1.0 — para que el
resultado siga en 0-100 aunque falte una variable en el dataset. Es robustez
ante nulos: si el dataset del evento no trae una columna, el modelo sigue
funcionando con las restantes en lugar de devolver `NULL`.

### 5.2 Componente no compensatorio (agravante)

Una media ponderada pura tiene un defecto grave para gestion de riesgo:
**permite que una dimension excelente compense una critica.** Una zona con
riesgo social de 95 y geologia de 20 promediaria "aceptable", cuando en la
realidad es inviable.

Por eso se agrega una penalizacion cuando la peor dimension supera un umbral:

```
agravante     = FACTOR * max(0, peor_dimension - UMBRAL)
riesgo_global = min(100, riesgo_base + agravante)

UMBRAL = 60    FACTOR = 0.50    (tabla GEORISK_PARAM_MODELO)
```

**Ejemplo.** Zona con base 58 y riesgo ambiental 84:
`agravante = 0.5 * (84 - 60) = 12` → `riesgo_global = 70` (pasa de ALTO a ALTO
pero sube 12 puntos en el ranking, reflejando que tiene un frente critico).

El agravante se reporta **como columna separada** (`AGRAVANTE`, `RIESGO_BASE`,
`PEOR_DIMENSION`) para que la trazabilidad no se pierda: siempre se puede
explicar cuanto del score viene del promedio y cuanto de la penalizacion.

---

## 6. Clasificacion

| Nivel | Rango | Color | Lectura operativa |
|---|---|---|---|
| **BAJO** | 0 – 25 | Verde `#2E7D32` | Viable; continuar exploracion |
| **MODERADO** | 25 – 50 | Amarillo `#F9A825` | Viable con medidas de manejo |
| **ALTO** | 50 – 75 | Naranja `#EF6C00` | Requiere mitigacion antes de avanzar |
| **CRITICO** | 75 – 100 | Rojo `#C62828` | Replantear o descartar |

---

## 7. Explicabilidad

La vista `V_GEORISK_CONTRIBUCION` descompone cada score:

```
peso_efectivo   = peso_variable * peso_subindice * peso_dimension
contribucion_pp = valor_normalizado * peso_efectivo
```

**La suma de todas las contribuciones reconstruye exactamente el riesgo base.**
Esto se verifica automaticamente en cada ejecucion de `validar_modelo.py`
(control 4). Es lo que permite responder "por que esta zona puntua asi" con
numeros, y lo que alimenta las respuestas en lenguaje natural de Joule.

`V_GEORISK_TOP_FACTORES` expone las 5 variables de mayor aporte por zona, con
el porcentaje del riesgo que cada una explica.

---

## 8. Resultados sobre el dataset de referencia

Dataset de 40 zonas en 12 regiones mineras (semilla 2026):

```
Riesgo global : min 24.16 | promedio 51.05 | max 81.01

BAJO        2  ##
MODERADO   20  ####################
ALTO       13  #############
CRITICO     5  #####
```

Distribucion unimodal con sesgo hacia el centro-alto, coherente con una
cartera de exploracion real: pocas zonas sin problemas, pocas inviables, la
mayoria gestionables con medidas.

---

## 9. Validacion automatica

`python data/validar_modelo.py` ejecuta cuatro controles:

1. **Coherencia de pesos** — suman 1.0 en dimension, subindice y variable.
2. **Paridad SQL ↔ Python** — los `INSERT` de `sql/01_ddl_tablas.sql` deben
   coincidir con los parametros de `data/motor_scoring.py`. Si alguien cambia
   una ponderacion en un solo lado, el control falla. Evita que el modelo de
   HANA y el de referencia se separen sin que nadie lo note.
3. **Rango** — todo score cae en 0-100.
4. **Reconstruccion** — las contribuciones suman el riesgo base, y
   `base + agravante = global`.

---

## 10. Limitaciones conocidas

- **Ponderaciones por juicio experto, no calibradas con datos historicos.** No
  hubo un dataset de resultados reales (proyectos exitosos vs. fallidos) para
  ajustar los pesos estadisticamente. Estan documentados y son editables.
- **Independencia asumida entre variables.** El modelo no captura interacciones
  (p. ej. alta precipitacion *combinada con* NP/AP bajo es peor que la suma de
  ambos efectos por separado).
- **Umbral del agravante (60) elegido por criterio**, no derivado de datos.
- **Sin componente temporal.** El scoring es una foto; no modela como
  evoluciona el riesgo a lo largo del ciclo del proyecto.

Ver `docs/07-supuestos-limitaciones.md` para el detalle completo.
