-- =====================================================================================
-- CASO 01 - Consultas de negocio (PN-01 a PN-08)
-- Ejecución: psql -d bcp_lab -f 04-consultas-negocio.sql
-- =====================================================================================

SET search_path TO caso01;

\echo '== PN-01: saldo total de captaciones por producto y moneda =='
SELECT  p.familia_cod,
        p.producto_cod,
        p.producto_nombre,
        c.moneda_cod,
        COUNT(*)                                        AS cant_cuentas,
        COUNT(*) FILTER (WHERE c.estado_cta_cod = 'ACT') AS cant_activas,
        SUM(c.saldo_contable)                           AS saldo_total,
        ROUND(AVG(c.saldo_contable), 2)                 AS saldo_promedio
FROM    cuenta   c
JOIN    producto p ON p.producto_id = c.producto_id
GROUP BY p.familia_cod, p.producto_cod, p.producto_nombre, c.moneda_cod
ORDER BY saldo_total DESC;

\echo ''
\echo '== PN-02: top 10 clientes por saldo consolidado (solo titulares principales) =='
-- Nota de modelado: se consolida por TITULAR. Si se contara también al mancomunado,
-- el mismo saldo se contaría dos veces. La definición debe estar en el glosario.
SELECT  cl.cliente_id,
        cl.tipo_doc_cod,
        cl.num_doc,
        cl.ape_paterno || ' ' || COALESCE(cl.ape_materno, '') || ', ' || cl.nombres AS cliente,
        COUNT(DISTINCT c.cuenta_id)                                              AS cant_cuentas,
        SUM(CASE WHEN c.moneda_cod = 'PEN' THEN c.saldo_contable ELSE 0 END)     AS saldo_pen,
        SUM(CASE WHEN c.moneda_cod = 'USD' THEN c.saldo_contable ELSE 0 END)     AS saldo_usd
FROM        cuenta_titular ct
JOIN        cuenta  c  ON c.cuenta_id  = ct.cuenta_id
JOIN        cliente cl ON cl.cliente_id = ct.cliente_id
WHERE       ct.rol_cod = 'TITULAR'
  AND       ct.fecha_hasta IS NULL
GROUP BY    cl.cliente_id, cl.tipo_doc_cod, cl.num_doc, cl.ape_paterno, cl.ape_materno, cl.nombres
-- OJO: no se suma PEN + USD. Sumar monedas distintas es un error de negocio;
-- para consolidar hace falta el tipo de cambio con fecha -> eso es el CASO 06.
ORDER BY    SUM(CASE WHEN c.moneda_cod = 'PEN' THEN c.saldo_contable ELSE 0 END) DESC
LIMIT 10;

\echo ''
\echo '== PN-03: movimientos por canal y mes (cantidad y monto) =='
SELECT  DATE_TRUNC('month', m.fecha_contable)::DATE AS mes,
        ca.canal_cod,
        ca.canal_desc,
        COUNT(*)                                    AS cant_movimientos,
        SUM(m.monto)                                AS monto_bruto,
        SUM(m.monto_con_signo)                      AS monto_neto
FROM    movimiento m
JOIN    cat_canal  ca ON ca.canal_cod = m.canal_cod
GROUP BY 1, 2, 3
ORDER BY 1, cant_movimientos DESC;

\echo ''
\echo '== PN-04: cuentas activas sin movimientos DEL CLIENTE en los ultimos 90 dias =='
-- Trampa del caso: comisiones, ITF e intereses los origina el BANCO (es_cliente = FALSE).
-- Si no se filtran, ninguna cuenta aparece como inactiva.
WITH fecha_ref AS (
    SELECT MAX(fecha_contable) AS hoy FROM movimiento
),
ult_mov_cliente AS (
    SELECT  m.cuenta_id,
            MAX(m.fecha_contable) AS ultima_fecha
    FROM    movimiento m
    JOIN    cat_canal  ca ON ca.canal_cod = m.canal_cod
    JOIN    cat_tipo_movimiento tm ON tm.tipo_mov_cod = m.tipo_mov_cod
    WHERE   ca.es_cliente = TRUE
      AND   tm.es_operacion_cliente = TRUE
    GROUP BY m.cuenta_id
)
SELECT  c.cuenta_id,
        c.num_cuenta,
        c.moneda_cod,
        c.saldo_contable,
        u.ultima_fecha                       AS ultimo_movimiento_cliente,
        (f.hoy - u.ultima_fecha)             AS dias_sin_actividad
FROM        cuenta c
CROSS JOIN  fecha_ref f
LEFT JOIN   ult_mov_cliente u ON u.cuenta_id = c.cuenta_id
WHERE       c.estado_cta_cod = 'ACT'
  AND      (u.ultima_fecha IS NULL OR f.hoy - u.ultima_fecha > 90)
ORDER BY    dias_sin_actividad DESC NULLS FIRST
LIMIT 20;

\echo ''
\echo '== PN-05: saldo promedio diario de junio 2026 (base del calculo de intereses) =='
-- Técnica: LOCF (last observation carried forward) con gaps-and-islands.
-- El saldo de un día sin movimientos es el del último día con movimiento.
WITH dias AS (
    SELECT generate_series(DATE '2026-06-01', DATE '2026-06-30', INTERVAL '1 day')::DATE AS dia
),
saldo_cierre_dia AS (
    SELECT DISTINCT ON (cuenta_id, fecha_contable)
           cuenta_id, fecha_contable, saldo_posterior
    FROM   movimiento
    ORDER  BY cuenta_id, fecha_contable, fecha_operacion DESC, movimiento_id DESC
),
malla AS (
    SELECT  c.cuenta_id,
            d.dia,
            s.saldo_posterior
    FROM        cuenta c
    CROSS JOIN  dias d
    LEFT JOIN   saldo_cierre_dia s ON s.cuenta_id = c.cuenta_id AND s.fecha_contable = d.dia
    WHERE       c.estado_cta_cod = 'ACT'
),
islas AS (
    SELECT  cuenta_id, dia, saldo_posterior,
            COUNT(saldo_posterior) OVER (PARTITION BY cuenta_id ORDER BY dia) AS grupo
    FROM    malla
),
saldo_diario AS (
    SELECT  cuenta_id, dia,
            COALESCE(
                FIRST_VALUE(saldo_posterior) OVER (PARTITION BY cuenta_id, grupo ORDER BY dia),
                0
            ) AS saldo_dia
    FROM    islas
)
SELECT  sd.cuenta_id,
        c.num_cuenta,
        c.moneda_cod,
        ROUND(AVG(sd.saldo_dia), 2)                       AS saldo_promedio_junio,
        ROUND(AVG(sd.saldo_dia) * p.trea_pct / 12, 2)     AS interes_estimado_mes
FROM    saldo_diario sd
JOIN    cuenta   c ON c.cuenta_id  = sd.cuenta_id
JOIN    producto p ON p.producto_id = c.producto_id
GROUP BY sd.cuenta_id, c.num_cuenta, c.moneda_cod, p.trea_pct
ORDER BY saldo_promedio_junio DESC
LIMIT 15;

\echo ''
\echo '== PN-06: oficinas con mayor captacion =='
SELECT  o.oficina_cod,
        o.oficina_nombre,
        u.departamento,
        u.provincia,
        COUNT(c.cuenta_id)                                                   AS cant_cuentas,
        SUM(CASE WHEN c.moneda_cod = 'PEN' THEN c.saldo_contable ELSE 0 END) AS captacion_pen,
        SUM(CASE WHEN c.moneda_cod = 'USD' THEN c.saldo_contable ELSE 0 END) AS captacion_usd
FROM    oficina    o
JOIN    cat_ubigeo u ON u.ubigeo = o.ubigeo
LEFT JOIN cuenta   c ON c.oficina_id = o.oficina_id
GROUP BY o.oficina_cod, o.oficina_nombre, u.departamento, u.provincia
ORDER BY captacion_pen DESC
LIMIT 10;

\echo ''
\echo '== PN-07: cuadre saldo contable vs. suma de movimientos (debe devolver 0 filas) =='
SELECT  c.cuenta_id,
        c.num_cuenta,
        c.saldo_contable,
        COALESCE(m.suma_movimientos, 0)                          AS suma_movimientos,
        c.saldo_contable - COALESCE(m.suma_movimientos, 0)       AS diferencia
FROM        cuenta c
LEFT JOIN  (SELECT cuenta_id, SUM(monto_con_signo) AS suma_movimientos
            FROM   movimiento GROUP BY cuenta_id) m ON m.cuenta_id = c.cuenta_id
WHERE       c.saldo_contable <> COALESCE(m.suma_movimientos, 0);

\echo ''
\echo '== PN-08: movimientos extornados e impacto neto =='
SELECT  orig.movimiento_id      AS mov_original,
        orig.num_operacion      AS op_original,
        orig.tipo_mov_cod       AS tipo_original,
        orig.monto              AS monto_original,
        ext.movimiento_id       AS mov_extorno,
        ext.fecha_contable      AS fecha_extorno,
        orig.monto_con_signo + ext.monto_con_signo AS impacto_neto
FROM    movimiento ext
JOIN    movimiento orig ON orig.movimiento_id = ext.movimiento_extornado_id
WHERE   ext.es_extorno = TRUE
ORDER BY ext.movimiento_id
LIMIT 15;

\echo ''
\echo '== Resumen: impacto total de extornos =='
SELECT  COUNT(*)                          AS cant_extornos,
        SUM(ext.monto)                    AS monto_extornado,
        SUM(orig.monto_con_signo + ext.monto_con_signo) AS impacto_neto_total
FROM    movimiento ext
JOIN    movimiento orig ON orig.movimiento_id = ext.movimiento_extornado_id
WHERE   ext.es_extorno = TRUE;
