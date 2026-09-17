-- =====================================================================================
-- CASO 04 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso04;

\echo '== PN-01: pulso diario del producto (primeros 10 dias) =='
SELECT dia, operaciones, exitosas, rechazadas, usuarios_activos, monto_transado, ticket_promedio
FROM   vw_actividad_diaria
ORDER BY dia
LIMIT 10;

\echo ''
\echo '== PN-02: usuarios activos mensuales (MAU) y transacciones por usuario activo =='
-- Es la métrica que reportan públicamente las billeteras digitales.
SELECT  TO_CHAR(t.fecha_operacion, 'YYYY-MM')                                   AS mes,
        COUNT(DISTINCT t.usuario_origen_id)                                     AS usuarios_activos,
        COUNT(*) FILTER (WHERE t.estado_cod = 'CONFIRMADA')                     AS operaciones,
        ROUND(COUNT(*) FILTER (WHERE t.estado_cod = 'CONFIRMADA')::NUMERIC
              / NULLIF(COUNT(DISTINCT t.usuario_origen_id), 0), 1)              AS op_por_usuario,
        SUM(t.monto) FILTER (WHERE t.estado_cod = 'CONFIRMADA')                 AS monto_transado
FROM    transferencia t
WHERE   t.tipo_op_cod IN ('ENVIO','PAGO_QR')
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '== PN-03: distribucion horaria (identificar la hora pico) =='
SELECT  EXTRACT(HOUR FROM t.fecha_operacion)::INT                           AS hora,
        COUNT(*)                                                            AS operaciones,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                  AS pct,
        REPEAT('#', (COUNT(*) / 900)::INT)                                  AS histograma
FROM    transferencia t
WHERE   t.tipo_op_cod IN ('ENVIO','PAGO_QR')
GROUP BY 1
ORDER BY 1;

\echo ''
\echo '== PN-04: tasa de rechazo por motivo =='
SELECT  mr.motivo_cod,
        mr.motivo_desc,
        mr.es_del_usuario,
        COUNT(*)                                                           AS rechazos,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                 AS pct_de_rechazos,
        SUM(t.monto)                                                       AS monto_no_procesado
FROM    transferencia t
JOIN    cat_motivo_rechazo mr ON mr.motivo_cod = t.motivo_cod
WHERE   t.estado_cod = 'RECHAZADA'
GROUP BY mr.motivo_cod, mr.motivo_desc, mr.es_del_usuario
ORDER BY rechazos DESC;

\echo ''
\echo '== PN-05: top 10 receptores de dinero =='
SELECT  u.usuario_id,
        u.num_celular,
        u.nombre_mostrado,
        u.es_negocio,
        COUNT(*)                        AS recepciones,
        SUM(t.monto)                    AS monto_recibido,
        ROUND(AVG(t.monto), 2)          AS ticket_promedio
FROM    transferencia t
JOIN    usuario_billetera u ON u.usuario_id = t.usuario_destino_id
WHERE   t.estado_cod = 'CONFIRMADA'
  AND   t.tipo_op_cod IN ('ENVIO','PAGO_QR')
GROUP BY u.usuario_id, u.num_celular, u.nombre_mostrado, u.es_negocio
ORDER BY monto_recibido DESC
LIMIT 10;

\echo ''
\echo '== PN-06: pares frecuentes (red de contactos) =='
-- Base para recomendaciones de "contactos frecuentes" y para detección de anillos de fraude.
SELECT  t.usuario_origen_id,
        t.usuario_destino_id,
        COUNT(*)            AS veces,
        SUM(t.monto)        AS monto_total,
        MIN(t.fecha_operacion)::DATE AS primera,
        MAX(t.fecha_operacion)::DATE AS ultima
FROM    transferencia t
WHERE   t.estado_cod = 'CONFIRMADA'
  AND   t.tipo_op_cod = 'ENVIO'
GROUP BY t.usuario_origen_id, t.usuario_destino_id
HAVING  COUNT(*) >= 3
ORDER BY veces DESC, monto_total DESC
LIMIT 15;

\echo ''
\echo '== PN-07: control de limites diarios contra el parametro vigente =='
WITH acumulado_dia AS (
    SELECT  t.usuario_origen_id,
            t.fecha_operacion::DATE AS dia,
            COUNT(*)                AS operaciones,
            SUM(t.monto)            AS monto_dia
    FROM    transferencia t
    WHERE   t.estado_cod = 'CONFIRMADA'
      AND   t.tipo_op_cod IN ('ENVIO','PAGO_QR')
    GROUP BY 1, 2
)
SELECT  a.usuario_origen_id,
        a.dia,
        a.operaciones,
        a.monto_dia,
        pl.monto_max_dia,
        pl.num_max_dia,
        CASE WHEN a.monto_dia   > pl.monto_max_dia THEN 'EXCEDE MONTO'
             WHEN a.operaciones > pl.num_max_dia   THEN 'EXCEDE CANTIDAD'
             ELSE 'OK' END AS situacion
FROM        acumulado_dia a
JOIN        usuario_billetera u ON u.usuario_id = a.usuario_origen_id
JOIN        par_limite pl ON pl.segmento_cod = CASE WHEN u.es_negocio THEN 'NEGOCIO' ELSE 'PERSONA_NATURAL' END
                         AND a.dia BETWEEN pl.fecha_desde AND pl.fecha_hasta
WHERE       a.monto_dia > pl.monto_max_dia OR a.operaciones > pl.num_max_dia
ORDER BY    a.monto_dia DESC
LIMIT 10;

\echo ''
\echo '== PN-08: cohortes de adopcion por anio de alta =='
SELECT  EXTRACT(YEAR FROM u.fecha_alta)::INT                                AS anio_alta,
        COUNT(DISTINCT u.usuario_id)                                        AS usuarios,
        COUNT(DISTINCT t.usuario_origen_id)                                 AS usuarios_con_actividad,
        ROUND(100.0 * COUNT(DISTINCT t.usuario_origen_id)
              / COUNT(DISTINCT u.usuario_id), 1)                            AS pct_activos,
        ROUND(AVG(sb.saldo), 2)                                             AS saldo_promedio
FROM        usuario_billetera u
LEFT JOIN   transferencia t  ON t.usuario_origen_id = u.usuario_id AND t.estado_cod = 'CONFIRMADA'
LEFT JOIN   saldo_billetera sb ON sb.usuario_id = u.usuario_id
GROUP BY    1
ORDER BY    1;

\echo ''
\echo '== PN-09: DEMOSTRACION DE PODA DE PARTICIONES =='
\echo '-- Consulta con filtro de fecha: PostgreSQL debe leer UNA sola particion'
EXPLAIN (COSTS OFF)
SELECT COUNT(*) FROM transferencia
WHERE  fecha_operacion >= TIMESTAMP '2026-08-01' AND fecha_operacion < TIMESTAMP '2026-09-01';

\echo ''
\echo '-- Misma consulta SIN filtro de fecha: lee TODAS las particiones'
EXPLAIN (COSTS OFF)
SELECT COUNT(*) FROM transferencia WHERE monto > 45;

\echo ''
\echo '== PN-10: distribucion de saldos en la billetera =='
SELECT  CASE
            WHEN saldo <  500 THEN 'a) menos de 500'
            WHEN saldo < 2000 THEN 'b) 500 a 2 000'
            WHEN saldo < 5000 THEN 'c) 2 000 a 5 000'
            ELSE                   'd) 5 000 o mas'
        END                              AS rango_saldo,
        COUNT(*)                         AS usuarios,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
        SUM(saldo)                       AS saldo_total
FROM    saldo_billetera
GROUP BY 1
ORDER BY 1;
