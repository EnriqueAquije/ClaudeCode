-- =====================================================================================
-- CASO 02 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso02;

\echo '== PN-01: tasa de aprobacion por canal de venta =='
SELECT  cv.canal_cod,
        cv.canal_desc,
        cv.es_digital,
        COUNT(*)                                                          AS solicitudes,
        COUNT(*) FILTER (WHERE s.estado_sol_cod = 'DESEMBOLSADA')         AS desembolsadas,
        COUNT(*) FILTER (WHERE s.estado_sol_cod = 'RECHAZADA')            AS rechazadas,
        ROUND(100.0 * COUNT(*) FILTER (WHERE s.estado_sol_cod = 'DESEMBOLSADA')
              / COUNT(*), 2)                                              AS pct_desembolso
FROM    solicitud_credito s
JOIN    cat_canal_venta  cv ON cv.canal_cod = s.canal_cod
GROUP BY cv.canal_cod, cv.canal_desc, cv.es_digital
ORDER BY pct_desembolso DESC;

\echo ''
\echo '== PN-02: motivos de rechazo =='
SELECT  mr.motivo_cod,
        mr.motivo_desc,
        COUNT(*)                                          AS casos,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
        ROUND(AVG(e.score), 0)                            AS score_promedio,
        ROUND(AVG(e.ratio_cuota_ingreso), 4)              AS ratio_promedio
FROM        solicitud_credito s
JOIN        cat_motivo_rechazo mr ON mr.motivo_cod = s.motivo_cod
LEFT JOIN   evaluacion_crediticia e ON e.solicitud_id = s.solicitud_id
WHERE       s.estado_sol_cod = 'RECHAZADA'
GROUP BY    mr.motivo_cod, mr.motivo_desc
ORDER BY    casos DESC;

\echo ''
\echo '== PN-03: desembolsos por mes y tipo de credito =='
SELECT  TO_CHAR(c.fecha_desembolso, 'YYYY-MM')  AS mes,
        tc.tipo_credito_desc,
        COUNT(*)                                AS operaciones,
        SUM(c.monto_desembolsado)               AS monto_desembolsado,
        ROUND(AVG(c.monto_desembolsado), 2)     AS ticket_promedio,
        ROUND(AVG(c.tea_pct) * 100, 2)          AS tea_promedio_pct
FROM    credito c
JOIN    cat_tipo_credito tc ON tc.tipo_credito_cod = c.tipo_credito_cod
GROUP BY 1, 2
ORDER BY 1, 2;

\echo ''
\echo '== PN-04: cartera por clasificacion SBS en el ultimo periodo =='
WITH ultimo AS (SELECT MAX(periodo) AS periodo FROM deudor_clasificacion_mes)
SELECT  cl.clasificacion_cod,
        cl.clasificacion_desc,
        COUNT(*)                                                   AS deudores,
        SUM(dcm.saldo_capital)                                     AS saldo_capital,
        ROUND(100.0 * SUM(dcm.saldo_capital)
              / SUM(SUM(dcm.saldo_capital)) OVER (), 2)            AS pct_cartera,
        SUM(dcm.monto_provision)                                   AS provision_requerida
FROM        deudor_clasificacion_mes dcm
JOIN        ultimo u  ON u.periodo = dcm.periodo
JOIN        cat_clasificacion cl ON cl.clasificacion_cod = dcm.clasificacion_cod
GROUP BY    cl.clasificacion_cod, cl.clasificacion_desc, cl.orden_riesgo
ORDER BY    cl.orden_riesgo;

\echo ''
\echo '== PN-05: evolucion mensual de cartera atrasada y provisiones =='
SELECT  dcm.periodo,
        COUNT(*)                                                                    AS deudores,
        SUM(dcm.saldo_capital)                                                      AS cartera_total,
        SUM(dcm.saldo_capital) FILTER (WHERE dcm.clasificacion_cod <> '0')          AS cartera_no_normal,
        ROUND(100.0 * SUM(dcm.saldo_capital) FILTER (WHERE dcm.clasificacion_cod <> '0')
              / NULLIF(SUM(dcm.saldo_capital), 0), 2)                               AS pct_no_normal,
        SUM(dcm.monto_provision)                                                    AS provisiones,
        ROUND(100.0 * SUM(dcm.monto_provision)
              / NULLIF(SUM(dcm.saldo_capital), 0), 2)                               AS pct_cobertura
FROM    deudor_clasificacion_mes dcm
GROUP BY dcm.periodo
ORDER BY dcm.periodo;

\echo ''
\echo '== PN-06: matriz de transicion de clasificacion (agosto -> setiembre 2026) =='
-- Pregunta clásica de riesgos: ¿cuántos deudores empeoraron de categoría?
SELECT  ant.clasificacion_cod AS clasif_anterior,
        act.clasificacion_cod AS clasif_actual,
        COUNT(*)              AS deudores,
        SUM(act.saldo_capital) AS saldo,
        CASE
            WHEN act.clasificacion_cod > ant.clasificacion_cod THEN 'DETERIORO'
            WHEN act.clasificacion_cod < ant.clasificacion_cod THEN 'MEJORA'
            ELSE 'SE MANTIENE'
        END AS movimiento
FROM    deudor_clasificacion_mes ant
JOIN    deudor_clasificacion_mes act ON act.deudor_id = ant.deudor_id
                                    AND ant.periodo = '202608'
                                    AND act.periodo = '202609'
GROUP BY 1, 2
ORDER BY 1, 2;

\echo ''
\echo '== PN-07: creditos con cuotas vencidas y su mayor atraso =='
SELECT  c.num_credito,
        d.num_doc,
        d.ape_paterno || ', ' || d.nombres                              AS deudor,
        c.monto_desembolsado,
        COUNT(*) FILTER (WHERE cu.estado_cuota = 'VENCIDA')             AS cuotas_vencidas,
        SUM(cu.monto_cuota) FILTER (WHERE cu.estado_cuota = 'VENCIDA')  AS monto_vencido,
        MAX(DATE '2026-09-16' - cu.fecha_vencimiento)
            FILTER (WHERE cu.estado_cuota = 'VENCIDA')                  AS dias_max_atraso
FROM    credito c
JOIN    deudor d          ON d.deudor_id = c.deudor_id
JOIN    cronograma_cuota cu ON cu.credito_id = c.credito_id
GROUP BY c.num_credito, d.num_doc, d.ape_paterno, d.nombres, c.monto_desembolsado
HAVING  COUNT(*) FILTER (WHERE cu.estado_cuota = 'VENCIDA') > 0
ORDER BY dias_max_atraso DESC
LIMIT 15;

\echo ''
\echo '== PN-08: analisis de cosecha (vintage) por mes de desembolso =='
-- Mide si las colocaciones de un mes se deterioran más que las de otro.
SELECT  TO_CHAR(c.fecha_desembolso, 'YYYY-MM')                              AS cosecha,
        COUNT(DISTINCT c.credito_id)                                        AS creditos,
        SUM(c.monto_desembolsado)                                           AS monto_colocado,
        COUNT(DISTINCT c.credito_id) FILTER (
            WHERE EXISTS (SELECT 1 FROM cronograma_cuota cu
                          WHERE cu.credito_id = c.credito_id
                            AND cu.estado_cuota = 'VENCIDA'))               AS creditos_con_mora,
        ROUND(100.0 * COUNT(DISTINCT c.credito_id) FILTER (
            WHERE EXISTS (SELECT 1 FROM cronograma_cuota cu
                          WHERE cu.credito_id = c.credito_id
                            AND cu.estado_cuota = 'VENCIDA'))
              / COUNT(DISTINCT c.credito_id), 2)                            AS pct_mora
FROM    credito c
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '== PN-09: tiempo de ciclo de la solicitud (ingreso -> desembolso) =='
SELECT  cv.canal_cod,
        COUNT(*)                                                              AS solicitudes,
        ROUND(AVG(EXTRACT(EPOCH FROM (fin.fecha_hora - ini.fecha_hora)) / 86400)::NUMERIC, 2) AS dias_promedio,
        ROUND(MIN(EXTRACT(EPOCH FROM (fin.fecha_hora - ini.fecha_hora)) / 86400)::NUMERIC, 2) AS dias_min,
        ROUND(MAX(EXTRACT(EPOCH FROM (fin.fecha_hora - ini.fecha_hora)) / 86400)::NUMERIC, 2) AS dias_max
FROM    solicitud_credito s
JOIN    cat_canal_venta cv ON cv.canal_cod = s.canal_cod
JOIN    solicitud_estado_hist ini ON ini.solicitud_id = s.solicitud_id AND ini.estado_sol_cod = 'INGRESADA'
JOIN    solicitud_estado_hist fin ON fin.solicitud_id = s.solicitud_id AND fin.estado_sol_cod = 'DESEMBOLSADA'
GROUP BY cv.canal_cod
ORDER BY dias_promedio;

\echo ''
\echo '== PN-10: simulacion de cambio normativo (el valor del modelo parametrizado) =='
-- ¿Qué pasaría si la SBS endureciera el tramo de CPP de 9-30 a 5-30 días?
-- No se toca ni el modelo ni el código: se compara contra un tramo alternativo.
SELECT  dcm.periodo,
        COUNT(*) FILTER (WHERE dcm.clasificacion_cod = '0')        AS normal_hoy,
        COUNT(*) FILTER (WHERE dcm.dias_atraso BETWEEN 5 AND 8)    AS pasarian_a_cpp,
        ROUND(SUM(dcm.saldo_capital) FILTER (WHERE dcm.dias_atraso BETWEEN 5 AND 8)
              * (0.05 - 0.01), 2)                                  AS provision_adicional_estimada
FROM    deudor_clasificacion_mes dcm
GROUP BY dcm.periodo
ORDER BY dcm.periodo;
