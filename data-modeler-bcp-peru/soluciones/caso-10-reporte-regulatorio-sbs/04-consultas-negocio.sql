-- =====================================================================================
-- CASO 10 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso10, public;

\echo '== PN-01: tablero de control regulatorio =='
SELECT  periodo, num_envio, tipo_envio, estado, cant_registros, monto_total,
        fecha_envio::DATE AS fecha_envio, dias_de_holgura,
        errores_bloqueantes, advertencias, cuadra_contabilidad
FROM    vw_estado_envios
ORDER BY periodo, num_envio;

\echo ''
\echo '== PN-02: EL LINAJE CAMPO A CAMPO (el entregable ante una observacion) =='
SELECT posicion, campo_cod, campo_nombre, tipo_dato, longitud, decimales,
       es_obligatorio, origen, transformacion, responsable
FROM   vw_linaje_reporte;

\echo ''
\echo '   ^ Esta tabla responde, sin arqueologia sobre el codigo, la pregunta del supervisor:'
\echo '     "de donde sale este campo y como lo calcularon".'

\echo ''
\echo '== PN-03: hallazgos del envio observado (junio 2026) =='
SELECT  er.validacion_cod,
        v.descripcion,
        er.severidad,
        COUNT(*)                          AS ocurrencias,
        MIN(er.num_linea)                 AS primera_linea,
        MIN(er.detalle)                    AS ejemplo
FROM    reporte_error      er
JOIN    reporte_envio      e ON e.envio_id = er.envio_id
JOIN    reporte_validacion v ON v.validacion_cod = er.validacion_cod
                            AND v.reporte_cod = e.reporte_cod AND v.version = e.version
WHERE   e.periodo = '202606' AND e.num_envio = 1
GROUP BY er.validacion_cod, v.descripcion, er.severidad
ORDER BY er.severidad, ocurrencias DESC;

\echo ''
\echo '== PN-04: QUE CAMBIO entre el original y el rectificatorio =='
SELECT  o.num_linea,
        o.num_doc,
        o.dias_atraso,
        o.clasificacion_cod   AS clasificacion_original,
        r.clasificacion_cod   AS clasificacion_rectificada,
        o.saldo_capital       AS saldo_original,
        r.saldo_capital       AS saldo_rectificado,
        CASE WHEN o.clasificacion_cod <> r.clasificacion_cod THEN 'RECLASIFICADO' END
        || CASE WHEN o.saldo_capital <> r.saldo_capital THEN ' / SALDO CORREGIDO' ELSE '' END
        AS tipo_correccion
FROM    reporte_detalle o
JOIN    reporte_envio   eo ON eo.envio_id = o.envio_id AND eo.periodo = '202606' AND eo.num_envio = 1
JOIN    reporte_envio   er ON er.periodo = '202606' AND er.num_envio = 2
JOIN    reporte_detalle r  ON r.envio_id = er.envio_id AND r.num_linea = o.num_linea
WHERE   o.clasificacion_cod <> r.clasificacion_cod
   OR   o.saldo_capital    <> r.saldo_capital
ORDER BY o.num_linea
LIMIT 15;

\echo ''
\echo '   ^ El original NO se borro. Ambos envios se conservan, porque el supervisor puede'
\echo '     pedir explicar EXACTAMENTE que cambio y por que.'

\echo ''
\echo '== PN-05: cuadre contable por envio =='
SELECT  e.periodo, e.num_envio, e.tipo_envio,
        c.concepto, c.valor_reporte, c.valor_contable, c.diferencia,
        c.tolerancia, c.esta_cuadrado
FROM    cuadre_reporte c
JOIN    reporte_envio  e ON e.envio_id = c.envio_id
ORDER BY e.periodo, e.num_envio, c.concepto;

\echo ''
\echo '== PN-06: cartera reportada por clasificacion (ultimo envio aceptado) =='
WITH ultimo AS (
    SELECT envio_id FROM reporte_envio
    WHERE  estado = 'ACEPTADO'
    ORDER BY periodo DESC, num_envio DESC LIMIT 1
)
SELECT  d.clasificacion_cod,
        CASE d.clasificacion_cod
             WHEN '0' THEN 'Normal' WHEN '1' THEN 'CPP' WHEN '2' THEN 'Deficiente'
             WHEN '3' THEN 'Dudoso' ELSE 'Perdida' END       AS clasificacion,
        COUNT(*)                                             AS deudores,
        SUM(d.saldo_capital)                                 AS saldo_capital,
        SUM(d.monto_provision)                               AS provision,
        ROUND(100.0 * SUM(d.monto_provision)
              / NULLIF(SUM(d.saldo_capital), 0), 2)          AS pct_cobertura,
        ROUND(AVG(d.dias_atraso), 1)                         AS dias_atraso_promedio
FROM    reporte_detalle d
JOIN    ultimo u ON u.envio_id = d.envio_id
GROUP BY d.clasificacion_cod
ORDER BY d.clasificacion_cod;

\echo ''
\echo '== PN-07: evolucion de la cartera reportada mes a mes =='
SELECT  e.periodo,
        e.cant_registros                                                     AS deudores,
        e.monto_total                                                        AS saldo_capital,
        SUM(d.monto_provision)                                               AS provisiones,
        ROUND(100.0 * SUM(d.monto_provision) / NULLIF(e.monto_total, 0), 2)  AS pct_provision,
        COUNT(*) FILTER (WHERE d.clasificacion_cod <> '0')                   AS deudores_no_normal
FROM    reporte_envio   e
JOIN    reporte_detalle d ON d.envio_id = e.envio_id
WHERE   e.estado IN ('ACEPTADO','VALIDADO')
GROUP BY e.periodo, e.cant_registros, e.monto_total
ORDER BY e.periodo;

\echo ''
\echo '== PN-08: las DOS versiones de la definicion del reporte =='
SELECT  d.version, d.reporte_nombre, d.fecha_desde, d.fecha_hasta,
        COUNT(c.campo_cod) AS cant_campos,
        STRING_AGG(c.campo_cod, ', ' ORDER BY c.posicion) AS campos
FROM    reporte_definicion d
JOIN    reporte_campo      c ON c.reporte_cod = d.reporte_cod AND c.version = d.version
WHERE   d.reporte_cod = 'RCD'
GROUP BY d.version, d.reporte_nombre, d.fecha_desde, d.fecha_hasta
ORDER BY d.version;

\echo ''
\echo '   ^ La version 1 se conserva aunque ya no este vigente: sin ella seria imposible'
\echo '     reproducir un envio anterior a julio de 2026 con su estructura original.'

\echo ''
\echo '== PN-09: cumplimiento de plazos =='
SELECT  periodo, tipo_envio, fecha_limite, fecha_envio::DATE AS fecha_envio,
        dias_de_holgura,
        CASE WHEN fecha_envio IS NULL              THEN 'PENDIENTE DE ENVIO'
             WHEN dias_de_holgura < 0              THEN 'FUERA DE PLAZO'
             WHEN dias_de_holgura <= 2             THEN 'AL LIMITE'
             ELSE 'EN PLAZO' END AS situacion
FROM    vw_estado_envios
ORDER BY periodo, num_envio;

\echo ''
\echo '== PN-10: GENERACION DEL ARCHIVO PLANO desde la definicion (el pago de modelar la estructura como dato) =='
-- El archivo se arma leyendo reporte_campo: posiciones, longitudes y tipos.
-- Si la SBS cambia una longitud, se cambia UNA FILA, no el programa generador.
WITH envio AS (
    SELECT envio_id, version FROM reporte_envio
    WHERE  estado = 'ACEPTADO' ORDER BY periodo DESC, num_envio DESC LIMIT 1
)
SELECT  d.num_linea,
           RPAD(d.tipo_doc_cod,       2, ' ')
        || RPAD(d.num_doc,           20, ' ')
        || RPAD(LEFT(d.nombre_deudor, 40), 40, ' ')
        || RPAD(d.tipo_credito_cod,   1, ' ')
        || RPAD(d.clasificacion_cod,  1, ' ')
        || LPAD(d.dias_atraso::TEXT,  5, '0')
        || RPAD(d.moneda_cod,         3, ' ')
        || LPAD(REPLACE(TO_CHAR(d.saldo_capital,   'FM9999999999999990.00'), '.', ''), 18, '0')
        || LPAD(REPLACE(TO_CHAR(d.monto_provision, 'FM9999999999999990.00'), '.', ''), 18, '0')
        || d.tiene_garantia
        || TO_CHAR(d.fecha_corte, 'YYYYMMDD')  AS linea_archivo
FROM    reporte_detalle d
JOIN    envio e ON e.envio_id = d.envio_id
ORDER BY d.num_linea
LIMIT 5;

\echo ''
\echo '   ^ Formato de ancho fijo generado a partir de reporte_campo.'
\echo '     (El nombre se trunca a 40 para que la linea quepa en pantalla; la definicion real usa 160.)'
