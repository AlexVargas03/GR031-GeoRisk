# 03 - Flujo de revision en SAP Build Process Automation

Especificacion para construir el proceso el dia del evento. Escrita como guia
de armado, no como descripcion: sigue los pasos en orden.

---

## 1. Que debe lograr el proceso

El entregable pide un flujo que permita **revisar, aprobar, observar o
registrar la decision** asociada a una zona, con trazabilidad.

```
Analista detecta zona de riesgo en SAC
        │
        ▼
[Formulario] Solicitud de revision
        │
        ▼
[Automatizacion] Congelar scoring  →  SP_GEORISK_CREAR_EVALUACION
        │
        ▼
[Condicion] ¿Nivel de riesgo?
        ├── CRITICO ──→ [Aprobacion] Gerente de Riesgos  (doble revision)
        │                      │
        └── otros ─────────────┤
                               ▼
                    [Tarea] Revision del especialista
                               │
                    Aprobar / Observar / Rechazar + justificacion
                               │
                               ▼
              [Automatizacion] SP_GEORISK_REGISTRAR_DECISION
                               │
                               ▼
                    [Notificacion] Resultado al solicitante
```

---

## 2. Construccion paso a paso

### Paso 1 — Crear el proyecto

En el Lobby de SAP Build Process Automation: **Create → Build an Automated
Process → Business Process**.

- Nombre: `GeoRisk Revision de Evaluacion`
- Identificador: `georisk_revision`

### Paso 2 — Formulario de solicitud (trigger)

Crear un **Form** llamado `Solicitud de Revision` con estos campos:

| Campo | Tipo | Obligatorio | Notas |
|---|---|---|---|
| `zonaId` | Text | Si | Ej. `Z001` |
| `nombreZona` | Text | No | Se muestra para confirmar |
| `motivoSolicitud` | Text (multilinea) | Si | Por que se pide revisar |
| `urgencia` | Dropdown | Si | Normal / Alta |
| `solicitante` | Text | Si | Correo del analista |

> Si el ambiente permite prellenar desde SAC, `zonaId` y `nombreZona` llegan
> como parametros de URL. Si no, el analista los escribe. **No bloquear la
> demo por esto.**

### Paso 3 — Obtener el scoring desde HANA

Aqui hay dos caminos segun lo que permita el trial. **Decidir en la Fase 0.**

**Opcion A — Destination HTTP a HANA (preferida).**
Crear en BTP un destination hacia el endpoint SQL/OData de HANA Cloud y
consumirlo con una accion de tipo API que invoque
`SP_GEORISK_CREAR_EVALUACION`.

**Opcion B — Datos en el proceso (plan B).**
Si la conexion no se logra a tiempo, el formulario incluye tambien los campos
`riesgoGlobal`, `riesgoGeologico`, `riesgoAmbiental`, `riesgoSocial` y
`nivelRiesgo`, que el analista copia desde SAC. El proceso funciona igual y la
demo se sostiene; se pierde solo la automatizacion de la lectura.

> **Recomendacion:** construir primero con la Opcion B para tener el flujo
> completo funcionando temprano, y migrar a la Opcion A si sobra tiempo. Un
> flujo simple que funciona vale mas que uno elegante a medio terminar.

### Paso 4 — Condicion por nivel de riesgo

Agregar un **Controller / Condition**:

```
Si  nivelRiesgo = "CRITICO"
    → rama de doble aprobacion (Gerente de Riesgos)
Si no
    → rama de revision estandar
```

Esto demuestra logica de negocio real, no un flujo lineal. Es un punto que el
jurado suele valorar.

### Paso 5 — Tarea de revision (Approval Form)

Crear un **Approval Form** llamado `Revision Tecnica de Zona`.

**Seccion informativa (solo lectura):**

- Zona, region, provincia
- Riesgo global y nivel, con el color correspondiente
- Los tres scores dimensionales
- Factor critico identificado
- Riesgo base y agravante (si aplica)

**Seccion de decision (editable):**

| Campo | Tipo | Obligatorio |
|---|---|---|
| `decision` | Dropdown: `APROBADO` / `OBSERVADO` / `RECHAZADO` | Si |
| `justificacion` | Text multilinea (min. 10 caracteres) | **Si** |
| `comentario` | Text multilinea | No |
| `accionesRequeridas` | Text multilinea | Solo si `OBSERVADO` |

> La justificacion obligatoria no es un detalle de forma: es el nucleo de la
> trazabilidad y el procedimiento en HANA la rechaza si viene vacia o con
> menos de 10 caracteres.

### Paso 6 — Persistir la decision

Accion que invoca `SP_GEORISK_REGISTRAR_DECISION` con:

```
IP_EVALUACION_ID  = id devuelto en el paso 3
IP_DECISION       = decision
IP_REVISOR        = usuario que completo la tarea
IP_COMENTARIO     = comentario
IP_JUSTIFICACION  = justificacion
```

El procedimiento valida que la evaluacion exista, que siga `PENDIENTE`, que la
decision sea uno de los tres valores admitidos y que haya justificacion. Si
algo falla devuelve `OP_MENSAJE` con el motivo — mostrarlo en el proceso.

### Paso 7 — Notificacion

Enviar correo al solicitante con la decision y la justificacion.

---

## 3. Contrato con HANA

### Crear evaluacion

```sql
CALL SP_GEORISK_CREAR_EVALUACION(
    IP_ZONA_ID      => 'Z001',
    IP_SOLICITANTE  => 'analista@georisk.pe',
    IP_PROCESO_INST => '<id de instancia BPA>',
    OP_EVALUACION_ID => ?,   -- devuelve 'EVAL000001'
    OP_MENSAJE       => ?
);
```

Comportamiento a tener en cuenta:
- Si la zona no existe → devuelve `NULL` y un mensaje explicativo.
- Si la zona ya tiene una revision `PENDIENTE` → **no crea otra**, devuelve la
  existente. Evita duplicados si el usuario envia dos veces.

### Registrar decision

```sql
CALL SP_GEORISK_REGISTRAR_DECISION(
    IP_EVALUACION_ID => 'EVAL000001',
    IP_DECISION      => 'OBSERVADO',
    IP_REVISOR       => 'especialista@georisk.pe',
    IP_COMENTARIO    => 'Requiere estudio hidrogeologico complementario',
    IP_JUSTIFICACION => 'El potencial de drenaje acido supera el umbral aceptable',
    OP_MENSAJE       => ?
);
```

### Consultar pendientes

```sql
SELECT * FROM V_GEORISK_PENDIENTES ORDER BY PRIORIDAD, DIAS_EN_ESPERA DESC;
```

Ya viene ordenable por `PRIORIDAD` (CRITICO primero) y trae `DIAS_EN_ESPERA`.

---

## 4. Estados

```
                  SP_CREAR_EVALUACION
                          │
                          ▼
                    ┌───────────┐
                    │ PENDIENTE │
                    └─────┬─────┘
                          │  SP_REGISTRAR_DECISION
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
     ┌──────────┐   ┌───────────┐   ┌────────────┐
     │ APROBADO │   │ OBSERVADO │   │ RECHAZADO  │
     └──────────┘   └───────────┘   └────────────┘
```

Los estados finales son inmutables: el procedimiento rechaza un segundo intento
de decision sobre una evaluacion ya cerrada. Si hace falta reevaluar, se crea
una evaluacion nueva y queda el historial de ambas.

---

## 5. Trazabilidad resultante

Cada evaluacion deja:

- **`GEORISK_EVALUACION`** — foto del scoring al enviar, decision, revisor,
  fechas y justificacion.
- **`GEORISK_EVAL_LOG`** — un registro por evento (`ENVIADA`, `APROBADA`,
  `OBSERVADA`, `RECHAZADA`), con usuario y timestamp.
- **`V_GEORISK_TRAZABILIDAD`** — compara el scoring congelado contra el
  vigente y marca si el modelo cambio desde la decision (`ALERTA_VIGENCIA`).

Esa ultima columna responde una pregunta que suele hacer el jurado: *"¿que pasa
si el modelo se recalibra despues de aprobar una zona?"* — el sistema lo
detecta y lo senala.

---

## 6. Prueba de humo

Antes de grabar la demo, verificar:

- [ ] El formulario dispara el proceso
- [ ] Se crea la evaluacion y devuelve un `EVALUACION_ID`
- [ ] La tarea aparece en la bandeja del revisor
- [ ] Enviar sin justificacion es rechazado
- [ ] Aprobar registra estado `APROBADO` en HANA
- [ ] `V_GEORISK_BITACORA` muestra los eventos en orden
- [ ] Una zona `CRITICO` toma la rama de doble aprobacion
- [ ] Enviar dos veces la misma zona no duplica la evaluacion

---

## 7. Riesgos de esta capa

| Riesgo | Mitigacion |
|---|---|
| La conexion BPA → HANA no se logra en el trial | Opcion B del paso 3: datos en el formulario |
| El destination requiere permisos no disponibles | Construir el flujo completo primero sin integracion |
| Se agota el tiempo | El flujo minimo viable es: formulario → tarea → decision. Las ramas condicionales y la notificacion son opcionales |
