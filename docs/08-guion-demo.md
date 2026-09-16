# 08 - Guion del video demo y presentacion ejecutiva

---

# PARTE A — Video demo (3 minutos)

El enunciado pide mostrar: **datos → scoring/analisis en SAC → evaluacion de
riesgo → envio a revision en BPA → experiencia en Work Zone.**

## Preparacion antes de grabar

- [ ] Instancia de HANA Cloud **arrancada** (se apaga sola en trial)
- [ ] Dashboard de SAC abierto y cargado
- [ ] Work Zone abierto en otra pestana
- [ ] Bandeja de BPA vacia de tareas viejas
- [ ] Modelo con los **pesos base** (revertir cualquier what-if previo)
- [ ] Zona elegida para la demo identificada
- [ ] Grabar en 1080p, sin notificaciones del sistema

**Zonas sugeridas para el contraste:** una CRITICO (`Pallcca`, Pasco, 81.0) y
una BAJO (`Yanamayo`, Ancash, 24.2).

---

## Minuto 0:00 – 0:25 · Problema y datos

> "Peru es uno de los mayores productores de cobre, plata y zinc del mundo.
> Pero decidir donde explorar no depende solo del potencial geologico: una zona
> tecnicamente excelente puede volverse inviable por conflictos sociales o
> restricciones ambientales. Hoy esa evaluacion se hace de forma fragmentada."

**Pantalla:** SAP HANA Cloud, tabla `GEORISK_ZONAS`.

> "GeoRisk parte de un dataset unico en SAP HANA Cloud: 40 zonas de exploracion
> con 41 variables geologicas, ambientales, sociales, geograficas e historicas."

## Minuto 0:25 – 1:15 · Scoring y analisis en SAC

**Pantalla:** dashboard SAC, pagina 1.

> "Sobre ese dataset construimos un modelo de scoring multidimensional: 26
> variables agrupadas en 9 subindices y 3 dimensiones. Todo el calculo vive en
> HANA como vistas, y las ponderaciones estan en tablas, no en codigo."

Mostrar los KPIs.

> "De 40 zonas, 18 estan en riesgo alto o critico — el 45 % de la cartera.
> Concentran mas de 157 mil personas en el area de influencia y 553 millones de
> dolares de inversion acumulada."

**Pantalla:** pagina 2, ranking apilado.

> "El ranking no muestra solo el total: descompone cada zona en sus tres
> dimensiones. Dos zonas con el mismo score pueden tener composiciones
> opuestas, y eso cambia la decision."

Seleccionar 2 zonas en el radar.

> "Aqui comparamos Pallcca, riesgo critico, contra Yanamayo, riesgo bajo."

## Minuto 1:15 – 1:50 · Explicabilidad

**Pantalla:** pagina 3, filtrar por Pallcca.

> "El modelo no es una caja negra. Cada score se descompone en los puntos que
> aporta cada variable. En Pallcca los tres factores de mayor peso son: una
> densidad de 3.8 fallas por kilometro cuadrado, estar a solo 1.8 km de un area
> natural protegida, y una ley mineral de 0.75 % que deja poco margen ante
> cualquier sobrecosto."

Senalar las tarjetas de descomposicion.

> "Y aqui esta la diferencia con un promedio ponderado: de los 81 puntos, 71
> vienen del promedio y **10 son un agravante no compensatorio**. Su dimension
> social llega a 80, y cuando una dimension supera el umbral critico su exceso
> penaliza el score. Una geologia razonable no puede tapar un riesgo social
> critico."

## Minuto 1:50 – 2:30 · Envio a revision en BPA

**Pantalla:** Work Zone → Nueva Solicitud.

> "Desde Work Zone, el analista envia la zona a revision."

Completar y enviar.

> "El proceso en SAP Build Process Automation congela el scoring del momento.
> Si el modelo se recalibra despues, la evaluacion sigue mostrando los numeros
> sobre los que se decidio."

**Pantalla:** Mis Revisiones → abrir tarea.

> "El especialista ve el scoring, los factores criticos y decide: aprobar,
> observar o rechazar. La justificacion es obligatoria."

Decidir "OBSERVADO" con justificacion.

## Minuto 2:30 – 3:00 · Cierre del ciclo

**Pantalla:** dashboard, seccion de trazabilidad.

> "La decision vuelve a HANA y se refleja en el dashboard: quien decidio, cuando
> y por que. El ciclo se cierra: del dato a la decision y de vuelta al dato."

*(Si hay Joule)* — 15 segundos:

> "Y con SAP Joule se puede consultar en lenguaje natural."
> Preguntar: *"¿Por que Pallcca tiene riesgo critico?"*

**Cierre:**

> "GeoRisk: cuatro capas SAP integradas para decidir donde explorar con
> criterio geologico, ambiental y social."

---

# PARTE B — Presentacion ejecutiva (10 minutos)

Enfasis pedido: **analitica, gestion del riesgo e impacto social y ambiental.**

## Estructura

| Min | Seccion | Contenido |
|---|---|---|
| 0-1 | **Problema** | Fragmentacion de la evaluacion de riesgo en exploracion |
| 1-2 | **Solucion** | GeoRisk y las cuatro capas SAP |
| 2-4 | **Modelo** | 26 variables, 3 dimensiones, ponderaciones justificadas |
| 4-5 | **Lo diferencial** | No compensatorio + explicabilidad + parametros en tabla |
| 5-7 | **Demo en vivo** | Ranking → explicabilidad → what-if → revision |
| 7-8.5 | **Impacto** | Social, ambiental y de negocio |
| 8.5-10 | **Limitaciones y siguientes pasos** | Honestidad tecnica |

## Los tres mensajes que deben quedar

### 1. El modelo es auditable, no una caja negra

> "Cada score se descompone en los puntos que aporta cada variable, y la suma
> reconstruye exactamente el resultado. Lo verificamos automaticamente en cada
> ejecucion."

### 2. La agregacion refleja como funciona el riesgo real

> "Un promedio ponderado permite que una dimension excelente compense una
> critica. En gestion de riesgo eso es incorrecto. Por eso agregamos una
> penalizacion cuando una dimension supera el umbral: un riesgo social critico
> no se compensa con buena geologia."

### 3. El modelo es gobernable por el negocio

> "Las ponderaciones viven en tablas de HANA, no en codigo. Cambiar la politica
> de riesgo de la empresa es un UPDATE, no un proyecto de desarrollo."

Demostrarlo en vivo con el escenario de what-if.

## Seccion de impacto (minutos 7-8.5)

**Ambiental**
- Identifica zonas con potencial de drenaje acido antes de comprometer
  inversion — el pasivo mas costoso y persistente de la mineria.
- Incorpora cercania a areas protegidas, biodiversidad y estres hidrico como
  criterios de decision temprana, no como tramite posterior.

**Social**
- Hace visible la poblacion en area de influencia y la conflictividad historica
  en la misma pantalla que la ley mineral.
- El estado de la consulta previa es una variable del modelo: **no cumplirla
  eleva el riesgo del proyecto de forma explicita y cuantificada.**

**Uso responsable** — decirlo antes de que lo pregunten:

> "Un score social alto mide riesgo *para el proyecto*, no merito de la
> poblacion. Que una zona tenga mayor pobreza eleva el score porque exige mas
> diligencia, no porque valga menos. Presentarlo de otro modo seria un uso
> indebido de la herramienta."

**De negocio**
- Prioriza la cartera cruzando riesgo con atractivo geologico (matriz de
  cuadrantes) en lugar de descartar por score.
- Reduce el tiempo de evaluacion y deja trazabilidad auditable de cada
  decision.

## Preguntas probables del jurado

| Pregunta | Respuesta |
|---|---|
| *¿Como validaron las ponderaciones?* | Son juicio experto documentado, no calibracion estadistica — no habia datos historicos de resultados. Por eso viven en tablas: recalibrar es un UPDATE. Esta declarado en limitaciones. |
| *¿Por que biodiversidad alta = mas riesgo?* | Mayor biodiversidad implica mayor impacto potencial y mayor exigencia regulatoria. Mide riesgo del proyecto, no valor del ecosistema. |
| *¿Que pasa si cambian los pesos despues de aprobar una zona?* | El scoring se congela al enviar a revision. `V_GEORISK_TRAZABILIDAD` compara la foto contra el modelo vigente y marca la desviacion. |
| *¿Funciona con el dataset real del evento?* | Si. Todas las vistas leen de `V_GEORISK_ZONAS_BASE`; se adapta esa unica vista y el resto no se toca. |
| *¿Por que 40/35/25?* | La geologia es condicion habilitante; lo ambiental determina permisos y costos de mitigacion; lo social tiene menor peso nominal pero es la dimension que mas activa el agravante, asi que su impacto efectivo es mayor. |

## Cierre

> "GeoRisk no decide por el especialista: le da un ranking explicable, le
> muestra por que, y deja registro de lo que decidio. La decision sigue siendo
> humana; lo que cambia es que ahora es trazable y comparable."
