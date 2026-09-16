# 07 - Supuestos y limitaciones

Documento de honestidad tecnica. Anticipa las preguntas del jurado y evita que
una limitacion no declarada se lea como un error no detectado.

---

## 1. Sobre los datos

### El dataset es sintetico

**Supuesto.** El reto indica que un dataset comun estara precargado en HANA
Cloud. Como el acceso no estaba disponible durante la preparacion, se genero un
dataset equivalente con `data/generar_dataset.py`: 40 zonas, 41 variables, 12
regiones mineras reales del Peru, semilla fija (2026) para reproducibilidad.

**Implicancia.** Los valores **no corresponden a zonas reales**. Los nombres de
region y provincia son reales para dar verosimilitud geografica, pero las
coordenadas y todas las variables son generadas.

**Como se adapta al dataset real.** Modificando unicamente la vista
`V_GEORISK_ZONAS_BASE` para mapear los nombres de tabla y columna reales. El
resto del modelo (12 vistas, 2 procedimientos) no se toca. Ver
`docs/01-arquitectura.md` §2.2.

### Las variables estan correlacionadas por diseno

**Supuesto.** El generador usa un *factor latente de favorabilidad* que acopla
todas las variables de una zona.

**Por que.** Con 26 variables independientes, el promedio colapsa hacia 50 por
el teorema del limite central: todas las zonas puntuarian casi igual y el
dashboard no discriminaria. En la realidad las condiciones de una zona **si**
estan correlacionadas — una zona conflictiva suele serlo en varios frentes.

**Implicancia.** La dispersion del dataset sintetico es una propiedad elegida,
no una medicion. Con datos reales la distribucion podria ser distinta.

### Cobertura de niveles garantizada

El factor latente se reparte de forma estratificada sobre `[0, 1]` para
asegurar que existan zonas en los cuatro niveles de riesgo. Con muestreo
puramente aleatorio los casos extremos podrian no aparecer y la demo se
quedaria sin contrastes.

---

## 2. Sobre el modelo

### Las ponderaciones son juicio experto, no calibracion estadistica

**Limitacion principal del proyecto.** No existio un conjunto de resultados
historicos (proyectos que prosperaron vs. que fracasaron) contra el cual
ajustar los pesos. Los valores 40/35/25 y todos los sub-pesos provienen de
criterio documentado, no de regresion.

**Mitigacion.** Los pesos viven en tablas (`GEORISK_PARAM_*`), de modo que
recalibrarlos cuando existan datos reales es un `UPDATE`, no un rediseno. La
justificacion de cada uno esta escrita en `docs/02-modelo-scoring.md` §3.

### El umbral del agravante (60) es una eleccion de criterio

El valor a partir del cual se penaliza una dimension critica no se derivo de
datos. Se eligio 60 porque marca el punto medio de la banda "ALTO" (50-75).

**Efecto de cambiarlo:** bajarlo a 50 haria el modelo mas conservador (mas
zonas penalizadas); subirlo a 70 lo haria mas permisivo. Es un parametro
editable y se usa como escenario en la demo de what-if.

### El modelo asume independencia entre variables

No captura interacciones. Ejemplo concreto: precipitacion alta **combinada
con** NP/AP bajo produce un riesgo de drenaje acido mayor que la suma de ambos
efectos por separado, y el modelo actual los suma linealmente.

**Por que se acepto.** Modelar interacciones exige datos para estimarlas.
Inventar terminos de interaccion sin evidencia habria anadido complejidad sin
mejorar la validez.

### Los rangos de referencia son tecnicos, no empiricos

`MIN_REF` y `MAX_REF` de cada variable se fijaron por criterio tecnico
(rangos plausibles del dominio), no como percentiles del dataset.

**Ventaja:** el score de una zona no cambia al agregar zonas nuevas.
**Costo:** si el dataset real tiene valores fuera de estos rangos, se saturan
en los extremos. Revisar los rangos al conectar el dataset del evento.

### El scoring no tiene dimension temporal

Es una foto del riesgo actual. No modela como evoluciona a lo largo del ciclo
del proyecto ni incorpora tendencia. Las variables historicas
(`incidentes_registrados_n`, `dias_paralizacion_acum`) estan en el dataset pero
**no entran al scoring**: se reservaron como contexto para el revisor.

---

## 3. Sobre la implementacion

### Paridad SQL / Python verificada solo en parametros

`validar_modelo.py` compara los parametros del DDL contra el motor Python, pero
**no ejecuta el SQL** (no hay HANA disponible en preparacion). La equivalencia
de las formulas se sostiene por revision manual.

**Accion pendiente el dia del evento:** tras desplegar en HANA, comparar
`SELECT * FROM V_GEORISK_SCORING` contra `data/out/georisk_scoring.csv`. Deben
coincidir salvo redondeo. Es la verificacion mas importante de la Fase 0.

### Riesgos de redondeo en HANA

El motor Python usa `float` (doble precision); las vistas usan
`DECIMAL(5,2)` con `CAST` intermedios. Pueden aparecer diferencias de centesimas.
**No es un error** mientras no supere 0.05 puntos.

### Los procedimientos no fueron ejecutados

`SP_GEORISK_CREAR_EVALUACION` y `SP_GEORISK_REGISTRAR_DECISION` estan escritos
en SQLScript pero no se pudieron probar sin instancia HANA. Puede requerir
ajustes de sintaxis menores el dia del evento.

**Mitigacion:** el archivo `sql/04_trazabilidad.sql` incluye un bloque `DO`
de prueba comentado al final para validarlos apenas haya conexion.

---

## 4. Sobre el alcance

### Dependencias externas no controlables

| Dependencia | Estado | Plan si falla |
|---|---|---|
| Acceso a ambientes SAP Trial | No confirmado | Ver `docs/00-accesos-y-cuentas.md` |
| Dataset comun precargado | No confirmado | Usar el generado localmente |
| Conexion SAC ↔ HANA | Por probar | Import en lugar de Live |
| Conexion BPA ↔ HANA | Por probar | Datos en el formulario (Opcion B) |
| SAP Joule | Depende de NTT DATA | Se omite; es bonus |
| Mapas geograficos en SAC | Depende del trial | Tabla por region |

### Lo que este prototipo no es

- **No es un sistema de produccion.** No tiene gestion de usuarios, control de
  concurrencia, versionado de modelo ni auditoria de cambios de parametros.
- **No sustituye un estudio de impacto ambiental.** Es una herramienta de
  priorizacion temprana para decidir donde profundizar el analisis.
- **No predice conflictos sociales.** Mide condiciones asociadas a mayor
  probabilidad de conflicto segun criterio experto.

---

## 5. Uso responsable

El modelo asigna scores a zonas donde viven comunidades reales. Dos
precauciones que el equipo asume explicitamente:

1. **Un score alto no justifica excluir a una comunidad del proceso de
   consulta.** El indicador social mide riesgo *para el proyecto*, no merito de
   la poblacion. Presentarlo de otro modo seria un uso indebido.

2. **La variable `pobreza_pct` e `idh_distrital` aumentan el score de riesgo.**
   Esto refleja que operar en contextos vulnerables exige mas diligencia — no
   que esas zonas "valgan menos". La lectura correcta es: *mayor
   responsabilidad requerida*, no *menor prioridad*.

Ambos puntos se mencionan explicitamente en la presentacion ejecutiva, en la
seccion de impacto social.
