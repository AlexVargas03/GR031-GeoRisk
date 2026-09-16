# 04 - Dashboard en SAP Analytics Cloud

Guia de construccion. El entregable pide **al menos 3 KPIs de riesgo y
visualizaciones comparativas entre zonas**; esta especificacion entrega 6 KPIs
y 7 visualizaciones distribuidas en 4 paginas.

---

## 1. Conexion a HANA Cloud

1. **Connections → Add Connection → SAP HANA Cloud**
2. Tipo: *Live Data Connection* (preferida) o *Import Data*
3. Datos: host de la instancia, puerto `443`, usuario y contrasena
4. Probar la conexion **antes de seguir**

> **Live vs Import.** Live refleja los cambios de parametros al instante — es
> lo que hace posible la demo de "que pasa si" cambiando una ponderacion. Si
> Live falla en el trial, usar Import y **documentar que el what-if requiere
> refrescar**. No perder mas de 45 minutos peleando con Live: el dashboard es
> mas importante que el modo de conexion.

### Modelos a crear

| Modelo | Vista origen | Alimenta |
|---|---|---|
| `M_Scoring` | `V_GEORISK_SCORING` | KPIs, ranking, detalle |
| `M_Radar` | `V_GEORISK_RADAR` | Comparacion por dimension |
| `M_Region` | `V_GEORISK_POR_REGION` | Agregados regionales |
| `M_Factores` | `V_GEORISK_TOP_FACTORES` | Explicabilidad |
| `M_Mapa` | `V_GEORISK_MAPA` | Capa geografica |
| `M_Matriz` | `V_GEORISK_MATRIZ` | Dispersion riesgo/atractivo |
| `M_Trazabilidad` | `V_GEORISK_TRAZABILIDAD` | Seguimiento de revisiones |

En `M_Mapa`, marcar `LATITUD` y `LONGITUD` como **dimensiones geograficas**
(tipo *Latitude/Longitude*), no como medidas.

---

## 2. Pagina 1 — Panorama de la cartera

### Fila de KPIs (6 tarjetas, modelo `M_Scoring` → `V_GEORISK_KPI`)

| KPI | Campo | Formato |
|---|---|---|
| Riesgo global promedio | `RIESGO_GLOBAL_PROMEDIO` | 1 decimal |
| Zonas en riesgo alto | `ZONAS_RIESGO_ALTO` | entero |
| % cartera en riesgo | `PCT_ZONAS_RIESGO_ALTO` | 1 decimal + % |
| Zonas criticas | `ZONAS_CRITICAS` | entero, rojo |
| Poblacion expuesta | `POBLACION_EN_RIESGO` | miles |
| Inversion en riesgo | `INVERSION_EN_RIESGO_MUSD` | MUSD |

Los tres ultimos son los que conectan el analisis con el **impacto social y
economico** — el enfasis que pide la presentacion ante el jurado.

### Grafico 1 — Distribucion por nivel de riesgo

- Tipo: barras horizontales apiladas o dona
- Modelo: `V_GEORISK_DISTRIBUCION`
- Dimension: `NIVEL_DESC` · Medida: `N_ZONAS`
- **Colores fijos** segun `NIVEL_COLOR`: verde `#2E7D32`, amarillo `#F9A825`,
  naranja `#EF6C00`, rojo `#C62828`. Usar siempre estos cuatro en todo el
  dashboard para que el lector aprenda el codigo una sola vez.
- Ordenar por `NIVEL_ORDEN`, no alfabeticamente.

### Grafico 2 — Riesgo promedio por region

- Tipo: barras horizontales, ordenadas de mayor a menor
- Modelo: `M_Region` · Dimension: `REGION` · Medida: `RIESGO_GLOBAL_PROM`
- Color por `DIMENSION_DOMINANTE`: muestra de un vistazo si una region sufre
  mas por geologia, ambiente o conflictividad social.

---

## 3. Pagina 2 — Ranking y comparacion

### Grafico 3 — Ranking de zonas (visualizacion principal)

- Tipo: barras horizontales apiladas
- Modelo: `M_Scoring` · Dimension: `NOMBRE_ZONA` (top 15 por `RIESGO_GLOBAL`)
- Medidas apiladas: `RIESGO_GEOLOGICO`, `RIESGO_AMBIENTAL`, `RIESGO_SOCIAL`

> Apilar las tres dimensiones en lugar de mostrar solo el total permite ver
> **de que esta hecho** el riesgo de cada zona. Dos zonas con score 70 pueden
> tener composiciones opuestas, y esa diferencia cambia la decision.

Paleta por dimension (consistente en todo el dashboard):
Geologico `#5B6C8F` · Ambiental `#3D8168` · Social `#B0763A`

### Grafico 4 — Radar comparativo

- Tipo: radar
- Modelo: `M_Radar` · Dimension: `DIMENSION` · Serie: `NOMBRE_ZONA`
- **Filtro de entrada** para seleccionar 2-3 zonas

Es el widget que responde "comparar zonas" del enunciado. En la demo:
seleccionar una zona critica y una de bajo riesgo — el contraste es inmediato.

### Grafico 5 — Matriz riesgo vs atractivo

- Tipo: dispersion (scatter)
- Modelo: `M_Matriz`
- Eje X: `ATRACTIVO_GEOLOGICO` · Eje Y: `RIESGO_GLOBAL`
- Tamano: `INVERSION_ACUMULADA_MUSD` · Color: `CUADRANTE`
- Lineas de referencia en X=50 e Y=50 para marcar los cuadrantes

Este grafico aporta lo que el ranking no puede: **priorizacion**. Una zona de
riesgo alto pero atractivo excepcional (cuadrante *Requiere mitigacion*) no se
descarta, se gestiona. Es el grafico que convierte el analisis en decision.

---

## 4. Pagina 3 — Explicabilidad de una zona

Pagina con **filtro de entrada por `ZONA_ID`** que gobierna todos los widgets.

### Grafico 6 — Factores que explican el score

- Tipo: barras horizontales
- Modelo: `M_Factores` · Dimension: `VARIABLE_DESC` · Medida: `CONTRIBUCION_PP`
- Ordenar por `ORDEN_FACTOR`, mostrar los 5 primeros
- Etiqueta adicional: `PCT_DEL_RIESGO`

### Tabla de detalle

Columnas: `VARIABLE_DESC`, `VALOR_ORIGINAL`, `UNIDAD`, `VALOR_NORM`,
`CONTRIBUCION_PP`, `PCT_DEL_RIESGO`.

Muestra el valor real junto al normalizado: el especialista ve que la
permeabilidad es de 340 mD **y** que eso equivale a 68/100 de riesgo.

### Tarjetas de descomposicion

`RIESGO_BASE` · `AGRAVANTE` · `RIESGO_GLOBAL` · `PEOR_DIMENSION`

Hace visible el componente no compensatorio: se ve cuanto del score viene del
promedio y cuanto de la penalizacion por tener un frente critico.

---

## 5. Pagina 4 — Mapa y proceso

### Grafico 7 — Mapa geografico

- Tipo: Geo Map, capa de burbujas
- Modelo: `M_Mapa` · Ubicacion: `LATITUD` / `LONGITUD`
- Color: `NIVEL_RIESGO` (misma paleta) · Tamano: `TAMANO_BURBUJA`
- Tooltip: nombre, region, riesgo global, factor critico

> Si el ambiente trial no habilita mapas geograficos, sustituir por una tabla
> agrupada por region con `RIESGO_GLOBAL_PROM`. El enunciado dice
> explicitamente que la representacion geografica se incorpora *"cuando el
> dataset y el ambiente lo permitan"*. **No es motivo para perder tiempo.**

### Seguimiento del proceso

Modelo `M_Trazabilidad`:
- KPIs: pendientes, aprobadas, observadas, rechazadas, dias de ciclo promedio
- Tabla de evaluaciones con `ALERTA_VIGENCIA`

---

## 6. Simulacion "que pasa si"

El bonus de simulacion de escenarios se logra sin funciones avanzadas de SAC,
porque los pesos viven en tablas de HANA:

```sql
-- Escenario: priorizar el frente social sobre el geologico
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.30 WHERE DIMENSION_COD = 'GEO';
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.35 WHERE DIMENSION_COD = 'AMB';
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.35 WHERE DIMENSION_COD = 'SOC';
```

Con conexion **Live**, refrescar el dashboard y el ranking se reordena en vivo.

Otros escenarios preparados para la demo:

```sql
-- Escenario "regulacion ambiental mas estricta"
UPDATE GEORISK_PARAM_MODELO SET VALOR = 50 WHERE PARAM_COD = 'AGRAVANTE_UMBRAL';

-- Volver al modelo base
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.40 WHERE DIMENSION_COD = 'GEO';
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.35 WHERE DIMENSION_COD = 'AMB';
UPDATE GEORISK_PARAM_DIMENSION SET PESO = 0.25 WHERE DIMENSION_COD = 'SOC';
UPDATE GEORISK_PARAM_MODELO    SET VALOR = 60 WHERE PARAM_COD = 'AGRAVANTE_UMBRAL';
```

> ⚠️ **Tener los comandos de vuelta al modelo base preparados y probados.** Si
> la demo termina con pesos alterados, los numeros de la presentacion no
> coincidiran con los del documento del modelo.

---

## 7. Criterios de diseno visual

- **Cuatro colores de nivel, sin excepciones.** El lector aprende el codigo una
  vez y lo aplica en todo el dashboard.
- **Ordenar por magnitud**, nunca alfabeticamente, salvo en el radar.
- **Escala 0-100 fija** en los ejes de riesgo. Un eje automatico exagera
  diferencias pequenas y enganа al lector.
- **Titulos que afirmen**, no que etiqueten: "5 zonas concentran el 60 % de la
  poblacion expuesta" comunica mas que "Poblacion por zona".
- Maximo 3 visualizaciones por pagina.

---

## 8. Prueba antes de la demo

- [ ] Los KPIs coinciden con `data/out/georisk_scoring.csv`
- [ ] El filtro de zona gobierna toda la pagina 3
- [ ] El radar compara correctamente 2 zonas
- [ ] Los colores de nivel son consistentes en las 4 paginas
- [ ] El what-if reordena el ranking y **se puede revertir**
- [ ] El dashboard carga en menos de 10 segundos
