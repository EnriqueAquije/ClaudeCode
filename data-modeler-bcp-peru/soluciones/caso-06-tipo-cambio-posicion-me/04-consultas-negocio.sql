-- =====================================================================================
-- CASO 06 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso06;

\echo '== PN-01: serie diaria de tipo de cambio con marca de arrastre (Semana Santa 2026) =='
SELECT  fecha, moneda_cod, es_dia_habil, tc_compra, tc_venta, tc_contable,
        spread, hubo_arrastre, dias_arrastre
FROM    vw_tipo_cambio_diario
WHERE   moneda_cod = 'USD'
  AND   fecha BETWEEN DATE '2026-03-30' AND DATE '2026-04-08'
ORDER BY fecha;

\echo ''
\echo '== PN-02: dias sin cotizacion y su motivo =='
SELECT  c.fecha,
        c.dia_semana,
        CASE WHEN c.es_feriado    THEN 'FERIADO: ' || c.nombre_feriado
             WHEN c.es_fin_semana THEN 'FIN DE SEMANA'
             ELSE 'SIN EXPLICACION - REVISAR CARGA' END AS motivo
FROM    cat_calendario c
WHERE   NOT EXISTS (SELECT 1 FROM tipo_cambio_publicado p
                    WHERE p.fecha = c.fecha AND p.moneda_cod = 'USD')
ORDER BY c.fecha
LIMIT 20;

\echo ''
\echo '== PN-03: resumen mensual del tipo de cambio y del spread =='
SELECT  c.periodo,
        COUNT(*)                                   AS dias_cotizados,
        ROUND(MIN(v.tc_contable), 4)               AS tc_min,
        ROUND(AVG(v.tc_contable), 4)               AS tc_promedio,
        ROUND(MAX(v.tc_contable), 4)               AS tc_max,
        ROUND(MAX(v.tc_contable) - MIN(v.tc_contable), 4) AS rango,
        ROUND(AVG(v.spread), 6)                    AS spread_promedio
FROM    vw_tipo_cambio_diario v
JOIN    cat_calendario c ON c.fecha = v.fecha
WHERE   v.moneda_cod = 'USD' AND NOT v.hubo_arrastre
GROUP BY c.periodo
ORDER BY c.periodo;

\echo ''
\echo '== PN-04: variacion diaria mas fuerte del tipo de cambio =='
SELECT  fecha, moneda_cod, tc_anterior, tc_contable, variacion_abs, variacion_pct
FROM    vw_variacion_cambiaria
WHERE   moneda_cod = 'USD' AND variacion_pct IS NOT NULL
ORDER BY ABS(variacion_pct) DESC
LIMIT 10;

\echo ''
\echo '== PN-05: posicion de cambio y resultado por diferencia de cambio (setiembre) =='
SELECT  p.fecha,
        p.moneda_cod,
        p.activos_me,
        p.pasivos_me,
        p.posicion_me,
        p.tipo_cambio_cierre,
        p.posicion_mn,
        p.resultado_cambio,
        CASE WHEN p.posicion_me > 0 THEN 'SOBRECOMPRA'
             WHEN p.posicion_me < 0 THEN 'SOBREVENTA'
             ELSE 'CALZADA' END AS situacion
FROM    posicion_cambio_dia p
WHERE   p.moneda_cod = 'USD'
  AND   p.fecha BETWEEN DATE '2026-09-01' AND DATE '2026-09-10'
ORDER BY p.fecha;

\echo ''
\echo '== PN-06: LA LECCION DEL CASO - el mismo saldo con tres tipos de cambio distintos =='
-- Un saldo de USD 1 000 000 valorizado al cierre del 2026-09-15.
WITH saldo AS (SELECT 1000000.00::NUMERIC AS monto_usd, DATE '2026-09-15' AS fecha)
SELECT  tc.tipo_tc_cod,
        tc.tipo_tc_desc,
        tc.fuente_cod,
        tc.uso_contable,
        v.valor                                     AS tipo_cambio,
        ROUND(s.monto_usd * v.valor, 2)             AS valor_en_soles,
        ROUND(s.monto_usd * v.valor
            - MIN(ROUND(s.monto_usd * v.valor, 2)) OVER (), 2) AS diferencia_vs_menor
FROM        saldo s
CROSS JOIN  tipo_cambio_vigente v
JOIN        cat_tipo_cambio tc ON tc.tipo_tc_cod = v.tipo_tc_cod
WHERE       v.fecha = s.fecha AND v.moneda_cod = 'USD'
ORDER BY    valor_en_soles;

\echo ''
\echo '   ^ Para UN millon de dolares la diferencia entre usar compra o venta es de miles de soles.'
\echo '     Por eso cat_tipo_cambio existe: el tipo de cambio NO es un solo numero por dia.'

\echo ''
\echo '== PN-07: uso de la funcion de conversion (una sola implementacion de la regla) =='
SELECT  s.fecha,
        s.moneda_cod,
        s.cuenta_contable,
        s.naturaleza,
        s.saldo_me,
        fn_convertir_a_mn(s.saldo_me, s.moneda_cod, s.fecha)                  AS saldo_mn_contable,
        fn_convertir_a_mn(s.saldo_me, s.moneda_cod, s.fecha, 'BANCARIO_VENTA') AS saldo_mn_venta
FROM    saldo_me_dia s
WHERE   s.fecha = DATE '2026-09-15'
ORDER BY s.moneda_cod, s.cuenta_contable;

\echo ''
\echo '== PN-08: periodos con mayor arrastre (feriados largos y fin de ano) =='
SELECT  v.fecha,
        v.fecha_cotizacion,
        v.dias_arrastre,
        v.valor,
        c.nombre_feriado
FROM    tipo_cambio_vigente v
JOIN    cat_calendario      c ON c.fecha = v.fecha
WHERE   v.moneda_cod  = 'USD'
  AND   v.tipo_tc_cod = 'CONTABLE_SBS'
  AND   v.dias_arrastre >= 3
ORDER BY v.dias_arrastre DESC, v.fecha
LIMIT 15;

\echo ''
\echo '== PN-09: resultado acumulado por diferencia de cambio, por mes =='
SELECT  c.periodo,
        p.moneda_cod,
        ROUND(AVG(p.posicion_me), 2)      AS posicion_promedio_me,
        ROUND(MIN(p.tipo_cambio_cierre), 4) AS tc_min,
        ROUND(MAX(p.tipo_cambio_cierre), 4) AS tc_max,
        SUM(p.resultado_cambio)           AS resultado_mes,
        SUM(SUM(p.resultado_cambio)) OVER (PARTITION BY p.moneda_cod
                                           ORDER BY c.periodo) AS resultado_acumulado
FROM    posicion_cambio_dia p
JOIN    cat_calendario      c ON c.fecha = p.fecha
GROUP BY c.periodo, p.moneda_cod
ORDER BY p.moneda_cod, c.periodo;

\echo ''
\echo '== PN-10: volatilidad mensual (desviacion estandar de la variacion diaria) =='
SELECT  c.periodo,
        v.moneda_cod,
        COUNT(*)                                   AS observaciones,
        ROUND(AVG(v.variacion_pct)::NUMERIC, 4)    AS variacion_promedio_pct,
        ROUND(STDDEV(v.variacion_pct)::NUMERIC, 4) AS volatilidad_pct,
        ROUND(MAX(ABS(v.variacion_pct))::NUMERIC, 4) AS maxima_variacion_pct
FROM    vw_variacion_cambiaria v
JOIN    cat_calendario c ON c.fecha = v.fecha
WHERE   v.variacion_pct IS NOT NULL AND c.es_dia_habil
GROUP BY c.periodo, v.moneda_cod
ORDER BY v.moneda_cod, c.periodo;
