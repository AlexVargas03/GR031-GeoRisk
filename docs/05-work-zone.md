# 05 - Experiencia en SAP Build Work Zone, standard edition

Work Zone es el **punto unico de acceso** del prototipo: desde ahi se llega al
dashboard, a las tareas de revision y a la documentacion del modelo.

---

## 1. Estructura del site

```
GeoRisk — Evaluacion de Riesgos de Exploracion
│
├── Inicio
│   ├── Tarjeta: Riesgo promedio de la cartera
│   ├── Tarjeta: Zonas en riesgo alto
│   ├── Tarjeta: Revisiones pendientes
│   └── Accesos rapidos a las cuatro secciones
│
├── Analisis de Riesgos          → dashboard de SAC embebido
├── Mis Revisiones               → bandeja de tareas de BPA
├── Nueva Solicitud              → formulario de BPA
└── Modelo y Documentacion
    ├── Como se calcula el riesgo
    ├── Variables y ponderaciones
    └── Supuestos y limitaciones
```

---

## 2. Construccion

### Paso 1 — Crear el site

En **Site Manager → Site Directory → Create Site**.
Nombre: `GeoRisk`.

### Paso 2 — Integrar SAP Analytics Cloud

**Content Manager → Content Explorer → Add integration** hacia SAC, o bien un
**URL App** apuntando a la story publicada.

- Titulo: `Analisis de Riesgos`
- Modo: nueva pestana o embebido segun lo permita el trial

> Si el embebido de SAC falla por politicas de iframe/CSP, usar un **URL App
> que abra en pestana nueva**. Es completamente valido para la demo y evita
> perder tiempo en configuracion de cabeceras.

### Paso 3 — Integrar SAP Build Process Automation

BPA expone sus tareas mediante la aplicacion **My Inbox**. Anadirla como
aplicacion del site:

- `Mis Revisiones` → My Inbox (tareas pendientes del revisor)
- `Nueva Solicitud` → URL del formulario de inicio del proceso

### Paso 4 — Pagina de documentacion

Crear una pagina con contenido estatico (Content Package o Workspace) que
resuma el modelo. Fuente: `docs/02-modelo-scoring.md`.

**Por que incluirla:** el enunciado pide documentar el modelo, y tenerla dentro
de la experiencia demuestra que la solucion es auditable por el usuario final,
no solo por el equipo tecnico. Es un detalle barato con buen retorno ante el
jurado.

### Paso 5 — Roles

| Rol | Ve | Puede |
|---|---|---|
| **Analista** | Dashboard, Nueva Solicitud | Consultar y enviar a revision |
| **Especialista** | Dashboard, Mis Revisiones | Revisar y decidir |
| **Gerente** | Todo + trazabilidad | Aprobar zonas criticas |

Si el trial no permite configurar tres roles a tiempo, usar uno solo y
**explicar la segregacion prevista en la presentacion**. No bloquea nada.

---

## 3. Recorrido de la demo

El orden en que se navega Work Zone durante el video:

```
1. Inicio            → las tarjetas muestran el estado de la cartera
2. Analisis          → dashboard SAC: ranking, radar, explicabilidad
3. Nueva Solicitud   → se envia una zona critica a revision
4. Mis Revisiones    → la tarea aparece en la bandeja
5. (decidir)         → aprobar/observar con justificacion
6. Analisis          → la trazabilidad refleja la decision
```

Ese ciclo cerrado — del dato a la decision y de vuelta al dato — es lo que
demuestra que las cuatro capas estan realmente integradas.

---

## 4. Plan de contingencia

| Si falla | Alternativa |
|---|---|
| Embebido de SAC | URL App en pestana nueva |
| My Inbox no disponible | Enlace directo a la URL de tareas de BPA |
| No se logra crear el site | Presentar cada herramienta por separado y explicar la integracion prevista |

Work Zone es la capa mas prescindible tecnicamente pero la mas visible en la
demo: **construirla al final, cuando SAC y BPA ya funcionen**, y con un limite
de tiempo estricto.
