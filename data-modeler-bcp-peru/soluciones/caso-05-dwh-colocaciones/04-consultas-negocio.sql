-- =====================================================================================
-- CASO 05 - Consultas de negocio sobre el modelo dimensional
-- =====================================================================================

SET search_path TO caso05;

\echo '== PN-01: captaciones por mes, familia de producto y moneda =='
SELECT  t.periodo,
        p.familia_cod,
        p.moneda_cod,
        COUNT(*)                         AS cant_cuentas,
        SUM(f.saldo_fin_mes)             AS saldo_fin_mes,
        SUM(f.saldo_promedio)            AS saldo_promedio_total
FROM    fact_saldo_captacion_mes f
JOIN    dim_tiempo   t ON t.tiempo_sk   = f.tiempo_sk
JOIN    dim_producto p ON p.producto_sk = f.producto_sk
GROUP BY t.periodo, p.familia_cod, p.moneda_cod
ORDER BY t.periodo, saldo_fin_mes DESC;

\echo ''
\echo '== PN-02: evolucion del saldo por macro region =='
SELECT  t.periodo,
        u.macro_region,
        COUNT(DISTINCT f.cuenta_id_origen) AS cuentas,
        SUM(f.saldo_fin_mes)               AS saldo,
        ROUND(100.0 * SUM(f.saldo_fin_mes)
              / NULLIF(SUM(SUM(f.saldo_fin_mes)) OVER (PARTITION BY t.periodo), 0), 2) AS pct_del_mes
FROM    fact_saldo_captacion_mes f
JOIN    dim_tiempo  t ON t.tiempo_sk  = f.tiempo_sk
JOIN    dim_oficina o ON o.oficina_sk = f.oficina_sk
JOIN    dim_ubigeo  u ON u.ubigeo_sk  = o.ubigeo_sk
GROUP BY t.periodo, u.macro_region
ORDER BY t.periodo, saldo DESC;

\echo ''
\echo '== PN-03: ranking de departamentos por captacion (periodo de referencia) =='
-- OJO, trampa real: MAX(periodo) NO siempre es el periodo representativo. Aqui el ultimo
-- mes solo contiene los movimientos de cierre de cuentas canceladas. El periodo de
-- referencia es el ultimo con volumen significativo. Documentarlo evita reportes absurdos.
WITH periodos_validos AS (
    SELECT t.periodo
    FROM   dim_tiempo t
    JOIN   fact_saldo_captacion_mes f ON f.tiempo_sk = t.tiempo_sk
    GROUP  BY t.periodo
    HAVING COUNT(*) >= 100
),
ultimo AS (SELECT MAX(periodo) AS periodo FROM periodos_validos)
SELECT  u.departamento,
        u.macro_region,
        COUNT(*)                                             AS cuentas,
        SUM(f.saldo_fin_mes)                                 AS saldo,
        RANK() OVER (ORDER BY SUM(f.saldo_fin_mes) DESC)     AS ranking
FROM    fact_saldo_captacion_mes f
JOIN    dim_tiempo  t ON t.tiempo_sk  = f.tiempo_sk
JOIN    ultimo ul ON ul.periodo = t.periodo
JOIN    dim_oficina o ON o.oficina_sk = f.oficina_sk
JOIN    dim_ubigeo  u ON u.ubigeo_sk  = o.ubigeo_sk
GROUP BY u.departamento, u.macro_region
ORDER BY ranking;

\echo ''
\echo '== PN-04: LA LECCION DEL SCD2 - segmento historico vs. segmento actual =='
-- Misma pregunta, dos respuestas. La diferencia es el error mas caro del modelado analitico.
\echo '-- (a) CORRECTO: atribuye cada movimiento al segmento que el cliente tenia ESE MES'
SELECT  t.periodo,
        c.segmento_cod,
        COUNT(*)      AS movimientos,
        SUM(f.monto)  AS monto
FROM    fact_movimiento f
JOIN    dim_tiempo  t ON t.tiempo_sk  = f.tiempo_sk
JOIN    dim_cliente c ON c.cliente_sk = f.cliente_sk     -- <- la SK ya apunta a la version correcta
WHERE   t.periodo IN ('202605','202606')
GROUP BY t.periodo, c.segmento_cod
ORDER BY t.periodo, monto DESC;

\echo ''
\echo '-- (b) INCORRECTO: reescribe la historia usando el segmento de HOY'
SELECT  t.periodo,
        cact.segmento_cod AS segmento_actual,
        COUNT(*)          AS movimientos,
        SUM(f.monto)      AS monto
FROM    fact_movimiento f
JOIN    dim_tiempo  t ON t.tiempo_sk  = f.tiempo_sk
JOIN    dim_cliente c ON c.cliente_sk = f.cliente_sk
JOIN    dim_cliente cact ON cact.tipo_doc_cod = c.tipo_doc_cod
                        AND cact.num_doc      = c.num_doc
                        AND cact.es_vigente                  -- <- el error: version actual
WHERE   t.periodo IN ('202605','202606')
GROUP BY t.periodo, cact.segmento_cod
ORDER BY t.periodo, monto DESC;

\echo ''
\echo '== PN-05: cartera de colocaciones por clasificacion SBS y region =='
SELECT  t.periodo,
        u.macro_region,
        f.clasificacion_cod,
        COUNT(*)                  AS deudores,
        SUM(f.saldo_capital)      AS saldo_capital,
        SUM(f.monto_provision)    AS provision
FROM    fact_colocacion_mes f
JOIN    dim_tiempo  t ON t.tiempo_sk  = f.tiempo_sk
JOIN    dim_cliente c ON c.cliente_sk = f.cliente_sk
JOIN    dim_ubigeo  u ON u.ubigeo_sk  = c.ubigeo_sk
GROUP BY t.periodo, u.macro_region, f.clasificacion_cod
ORDER BY t.periodo, u.macro_region, f.clasificacion_cod;

\echo ''
\echo '== PN-06: el valor de la dimension CONFORMADA - vision 360 del cliente =='
-- Solo es posible porque dim_cliente y dim_producto sirven a AMBOS hechos.
SELECT  c.segmento_cod,
        COUNT(DISTINCT c.cliente_sk) FILTER (WHERE cap.cliente_sk IS NOT NULL)  AS con_captacion,
        COUNT(DISTINCT c.cliente_sk) FILTER (WHERE col.cliente_sk IS NOT NULL)  AS con_colocacion,
        COUNT(DISTINCT c.cliente_sk) FILTER (WHERE cap.cliente_sk IS NOT NULL
                                               AND col.cliente_sk IS NOT NULL)  AS con_ambos,
        COALESCE(SUM(cap.saldo), 0)                                             AS saldo_captacion,
        COALESCE(SUM(col.saldo), 0)                                             AS saldo_colocacion
FROM        dim_cliente c
LEFT JOIN  (SELECT cliente_sk, SUM(saldo_fin_mes) AS saldo
            FROM   fact_saldo_captacion_mes GROUP BY cliente_sk) cap ON cap.cliente_sk = c.cliente_sk
LEFT JOIN  (SELECT cliente_sk, SUM(saldo_capital) AS saldo
            FROM   fact_colocacion_mes GROUP BY cliente_sk) col ON col.cliente_sk = c.cliente_sk
WHERE       c.es_vigente
GROUP BY    c.segmento_cod
ORDER BY    con_ambos DESC;

\echo ''
\echo '== PN-07: canales digitales vs. presenciales =='
SELECT  t.periodo,
        CASE WHEN ca.es_digital THEN 'DIGITAL' ELSE 'PRESENCIAL' END AS tipo_canal,
        COUNT(*)                                                     AS movimientos,
        SUM(f.monto)                                                 AS monto,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY t.periodo), 2) AS pct_operaciones
FROM    fact_movimiento f
JOIN    dim_tiempo t  ON t.tiempo_sk = f.tiempo_sk
JOIN    dim_canal  ca ON ca.canal_sk = f.canal_sk
GROUP BY t.periodo, ca.es_digital
ORDER BY t.periodo, tipo_canal;

\echo ''
\echo '== PN-08: MEDIDA SEMIADITIVA - por que NO se suman saldos entre meses =='
SELECT  'CORRECTO: saldo del periodo de referencia' AS enfoque,
        SUM(f.saldo_fin_mes)                       AS valor
FROM    fact_saldo_captacion_mes f
JOIN    dim_tiempo t ON t.tiempo_sk = f.tiempo_sk
WHERE   t.periodo = (SELECT MAX(x.periodo) FROM (
                        SELECT t2.periodo
                        FROM   dim_tiempo t2
                        JOIN   fact_saldo_captacion_mes f2 ON f2.tiempo_sk = t2.tiempo_sk
                        GROUP  BY t2.periodo HAVING COUNT(*) >= 100) x)
UNION ALL
SELECT  'CORRECTO: promedio mensual del saldo',
        ROUND(AVG(mes.saldo), 2)
FROM   (SELECT t.periodo, SUM(f.saldo_fin_mes) AS saldo
        FROM   fact_saldo_captacion_mes f
        JOIN   dim_tiempo t ON t.tiempo_sk = f.tiempo_sk
        GROUP  BY t.periodo) mes
UNION ALL
SELECT  'INCORRECTO: sumar el saldo de todos los meses',
        SUM(f.saldo_fin_mes)
FROM    fact_saldo_captacion_mes f;

\echo ''
\echo '   ^ La tercera cifra NO significa nada: suma el mismo dinero tantas veces como meses hay.'
\echo '     Por eso el saldo es una MEDIDA SEMIADITIVA y debe documentarse como tal.'

\echo ''
\echo '== PN-09: top 10 clientes por saldo de captacion (ultimo periodo) =='
WITH tiempos_validos AS (
    SELECT t.tiempo_sk
    FROM   dim_tiempo t
    JOIN   fact_saldo_captacion_mes f ON f.tiempo_sk = t.tiempo_sk
    GROUP  BY t.tiempo_sk
    HAVING COUNT(*) >= 100
),
ultimo AS (SELECT MAX(tiempo_sk) AS tiempo_sk FROM tiempos_validos)
SELECT  c.num_doc,
        c.nombre_completo,
        c.segmento_cod,
        c.rango_edad,
        u.departamento,
        COUNT(*)              AS cuentas,
        SUM(f.saldo_fin_mes)  AS saldo
FROM    fact_saldo_captacion_mes f
JOIN    ultimo ul ON ul.tiempo_sk = f.tiempo_sk
JOIN    dim_cliente c ON c.cliente_sk = f.cliente_sk
JOIN    dim_ubigeo  u ON u.ubigeo_sk  = c.ubigeo_sk
GROUP BY c.num_doc, c.nombre_completo, c.segmento_cod, c.rango_edad, u.departamento
ORDER BY saldo DESC
LIMIT 10;

\echo ''
\echo '== PN-10: cuadre DWH contra los sistemas fuente (debe dar diferencia 0) =='
SELECT  'Movimientos (cantidad)' AS concepto,
        (SELECT COUNT(*) FROM caso01.movimiento) AS origen,
        (SELECT COUNT(*) FROM fact_movimiento)   AS dwh,
        (SELECT COUNT(*) FROM caso01.movimiento) - (SELECT COUNT(*) FROM fact_movimiento) AS diferencia
UNION ALL
SELECT  'Movimientos (monto)',
        (SELECT SUM(monto)::BIGINT FROM caso01.movimiento),
        (SELECT SUM(monto)::BIGINT FROM fact_movimiento),
        (SELECT SUM(monto)::BIGINT FROM caso01.movimiento) - (SELECT SUM(monto)::BIGINT FROM fact_movimiento)
UNION ALL
SELECT  'Colocaciones (cantidad)',
        (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes),
        (SELECT COUNT(*) FROM fact_colocacion_mes),
        (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes) - (SELECT COUNT(*) FROM fact_colocacion_mes)
UNION ALL
SELECT  'Provisiones (monto)',
        (SELECT SUM(monto_provision)::BIGINT FROM caso02.deudor_clasificacion_mes),
        (SELECT SUM(monto_provision)::BIGINT FROM fact_colocacion_mes),
        (SELECT SUM(monto_provision)::BIGINT FROM caso02.deudor_clasificacion_mes)
      - (SELECT SUM(monto_provision)::BIGINT FROM fact_colocacion_mes);
