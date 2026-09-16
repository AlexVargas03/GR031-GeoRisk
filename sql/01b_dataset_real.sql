-- =====================================================================
-- GeoRisk :: 01b - Adaptacion al dataset real del evento (GR031)
-- Plataforma: SAP HANA Cloud / SAP Datasphere
-- Requiere: 01_ddl_tablas.sql ya ejecutado (tablas GEORISK_PARAM_*)
-- Orden de ejecucion: 01 -> 01b -> 02 -> 03 -> 04
-- =====================================================================
-- CONTEXTO (confirmado por "Ambiente y Consideraciones - Hackathon SAP
-- Mineria Peru 2026"): dataset_tema2_georisk.csv es, por diseno del
-- reto, "un registro por evaluacion mensual de riesgo de una zona" -- no
-- una tabla estatica de 40 zonas como se asumio en 01_ddl_tablas.sql.
-- Son 11458 filas / 140 zonas, con columnas que no coinciden 1 a 1 con
-- las 26 variables del modelo de scoring.
--
-- El documento recomienda separar "los atributos de zona en una tabla de
-- dimension propia y dejar el resto como tabla de hechos". Este script:
--   1. Importa el CSV tal cual a una tabla STAGING (GEORISK_ZONAS_RAW).
--   2. La reparte en GEORISK_ZONAS_DIM (1 fila x zona, atributos fijos)
--      y GEORISK_EVALUACIONES_FACT (1 fila x evaluacion mensual).
--   3. V_GEORISK_ZONAS_ULTIMA arma la foto vigente por zona (ultima
--      evaluacion) uniendo dimension + hechos.
--   4. V_GEORISK_ZONAS_BASE traduce/renombra al vocabulario que espera
--      02_vistas_scoring.sql (sin tocar ese archivo). Donde no hay dato
--      equivalente, se entrega el punto medio de [MIN_REF, MAX_REF] de
--      esa variable, que normaliza exactamente a 50/100 -- neutro.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Staging: estructura identica al CSV del evento
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_ZONAS_RAW (
    EVALUACION_ID                   NVARCHAR(20),
    ZONA_ID                         NVARCHAR(10)  NOT NULL,
    ZONA_NOMBRE                     NVARCHAR(80),
    REGION                          NVARCHAR(40),
    PROVINCIA                       NVARCHAR(60),
    DISTRITO                        NVARCHAR(80),
    LATITUD                         DECIMAL(9,5),
    LONGITUD                        DECIMAL(9,5),
    ALTITUD_MSNM                    INTEGER,
    SUPERFICIE_HA                   DECIMAL(10,2),
    TIPO_YACIMIENTO                 NVARCHAR(40),
    MINERAL_PRINCIPAL               NVARCHAR(30),
    CONCESION_ID                    NVARCHAR(20),
    ESTADO_CONCESION                NVARCHAR(20),
    EMPRESA_OPERADORA                NVARCHAR(80),
    ACCESIBILIDAD_SCORE             DECIMAL(6,2),
    DISPONIBILIDAD_AGUA_SCORE       DECIMAL(6,2),
    DISTANCIA_VIA_PRINCIPAL_KM      DECIMAL(7,2),
    DISTANCIA_PLANTA_KM             DECIMAL(7,2),
    FASE_EXPLORACION                NVARCHAR(40),
    ANIO                            INTEGER,
    TRIMESTRE                       NVARCHAR(4),
    MES                             NVARCHAR(7),
    FECHA_EVALUACION                DATE,
    EVALUADOR                       NVARCHAR(60),
    METODO_EVALUACION               NVARCHAR(60),
    SISMICIDAD_INDICE               DECIMAL(6,2),
    DISTANCIA_FALLA_GEOLOGICA_KM    DECIMAL(7,2),
    ESTABILIDAD_TALUD_SCORE         DECIMAL(6,2),
    PENDIENTE_PROMEDIO_PCT          DECIMAL(6,2),
    NIVEL_FREATICO_M                DECIMAL(7,2),
    CAUDAL_INFILTRACION_LPS         DECIMAL(9,2),
    POTENCIAL_DRENAJE_ACIDO_PH      DECIMAL(5,2),
    EVENTOS_GEOLOGICOS_12M          INTEGER,
    DISTANCIA_AREA_PROTEGIDA_KM     DECIMAL(7,2),
    DISTANCIA_CUERPO_AGUA_KM        DECIMAL(7,2),
    INDICE_ESTRES_HIDRICO           DECIMAL(6,3),
    COBERTURA_VEGETAL_PCT           DECIMAL(6,2),
    CALIDAD_AIRE_PM10_UGM3          DECIMAL(7,2),
    PASIVOS_AMBIENTALES_NUM         INTEGER,
    ESPECIES_SENSIBLES_NUM          INTEGER,
    CONSUMO_AGUA_M3_MES             DECIMAL(12,2),
    HUELLA_CARBONO_TCO2E_MES        DECIMAL(12,2),
    COMUNIDADES_INFLUENCIA_NUM      INTEGER,
    POBLACION_INFLUENCIA            INTEGER,
    DISTANCIA_COMUNIDAD_KM          DECIMAL(7,2),
    CONFLICTOS_REGISTRADOS_12M      INTEGER,
    DIAS_PARALIZACION_12M           INTEGER,
    INDICE_ACEPTACION_SOCIAL        DECIMAL(6,3),
    CONVENIOS_VIGENTES_NUM          INTEGER,
    EMPLEO_LOCAL_PCT                DECIMAL(6,2),
    IDH_DISTRITAL                   DECIMAL(5,3),
    POBREZA_DISTRITAL_PCT           DECIMAL(6,2),
    QUEJAS_REGISTRADAS_12M          INTEGER,
    COSTO_MITIGACION_EJECUTADO_USD  DECIMAL(14,2),
    ACCIONES_MITIGACION_NUM         INTEGER,
    ESTADO_REVISION                 NVARCHAR(20),
    REVISOR_ASIGNADO                NVARCHAR(60),
    DECISION_ESPECIALISTA           NVARCHAR(60),
    FECHA_DECISION                  DATE,
    COMENTARIO_REVISION             NVARCHAR(500),
    MONEDA                          NVARCHAR(5)
);

COMMENT ON TABLE GEORISK_ZONAS_RAW IS 'STAGING: destino de la importacion de dataset_tema2_georisk.csv, tal cual. Se reparte en GEORISK_ZONAS_DIM y GEORISK_EVALUACIONES_FACT.';

-- ---------------------------------------------------------------------
-- Carga de datos: usar el wizard "Import Data" del HANA Database Explorer
-- (clic derecho sobre GEORISK_ZONAS_RAW en el arbol -> Import Data ->
-- seleccionar dataset_tema2_georisk.csv, header en la fila 1, delimitador
-- coma, codificacion UTF-8). No se genera INSERT manual por las 11458 filas.
-- EJECUTAR LA IMPORTACION AHORA, antes de continuar con la seccion 2.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- 2. Tabla de dimension: atributos fijos de zona (1 fila por ZONA_ID)
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_ZONAS_DIM (
    ZONA_ID             NVARCHAR(10)  PRIMARY KEY,
    ZONA_NOMBRE         NVARCHAR(80)  NOT NULL,
    REGION              NVARCHAR(40),
    PROVINCIA           NVARCHAR(60),
    DISTRITO            NVARCHAR(80),
    LATITUD             DECIMAL(9,5),
    LONGITUD            DECIMAL(9,5),
    ALTITUD_MSNM        INTEGER,
    SUPERFICIE_HA       DECIMAL(10,2),
    TIPO_YACIMIENTO     NVARCHAR(40),
    MINERAL_PRINCIPAL   NVARCHAR(30),
    CONCESION_ID        NVARCHAR(20),
    EMPRESA_OPERADORA   NVARCHAR(80)
);

COMMENT ON TABLE GEORISK_ZONAS_DIM IS 'Dimension: atributos de zona que no cambian entre evaluaciones';

-- MAX(...) por columna colapsa a un valor unico por ZONA_ID incluso si el
-- staging trajera alguna inconsistencia entre filas de la misma zona.
INSERT INTO GEORISK_ZONAS_DIM
SELECT
    ZONA_ID,
    MAX(ZONA_NOMBRE),
    MAX(REGION),
    MAX(PROVINCIA),
    MAX(DISTRITO),
    MAX(LATITUD),
    MAX(LONGITUD),
    MAX(ALTITUD_MSNM),
    MAX(SUPERFICIE_HA),
    MAX(TIPO_YACIMIENTO),
    MAX(MINERAL_PRINCIPAL),
    MAX(CONCESION_ID),
    MAX(EMPRESA_OPERADORA)
FROM GEORISK_ZONAS_RAW
GROUP BY ZONA_ID;


-- ---------------------------------------------------------------------
-- 3. Tabla de hechos: una fila por evaluacion mensual
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_EVALUACIONES_FACT (
    EVALUACION_ID                   NVARCHAR(20)  PRIMARY KEY,
    ZONA_ID                         NVARCHAR(10)  NOT NULL,
    FECHA_EVALUACION                DATE          NOT NULL,
    ANIO                            INTEGER,
    TRIMESTRE                       NVARCHAR(4),
    MES                             NVARCHAR(7),
    EVALUADOR                       NVARCHAR(60),
    METODO_EVALUACION               NVARCHAR(60),
    ESTADO_CONCESION                NVARCHAR(20),
    FASE_EXPLORACION                NVARCHAR(40),
    ACCESIBILIDAD_SCORE             DECIMAL(6,2),
    DISPONIBILIDAD_AGUA_SCORE       DECIMAL(6,2),
    DISTANCIA_VIA_PRINCIPAL_KM      DECIMAL(7,2),
    DISTANCIA_PLANTA_KM             DECIMAL(7,2),
    SISMICIDAD_INDICE               DECIMAL(6,2),
    DISTANCIA_FALLA_GEOLOGICA_KM    DECIMAL(7,2),
    ESTABILIDAD_TALUD_SCORE         DECIMAL(6,2),
    PENDIENTE_PROMEDIO_PCT          DECIMAL(6,2),
    NIVEL_FREATICO_M                DECIMAL(7,2),
    CAUDAL_INFILTRACION_LPS         DECIMAL(9,2),
    POTENCIAL_DRENAJE_ACIDO_PH      DECIMAL(5,2),
    EVENTOS_GEOLOGICOS_12M          INTEGER,
    DISTANCIA_AREA_PROTEGIDA_KM     DECIMAL(7,2),
    DISTANCIA_CUERPO_AGUA_KM        DECIMAL(7,2),
    INDICE_ESTRES_HIDRICO           DECIMAL(6,3),
    COBERTURA_VEGETAL_PCT           DECIMAL(6,2),
    CALIDAD_AIRE_PM10_UGM3          DECIMAL(7,2),
    PASIVOS_AMBIENTALES_NUM         INTEGER,
    ESPECIES_SENSIBLES_NUM          INTEGER,
    CONSUMO_AGUA_M3_MES             DECIMAL(12,2),
    HUELLA_CARBONO_TCO2E_MES        DECIMAL(12,2),
    COMUNIDADES_INFLUENCIA_NUM      INTEGER,
    POBLACION_INFLUENCIA            INTEGER,
    DISTANCIA_COMUNIDAD_KM          DECIMAL(7,2),
    CONFLICTOS_REGISTRADOS_12M      INTEGER,
    DIAS_PARALIZACION_12M           INTEGER,
    INDICE_ACEPTACION_SOCIAL        DECIMAL(6,3),
    CONVENIOS_VIGENTES_NUM          INTEGER,
    EMPLEO_LOCAL_PCT                DECIMAL(6,2),
    IDH_DISTRITAL                   DECIMAL(5,3),
    POBREZA_DISTRITAL_PCT           DECIMAL(6,2),
    QUEJAS_REGISTRADAS_12M          INTEGER,
    COSTO_MITIGACION_EJECUTADO_USD  DECIMAL(14,2),
    ACCIONES_MITIGACION_NUM         INTEGER,
    ESTADO_REVISION                 NVARCHAR(20),
    REVISOR_ASIGNADO                NVARCHAR(60),
    DECISION_ESPECIALISTA           NVARCHAR(60),
    FECHA_DECISION                  DATE,
    COMENTARIO_REVISION             NVARCHAR(500),
    MONEDA                          NVARCHAR(5)
);

COMMENT ON TABLE GEORISK_EVALUACIONES_FACT IS 'Hechos: una evaluacion de riesgo mensual por zona (historial completo, 11458 filas esperadas)';

CREATE INDEX IDX_FACT_ZONA  ON GEORISK_EVALUACIONES_FACT (ZONA_ID);
CREATE INDEX IDX_FACT_FECHA ON GEORISK_EVALUACIONES_FACT (FECHA_EVALUACION);

INSERT INTO GEORISK_EVALUACIONES_FACT
SELECT
    EVALUACION_ID, ZONA_ID, FECHA_EVALUACION, ANIO, TRIMESTRE, MES,
    EVALUADOR, METODO_EVALUACION, ESTADO_CONCESION, FASE_EXPLORACION,
    ACCESIBILIDAD_SCORE, DISPONIBILIDAD_AGUA_SCORE, DISTANCIA_VIA_PRINCIPAL_KM,
    DISTANCIA_PLANTA_KM, SISMICIDAD_INDICE, DISTANCIA_FALLA_GEOLOGICA_KM,
    ESTABILIDAD_TALUD_SCORE, PENDIENTE_PROMEDIO_PCT, NIVEL_FREATICO_M,
    CAUDAL_INFILTRACION_LPS, POTENCIAL_DRENAJE_ACIDO_PH, EVENTOS_GEOLOGICOS_12M,
    DISTANCIA_AREA_PROTEGIDA_KM, DISTANCIA_CUERPO_AGUA_KM, INDICE_ESTRES_HIDRICO,
    COBERTURA_VEGETAL_PCT, CALIDAD_AIRE_PM10_UGM3, PASIVOS_AMBIENTALES_NUM,
    ESPECIES_SENSIBLES_NUM, CONSUMO_AGUA_M3_MES, HUELLA_CARBONO_TCO2E_MES,
    COMUNIDADES_INFLUENCIA_NUM, POBLACION_INFLUENCIA, DISTANCIA_COMUNIDAD_KM,
    CONFLICTOS_REGISTRADOS_12M, DIAS_PARALIZACION_12M, INDICE_ACEPTACION_SOCIAL,
    CONVENIOS_VIGENTES_NUM, EMPLEO_LOCAL_PCT, IDH_DISTRITAL, POBREZA_DISTRITAL_PCT,
    QUEJAS_REGISTRADAS_12M, COSTO_MITIGACION_EJECUTADO_USD, ACCIONES_MITIGACION_NUM,
    ESTADO_REVISION, REVISOR_ASIGNADO, DECISION_ESPECIALISTA, FECHA_DECISION,
    COMENTARIO_REVISION, MONEDA
FROM GEORISK_ZONAS_RAW;


-- ---------------------------------------------------------------------
-- 4. Recalibracion de variables con proxy (unidad/sentido distintos al
--    diseno original)
-- ---------------------------------------------------------------------
-- DENSIDAD_FALLAS_KM2 (originalmente densidad, 'D') se reemplaza por
-- DISTANCIA_FALLA_GEOLOGICA_KM (distancia, sentido inverso: mas lejos de
-- una falla = menos riesgo). Rango real observado: 0.2 - 48.0 km.
UPDATE GEORISK_PARAM_VARIABLE
   SET VARIABLE_DESC = 'Distancia a falla geologica (proxy de densidad de fallas)',
       UNIDAD        = 'km',
       MIN_REF       = 0.0,
       MAX_REF       = 50.0,
       SENTIDO       = 'I'
 WHERE VARIABLE_COD = 'DENSIDAD_FALLAS_KM2';

-- POTENCIAL_DAM_NPAP (ratio NP/AP, 'I') se reemplaza por
-- POTENCIAL_DRENAJE_ACIDO_PH (pH; mas bajo = mas acido = mas riesgo, por lo
-- tanto sentido inverso: mayor pH -> menor riesgo). Rango real: 3.1 - 8.4.
UPDATE GEORISK_PARAM_VARIABLE
   SET VARIABLE_DESC = 'pH de drenaje acido (proxy de NP/AP)',
       UNIDAD        = 'pH',
       MIN_REF       = 3.0,
       MAX_REF       = 9.0,
       SENTIDO       = 'I'
 WHERE VARIABLE_COD = 'POTENCIAL_DAM_NPAP';

-- INDICE_BIODIVERSIDAD ('D': mas biodiversidad = zona mas sensible = mas
-- riesgo) se reemplaza por COBERTURA_VEGETAL_PCT, misma direccion. Rango
-- real: 2.0 - 78.0 %.
UPDATE GEORISK_PARAM_VARIABLE
   SET VARIABLE_DESC = 'Cobertura vegetal (proxy de biodiversidad)',
       UNIDAD        = '%',
       MIN_REF       = 0.0,
       MAX_REF       = 80.0,
       SENTIDO       = 'D'
 WHERE VARIABLE_COD = 'INDICE_BIODIVERSIDAD';

-- SISMICIDAD_PGA_G (g, 0.10-0.60) se reemplaza por SISMICIDAD_INDICE
-- (escala 1-9, mismo sentido: mas indice = mas riesgo).
UPDATE GEORISK_PARAM_VARIABLE
   SET VARIABLE_DESC = 'Indice de sismicidad (proxy de PGA)',
       UNIDAD        = '1-9',
       MIN_REF       = 1.0,
       MAX_REF       = 9.0,
       SENTIDO       = 'D'
 WHERE VARIABLE_COD = 'SISMICIDAD_PGA_G';

-- INDICE_ESTABILIDAD_TALUD (0-10, 'I') se reemplaza por
-- ESTABILIDAD_TALUD_SCORE (escala real observada 1-5, mismo sentido).
UPDATE GEORISK_PARAM_VARIABLE
   SET VARIABLE_DESC = 'Score de estabilidad de talud (escala real 1-5)',
       UNIDAD        = '1-5',
       MIN_REF       = 1.0,
       MAX_REF       = 5.0,
       SENTIDO       = 'I'
 WHERE VARIABLE_COD = 'INDICE_ESTABILIDAD_TALUD';


-- ---------------------------------------------------------------------
-- 5. Catalogo de categoricas: valores reales del dataset
-- ---------------------------------------------------------------------
-- ESTADO_LICENCIA_SCORE ahora se alimenta de ESTADO_CONCESION, cuyos
-- valores reales son 'Vigente' | 'En tramite' | 'Por renovar' (no existen
-- 'Observada' ni 'Sin licencia' en el dataset real; se mantienen por si
-- aparecen en datos futuros).
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('ESTADO_LICENCIA', 'Por renovar', 60.0);

-- CONSULTA_PREVIA_ESTADO no existe en el dataset real: se usa un valor
-- centinela 'NEUTRO' que traduce a score 50 (neutro, no penaliza ni premia).
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('CONSULTA_PREVIA_ESTADO', 'NEUTRO', 50.0);


-- ---------------------------------------------------------------------
-- 6. Foto vigente por zona: ultima evaluacion segun FECHA_EVALUACION,
--    dimension + hechos ya unidos
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_ZONAS_ULTIMA AS
SELECT
    d.ZONA_ID, d.ZONA_NOMBRE, d.REGION, d.PROVINCIA, d.DISTRITO, d.LATITUD,
    d.LONGITUD, d.ALTITUD_MSNM, d.SUPERFICIE_HA, d.TIPO_YACIMIENTO,
    d.MINERAL_PRINCIPAL, d.CONCESION_ID, d.EMPRESA_OPERADORA,
    f.EVALUACION_ID, f.FECHA_EVALUACION, f.ANIO, f.TRIMESTRE, f.MES,
    f.EVALUADOR, f.METODO_EVALUACION, f.ESTADO_CONCESION, f.FASE_EXPLORACION,
    f.ACCESIBILIDAD_SCORE, f.DISPONIBILIDAD_AGUA_SCORE, f.DISTANCIA_VIA_PRINCIPAL_KM,
    f.DISTANCIA_PLANTA_KM, f.SISMICIDAD_INDICE, f.DISTANCIA_FALLA_GEOLOGICA_KM,
    f.ESTABILIDAD_TALUD_SCORE, f.PENDIENTE_PROMEDIO_PCT, f.NIVEL_FREATICO_M,
    f.CAUDAL_INFILTRACION_LPS, f.POTENCIAL_DRENAJE_ACIDO_PH, f.EVENTOS_GEOLOGICOS_12M,
    f.DISTANCIA_AREA_PROTEGIDA_KM, f.DISTANCIA_CUERPO_AGUA_KM, f.INDICE_ESTRES_HIDRICO,
    f.COBERTURA_VEGETAL_PCT, f.CALIDAD_AIRE_PM10_UGM3, f.PASIVOS_AMBIENTALES_NUM,
    f.ESPECIES_SENSIBLES_NUM, f.CONSUMO_AGUA_M3_MES, f.HUELLA_CARBONO_TCO2E_MES,
    f.COMUNIDADES_INFLUENCIA_NUM, f.POBLACION_INFLUENCIA, f.DISTANCIA_COMUNIDAD_KM,
    f.CONFLICTOS_REGISTRADOS_12M, f.DIAS_PARALIZACION_12M, f.INDICE_ACEPTACION_SOCIAL,
    f.CONVENIOS_VIGENTES_NUM, f.EMPLEO_LOCAL_PCT, f.IDH_DISTRITAL, f.POBREZA_DISTRITAL_PCT,
    f.QUEJAS_REGISTRADAS_12M, f.COSTO_MITIGACION_EJECUTADO_USD, f.ACCIONES_MITIGACION_NUM,
    f.ESTADO_REVISION, f.REVISOR_ASIGNADO, f.DECISION_ESPECIALISTA, f.FECHA_DECISION,
    f.COMENTARIO_REVISION, f.MONEDA
FROM GEORISK_ZONAS_DIM d
INNER JOIN (
    SELECT *
    FROM (
        SELECT
            e.*,
            ROW_NUMBER() OVER (
                PARTITION BY e.ZONA_ID
                ORDER BY e.FECHA_EVALUACION DESC, e.EVALUACION_ID DESC
            ) AS RN
        FROM GEORISK_EVALUACIONES_FACT e
    )
    WHERE RN = 1
) f ON f.ZONA_ID = d.ZONA_ID;


-- ---------------------------------------------------------------------
-- 7. Punto unico de adaptacion: reemplaza la definicion de
--    V_GEORISK_ZONAS_BASE creada en 01_ddl_tablas.sql
-- ---------------------------------------------------------------------
-- Variables sin ninguna columna equivalente en el dataset real (9):
-- LEY_MINERAL_PCT, PROFUNDIDAD_DEPOSITO_M, TONELAJE_ESTIMADO_MT,
-- PERMEABILIDAD_MD, CALIDAD_AGUA_ICA, COBERTURA_GLACIAR_PCT,
-- PRECIPITACION_ANUAL_MM, PERMISOS_PENDIENTES_N, CONSULTA_PREVIA_ESTADO.
-- Se entrega el punto medio de [MIN_REF, MAX_REF] de GEORISK_PARAM_VARIABLE:
-- normaliza exactamente a 50/100 sin tocar 02_vistas_scoring.sql.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_ZONAS_BASE AS
SELECT
    u.ZONA_ID,
    u.ZONA_NOMBRE                    AS NOMBRE_ZONA,
    u.REGION,
    u.PROVINCIA,
    u.DISTRITO,
    u.MINERAL_PRINCIPAL,
    u.FASE_EXPLORACION               AS FASE_PROYECTO,
    u.LATITUD,
    u.LONGITUD,
    u.ALTITUD_MSNM,
    CAST(u.SUPERFICIE_HA AS INTEGER) AS SUPERFICIE_HA,

    -- Geologicas
    u.DISTANCIA_FALLA_GEOLOGICA_KM   AS DENSIDAD_FALLAS_KM2,      -- proxy, ver seccion 4
    u.ESTABILIDAD_TALUD_SCORE        AS INDICE_ESTABILIDAD_TALUD, -- proxy, ver seccion 4
    u.SISMICIDAD_INDICE              AS SISMICIDAD_PGA_G,         -- proxy, ver seccion 4
    CAST(1.10   AS DECIMAL(12,4))    AS LEY_MINERAL_PCT,          -- sin dato: neutro
    CAST(425.0  AS DECIMAL(12,4))    AS PROFUNDIDAD_DEPOSITO_M,   -- sin dato: neutro
    CAST(505.0  AS DECIMAL(12,4))    AS TONELAJE_ESTIMADO_MT,     -- sin dato: neutro
    CAST(250.05 AS DECIMAL(12,4))    AS PERMEABILIDAD_MD,         -- sin dato: neutro
    u.POTENCIAL_DRENAJE_ACIDO_PH     AS POTENCIAL_DAM_NPAP,       -- proxy, ver seccion 4

    -- Ambientales
    u.DISTANCIA_CUERPO_AGUA_KM       AS DIST_FUENTE_AGUA_KM,
    CAST(50.0   AS DECIMAL(12,4))    AS CALIDAD_AGUA_ICA,         -- sin dato: neutro
    u.INDICE_ESTRES_HIDRICO          AS ESTRES_HIDRICO_IDX,
    u.DISTANCIA_AREA_PROTEGIDA_KM    AS DIST_AREA_PROTEGIDA_KM,
    u.COBERTURA_VEGETAL_PCT          AS INDICE_BIODIVERSIDAD,     -- proxy, ver seccion 4
    CAST(u.ESPECIES_SENSIBLES_NUM AS INTEGER)  AS ESPECIES_AMENAZADAS_N,
    CAST(u.PASIVOS_AMBIENTALES_NUM AS INTEGER) AS PASIVOS_AMBIENTALES_N,
    CAST(15.0   AS DECIMAL(12,4))    AS COBERTURA_GLACIAR_PCT,    -- sin dato: neutro
    CAST(900.0  AS DECIMAL(12,4))    AS PRECIPITACION_ANUAL_MM,   -- sin dato: neutro

    -- Sociales
    CAST(u.COMUNIDADES_INFLUENCIA_NUM AS INTEGER) AS COMUNIDADES_INFLUENCIA_N,
    CAST(u.POBLACION_INFLUENCIA AS INTEGER)       AS POBLACION_AFECTADA,
    u.INDICE_ACEPTACION_SOCIAL,
    CAST(u.CONFLICTOS_REGISTRADOS_12M AS INTEGER) AS CONFLICTOS_HISTORICOS_N,
    N'NEUTRO'                                     AS CONSULTA_PREVIA_ESTADO,  -- sin dato: neutro
    CAST(6.0    AS DECIMAL(12,4))                 AS PERMISOS_PENDIENTES_N,   -- sin dato: neutro
    u.ESTADO_CONCESION                            AS ESTADO_LICENCIA,        -- proxy, ver seccion 5
    u.DISTANCIA_COMUNIDAD_KM                      AS DIST_CENTRO_POBLADO_KM,
    u.IDH_DISTRITAL,
    u.POBREZA_DISTRITAL_PCT                       AS POBREZA_PCT,

    -- Historicas / informativas (no entran al calculo de scoring)
    CAST(NULL AS DATE)                            AS FECHA_INICIO_EXPLORACION,
    CAST(NULL AS DECIMAL(9,2))                    AS INVERSION_ACUMULADA_MUSD, -- sin equivalente real
    CAST(u.EVENTOS_GEOLOGICOS_12M AS INTEGER)     AS INCIDENTES_REGISTRADOS_N,
    CAST(u.DIAS_PARALIZACION_12M AS INTEGER)      AS DIAS_PARALIZACION_ACUM
FROM V_GEORISK_ZONAS_ULTIMA u;
