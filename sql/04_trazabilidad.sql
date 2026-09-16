-- =====================================================================
-- GeoRisk :: 04 - Trazabilidad y procedimientos para SAP BPA
-- Plataforma: SAP HANA Cloud (SQLScript)
-- Requiere: 01_ddl_tablas.sql, 02_vistas_scoring.sql
-- =====================================================================
-- Contrato de integracion con SAP Build Process Automation:
--
--   1. El usuario envia una zona a revision desde SAC/Work Zone
--        -> BPA llama a SP_GEORISK_CREAR_EVALUACION
--        -> se congela una FOTO del scoring del momento
--   2. El especialista revisa y decide en la tarea de BPA
--        -> BPA llama a SP_GEORISK_REGISTRAR_DECISION
--   3. Toda accion queda registrada en GEORISK_EVAL_LOG
--
-- Por que se congela el scoring: si el modelo se recalibra despues, la
-- evaluacion revisada debe seguir mostrando los numeros sobre los que la
-- persona decidio. Sin esa foto, la trazabilidad no seria auditable.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Crear evaluacion y enviarla a revision
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_GEORISK_CREAR_EVALUACION (
    IN  IP_ZONA_ID        NVARCHAR(10),
    IN  IP_SOLICITANTE    NVARCHAR(120),
    IN  IP_PROCESO_INST   NVARCHAR(80),
    OUT OP_EVALUACION_ID  NVARCHAR(20),
    OUT OP_MENSAJE        NVARCHAR(200)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE LV_EXISTE      INTEGER;
    DECLARE LV_PENDIENTE   INTEGER;
    DECLARE LV_CORRELATIVO INTEGER;

    -- La zona debe existir en el scoring
    SELECT COUNT(*) INTO LV_EXISTE
    FROM   V_GEORISK_SCORING
    WHERE  ZONA_ID = :IP_ZONA_ID;

    IF :LV_EXISTE = 0 THEN
        OP_EVALUACION_ID := NULL;
        OP_MENSAJE := 'La zona ' || :IP_ZONA_ID || ' no existe o no tiene scoring calculado';
        RETURN;
    END IF;

    -- Evitar duplicados: una zona no puede tener dos revisiones abiertas
    SELECT COUNT(*) INTO LV_PENDIENTE
    FROM   GEORISK_EVALUACION
    WHERE  ZONA_ID = :IP_ZONA_ID
      AND  ESTADO  = 'PENDIENTE';

    IF :LV_PENDIENTE > 0 THEN
        SELECT EVALUACION_ID INTO OP_EVALUACION_ID
        FROM   GEORISK_EVALUACION
        WHERE  ZONA_ID = :IP_ZONA_ID AND ESTADO = 'PENDIENTE'
        LIMIT 1;
        OP_MENSAJE := 'La zona ya tiene una evaluacion pendiente de revision';
        RETURN;
    END IF;

    SELECT COALESCE(MAX(TO_INTEGER(SUBSTRING(EVALUACION_ID, 5))), 0) + 1
      INTO LV_CORRELATIVO
    FROM GEORISK_EVALUACION;

    OP_EVALUACION_ID := 'EVAL' || LPAD(TO_VARCHAR(:LV_CORRELATIVO), 6, '0');

    -- Foto del scoring vigente en este instante
    INSERT INTO GEORISK_EVALUACION (
        EVALUACION_ID, ZONA_ID, FECHA_EVALUACION,
        RIESGO_GLOBAL, RIESGO_GEOLOGICO, RIESGO_AMBIENTAL, RIESGO_SOCIAL,
        NIVEL_RIESGO, FACTOR_CRITICO,
        ESTADO, SOLICITANTE, PROCESO_INSTANCIA
    )
    SELECT
        :OP_EVALUACION_ID, ZONA_ID, CURRENT_TIMESTAMP,
        RIESGO_GLOBAL, RIESGO_GEOLOGICO, RIESGO_AMBIENTAL, RIESGO_SOCIAL,
        NIVEL_RIESGO, FACTOR_CRITICO,
        'PENDIENTE', :IP_SOLICITANTE, :IP_PROCESO_INST
    FROM V_GEORISK_SCORING
    WHERE ZONA_ID = :IP_ZONA_ID;

    INSERT INTO GEORISK_EVAL_LOG (EVALUACION_ID, FECHA_EVENTO, EVENTO, USUARIO, DETALLE)
    VALUES (:OP_EVALUACION_ID, CURRENT_TIMESTAMP, 'ENVIADA', :IP_SOLICITANTE,
            'Evaluacion de la zona ' || :IP_ZONA_ID || ' enviada a revision');

    OP_MENSAJE := 'Evaluacion ' || :OP_EVALUACION_ID || ' creada y enviada a revision';
END;


-- ---------------------------------------------------------------------
-- 2. Registrar la decision del especialista
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_GEORISK_REGISTRAR_DECISION (
    IN  IP_EVALUACION_ID  NVARCHAR(20),
    IN  IP_DECISION       NVARCHAR(20),    -- APROBADO | OBSERVADO | RECHAZADO
    IN  IP_REVISOR        NVARCHAR(120),
    IN  IP_COMENTARIO     NVARCHAR(1000),
    IN  IP_JUSTIFICACION  NVARCHAR(2000),
    OUT OP_MENSAJE        NVARCHAR(200)
)
LANGUAGE SQLSCRIPT
AS
BEGIN
    DECLARE LV_ESTADO NVARCHAR(20);

    SELECT MAX(ESTADO) INTO LV_ESTADO
    FROM   GEORISK_EVALUACION
    WHERE  EVALUACION_ID = :IP_EVALUACION_ID;

    IF :LV_ESTADO IS NULL THEN
        OP_MENSAJE := 'No existe la evaluacion ' || :IP_EVALUACION_ID;
        RETURN;
    END IF;

    IF :LV_ESTADO <> 'PENDIENTE' THEN
        OP_MENSAJE := 'La evaluacion ya fue cerrada con estado ' || :LV_ESTADO;
        RETURN;
    END IF;

    IF :IP_DECISION NOT IN ('APROBADO', 'OBSERVADO', 'RECHAZADO') THEN
        OP_MENSAJE := 'Decision invalida: ' || :IP_DECISION;
        RETURN;
    END IF;

    -- La justificacion es obligatoria: es el nucleo de la trazabilidad
    IF :IP_JUSTIFICACION IS NULL OR LENGTH(TRIM(:IP_JUSTIFICACION)) < 10 THEN
        OP_MENSAJE := 'La justificacion es obligatoria (minimo 10 caracteres)';
        RETURN;
    END IF;

    UPDATE GEORISK_EVALUACION
    SET    ESTADO              = :IP_DECISION,
           REVISOR             = :IP_REVISOR,
           FECHA_DECISION      = CURRENT_TIMESTAMP,
           DECISION_COMENTARIO = :IP_COMENTARIO,
           JUSTIFICACION       = :IP_JUSTIFICACION
    WHERE  EVALUACION_ID = :IP_EVALUACION_ID;

    INSERT INTO GEORISK_EVAL_LOG (EVALUACION_ID, FECHA_EVENTO, EVENTO, USUARIO, DETALLE)
    VALUES (:IP_EVALUACION_ID, CURRENT_TIMESTAMP, :IP_DECISION, :IP_REVISOR,
            :IP_JUSTIFICACION);

    OP_MENSAJE := 'Evaluacion ' || :IP_EVALUACION_ID || ' registrada como ' || :IP_DECISION;
END;


-- ---------------------------------------------------------------------
-- 3. Bandeja de tareas pendientes (la consume BPA / Work Zone)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_PENDIENTES AS
SELECT
    e.EVALUACION_ID,
    e.ZONA_ID,
    s.NOMBRE_ZONA,
    s.REGION,
    s.PROVINCIA,
    e.FECHA_EVALUACION,
    e.RIESGO_GLOBAL,
    e.RIESGO_GEOLOGICO,
    e.RIESGO_AMBIENTAL,
    e.RIESGO_SOCIAL,
    e.NIVEL_RIESGO,
    e.FACTOR_CRITICO,
    e.SOLICITANTE,
    e.PROCESO_INSTANCIA,
    DAYS_BETWEEN(e.FECHA_EVALUACION, CURRENT_TIMESTAMP)          AS DIAS_EN_ESPERA,
    -- Prioridad de atencion: el riesgo critico se atiende primero
    CASE e.NIVEL_RIESGO
         WHEN 'CRITICO'  THEN 1
         WHEN 'ALTO'     THEN 2
         WHEN 'MODERADO' THEN 3
         ELSE 4 END                                              AS PRIORIDAD
FROM       GEORISK_EVALUACION e
INNER JOIN V_GEORISK_SCORING  s ON s.ZONA_ID = e.ZONA_ID
WHERE      e.ESTADO = 'PENDIENTE';


-- ---------------------------------------------------------------------
-- 4. Historial completo de decisiones
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_TRAZABILIDAD AS
SELECT
    e.EVALUACION_ID,
    e.ZONA_ID,
    s.NOMBRE_ZONA,
    s.REGION,
    e.FECHA_EVALUACION,
    e.ESTADO,
    e.SOLICITANTE,
    e.REVISOR,
    e.FECHA_DECISION,
    e.DECISION_COMENTARIO,
    e.JUSTIFICACION,
    -- Scoring congelado al momento del envio
    e.RIESGO_GLOBAL                                              AS RIESGO_AL_EVALUAR,
    e.NIVEL_RIESGO                                               AS NIVEL_AL_EVALUAR,
    e.FACTOR_CRITICO,
    -- Scoring vigente hoy
    s.RIESGO_GLOBAL                                              AS RIESGO_ACTUAL,
    s.NIVEL_RIESGO                                               AS NIVEL_ACTUAL,
    -- Alerta de desviacion: el modelo cambio desde que se decidio
    CAST(s.RIESGO_GLOBAL - e.RIESGO_GLOBAL AS DECIMAL(5,2))      AS DELTA_RIESGO,
    CASE WHEN ABS(s.RIESGO_GLOBAL - e.RIESGO_GLOBAL) > 5
         THEN 'Revisar: el scoring cambio desde la decision'
         ELSE 'Sin cambios relevantes' END                       AS ALERTA_VIGENCIA,
    CASE WHEN e.FECHA_DECISION IS NOT NULL
         THEN DAYS_BETWEEN(e.FECHA_EVALUACION, e.FECHA_DECISION)
         ELSE DAYS_BETWEEN(e.FECHA_EVALUACION, CURRENT_TIMESTAMP)
    END                                                          AS DIAS_CICLO
FROM       GEORISK_EVALUACION e
INNER JOIN V_GEORISK_SCORING  s ON s.ZONA_ID = e.ZONA_ID;


-- ---------------------------------------------------------------------
-- 5. Bitacora detallada por evaluacion
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_BITACORA AS
SELECT
    l.LOG_ID,
    l.EVALUACION_ID,
    e.ZONA_ID,
    s.NOMBRE_ZONA,
    l.FECHA_EVENTO,
    l.EVENTO,
    l.USUARIO,
    l.DETALLE,
    ROW_NUMBER() OVER (PARTITION BY l.EVALUACION_ID ORDER BY l.FECHA_EVENTO) AS PASO
FROM       GEORISK_EVAL_LOG   l
INNER JOIN GEORISK_EVALUACION e ON e.EVALUACION_ID = l.EVALUACION_ID
INNER JOIN V_GEORISK_SCORING  s ON s.ZONA_ID       = e.ZONA_ID;


-- ---------------------------------------------------------------------
-- 6. KPIs del proceso de revision
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_KPI_PROCESO AS
SELECT
    COUNT(*)                                                            AS TOTAL_EVALUACIONES,
    SUM(CASE WHEN ESTADO = 'PENDIENTE' THEN 1 ELSE 0 END)               AS PENDIENTES,
    SUM(CASE WHEN ESTADO = 'APROBADO'  THEN 1 ELSE 0 END)               AS APROBADAS,
    SUM(CASE WHEN ESTADO = 'OBSERVADO' THEN 1 ELSE 0 END)               AS OBSERVADAS,
    SUM(CASE WHEN ESTADO = 'RECHAZADO' THEN 1 ELSE 0 END)               AS RECHAZADAS,
    CAST(AVG(CASE WHEN FECHA_DECISION IS NOT NULL
                  THEN DAYS_BETWEEN(FECHA_EVALUACION, FECHA_DECISION) END)
         AS DECIMAL(6,2))                                               AS DIAS_CICLO_PROMEDIO,
    CAST(100.0 * SUM(CASE WHEN ESTADO = 'APROBADO' THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN ESTADO <> 'PENDIENTE' THEN 1 ELSE 0 END), 0)
         AS DECIMAL(5,2))                                               AS PCT_APROBACION
FROM GEORISK_EVALUACION;


-- =====================================================================
-- Ejemplo de uso (descomentar para probar tras cargar datos)
-- =====================================================================
-- DO BEGIN
--     DECLARE LV_ID  NVARCHAR(20);
--     DECLARE LV_MSG NVARCHAR(200);
--     CALL SP_GEORISK_CREAR_EVALUACION('Z001', 'analista@georisk.pe', 'BPA-0001', LV_ID, LV_MSG);
--     SELECT :LV_ID AS EVALUACION_ID, :LV_MSG AS MENSAJE FROM DUMMY;
--     CALL SP_GEORISK_REGISTRAR_DECISION(:LV_ID, 'OBSERVADO', 'especialista@georisk.pe',
--          'Requiere estudio hidrogeologico complementario',
--          'El potencial de drenaje acido supera el umbral aceptable para la fase actual',
--          LV_MSG);
--     SELECT :LV_MSG AS MENSAJE FROM DUMMY;
-- END;
