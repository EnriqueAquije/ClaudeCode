-- =====================================================================================
-- CASO 03 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso03;

\echo '== PN-01: segmentacion por perfil de pago y periodo =='
SELECT  periodo,
        perfil_pago,
        COUNT(*)                                                   AS cuentas,
        SUM(saldo_actual)                                          AS saldo_total,
        ROUND(AVG(pct_utilizacion), 2)                             AS utilizacion_promedio
FROM    vw_utilizacion_linea
GROUP BY periodo, perfil_pago
ORDER BY periodo, saldo_total DESC;

\echo ''
\echo '== PN-02: ingresos financieros del producto (intereses y comisiones) =='
SELECT  t.periodo_cargo                              AS periodo,
        tt.tipo_trx_desc,
        COUNT(*)                                     AS operaciones,
        SUM(t.monto)                                 AS monto
FROM    transaccion t
JOIN    cat_tipo_transaccion tt ON tt.tipo_trx_cod = t.tipo_trx_cod
WHERE   t.tipo_trx_cod IN ('INT','COM')
GROUP BY t.periodo_cargo, tt.tipo_trx_desc
ORDER BY 1, 2;

\echo ''
\echo '== PN-03: consumo por rubro (top 10) =='
SELECT  r.rubro_cod,
        r.rubro_desc,
        COUNT(*)                                                    AS transacciones,
        SUM(t.monto)                                                AS monto_total,
        ROUND(AVG(t.monto), 2)                                      AS ticket_promedio,
        ROUND(100.0 * SUM(t.monto) / SUM(SUM(t.monto)) OVER (), 2)  AS pct_participacion
FROM    transaccion t
JOIN    cat_rubro    r ON r.rubro_cod = t.rubro_cod
WHERE   t.tipo_trx_cod IN ('CON','CUO')
GROUP BY r.rubro_cod, r.rubro_desc
ORDER BY monto_total DESC;

\echo ''
\echo '== PN-04: penetracion de las compras en cuotas =='
SELECT  t.periodo_cargo                                                      AS periodo_compra,
        COUNT(*) FILTER (WHERE t.tipo_trx_cod = 'CUO')                       AS compras_en_cuotas,
        COUNT(*) FILTER (WHERE t.tipo_trx_cod = 'CON')                       AS compras_contado,
        ROUND(100.0 * COUNT(*) FILTER (WHERE t.tipo_trx_cod = 'CUO')
              / NULLIF(COUNT(*) FILTER (WHERE t.tipo_trx_cod IN ('CON','CUO')), 0), 2) AS pct_cuotas,
        ROUND(AVG(t.monto) FILTER (WHERE t.tipo_trx_cod = 'CUO'), 2)         AS ticket_cuotas,
        ROUND(AVG(t.monto) FILTER (WHERE t.tipo_trx_cod = 'CON'), 2)         AS ticket_contado
FROM    transaccion t
WHERE   t.tipo_trx_cod IN ('CON','CUO')
GROUP BY t.periodo_cargo
ORDER BY 1;

\echo ''
\echo '== PN-05: deuda futura ya comprometida en cuotas (backlog) =='
-- Lo que el cliente YA debe pero aun no se le ha facturado. Crítico para proyectar ingresos.
SELECT  tc.periodo_cargo                        AS periodo_futuro,
        COUNT(DISTINCT t.cuenta_tj_id)          AS cuentas,
        COUNT(*)                                AS cuotas_por_vencer,
        SUM(tc.monto_capital)                   AS capital_comprometido,
        SUM(tc.monto_interes)                   AS interes_proyectado,
        SUM(tc.monto_cuota)                     AS total_a_facturar
FROM    transaccion_cuota tc
JOIN    transaccion t ON t.transaccion_id = tc.transaccion_id
WHERE   tc.periodo_cargo > '202609'
GROUP BY tc.periodo_cargo
ORDER BY 1;

\echo ''
\echo '== PN-06: cuentas que exceden la linea aprobada =='
SELECT  ec.periodo,
        COUNT(*)                                                       AS cuentas_sobre_linea,
        SUM(ec.saldo_actual - ec.linea_aprobada)                       AS exceso_total,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY ec.periodo), 2) AS pct
FROM    estado_cuenta ec
WHERE   ec.saldo_actual > ec.linea_aprobada
GROUP BY ec.periodo
ORDER BY ec.periodo;

\echo ''
\echo '== PN-07: mora - cuentas que no cubrieron el pago minimo =='
SELECT  ec.periodo,
        COUNT(*) FILTER (WHERE ec.dias_atraso > 0)                                  AS cuentas_en_mora,
        SUM(ec.saldo_actual) FILTER (WHERE ec.dias_atraso > 0)                      AS saldo_en_mora,
        ROUND(100.0 * SUM(ec.saldo_actual) FILTER (WHERE ec.dias_atraso > 0)
              / NULLIF(SUM(ec.saldo_actual), 0), 2)                                 AS pct_cartera_en_mora,
        COUNT(*) FILTER (WHERE ec.dias_atraso > 30)                                 AS mora_mayor_30d
FROM    estado_cuenta ec
GROUP BY ec.periodo
ORDER BY ec.periodo;

\echo ''
\echo '== PN-08: cuadre del estado de cuenta contra las transacciones (debe dar 0 filas) =='
WITH consumo_trx AS (
    SELECT cuenta_tj_id, periodo_cargo AS periodo, SUM(monto) AS monto
    FROM   transaccion WHERE tipo_trx_cod IN ('CON','DISP')
    GROUP  BY 1, 2
    UNION ALL
    SELECT t.cuenta_tj_id, tc.periodo_cargo, SUM(tc.monto_cuota)
    FROM   transaccion_cuota tc JOIN transaccion t ON t.transaccion_id = tc.transaccion_id
    GROUP  BY 1, 2
),
consumo AS (SELECT cuenta_tj_id, periodo, SUM(monto) AS monto FROM consumo_trx GROUP BY 1, 2)
SELECT  ec.cuenta_tj_id, ec.periodo, ec.total_consumos, COALESCE(c.monto, 0) AS segun_transacciones,
        ec.total_consumos - COALESCE(c.monto, 0) AS diferencia
FROM        estado_cuenta ec
LEFT JOIN   consumo c ON c.cuenta_tj_id = ec.cuenta_tj_id AND c.periodo = ec.periodo
WHERE       ec.total_consumos <> COALESCE(c.monto, 0);

\echo ''
\echo '== PN-09: evolucion de la linea de credito (SCD2) =='
SELECT  lh.cuenta_tj_id,
        ct.num_cuenta_tj,
        lh.fecha_desde,
        lh.fecha_hasta,
        lh.linea_anterior,
        lh.linea_nueva,
        lh.motivo,
        CASE WHEN lh.linea_anterior IS NOT NULL
             THEN ROUND(100.0 * (lh.linea_nueva - lh.linea_anterior) / lh.linea_anterior, 1)
        END AS pct_variacion
FROM    linea_credito_hist lh
JOIN    cuenta_tarjeta     ct ON ct.cuenta_tj_id = lh.cuenta_tj_id
WHERE   lh.motivo <> 'APERTURA'
ORDER BY lh.cuenta_tj_id
LIMIT 15;

\echo ''
\echo '== PN-10: estado de cuenta completo de una tarjeta (simulacion de la cartilla) =='
SELECT  ec.periodo,
        ec.fecha_cierre,
        ec.fecha_vencimiento,
        ec.saldo_anterior,
        ec.total_consumos,
        ec.total_cargos,
        ec.total_pagos,
        ec.saldo_actual,
        ec.pago_minimo,
        ec.linea_disponible,
        ec.monto_pagado,
        ec.dias_atraso
FROM    estado_cuenta ec
WHERE   ec.cuenta_tj_id = 9
ORDER BY ec.periodo;
