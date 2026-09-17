-- =====================================================================================
-- CASO 07 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso07;

\echo '== PN-01: alertas por regla, severidad y estado =='
SELECT  a.regla_cod,
        r.regla_nombre,
        r.tipo_regla,
        a.severidad,
        COUNT(*)                                                       AS alertas,
        COUNT(DISTINCT a.cliente_id)                                   AS clientes,
        SUM(a.monto_involucrado)                                       AS monto_involucrado,
        COUNT(*) FILTER (WHERE a.estado_alerta_cod = 'ESCALADA')       AS escaladas,
        COUNT(*) FILTER (WHERE a.estado_alerta_cod = 'DESCARTADA')     AS descartadas
FROM    alerta a
JOIN    regla_monitoreo r ON r.regla_cod = a.regla_cod
                         AND a.fecha_deteccion BETWEEN r.fecha_desde AND r.fecha_hasta
GROUP BY a.regla_cod, r.regla_nombre, r.tipo_regla, a.severidad
ORDER BY a.severidad DESC, alertas DESC;

\echo ''
\echo '== PN-02: tasa de falsos positivos por regla =='
-- Indicador clave de un sistema de monitoreo: una regla que descarta el 99% satura al
-- equipo y termina ignorándose. Medirlo es la única forma de calibrar.
SELECT  a.regla_cod,
        COUNT(*)                                                                    AS total,
        COUNT(*) FILTER (WHERE a.estado_alerta_cod = 'DESCARTADA')                  AS descartadas,
        ROUND(100.0 * COUNT(*) FILTER (WHERE a.estado_alerta_cod = 'DESCARTADA')
              / COUNT(*), 1)                                                        AS pct_falsos_positivos,
        COUNT(*) FILTER (WHERE a.caso_id IS NOT NULL)                               AS con_caso
FROM    alerta a
GROUP BY a.regla_cod
ORDER BY pct_falsos_positivos DESC;

\echo ''
\echo '== PN-03: FRACCIONAMIENTO detectado (el patron estrella del caso) =='
SELECT  a.cliente_id,
        c.nombre_completo,
        p.nivel_riesgo,
        a.fecha_desde_eval,
        a.fecha_hasta_eval,
        a.cant_operaciones,
        a.monto_involucrado,
        (a.detalle ->> 'operacion_mayor')::NUMERIC   AS operacion_mayor,
        (a.detalle ->> 'umbral_individual')::NUMERIC AS umbral,
        a.detalle ->> 'observacion'                  AS observacion
FROM    alerta a
JOIN    cliente c ON c.cliente_id = a.cliente_id
LEFT JOIN cliente_perfil p ON p.cliente_id = a.cliente_id AND p.fecha_hasta = DATE '9999-12-31'
WHERE   a.regla_cod = 'R02-FRACC'
ORDER BY a.monto_involucrado DESC
LIMIT 10;

\echo ''
\echo '== PN-03b: el detalle operacion por operacion de un caso de fraccionamiento =='
SELECT  o.fecha_contable,
        o.num_operacion,
        o.tipo_op_cod,
        o.canal_cod,
        o.monto_mn,
        CASE WHEN o.monto_mn >= 40000 THEN 'SOBRE UMBRAL' ELSE 'bajo umbral' END AS vs_umbral,
        SUM(o.monto_mn) OVER (ORDER BY o.fecha_contable, o.operacion_id)         AS acumulado
FROM    operacion o
WHERE   o.cliente_id = (SELECT cliente_id FROM alerta WHERE regla_cod = 'R02-FRACC'
                        ORDER BY monto_involucrado DESC LIMIT 1)
  AND   o.fecha_contable BETWEEN DATE '2026-08-10' AND DATE '2026-08-14'
ORDER BY o.fecha_contable, o.operacion_id;

\echo ''
\echo '   ^ Ninguna operacion supera 40 000, pero el acumulado si. Eso es fraccionamiento:'
\echo '     invisible para una regla que evalue operacion por operacion.'

\echo ''
\echo '== PN-04: clientes con MULTIPLES reglas disparadas (riesgo acumulado) =='
SELECT  a.cliente_id,
        c.nombre_completo,
        c.es_persona_juridica,
        ae.actividad_desc,
        p.nivel_riesgo,
        p.es_pep,
        COUNT(DISTINCT a.regla_cod)               AS reglas_distintas,
        STRING_AGG(DISTINCT a.regla_cod, ', ')    AS reglas,
        MAX(a.severidad)                          AS severidad_maxima,
        SUM(a.monto_involucrado)                  AS monto_total
FROM        alerta a
JOIN        cliente c  ON c.cliente_id = a.cliente_id
LEFT JOIN   cat_actividad_economica ae ON ae.ciiu_cod = c.ciiu_cod
LEFT JOIN   cliente_perfil p ON p.cliente_id = a.cliente_id AND p.fecha_hasta = DATE '9999-12-31'
GROUP BY    a.cliente_id, c.nombre_completo, c.es_persona_juridica, ae.actividad_desc,
            p.nivel_riesgo, p.es_pep
HAVING      COUNT(DISTINCT a.regla_cod) >= 2
ORDER BY    reglas_distintas DESC, monto_total DESC
LIMIT 15;

\echo ''
\echo '== PN-05: carga de trabajo y tiempo de atencion por analista =='
SELECT  ci.analista,
        COUNT(*)                                                      AS casos,
        COUNT(*) FILTER (WHERE ci.fecha_cierre IS NULL)               AS abiertos,
        COUNT(*) FILTER (WHERE ci.disposicion_cod = 'SOSPECHOSA')     AS reportados_uif,
        ROUND(AVG(ci.fecha_cierre - ci.fecha_apertura), 1)            AS dias_promedio_cierre,
        MAX(ci.fecha_cierre - ci.fecha_apertura)                      AS dias_maximo,
        SUM(ci.monto_total)                                           AS monto_investigado
FROM    caso_investigacion ci
GROUP BY ci.analista
ORDER BY casos DESC;

\echo ''
\echo '== PN-06: Registro de Operaciones (obligacion normativa) =='
SELECT  ro.umbral_cod,
        o.tipo_op_cod,
        COUNT(*)                          AS operaciones_registradas,
        MIN(ro.monto_operacion)           AS monto_minimo,
        ROUND(AVG(ro.monto_operacion), 2) AS monto_promedio,
        MAX(ro.monto_operacion)           AS monto_maximo,
        MIN(ro.monto_umbral)              AS umbral_aplicado
FROM    registro_operacion ro
JOIN    operacion o ON o.operacion_id = ro.operacion_id
GROUP BY ro.umbral_cod, o.tipo_op_cod
ORDER BY operaciones_registradas DESC;

\echo ''
\echo '== PN-07: clientes PEP y su operativa =='
SELECT  c.cliente_id,
        c.nombre_completo,
        p.nivel_riesgo,
        p.fecha_ultima_dd,
        (CURRENT_DATE - p.fecha_ultima_dd)                       AS dias_desde_ultima_dd,
        COALESCE(SUM(cm.monto_total_mn), 0)                      AS monto_transado,
        COALESCE(SUM(cm.monto_efectivo_mn), 0)                   AS monto_efectivo,
        COUNT(DISTINCT a.alerta_id)                              AS alertas
FROM        cliente_perfil p
JOIN        cliente c ON c.cliente_id = p.cliente_id
LEFT JOIN   vw_comportamiento_mes cm ON cm.cliente_id = c.cliente_id
LEFT JOIN   alerta a ON a.cliente_id = c.cliente_id
WHERE       p.es_pep AND p.fecha_hasta = DATE '9999-12-31'
GROUP BY    c.cliente_id, c.nombre_completo, p.nivel_riesgo, p.fecha_ultima_dd
ORDER BY    monto_efectivo DESC;

\echo ''
\echo '== PN-08: comportamiento REAL vs perfil DECLARADO (mayores desviaciones) =='
SELECT  cm.cliente_id,
        c.nombre_completo,
        cm.periodo,
        p.monto_esperado_mes                                            AS esperado,
        cm.monto_total_mn                                               AS real,
        ROUND(cm.monto_total_mn / NULLIF(p.monto_esperado_mes, 0), 2)    AS factor,
        p.num_op_esperadas_mes                                          AS ops_esperadas,
        cm.cant_operaciones                                             AS ops_reales,
        p.nivel_riesgo
FROM    vw_comportamiento_mes cm
JOIN    cliente c ON c.cliente_id = cm.cliente_id
JOIN    cliente_perfil p ON p.cliente_id = cm.cliente_id AND p.fecha_hasta = DATE '9999-12-31'
ORDER BY cm.monto_total_mn / NULLIF(p.monto_esperado_mes, 0) DESC
LIMIT 15;

\echo ''
\echo '== PN-09: operaciones con jurisdicciones de alto riesgo =='
SELECT  pa.pais_cod,
        pa.pais_desc,
        COUNT(*)                          AS operaciones,
        COUNT(DISTINCT o.cliente_id)      AS clientes,
        SUM(o.monto_mn)                   AS monto_mn,
        ROUND(AVG(o.monto_mn), 2)         AS ticket_promedio
FROM    operacion o
JOIN    cat_pais pa ON pa.pais_cod = o.pais_contraparte
WHERE   pa.es_alto_riesgo
GROUP BY pa.pais_cod, pa.pais_desc
ORDER BY monto_mn DESC;

\echo ''
\echo '== PN-10: DEBER DE RESERVA - quien puede ver el ROS =='
SELECT  c.relname                AS tabla,
        c.relrowsecurity         AS tiene_rls_activo,
        p.polname                AS politica,
        p.polcmd                 AS comando,
        ARRAY(SELECT rolname FROM pg_roles WHERE oid = ANY(p.polroles)) AS roles_autorizados
FROM    pg_class c
LEFT JOIN pg_policy p ON p.polrelid = c.oid
WHERE   c.relname = 'ros'
  AND   c.relnamespace = 'caso07'::REGNAMESPACE;

\echo ''
\echo '-- Privilegios otorgados sobre las tablas del esquema --'
SELECT  table_name, grantee, privilege_type
FROM    information_schema.table_privileges
WHERE   table_schema = 'caso07'
  AND   grantee IN ('rol_oficial_cumplimiento','rol_analista_negocio')
ORDER BY table_name, grantee;

\echo ''
\echo '   ^ rol_analista_negocio NO aparece con privilegios sobre ros: el deber de reserva'
\echo '     esta implementado en la BASE DE DATOS, no en la aplicacion.'

\echo ''
\echo '-- Bitacora de acceso al ROS (exigible ante una revision) --'
SELECT b.acceso_id, b.ros_id, b.usuario_bd, b.fecha_hora, b.tipo_acceso, b.motivo
FROM   bitacora_acceso_ros b
ORDER BY b.fecha_hora;
