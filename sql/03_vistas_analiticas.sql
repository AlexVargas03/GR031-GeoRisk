-- =====================================================================
-- GeoRisk :: 03 - Vistas analiticas para SAP Analytics Cloud
-- Plataforma: SAP HANA Cloud
-- Requiere: 01_ddl_tablas.sql, 02_vistas_scoring.sql
-- =====================================================================
-- Cada vista esta pensada para alimentar un widget concreto del dashboard.
-- Se entregan en formato "tidy" (una fila por observacion) porque SAC
-- construye graficos de series y categorias con menos friccion asi.
--
--   V_GEORISK_KPI            -> tarjetas de KPI (fila unica)
--   V_GEORISK_RANKING        -> tabla y barras del ranking de zonas
--   V_GEORISK_POR_REGION     -> mapa/barras agregadas por region
--   V_GEORISK_RADAR          -> grafico radar por dimension
--   V_GEORISK_TOP_FACTORES   -> "por que" de cada zona (top 5 variables)
--   V_GEORISK_MAPA           -> capa geografica de puntos
--   V_GEORISK_MATRIZ         -> dispersion riesgo vs atractivo
--   V_GEORISK_DISTRIBUCION   -> histograma por nivel de riesgo
-- =====================================================================
-- ---------------------------------------------------------------------
-- 1. KPIs de cabecera (una sola fila)
-- ---------------------------------------------------------------------
-- Cubre el entregable "al menos 3 KPIs de riesgo".
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_KPI AS
SELECT
    COUNT(*)                                                     AS TOTAL_ZONAS,
    CAST(AVG(RIESGO_GLOBAL) AS DECIMAL(5,2))                     AS RIESGO_GLOBAL_PROMEDIO,
    CAST(MAX(RIESGO_GLOBAL) AS DECIMAL(5,2))                     AS RIESGO_MAXIMO,
    CAST(MIN(RIESGO_GLOBAL) AS DECIMAL(5,2))                     AS RIESGO_MINIMO,
    -- Zonas que exigen atencion: nivel ALTO o CRITICO
    SUM(CASE WHEN NIVEL_RIESGO IN ('ALTO','CRITICO') THEN 1 ELSE 0 END) AS ZONAS_RIESGO_ALTO,
    CAST(100.0 * SUM(CASE WHEN NIVEL_RIESGO IN ('ALTO','CRITICO') THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS DECIMAL(5,2))                  AS PCT_ZONAS_RIESGO_ALTO,
    SUM(CASE WHEN NIVEL_RIESGO = 'CRITICO' THEN 1 ELSE 0 END)    AS ZONAS_CRITICAS,
    -- Promedios por dimension: permiten ver que frente pesa mas en la cartera
    CAST(AVG(RIESGO_GEOLOGICO) AS DECIMAL(5,2))                  AS PROM_RIESGO_GEOLOGICO,
    CAST(AVG(RIESGO_AMBIENTAL) AS DECIMAL(5,2))                  AS PROM_RIESGO_AMBIENTAL,
    CAST(AVG(RIESGO_SOCIAL)    AS DECIMAL(5,2))                  AS PROM_RIESGO_SOCIAL,
    -- Exposicion social y economica concentrada en zonas de alto riesgo
    SUM(CASE WHEN NIVEL_RIESGO IN ('ALTO','CRITICO')
             THEN POBLACION_AFECTADA ELSE 0 END)                 AS POBLACION_EN_RIESGO,
    CAST(SUM(CASE WHEN NIVEL_RIESGO IN ('ALTO','CRITICO')
                  THEN INVERSION_ACUMULADA_MUSD ELSE 0 END) AS DECIMAL(12,2)) AS INVERSION_EN_RIESGO_MUSD,
    -- Cuantas zonas reciben penalizacion no compensatoria
    SUM(CASE WHEN AGRAVANTE > 0 THEN 1 ELSE 0 END)               AS ZONAS_CON_AGRAVANTE
FROM V_GEORISK_SCORING;


-- ---------------------------------------------------------------------
-- 2. Ranking de zonas
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_RANKING AS
SELECT
    RANKING_RIESGO,
    ZONA_ID,
    NOMBRE_ZONA,
    REGION,
    PROVINCIA,
    MINERAL_PRINCIPAL,
    FASE_PROYECTO,
    RIESGO_GLOBAL,
    RIESGO_BASE,
    AGRAVANTE,
    RIESGO_GEOLOGICO,
    RIESGO_AMBIENTAL,
    RIESGO_SOCIAL,
    NIVEL_RIESGO,
    NIVEL_RIESGO_DESC,
    NIVEL_COLOR,
    FACTOR_CRITICO,
    FACTOR_CRITICO_SCORE,
    POBLACION_AFECTADA,
    COMUNIDADES_INFLUENCIA_N,
    INVERSION_ACUMULADA_MUSD,
    -- Cuartil de riesgo: util para filtros rapidos en SAC
    NTILE(4) OVER (ORDER BY RIESGO_GLOBAL DESC)   AS CUARTIL_RIESGO
FROM V_GEORISK_SCORING;


-- ---------------------------------------------------------------------
-- 3. Agregado por region
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_POR_REGION AS
SELECT
    REGION,
    COUNT(*)                                                     AS N_ZONAS,
    CAST(AVG(RIESGO_GLOBAL)    AS DECIMAL(5,2))                  AS RIESGO_GLOBAL_PROM,
    CAST(MAX(RIESGO_GLOBAL)    AS DECIMAL(5,2))                  AS RIESGO_GLOBAL_MAX,
    CAST(AVG(RIESGO_GEOLOGICO) AS DECIMAL(5,2))                  AS RIESGO_GEOLOGICO_PROM,
    CAST(AVG(RIESGO_AMBIENTAL) AS DECIMAL(5,2))                  AS RIESGO_AMBIENTAL_PROM,
    CAST(AVG(RIESGO_SOCIAL)    AS DECIMAL(5,2))                  AS RIESGO_SOCIAL_PROM,
    SUM(CASE WHEN NIVEL_RIESGO IN ('ALTO','CRITICO') THEN 1 ELSE 0 END) AS ZONAS_RIESGO_ALTO,
    SUM(POBLACION_AFECTADA)                                      AS POBLACION_TOTAL,
    CAST(SUM(INVERSION_ACUMULADA_MUSD) AS DECIMAL(12,2))         AS INVERSION_TOTAL_MUSD,
    -- Dimension dominante de la region
    CASE
        WHEN AVG(RIESGO_GEOLOGICO) >= AVG(RIESGO_AMBIENTAL)
         AND AVG(RIESGO_GEOLOGICO) >= AVG(RIESGO_SOCIAL)    THEN 'Geologico'
        WHEN AVG(RIESGO_AMBIENTAL) >= AVG(RIESGO_SOCIAL)    THEN 'Ambiental'
        ELSE 'Social'
    END                                                          AS DIMENSION_DOMINANTE
FROM V_GEORISK_SCORING
GROUP BY REGION;


-- ---------------------------------------------------------------------
-- 4. Formato largo por dimension (grafico radar / comparacion de zonas)
-- ---------------------------------------------------------------------
-- SAC construye radares y barras agrupadas mas facilmente con una fila por
-- (zona, dimension) que con tres columnas separadas.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_RADAR AS
SELECT ZONA_ID, NOMBRE_ZONA, REGION, 'Geologico' AS DIMENSION, 1 AS ORDEN_DIM,
       RIESGO_GEOLOGICO AS SCORE, NIVEL_RIESGO
FROM   V_GEORISK_SCORING
UNION ALL
SELECT ZONA_ID, NOMBRE_ZONA, REGION, 'Ambiental', 2, RIESGO_AMBIENTAL, NIVEL_RIESGO
FROM   V_GEORISK_SCORING
UNION ALL
SELECT ZONA_ID, NOMBRE_ZONA, REGION, 'Social', 3, RIESGO_SOCIAL, NIVEL_RIESGO
FROM   V_GEORISK_SCORING;


-- ---------------------------------------------------------------------
-- 5. Explicabilidad: las 5 variables que mas pesan en cada zona
-- ---------------------------------------------------------------------
-- Responde la pregunta del jurado "¿por que esta zona puntua asi?" y es la
-- fuente que consume la skill de Joule para explicar en lenguaje natural.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_TOP_FACTORES AS
SELECT
    ZONA_ID,
    NOMBRE_ZONA,
    ORDEN_FACTOR,
    DIMENSION_DESC,
    SUBINDICE_DESC,
    VARIABLE_DESC,
    VALOR_ORIGINAL,
    UNIDAD,
    VALOR_NORM,
    CONTRIBUCION_PP,
    -- Porcentaje del riesgo base explicado por esta variable
    CAST(100.0 * CONTRIBUCION_PP / NULLIF(TOTAL_ZONA, 0) AS DECIMAL(5,2)) AS PCT_DEL_RIESGO
FROM (
    SELECT
        c.*,
        ROW_NUMBER() OVER (PARTITION BY c.ZONA_ID ORDER BY c.CONTRIBUCION_PP DESC) AS ORDEN_FACTOR,
        SUM(c.CONTRIBUCION_PP) OVER (PARTITION BY c.ZONA_ID)                       AS TOTAL_ZONA
    FROM V_GEORISK_CONTRIBUCION c
)
WHERE ORDEN_FACTOR <= 5;


-- ---------------------------------------------------------------------
-- 6. Capa geografica para el mapa de riesgos
-- ---------------------------------------------------------------------
-- SAC necesita latitud/longitud numericas y una medida para el color.
-- Si el ambiente no habilita mapas, esta vista alimenta igual una tabla.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_MAPA AS
SELECT
    ZONA_ID,
    NOMBRE_ZONA,
    REGION,
    PROVINCIA,
    DISTRITO,
    LATITUD,
    LONGITUD,
    ALTITUD_MSNM,
    MINERAL_PRINCIPAL,
    FASE_PROYECTO,
    RIESGO_GLOBAL,
    RIESGO_GEOLOGICO,
    RIESGO_AMBIENTAL,
    RIESGO_SOCIAL,
    NIVEL_RIESGO,
    NIVEL_COLOR,
    NIVEL_ORDEN,
    FACTOR_CRITICO,
    POBLACION_AFECTADA,
    -- Tamano de burbuja proporcional a la exposicion social
    CASE WHEN POBLACION_AFECTADA > 0
         THEN CAST(LOG(10, POBLACION_AFECTADA) * 10 AS DECIMAL(6,2))
         ELSE 5 END                                              AS TAMANO_BURBUJA
FROM V_GEORISK_SCORING;


-- ---------------------------------------------------------------------
-- 7. Matriz riesgo vs atractivo (dispersion para priorizacion)
-- ---------------------------------------------------------------------
-- El reto pide priorizar zonas, no solo puntuarlas. Una zona de riesgo alto
-- puede seguir siendo prioritaria si su atractivo geologico es excepcional;
-- este cruce es el que suele decidir la cartera de exploracion.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_MATRIZ AS
SELECT
    s.ZONA_ID,
    s.NOMBRE_ZONA,
    s.REGION,
    s.MINERAL_PRINCIPAL,
    s.RIESGO_GLOBAL,
    s.NIVEL_RIESGO,
    s.NIVEL_COLOR,
    -- Atractivo: ley mineral y tonelaje normalizados a 0-100 (100 = mejor)
    CAST(
        0.60 * 100.0 * (LEAST(GREATEST(z.LEY_MINERAL_PCT, 0.20), 2.00) - 0.20) / 1.80
      + 0.40 * 100.0 * (LEAST(GREATEST(z.TONELAJE_ESTIMADO_MT, 10.0), 1000.0) - 10.0) / 990.0
        AS DECIMAL(5,2))                                         AS ATRACTIVO_GEOLOGICO,
    z.LEY_MINERAL_PCT,
    z.TONELAJE_ESTIMADO_MT,
    s.INVERSION_ACUMULADA_MUSD,
    -- Cuadrante de decision
    CASE
        WHEN s.RIESGO_GLOBAL <  50 AND
             (0.60 * (z.LEY_MINERAL_PCT - 0.20) / 1.80
            + 0.40 * (z.TONELAJE_ESTIMADO_MT - 10.0) / 990.0) >= 0.50 THEN 'Prioritaria'
        WHEN s.RIESGO_GLOBAL <  50                                    THEN 'Viable'
        WHEN (0.60 * (z.LEY_MINERAL_PCT - 0.20) / 1.80
            + 0.40 * (z.TONELAJE_ESTIMADO_MT - 10.0) / 990.0) >= 0.50 THEN 'Requiere mitigacion'
        ELSE 'Descartable'
    END                                                          AS CUADRANTE
FROM       V_GEORISK_SCORING   s
INNER JOIN V_GEORISK_ZONAS_BASE z ON z.ZONA_ID = s.ZONA_ID;


-- ---------------------------------------------------------------------
-- 8. Distribucion por nivel de riesgo (histograma)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_DISTRIBUCION AS
SELECT
    e.NIVEL_COD                                                  AS NIVEL_RIESGO,
    e.NIVEL_DESC,
    e.COLOR_HEX                                                  AS NIVEL_COLOR,
    e.ORDEN                                                      AS NIVEL_ORDEN,
    e.LIMITE_INF,
    e.LIMITE_SUP,
    COUNT(s.ZONA_ID)                                             AS N_ZONAS,
    CAST(100.0 * COUNT(s.ZONA_ID)
         / NULLIF((SELECT COUNT(*) FROM V_GEORISK_SCORING), 0) AS DECIMAL(5,2)) AS PCT_ZONAS,
    COALESCE(SUM(s.POBLACION_AFECTADA), 0)                       AS POBLACION_AFECTADA
FROM      GEORISK_PARAM_ESCALA e
LEFT JOIN V_GEORISK_SCORING    s ON s.NIVEL_RIESGO = e.NIVEL_COD
GROUP BY  e.NIVEL_COD, e.NIVEL_DESC, e.COLOR_HEX, e.ORDEN, e.LIMITE_INF, e.LIMITE_SUP;


-- ---------------------------------------------------------------------
-- 9. Documentacion viva del modelo
-- ---------------------------------------------------------------------
-- Expone las ponderaciones vigentes para mostrarlas en el dashboard y en la
-- presentacion: el jurado puede ver el modelo real, no una lamina aparte.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GEORISK_MODELO_DOC AS
SELECT
    d.DIMENSION_COD,
    d.DIMENSION_DESC,
    d.PESO                                        AS PESO_DIMENSION,
    si.SUBINDICE_COD,
    si.SUBINDICE_DESC,
    si.PESO                                       AS PESO_SUBINDICE,
    v.VARIABLE_COD,
    v.VARIABLE_DESC,
    v.UNIDAD,
    v.MIN_REF,
    v.MAX_REF,
    CASE v.SENTIDO WHEN 'D' THEN 'Mas valor = mas riesgo'
                   ELSE 'Mas valor = menos riesgo' END AS INTERPRETACION,
    v.PESO                                        AS PESO_VARIABLE,
    -- Peso efectivo sobre el riesgo global
    CAST(v.PESO * si.PESO * d.PESO AS DECIMAL(7,5)) AS PESO_EFECTIVO_GLOBAL
FROM       GEORISK_PARAM_VARIABLE  v
INNER JOIN GEORISK_PARAM_SUBINDICE si ON si.SUBINDICE_COD = v.SUBINDICE_COD
INNER JOIN GEORISK_PARAM_DIMENSION d  ON d.DIMENSION_COD  = si.DIMENSION_COD;
