-- =====================================================================================
-- CASO 06 - Carga de datos
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS. Requisito previo: 03-modelo-fisico.sql
--
-- La serie de tipo de cambio es SIMULADA pero mantiene las propiedades estructurales
-- de la serie real del BCRP: solo días hábiles, spread compra-venta, y variación diaria
-- acotada. Para usar la serie REAL, ver carga_bcrp_real.sql en esta misma carpeta.
-- =====================================================================================

SET search_path TO caso06;

TRUNCATE posicion_cambio_dia, saldo_me_dia, tipo_cambio_vigente, tipo_cambio_publicado,
         cat_calendario, cat_tipo_cambio, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc, es_moneda_local, decimales) VALUES
    ('PEN', 'Sol peruano',          TRUE,  2),
    ('USD', 'Dólar estadounidense', FALSE, 2),
    ('EUR', 'Euro',                 FALSE, 2);

INSERT INTO cat_tipo_cambio (tipo_tc_cod, tipo_tc_desc, fuente_cod, uso_contable) VALUES
    ('BANCARIO_COMPRA', 'Tipo de cambio bancario promedio - compra', 'BCRP', FALSE),
    ('BANCARIO_VENTA',  'Tipo de cambio bancario promedio - venta',  'BCRP', FALSE),
    ('CONTABLE_SBS',    'Tipo de cambio contable (cierre)',          'SBS',  TRUE),
    ('SUNAT_VENTA',     'Tipo de cambio SUNAT - venta (tributario)', 'SUNAT',FALSE);

-- =====================================================================================
-- 2. CALENDARIO 2026 con feriados nacionales del Perú
--    ⚠️ Lista REFERENCIAL con fines educativos. Los feriados se establecen por norma y
--    pueden variar (feriados largos, días no laborables del sector público).
--    Verificar en https://www.gob.pe/ antes de usar en producción.
-- =====================================================================================

INSERT INTO cat_calendario (fecha, anio, mes, periodo, dia_semana, es_fin_semana,
                            es_feriado, nombre_feriado, es_dia_habil, es_fin_mes)
SELECT  d::DATE,
        EXTRACT(YEAR  FROM d)::SMALLINT,
        EXTRACT(MONTH FROM d)::SMALLINT,
        TO_CHAR(d, 'YYYYMM'),
        EXTRACT(ISODOW FROM d)::SMALLINT,
        EXTRACT(ISODOW FROM d) >= 6,
        fer.nombre IS NOT NULL,
        fer.nombre,
        EXTRACT(ISODOW FROM d) < 6 AND fer.nombre IS NULL,
        d::DATE = (DATE_TRUNC('month', d) + INTERVAL '1 month - 1 day')::DATE
FROM        generate_series(DATE '2026-01-01', DATE '2026-12-31', INTERVAL '1 day') AS d
LEFT JOIN  (VALUES
        (DATE '2026-01-01', 'Año Nuevo'),
        (DATE '2026-04-02', 'Jueves Santo'),
        (DATE '2026-04-03', 'Viernes Santo'),
        (DATE '2026-05-01', 'Día del Trabajo'),
        (DATE '2026-06-29', 'San Pedro y San Pablo'),
        (DATE '2026-07-23', 'Día de la Fuerza Aérea'),
        (DATE '2026-07-28', 'Fiestas Patrias'),
        (DATE '2026-07-29', 'Fiestas Patrias'),
        (DATE '2026-08-06', 'Batalla de Junín'),
        (DATE '2026-08-30', 'Santa Rosa de Lima'),
        (DATE '2026-10-08', 'Combate de Angamos'),
        (DATE '2026-11-01', 'Todos los Santos'),
        (DATE '2026-12-08', 'Inmaculada Concepción'),
        (DATE '2026-12-09', 'Batalla de Ayacucho'),
        (DATE '2026-12-25', 'Navidad')
) AS fer(fecha, nombre) ON fer.fecha = d::DATE;

-- =====================================================================================
-- 3. TIPO DE CAMBIO PUBLICADO
--    SOLO se publica en días hábiles: esa es exactamente la característica que crea
--    los huecos que el modelo debe resolver.
-- =====================================================================================

-- USD: serie que oscila alrededor de 3.72 con deriva y estacionalidad determinísticas
INSERT INTO tipo_cambio_publicado (fecha, moneda_cod, tipo_tc_cod, valor, codigo_serie)
SELECT  c.fecha,
        'USD',
        t.tipo_tc_cod,
        ROUND((base.mid + t.ajuste)::NUMERIC, 6),
        t.codigo_serie
FROM        cat_calendario c
CROSS JOIN LATERAL (
        SELECT 3.720000
             + 0.045 * SIN((EXTRACT(DOY FROM c.fecha)::NUMERIC / 58.0))
             + 0.018 * COS((EXTRACT(DOY FROM c.fecha)::NUMERIC / 17.0))
             + (EXTRACT(DOY FROM c.fecha)::NUMERIC * 0.00012) AS mid
) AS base
CROSS JOIN (VALUES
        ('BANCARIO_COMPRA', -0.004000, 'PD04637PD'),
        ('BANCARIO_VENTA',   0.004000, 'PD04638PD'),
        ('CONTABLE_SBS',     0.002000, 'TC_CONTABLE'),
        ('SUNAT_VENTA',      0.005000, 'TC_SUNAT')
) AS t(tipo_tc_cod, ajuste, codigo_serie)
WHERE       c.es_dia_habil;

-- EUR: solo tipo contable, para demostrar que no todas las monedas tienen todas las series
INSERT INTO tipo_cambio_publicado (fecha, moneda_cod, tipo_tc_cod, valor, codigo_serie)
SELECT  c.fecha,
        'EUR',
        'CONTABLE_SBS',
        ROUND((4.050000
              + 0.060 * SIN((EXTRACT(DOY FROM c.fecha)::NUMERIC / 43.0))
              + (EXTRACT(DOY FROM c.fecha)::NUMERIC * 0.00009))::NUMERIC, 6),
        'TC_EUR_CONTABLE'
FROM    cat_calendario c
WHERE   c.es_dia_habil;

-- =====================================================================================
-- 4. TIPO DE CAMBIO VIGENTE (resolución de huecos con arrastre / LOCF)
--    Técnica: gaps-and-islands.
--      (a) malla completa   = calendario x moneda x tipo
--      (b) grupo de isla    = COUNT(valor) acumulado ordenado por fecha
--      (c) valor arrastrado = primer valor no nulo de cada isla
--    Se conserva la fecha de cotización original y los días de arrastre.
-- =====================================================================================

INSERT INTO tipo_cambio_vigente (fecha, moneda_cod, tipo_tc_cod, valor,
                                 fecha_cotizacion, origen_valor, dias_arrastre)
WITH combinaciones AS (
    SELECT DISTINCT moneda_cod, tipo_tc_cod FROM tipo_cambio_publicado
),
malla AS (
    SELECT  c.fecha, k.moneda_cod, k.tipo_tc_cod, p.valor, p.fecha AS fecha_pub
    FROM        cat_calendario c
    CROSS JOIN  combinaciones k
    LEFT JOIN   tipo_cambio_publicado p ON p.fecha       = c.fecha
                                       AND p.moneda_cod  = k.moneda_cod
                                       AND p.tipo_tc_cod = k.tipo_tc_cod
),
islas AS (
    SELECT  m.*,
            COUNT(m.valor) OVER (PARTITION BY m.moneda_cod, m.tipo_tc_cod
                                 ORDER BY m.fecha
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS isla
    FROM    malla m
),
arrastrado AS (
    SELECT  i.fecha, i.moneda_cod, i.tipo_tc_cod,
            FIRST_VALUE(i.valor)     OVER w AS valor,
            FIRST_VALUE(i.fecha_pub) OVER w AS fecha_cotizacion
    FROM    islas i
    WHERE   i.isla > 0     -- descarta los días anteriores a la primera cotización
    WINDOW  w AS (PARTITION BY i.moneda_cod, i.tipo_tc_cod, i.isla ORDER BY i.fecha)
)
SELECT  a.fecha, a.moneda_cod, a.tipo_tc_cod, a.valor, a.fecha_cotizacion,
        CASE WHEN a.fecha = a.fecha_cotizacion THEN 'PUBLICADO' ELSE 'ARRASTRE' END,
        (a.fecha - a.fecha_cotizacion)::SMALLINT
FROM    arrastrado a;

-- =====================================================================================
-- 5. SALDOS EN MONEDA EXTRANJERA (posiciones diarias sintéticas)
-- =====================================================================================

INSERT INTO saldo_me_dia (fecha, moneda_cod, cuenta_contable, naturaleza, saldo_me)
SELECT  c.fecha,
        m.moneda_cod,
        m.cuenta_contable,
        m.naturaleza,
        ROUND((m.base + m.amplitud * SIN(EXTRACT(DOY FROM c.fecha)::NUMERIC / m.divisor))::NUMERIC, 2)
FROM        cat_calendario c
CROSS JOIN (VALUES
        ('USD', '111101', 'ACTIVO',  18000000, 1200000, 29.0),   -- disponible
        ('USD', '141101', 'ACTIVO',  42000000, 2600000, 41.0),   -- colocaciones ME
        ('USD', '211101', 'PASIVO',  46000000, 3100000, 37.0),   -- depósitos ME
        ('USD', '231101', 'PASIVO',   9000000,  700000, 23.0),   -- adeudados ME
        ('EUR', '111102', 'ACTIVO',   2200000,  180000, 31.0),
        ('EUR', '211102', 'PASIVO',   1900000,  150000, 19.0)
) AS m(moneda_cod, cuenta_contable, naturaleza, base, amplitud, divisor);

-- =====================================================================================
-- 6. POSICIÓN DE CAMBIO DIARIA
--    posicion_me = activos - pasivos;  posicion_mn = posicion_me x TC contable del día
-- =====================================================================================

INSERT INTO posicion_cambio_dia (fecha, moneda_cod, activos_me, pasivos_me, posicion_me,
                                 tipo_cambio_cierre, posicion_mn)
SELECT  s.fecha,
        s.moneda_cod,
        s.activos,
        s.pasivos,
        s.activos - s.pasivos,
        v.valor,
        ROUND((s.activos - s.pasivos) * v.valor, 2)
FROM   (SELECT  fecha, moneda_cod,
                SUM(saldo_me) FILTER (WHERE naturaleza = 'ACTIVO') AS activos,
                SUM(saldo_me) FILTER (WHERE naturaleza = 'PASIVO') AS pasivos
        FROM    saldo_me_dia
        GROUP BY fecha, moneda_cod) s
JOIN    tipo_cambio_vigente v ON v.fecha       = s.fecha
                             AND v.moneda_cod  = s.moneda_cod
                             AND v.tipo_tc_cod = 'CONTABLE_SBS';

-- Resultado por diferencia de cambio: posición del día anterior x variación del TC
WITH variacion AS (
    SELECT  p.fecha, p.moneda_cod,
            LAG(p.posicion_me)        OVER (PARTITION BY p.moneda_cod ORDER BY p.fecha) AS pos_ant,
            p.tipo_cambio_cierre
          - LAG(p.tipo_cambio_cierre) OVER (PARTITION BY p.moneda_cod ORDER BY p.fecha) AS delta_tc
    FROM    posicion_cambio_dia p
)
UPDATE posicion_cambio_dia p
SET    resultado_cambio = ROUND(COALESCE(v.pos_ant, 0) * COALESCE(v.delta_tc, 0), 2)
FROM   variacion v
WHERE  v.fecha = p.fecha AND v.moneda_cod = p.moneda_cod;

-- =====================================================================================
-- 7. RESUMEN
-- =====================================================================================

SELECT 'calendario (dias)'            AS entidad, COUNT(*) AS filas FROM cat_calendario
UNION ALL SELECT '  de los cuales habiles',       COUNT(*) FROM cat_calendario WHERE es_dia_habil
UNION ALL SELECT '  de los cuales feriados',      COUNT(*) FROM cat_calendario WHERE es_feriado
UNION ALL SELECT 'tipo_cambio_publicado',         COUNT(*) FROM tipo_cambio_publicado
UNION ALL SELECT 'tipo_cambio_vigente',           COUNT(*) FROM tipo_cambio_vigente
UNION ALL SELECT '  de los cuales por arrastre',  COUNT(*) FROM tipo_cambio_vigente WHERE origen_valor = 'ARRASTRE'
UNION ALL SELECT 'saldo_me_dia',                  COUNT(*) FROM saldo_me_dia
UNION ALL SELECT 'posicion_cambio_dia',           COUNT(*) FROM posicion_cambio_dia
ORDER BY 1;
