-- =====================================================================
-- GeoRisk :: 02 - Vistas de scoring multidimensional
-- Plataforma: SAP HANA Cloud
-- Requiere: 01_ddl_tablas.sql
-- =====================================================================
-- DISENO: el scoring es data-driven. Las vistas no contienen pesos ni
-- rangos: todo se lee de GEORISK_PARAM_*. Agregar una variable al modelo
-- = insertar una fila en GEORISK_PARAM_VARIABLE + una rama en
-- V_GEORISK_VALORES. Cambiar una ponderacion = un UPDATE, sin tocar SQL.
--
-- Cadena de vistas:
--   V_GEORISK_VALORES     (ancho -> largo, resuelve categoricas)
--        v
--   V_GEORISK_NORM        (normaliza cada variable a 0-100)
--        v
--   V_GEORISK_SUBINDICE   (agrega por subindice)
--        v
--   V_GEORISK_DIMENSION   (agrega por dimension)
--        v
--   V_GEORISK_SCORING     (riesgo global + nivel)  <-- consumir desde SAC
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. Desnormalizacion: tabla ancha -> formato largo
-- ---------------------------------------------------------------------
-- Las variables numericas se toman directo. Las categoricas se traducen a
-- score mediante GEORISK_PARAM_CATEGORIA.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_VALORES AS
-- --- Geologicas ---
SELECT ZONA_ID, 'DENSIDAD_FALLAS_KM2'      AS VARIABLE_COD, CAST(DENSIDAD_FALLAS_KM2      AS DECIMAL(12,4)) AS VALOR FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'INDICE_ESTABILIDAD_TALUD', CAST(INDICE_ESTABILIDAD_TALUD AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'SISMICIDAD_PGA_G',         CAST(SISMICIDAD_PGA_G         AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'LEY_MINERAL_PCT',          CAST(LEY_MINERAL_PCT          AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'PROFUNDIDAD_DEPOSITO_M',   CAST(PROFUNDIDAD_DEPOSITO_M   AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'TONELAJE_ESTIMADO_MT',     CAST(TONELAJE_ESTIMADO_MT     AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'PERMEABILIDAD_MD',         CAST(PERMEABILIDAD_MD         AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'POTENCIAL_DAM_NPAP',       CAST(POTENCIAL_DAM_NPAP       AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
-- --- Ambientales ---
UNION ALL SELECT ZONA_ID, 'DIST_FUENTE_AGUA_KM',      CAST(DIST_FUENTE_AGUA_KM      AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'CALIDAD_AGUA_ICA',         CAST(CALIDAD_AGUA_ICA         AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'ESTRES_HIDRICO_IDX',       CAST(ESTRES_HIDRICO_IDX       AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'DIST_AREA_PROTEGIDA_KM',   CAST(DIST_AREA_PROTEGIDA_KM   AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'INDICE_BIODIVERSIDAD',     CAST(INDICE_BIODIVERSIDAD     AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'ESPECIES_AMENAZADAS_N',    CAST(ESPECIES_AMENAZADAS_N    AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'PASIVOS_AMBIENTALES_N',    CAST(PASIVOS_AMBIENTALES_N    AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'COBERTURA_GLACIAR_PCT',    CAST(COBERTURA_GLACIAR_PCT    AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'PRECIPITACION_ANUAL_MM',   CAST(PRECIPITACION_ANUAL_MM   AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
-- --- Sociales numericas ---
UNION ALL SELECT ZONA_ID, 'INDICE_ACEPTACION_SOCIAL', CAST(INDICE_ACEPTACION_SOCIAL AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'CONFLICTOS_HISTORICOS_N',  CAST(CONFLICTOS_HISTORICOS_N  AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'COMUNIDADES_INFLUENCIA_N', CAST(COMUNIDADES_INFLUENCIA_N AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'PERMISOS_PENDIENTES_N',    CAST(PERMISOS_PENDIENTES_N    AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'DIST_CENTRO_POBLADO_KM',   CAST(DIST_CENTRO_POBLADO_KM   AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'POBREZA_PCT',              CAST(POBREZA_PCT              AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
UNION ALL SELECT ZONA_ID, 'IDH_DISTRITAL',            CAST(IDH_DISTRITAL            AS DECIMAL(12,4)) FROM V_GEORISK_ZONAS_BASE
-- --- Sociales categoricas (traducidas por catalogo) ---
UNION ALL
SELECT z.ZONA_ID, 'CONSULTA_PREVIA_SCORE', CAST(c.SCORE AS DECIMAL(12,4))
FROM   V_GEORISK_ZONAS_BASE z
JOIN   GEORISK_PARAM_CATEGORIA c
       ON c.VARIABLE_COD = 'CONSULTA_PREVIA_ESTADO'
      AND c.VALOR        = z.CONSULTA_PREVIA_ESTADO
UNION ALL
SELECT z.ZONA_ID, 'ESTADO_LICENCIA_SCORE', CAST(c.SCORE AS DECIMAL(12,4))
FROM   V_GEORISK_ZONAS_BASE z
JOIN   GEORISK_PARAM_CATEGORIA c
       ON c.VARIABLE_COD = 'ESTADO_LICENCIA'
      AND c.VALOR        = z.ESTADO_LICENCIA;


-- ---------------------------------------------------------------------
-- 2. Normalizacion min-max con recorte a rangos de referencia
-- ---------------------------------------------------------------------
--   SENTIDO 'D' : norm = 100 * (x - min) / (max - min)
--   SENTIDO 'I' : norm = 100 - [lo anterior]
-- El valor se recorta al rango [MIN_REF, MAX_REF] antes de normalizar, de
-- modo que un outlier no distorsiona la escala ni produce valores fuera
-- de 0-100. Resultado: 0 = sin riesgo, 100 = riesgo maximo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_NORM AS
SELECT
    v.ZONA_ID,
    v.VARIABLE_COD,
    p.VARIABLE_DESC,
    p.SUBINDICE_COD,
    s.DIMENSION_COD,
    v.VALOR                                                   AS VALOR_ORIGINAL,
    p.UNIDAD,
    p.SENTIDO,
    CAST(
        CASE WHEN p.SENTIDO = 'D'
             THEN 100.0 * (LEAST(GREATEST(v.VALOR, p.MIN_REF), p.MAX_REF) - p.MIN_REF)
                        / NULLIF(p.MAX_REF - p.MIN_REF, 0)
             ELSE 100.0 - 100.0 * (LEAST(GREATEST(v.VALOR, p.MIN_REF), p.MAX_REF) - p.MIN_REF)
                                / NULLIF(p.MAX_REF - p.MIN_REF, 0)
        END AS DECIMAL(7,3))                                  AS VALOR_NORM,
    p.PESO                                                    AS PESO_EN_SUBINDICE
FROM        V_GEORISK_VALORES     v
INNER JOIN  GEORISK_PARAM_VARIABLE  p ON p.VARIABLE_COD  = v.VARIABLE_COD
INNER JOIN  GEORISK_PARAM_SUBINDICE s ON s.SUBINDICE_COD = p.SUBINDICE_COD;


-- ---------------------------------------------------------------------
-- 3. Agregacion por subindice
-- ---------------------------------------------------------------------
-- Media ponderada de las variables del subindice. Se divide por la suma de
-- pesos presentes para que el resultado siga en 0-100 aunque falte una
-- variable (robustez ante nulos en el dataset del evento).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_SUBINDICE AS
SELECT
    n.ZONA_ID,
    n.SUBINDICE_COD,
    si.SUBINDICE_DESC,
    n.DIMENSION_COD,
    CAST(SUM(n.VALOR_NORM * n.PESO_EN_SUBINDICE)
         / NULLIF(SUM(n.PESO_EN_SUBINDICE), 0) AS DECIMAL(5,2)) AS SCORE_SUBINDICE,
    si.PESO                                                     AS PESO_EN_DIMENSION,
    COUNT(*)                                                    AS N_VARIABLES
FROM        V_GEORISK_NORM          n
INNER JOIN  GEORISK_PARAM_SUBINDICE si ON si.SUBINDICE_COD = n.SUBINDICE_COD
GROUP BY    n.ZONA_ID, n.SUBINDICE_COD, si.SUBINDICE_DESC, n.DIMENSION_COD, si.PESO;


-- ---------------------------------------------------------------------
-- 4. Agregacion por dimension
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_DIMENSION AS
SELECT
    sub.ZONA_ID,
    sub.DIMENSION_COD,
    d.DIMENSION_DESC,
    CAST(SUM(sub.SCORE_SUBINDICE * sub.PESO_EN_DIMENSION)
         / NULLIF(SUM(sub.PESO_EN_DIMENSION), 0) AS DECIMAL(5,2)) AS SCORE_DIMENSION,
    d.PESO                                                        AS PESO_EN_GLOBAL
FROM        V_GEORISK_SUBINDICE      sub
INNER JOIN  GEORISK_PARAM_DIMENSION  d ON d.DIMENSION_COD = sub.DIMENSION_COD
WHERE       d.ACTIVO = 1
GROUP BY    sub.ZONA_ID, sub.DIMENSION_COD, d.DIMENSION_DESC, d.PESO;


-- ---------------------------------------------------------------------
-- 5. VISTA PRINCIPAL: scoring global por zona
-- ---------------------------------------------------------------------
-- Esta es la vista que consume SAP Analytics Cloud como modelo base.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_SCORING AS
WITH DIM_PIVOT AS (
    SELECT
        ZONA_ID,
        MAX(CASE WHEN DIMENSION_COD = 'GEO' THEN SCORE_DIMENSION END) AS RIESGO_GEOLOGICO,
        MAX(CASE WHEN DIMENSION_COD = 'AMB' THEN SCORE_DIMENSION END) AS RIESGO_AMBIENTAL,
        MAX(CASE WHEN DIMENSION_COD = 'SOC' THEN SCORE_DIMENSION END) AS RIESGO_SOCIAL,
        -- Componente compensatorio: media ponderada de las tres dimensiones
        CAST(SUM(SCORE_DIMENSION * PESO_EN_GLOBAL)
             / NULLIF(SUM(PESO_EN_GLOBAL), 0) AS DECIMAL(5,2))        AS RIESGO_BASE,
        -- Dimension mas alta: alimenta la penalizacion no compensatoria
        MAX(SCORE_DIMENSION)                                          AS PEOR_DIMENSION
    FROM   V_GEORISK_DIMENSION
    GROUP BY ZONA_ID
),
PARAM AS (
    SELECT
        MAX(CASE WHEN PARAM_COD = 'AGRAVANTE_UMBRAL' THEN VALOR END) AS UMBRAL,
        MAX(CASE WHEN PARAM_COD = 'AGRAVANTE_FACTOR' THEN VALOR END) AS FACTOR
    FROM GEORISK_PARAM_MODELO
),
-- Aplicacion del principio no compensatorio: si alguna dimension supera el
-- umbral, su exceso se suma al riesgo base. Asi una geologia excelente no
-- puede "tapar" un riesgo social critico.
SCORE AS (
    SELECT
        dp.ZONA_ID,
        dp.RIESGO_GEOLOGICO,
        dp.RIESGO_AMBIENTAL,
        dp.RIESGO_SOCIAL,
        dp.RIESGO_BASE,
        dp.PEOR_DIMENSION,
        CAST(CASE WHEN dp.PEOR_DIMENSION > pm.UMBRAL
                  THEN pm.FACTOR * (dp.PEOR_DIMENSION - pm.UMBRAL)
                  ELSE 0 END AS DECIMAL(5,2))                          AS AGRAVANTE,
        CAST(LEAST(100.0,
                   dp.RIESGO_BASE
                   + CASE WHEN dp.PEOR_DIMENSION > pm.UMBRAL
                          THEN pm.FACTOR * (dp.PEOR_DIMENSION - pm.UMBRAL)
                          ELSE 0 END) AS DECIMAL(5,2))                 AS RIESGO_GLOBAL
    FROM DIM_PIVOT dp
    CROSS JOIN PARAM pm
),
-- Subindice que mas contribuye al riesgo global: sirve como "factor critico"
FACTOR_TOP AS (
    SELECT ZONA_ID, SUBINDICE_DESC, SCORE_SUBINDICE
    FROM (
        SELECT
            s.ZONA_ID,
            s.SUBINDICE_DESC,
            s.SCORE_SUBINDICE,
            ROW_NUMBER() OVER (
                PARTITION BY s.ZONA_ID
                ORDER BY s.SCORE_SUBINDICE * s.PESO_EN_DIMENSION * d.PESO DESC
            ) AS RN
        FROM       V_GEORISK_SUBINDICE     s
        INNER JOIN GEORISK_PARAM_DIMENSION d ON d.DIMENSION_COD = s.DIMENSION_COD
    )
    WHERE RN = 1
)
SELECT
    z.ZONA_ID,
    z.NOMBRE_ZONA,
    z.REGION,
    z.PROVINCIA,
    z.DISTRITO,
    z.MINERAL_PRINCIPAL,
    z.FASE_PROYECTO,
    z.LATITUD,
    z.LONGITUD,
    z.ALTITUD_MSNM,
    z.SUPERFICIE_HA,
    z.POBLACION_AFECTADA,
    z.COMUNIDADES_INFLUENCIA_N,
    z.INVERSION_ACUMULADA_MUSD,
    -- Scores por dimension
    p.RIESGO_GEOLOGICO,
    p.RIESGO_AMBIENTAL,
    p.RIESGO_SOCIAL,
    -- Descomposicion del riesgo global: base compensatoria + agravante
    p.RIESGO_BASE,
    p.PEOR_DIMENSION,
    p.AGRAVANTE,
    p.RIESGO_GLOBAL,
    -- Clasificacion
    e.NIVEL_COD                                   AS NIVEL_RIESGO,
    e.NIVEL_DESC                                  AS NIVEL_RIESGO_DESC,
    e.COLOR_HEX                                   AS NIVEL_COLOR,
    e.ORDEN                                       AS NIVEL_ORDEN,
    -- Explicabilidad
    f.SUBINDICE_DESC                              AS FACTOR_CRITICO,
    f.SCORE_SUBINDICE                             AS FACTOR_CRITICO_SCORE,
    -- Ranking (1 = mas riesgoso)
    RANK() OVER (ORDER BY p.RIESGO_GLOBAL DESC)   AS RANKING_RIESGO,
    RANK() OVER (PARTITION BY z.REGION ORDER BY p.RIESGO_GLOBAL DESC) AS RANKING_EN_REGION
FROM        V_GEORISK_ZONAS_BASE z
INNER JOIN  SCORE                p ON p.ZONA_ID = z.ZONA_ID
LEFT JOIN   FACTOR_TOP           f ON f.ZONA_ID = z.ZONA_ID
LEFT JOIN   GEORISK_PARAM_ESCALA e ON p.RIESGO_GLOBAL >= e.LIMITE_INF
                                  AND p.RIESGO_GLOBAL <  e.LIMITE_SUP;


-- ---------------------------------------------------------------------
-- 6. Contribucion de cada variable al riesgo global (explicabilidad)
-- ---------------------------------------------------------------------
-- Responde: "por que esta zona tiene este score". Cada fila indica cuantos
-- puntos del riesgo global aporta esa variable. La suma de CONTRIBUCION_PP
-- por zona reconstruye el RIESGO_GLOBAL.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_CONTRIBUCION AS
SELECT
    n.ZONA_ID,
    z.NOMBRE_ZONA,
    n.DIMENSION_COD,
    d.DIMENSION_DESC,
    n.SUBINDICE_COD,
    si.SUBINDICE_DESC,
    n.VARIABLE_COD,
    n.VARIABLE_DESC,
    n.UNIDAD,
    n.VALOR_ORIGINAL,
    n.VALOR_NORM,
    n.SENTIDO,
    -- Peso efectivo de la variable sobre el riesgo global
    CAST(n.PESO_EN_SUBINDICE * si.PESO * d.PESO AS DECIMAL(7,5))            AS PESO_EFECTIVO,
    -- Puntos que esta variable aporta al riesgo global (0-100)
    CAST(n.VALOR_NORM * n.PESO_EN_SUBINDICE * si.PESO * d.PESO AS DECIMAL(7,3)) AS CONTRIBUCION_PP
FROM        V_GEORISK_NORM           n
INNER JOIN  V_GEORISK_ZONAS_BASE     z  ON z.ZONA_ID       = n.ZONA_ID
INNER JOIN  GEORISK_PARAM_SUBINDICE  si ON si.SUBINDICE_COD = n.SUBINDICE_COD
INNER JOIN  GEORISK_PARAM_DIMENSION  d  ON d.DIMENSION_COD  = n.DIMENSION_COD;
