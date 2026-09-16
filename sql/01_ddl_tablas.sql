-- =====================================================================
-- GeoRisk :: 01 - DDL de tablas base
-- Plataforma: SAP HANA Cloud
-- Orden de ejecucion: 01 -> 02 -> 03 -> 04
-- =====================================================================
-- Si la organizacion entrega el dataset comun ya cargado, NO ejecutar la
-- creacion de GEORISK_ZONAS: en su lugar ajustar el nombre de esquema/tabla
-- en la vista V_GEORISK_ZONAS_BASE (final de este archivo).
-- =====================================================================

-- CREATE SCHEMA GEORISK;
-- SET SCHEMA GEORISK;


-- ---------------------------------------------------------------------
-- 1. Tabla base de zonas de exploracion
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_ZONAS (
    -- Identificacion
    ZONA_ID                   NVARCHAR(10)  PRIMARY KEY,
    NOMBRE_ZONA               NVARCHAR(80)  NOT NULL,
    REGION                    NVARCHAR(40)  NOT NULL,
    PROVINCIA                 NVARCHAR(60),
    DISTRITO                  NVARCHAR(80),
    MINERAL_PRINCIPAL         NVARCHAR(30),
    FASE_PROYECTO             NVARCHAR(40),

    -- Geograficas
    LATITUD                   DECIMAL(9,5),
    LONGITUD                  DECIMAL(9,5),
    ALTITUD_MSNM              INTEGER,
    SUPERFICIE_HA             INTEGER,

    -- Geologicas
    DENSIDAD_FALLAS_KM2       DECIMAL(6,2),   -- fallas por km2
    INDICE_ESTABILIDAD_TALUD  DECIMAL(5,2),   -- 0 (inestable) .. 10 (estable)
    SISMICIDAD_PGA_G          DECIMAL(5,3),   -- aceleracion pico en g
    LEY_MINERAL_PCT           DECIMAL(6,3),   -- % equivalente
    PROFUNDIDAD_DEPOSITO_M    INTEGER,
    TONELAJE_ESTIMADO_MT      DECIMAL(9,1),   -- millones de toneladas
    PERMEABILIDAD_MD          DECIMAL(9,2),   -- milidarcys
    POTENCIAL_DAM_NPAP        DECIMAL(6,2),   -- ratio NP/AP; <1 = riesgo acido

    -- Ambientales
    DIST_FUENTE_AGUA_KM       DECIMAL(6,2),
    CALIDAD_AGUA_ICA          DECIMAL(5,2),   -- 0 (mala) .. 100 (buena)
    ESTRES_HIDRICO_IDX        DECIMAL(5,2),   -- 0 .. 100
    DIST_AREA_PROTEGIDA_KM    DECIMAL(6,2),
    INDICE_BIODIVERSIDAD      DECIMAL(5,2),   -- 0 .. 100
    ESPECIES_AMENAZADAS_N     INTEGER,
    PASIVOS_AMBIENTALES_N     INTEGER,
    COBERTURA_GLACIAR_PCT     DECIMAL(5,2),
    PRECIPITACION_ANUAL_MM    INTEGER,

    -- Sociales
    COMUNIDADES_INFLUENCIA_N  INTEGER,
    POBLACION_AFECTADA        INTEGER,
    INDICE_ACEPTACION_SOCIAL  DECIMAL(5,2),   -- 0 (rechazo) .. 100 (aceptacion)
    CONFLICTOS_HISTORICOS_N   INTEGER,
    CONSULTA_PREVIA_ESTADO    NVARCHAR(20),   -- Concluida|En proceso|No iniciada|No aplica
    PERMISOS_PENDIENTES_N     INTEGER,
    ESTADO_LICENCIA           NVARCHAR(20),   -- Vigente|En tramite|Observada|Sin licencia
    DIST_CENTRO_POBLADO_KM    DECIMAL(6,2),
    IDH_DISTRITAL             DECIMAL(4,3),   -- 0 .. 1
    POBREZA_PCT               DECIMAL(5,2),

    -- Historicas
    FECHA_INICIO_EXPLORACION  DATE,
    INVERSION_ACUMULADA_MUSD  DECIMAL(9,2),
    INCIDENTES_REGISTRADOS_N  INTEGER,
    DIAS_PARALIZACION_ACUM    INTEGER
);

COMMENT ON TABLE GEORISK_ZONAS IS 'Zonas de exploracion minera con variables geologicas, ambientales, sociales, geograficas e historicas';


-- ---------------------------------------------------------------------
-- 2. Parametros del modelo: pesos por dimension
-- ---------------------------------------------------------------------
-- Los pesos NO estan hardcodeados en las vistas: viven aqui para permitir
-- simulacion "que pasa si" cambiando una fila, sin tocar SQL.
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_DIMENSION (
    DIMENSION_COD   NVARCHAR(10)  PRIMARY KEY,   -- GEO | AMB | SOC
    DIMENSION_DESC  NVARCHAR(60)  NOT NULL,
    PESO            DECIMAL(5,4)  NOT NULL,      -- debe sumar 1.0000
    ACTIVO          SMALLINT      DEFAULT 1
);

INSERT INTO GEORISK_PARAM_DIMENSION VALUES ('GEO', 'Riesgo geologico',  0.4000, 1);
INSERT INTO GEORISK_PARAM_DIMENSION VALUES ('AMB', 'Riesgo ambiental',  0.3500, 1);
INSERT INTO GEORISK_PARAM_DIMENSION VALUES ('SOC', 'Riesgo social',     0.2500, 1);


-- ---------------------------------------------------------------------
-- 3. Parametros del modelo: pesos por subindice
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_SUBINDICE (
    SUBINDICE_COD   NVARCHAR(20)  PRIMARY KEY,
    DIMENSION_COD   NVARCHAR(10)  NOT NULL,
    SUBINDICE_DESC  NVARCHAR(80)  NOT NULL,
    PESO            DECIMAL(5,4)  NOT NULL       -- suma 1.0000 dentro de su dimension
);

INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('GEO_ESTAB',  'GEO', 'Estabilidad estructural',        0.4000);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('GEO_DEPOS',  'GEO', 'Caracteristicas del deposito',   0.3500);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('GEO_HIDRO',  'GEO', 'Hidrogeologia y drenaje acido',  0.2500);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('AMB_AGUA',   'AMB', 'Recurso hidrico',                0.4000);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('AMB_BIO',    'AMB', 'Biodiversidad y areas naturales',0.3500);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('AMB_RESID',  'AMB', 'Pasivos, emisiones y residuos',  0.2500);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('SOC_ACEPT',  'SOC', 'Aceptacion comunitaria',         0.4000);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('SOC_LEGAL',  'SOC', 'Contexto legal y permisos',      0.3500);
INSERT INTO GEORISK_PARAM_SUBINDICE VALUES ('SOC_TERR',   'SOC', 'Contexto territorial',           0.2500);


-- ---------------------------------------------------------------------
-- 4. Parametros de normalizacion por variable
-- ---------------------------------------------------------------------
-- SENTIDO = 'D' (directo: mas valor -> mas riesgo)
-- SENTIDO = 'I' (inverso: mas valor -> menos riesgo)
-- Los rangos son de REFERENCIA TECNICA, no min/max del dataset: asi el score
-- de una zona no cambia cuando se agregan zonas nuevas (score estable).
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_VARIABLE (
    VARIABLE_COD    NVARCHAR(40)  PRIMARY KEY,
    SUBINDICE_COD   NVARCHAR(20)  NOT NULL,
    VARIABLE_DESC   NVARCHAR(100) NOT NULL,
    UNIDAD          NVARCHAR(20),
    MIN_REF         DECIMAL(12,4) NOT NULL,
    MAX_REF         DECIMAL(12,4) NOT NULL,
    SENTIDO         NVARCHAR(1)   NOT NULL,
    PESO            DECIMAL(5,4)  NOT NULL       -- suma 1.0000 dentro del subindice
);

-- Dimension GEOLOGICA
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('DENSIDAD_FALLAS_KM2',      'GEO_ESTAB', 'Densidad de fallas geologicas',        'fallas/km2', 0.0,   5.0,   'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('INDICE_ESTABILIDAD_TALUD', 'GEO_ESTAB', 'Indice de estabilidad de taludes',     '0-10',       0.0,   10.0,  'I', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('SISMICIDAD_PGA_G',         'GEO_ESTAB', 'Sismicidad (aceleracion pico)',        'g',          0.10,  0.60,  'D', 0.3000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('LEY_MINERAL_PCT',          'GEO_DEPOS', 'Ley mineral equivalente',              '%',          0.20,  2.00,  'I', 0.4000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('PROFUNDIDAD_DEPOSITO_M',   'GEO_DEPOS', 'Profundidad del deposito',             'm',          50.0,  800.0, 'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('TONELAJE_ESTIMADO_MT',     'GEO_DEPOS', 'Tonelaje estimado',                    'Mt',         10.0,  1000.0,'I', 0.2500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('PERMEABILIDAD_MD',         'GEO_HIDRO', 'Permeabilidad de la roca',             'mD',         0.10,  500.0, 'D', 0.4000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('POTENCIAL_DAM_NPAP',       'GEO_HIDRO', 'Potencial de drenaje acido (NP/AP)',   'ratio',      0.20,  3.00,  'I', 0.6000);

-- Dimension AMBIENTAL
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('DIST_FUENTE_AGUA_KM',      'AMB_AGUA',  'Distancia a fuente de agua',           'km',         0.0,   10.0,  'I', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('CALIDAD_AGUA_ICA',         'AMB_AGUA',  'Indice de calidad de agua',            '0-100',      0.0,   100.0, 'I', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('ESTRES_HIDRICO_IDX',       'AMB_AGUA',  'Indice de estres hidrico',             '0-100',      0.0,   100.0, 'D', 0.3000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('DIST_AREA_PROTEGIDA_KM',   'AMB_BIO',   'Distancia a area natural protegida',   'km',         0.0,   50.0,  'I', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('INDICE_BIODIVERSIDAD',     'AMB_BIO',   'Indice de biodiversidad local',        '0-100',      0.0,   100.0, 'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('ESPECIES_AMENAZADAS_N',    'AMB_BIO',   'Especies amenazadas registradas',      'conteo',     0.0,   25.0,  'D', 0.3000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('PASIVOS_AMBIENTALES_N',    'AMB_RESID', 'Pasivos ambientales preexistentes',    'conteo',     0.0,   15.0,  'D', 0.4000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('COBERTURA_GLACIAR_PCT',    'AMB_RESID', 'Cobertura glaciar en el area',         '%',          0.0,   30.0,  'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('PRECIPITACION_ANUAL_MM',   'AMB_RESID', 'Precipitacion anual',                  'mm',         200.0, 1600.0,'D', 0.2500);

-- Dimension SOCIAL
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('INDICE_ACEPTACION_SOCIAL', 'SOC_ACEPT', 'Indice de aceptacion social',          '0-100',      0.0,   100.0, 'I', 0.4500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('CONFLICTOS_HISTORICOS_N',  'SOC_ACEPT', 'Conflictos sociales historicos',       'conteo',     0.0,   12.0,  'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('COMUNIDADES_INFLUENCIA_N', 'SOC_ACEPT', 'Comunidades en area de influencia',    'conteo',     0.0,   15.0,  'D', 0.2000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('CONSULTA_PREVIA_SCORE',    'SOC_LEGAL', 'Estado de la consulta previa',         'score',      0.0,   100.0, 'D', 0.4000);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('ESTADO_LICENCIA_SCORE',    'SOC_LEGAL', 'Estado de la licencia social/ambiental','score',     0.0,   100.0, 'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('PERMISOS_PENDIENTES_N',    'SOC_LEGAL', 'Permisos pendientes',                  'conteo',     0.0,   12.0,  'D', 0.2500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('DIST_CENTRO_POBLADO_KM',   'SOC_TERR',  'Distancia a centro poblado',           'km',         0.0,   20.0,  'I', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('POBREZA_PCT',              'SOC_TERR',  'Incidencia de pobreza',                '%',          0.0,   70.0,  'D', 0.3500);
INSERT INTO GEORISK_PARAM_VARIABLE VALUES ('IDH_DISTRITAL',            'SOC_TERR',  'Indice de desarrollo humano distrital','0-1',        0.20,  0.70,  'I', 0.3000);


-- ---------------------------------------------------------------------
-- 5. Catalogo de scores para variables categoricas
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_CATEGORIA (
    VARIABLE_COD  NVARCHAR(40)  NOT NULL,
    VALOR         NVARCHAR(30)  NOT NULL,
    SCORE         DECIMAL(5,2)  NOT NULL,   -- 0 = sin riesgo, 100 = riesgo maximo
    PRIMARY KEY (VARIABLE_COD, VALOR)
);

INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('CONSULTA_PREVIA_ESTADO', 'Concluida',    0.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('CONSULTA_PREVIA_ESTADO', 'No aplica',   15.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('CONSULTA_PREVIA_ESTADO', 'En proceso',  45.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('CONSULTA_PREVIA_ESTADO', 'No iniciada', 85.0);

INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('ESTADO_LICENCIA', 'Vigente',       0.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('ESTADO_LICENCIA', 'En tramite',   50.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('ESTADO_LICENCIA', 'Observada',    80.0);
INSERT INTO GEORISK_PARAM_CATEGORIA VALUES ('ESTADO_LICENCIA', 'Sin licencia',100.0);


-- ---------------------------------------------------------------------
-- 6. Escala de clasificacion del riesgo global
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_ESCALA (
    NIVEL_COD    NVARCHAR(10)  PRIMARY KEY,
    NIVEL_DESC   NVARCHAR(30)  NOT NULL,
    LIMITE_INF   DECIMAL(5,2)  NOT NULL,
    LIMITE_SUP   DECIMAL(5,2)  NOT NULL,
    COLOR_HEX    NVARCHAR(7),
    ORDEN        SMALLINT
);

INSERT INTO GEORISK_PARAM_ESCALA VALUES ('BAJO',     'Riesgo bajo',      0.00,  25.00, '#2E7D32', 1);
INSERT INTO GEORISK_PARAM_ESCALA VALUES ('MODERADO', 'Riesgo moderado', 25.00,  50.00, '#F9A825', 2);
INSERT INTO GEORISK_PARAM_ESCALA VALUES ('ALTO',     'Riesgo alto',     50.00,  75.00, '#EF6C00', 3);
INSERT INTO GEORISK_PARAM_ESCALA VALUES ('CRITICO',  'Riesgo critico',  75.00, 100.01, '#C62828', 4);


-- ---------------------------------------------------------------------
-- 7. Parametros generales del modelo (clave-valor)
-- ---------------------------------------------------------------------
-- AGRAVANTE_UMBRAL / AGRAVANTE_FACTOR implementan el principio NO
-- COMPENSATORIO del scoring: una media ponderada pura permitiria que una
-- excelente geologia "tape" un riesgo social critico. En gestion de riesgo
-- eso es incorrecto -- un factor critico no se compensa. Por eso, cuando la
-- dimension mas alta supera el umbral, se suma una penalizacion:
--
--   RIESGO_GLOBAL = MIN(100, RIESGO_BASE + FACTOR * MAX(0, peor_dim - UMBRAL))
--
-- El riesgo base sigue siendo explicable variable a variable; el agravante
-- se reporta por separado para que la trazabilidad no se pierda.
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_PARAM_MODELO (
    PARAM_COD   NVARCHAR(30)   PRIMARY KEY,
    PARAM_DESC  NVARCHAR(150)  NOT NULL,
    VALOR       DECIMAL(10,4)  NOT NULL
);

INSERT INTO GEORISK_PARAM_MODELO VALUES ('AGRAVANTE_UMBRAL', 'Score de dimension a partir del cual se aplica penalizacion no compensatoria', 60.0000);
INSERT INTO GEORISK_PARAM_MODELO VALUES ('AGRAVANTE_FACTOR', 'Proporcion del exceso sobre el umbral que se suma al riesgo global',          0.5000);


-- ---------------------------------------------------------------------
-- 8. Trazabilidad: evaluaciones enviadas a revision
-- ---------------------------------------------------------------------
-- Escrita por SAP Build Process Automation al iniciar y cerrar el flujo.
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_EVALUACION (
    EVALUACION_ID       NVARCHAR(20)  PRIMARY KEY,
    ZONA_ID             NVARCHAR(10)  NOT NULL,
    FECHA_EVALUACION    TIMESTAMP     NOT NULL,
    -- Foto del scoring en el momento del envio (el modelo puede cambiar despues)
    RIESGO_GLOBAL       DECIMAL(5,2)  NOT NULL,
    RIESGO_GEOLOGICO    DECIMAL(5,2)  NOT NULL,
    RIESGO_AMBIENTAL    DECIMAL(5,2)  NOT NULL,
    RIESGO_SOCIAL       DECIMAL(5,2)  NOT NULL,
    NIVEL_RIESGO        NVARCHAR(10)  NOT NULL,
    FACTOR_CRITICO      NVARCHAR(100),          -- subindice que mas aporta
    -- Flujo de revision
    ESTADO              NVARCHAR(20)  NOT NULL, -- PENDIENTE|APROBADO|OBSERVADO|RECHAZADO
    SOLICITANTE         NVARCHAR(120),
    REVISOR             NVARCHAR(120),
    FECHA_DECISION      TIMESTAMP,
    DECISION_COMENTARIO NVARCHAR(1000),
    JUSTIFICACION       NVARCHAR(2000),
    PROCESO_INSTANCIA   NVARCHAR(80)            -- id de instancia en SAP BPA
);

CREATE INDEX IDX_EVAL_ZONA   ON GEORISK_EVALUACION (ZONA_ID);
CREATE INDEX IDX_EVAL_ESTADO ON GEORISK_EVALUACION (ESTADO);


-- ---------------------------------------------------------------------
-- 8. Bitacora de eventos (trazabilidad fina del flujo)
-- ---------------------------------------------------------------------
CREATE COLUMN TABLE GEORISK_EVAL_LOG (
    LOG_ID          BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    EVALUACION_ID   NVARCHAR(20)  NOT NULL,
    FECHA_EVENTO    TIMESTAMP     NOT NULL,
    EVENTO          NVARCHAR(40)  NOT NULL,   -- CREADA|ENVIADA|APROBADA|OBSERVADA|RECHAZADA|COMENTARIO
    USUARIO         NVARCHAR(120),
    DETALLE         NVARCHAR(1000)
);

CREATE INDEX IDX_LOG_EVAL ON GEORISK_EVAL_LOG (EVALUACION_ID);


-- ---------------------------------------------------------------------
-- 9. Punto unico de adaptacion al dataset comun del evento
-- ---------------------------------------------------------------------
-- Todas las vistas de scoring leen de V_GEORISK_ZONAS_BASE, nunca de la tabla
-- directamente. Si la organizacion entrega el dataset con otro nombre o con
-- otros nombres de columna, SOLO se modifica esta vista y el resto del modelo
-- sigue funcionando sin cambios.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_ZONAS_BASE AS
SELECT * FROM GEORISK_ZONAS;
