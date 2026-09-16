# 06 - SAP Joule y Joule Studio (extension opcional)

> **Estado:** bonus. Requiere que NTT DATA habilite el acceso desde su
> subcuenta; no existe trial publico. Ver `docs/00-accesos-y-cuentas.md`.
>
> **Regla de alcance:** Joule se construye **solo cuando los 8 entregables
> obligatorios esten cerrados**. Es la capa mas vistosa y la mas facil de
> subestimar en tiempo; empezarla antes es el error clasico que deja un
> prototipo incompleto.

---

## 1. Por que este proyecto se presta bien a Joule

El modelo ya produce las respuestas en forma estructurada. `V_GEORISK_TOP_FACTORES`
entrega, por zona, las cinco variables que mas pesan con su valor real y el
porcentaje del riesgo que explican. Una skill de Joule no tiene que *razonar*
sobre el scoring: solo tiene que **consultar y redactar**.

Eso hace la integracion viable en pocas horas y, sobre todo, hace que las
respuestas sean verificables contra el dashboard — no alucinadas.

---

## 2. Skills propuestas

### Skill 1 — Consultar el riesgo de una zona

**Intencion:** *"¿Cual es el riesgo de la zona Pallcca?"*

```
Entrada : nombre o codigo de zona
Consulta: SELECT * FROM V_GEORISK_SCORING WHERE UPPER(NOMBRE_ZONA) LIKE ...
Salida  : nivel, score global, los tres scores dimensionales, factor critico
```

Respuesta esperada (cifras reales del dataset de referencia):

> La zona Pallcca (Pasco) tiene un riesgo global de 81.0, nivel **CRITICO**.
> Se descompone en riesgo geologico 66.3, ambiental 70.1 y social 80.0. El
> factor critico es *Biodiversidad y areas naturales*. De los 81 puntos, 71.0
> corresponden al riesgo base y 10.0 a un agravante por superar el umbral en la
> dimension social.

### Skill 2 — Explicar un score

**Intencion:** *"¿Por que Pallcca tiene riesgo critico?"*

```
Consulta: SELECT * FROM V_GEORISK_TOP_FACTORES WHERE ZONA_ID = ...
          ORDER BY ORDEN_FACTOR
Salida  : las 5 variables de mayor contribucion con valor real y porcentaje
```

Respuesta esperada (cifras reales del dataset de referencia):

> El riesgo de Pallcca se explica principalmente por: densidad de fallas
> geologicas de 3.78 por km2 (aporta 4.2 puntos), distancia a area natural
> protegida de solo 1.84 km (4.1 puntos) y ley mineral de 0.75 %, baja para el
> nivel de riesgo que enfrenta (3.9 puntos).

### Skill 3 — Comparar zonas

**Intencion:** *"Compara Pallcca con Yanamayo"*

```
Consulta: V_GEORISK_RADAR filtrado por dos zonas
Salida  : diferencias por dimension y cual es preferible
```

### Skill 4 — Ranking y filtros

**Intencion:** *"¿Cuales son las 5 zonas de mayor riesgo en Cusco?"*

```
Consulta: V_GEORISK_RANKING con filtro de region
```

### Skill 5 — Estado de revisiones

**Intencion:** *"¿Que evaluaciones estan pendientes?"*

```
Consulta: V_GEORISK_PENDIENTES ORDER BY PRIORIDAD
```

---

## 3. Construccion en Joule Studio

1. Crear un proyecto de skills en Joule Studio.
2. Definir una **skill por intencion** (no una skill genérica que lo haga todo:
   la desambiguacion se vuelve fragil).
3. Configurar la conexion a HANA Cloud como fuente de datos.
4. Declarar los parametros de entrada (`nombre_zona`, `region`, `n`).
5. Definir plantillas de respuesta que **citen siempre los numeros**.
6. Probar con las frases exactas que se usaran en la demo.

---

## 4. Reglas de diseno de las respuestas

- **Siempre citar el numero.** "Riesgo alto" sin el score no es verificable
  contra el dashboard.
- **Nunca inventar una recomendacion que el modelo no sustente.** Si la skill
  no tiene el dato, debe decirlo.
- **Distinguir base y agravante** cuando el agravante sea mayor que cero: es
  la parte del modelo mas dificil de entender y la que mas luce al explicarla.
- **Responder en las unidades originales** ademas del score normalizado: "NP/AP
  de 0.4" es mas util para un especialista que "68/100".

---

## 5. Guion sugerido para la demo (60-90 segundos)

```
1. "¿Cual es el riesgo de la zona Pallcca?"
       → respuesta con score y dimensiones

2. "¿Por que?"
       → los 5 factores principales con sus valores reales

3. "Comparala con Yanamayo"
       → contraste por dimension

4. "¿Cuantas evaluaciones estan pendientes de revision?"
       → cierra el ciclo mostrando que Joule tambien ve el proceso
```

La cuarta pregunta es la que demuestra que Joule esta conectado a **toda** la
solucion y no solo al dataset.

---

## 6. Si Joule no esta disponible

No afecta ningun entregable obligatorio. En la presentacion:

- Mencionar que la arquitectura lo contempla como capa aditiva.
- Mostrar `V_GEORISK_TOP_FACTORES` y explicar que **la explicabilidad ya esta
  resuelta en la capa de datos**; Joule seria la interfaz conversacional sobre
  una capacidad que ya existe.

Ese argumento es mas solido que una integracion a medio terminar: demuestra que
la decision de alcance fue deliberada, no una falta de tiempo.
