-- =====================================================================================
-- CASO 07 - Reglas de calidad de datos
-- =====================================================================================

SET search_path TO caso07;

\echo '-- CAL-07 (detalle): alertas de fraccionamiento mal formadas'
-- Si una alerta de fraccionamiento contiene una operación que ya supera el umbral por sí
-- sola, la regla está mal implementada: eso es R01, no R02.
SELECT a.alerta_id, a.cliente_id,
       (a.detalle ->> 'operacion_mayor')::NUMERIC   AS operacion_mayor,
       (a.detalle ->> 'umbral_individual')::NUMERIC AS umbral
FROM   alerta a
WHERE  a.regla_cod = 'R02-FRACC'
  AND  (a.detalle ->> 'operacion_mayor')::NUMERIC >= (a.detalle ->> 'umbral_individual')::NUMERIC;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 07'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: operaciones monitoreadas' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM operacion) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Regulatoria',
           'Toda operacion del Registro supera efectivamente su umbral',
           (SELECT COUNT(*) FROM registro_operacion WHERE monto_operacion < monto_umbral) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Integridad referencial', 'Toda alerta corresponde a una regla vigente a su fecha',
           (SELECT COUNT(*) FROM alerta a
            WHERE NOT EXISTS (SELECT 1 FROM regla_monitoreo r
                              WHERE r.regla_cod = a.regla_cod
                                AND a.fecha_deteccion BETWEEN r.fecha_desde AND r.fecha_hasta))
    UNION ALL
    SELECT 'CAL-03', 'Consistencia', 'Todo caso cerrado tiene disposicion y ninguno abierto la tiene',
           (SELECT COUNT(*) FROM caso_investigacion
            WHERE (fecha_cierre IS NOT NULL AND disposicion_cod IS NULL)
               OR (fecha_cierre IS NULL     AND disposicion_cod IS NOT NULL))
    UNION ALL
    SELECT 'CAL-04', 'Regulatoria', 'Todo ROS proviene de un caso con disposicion que lo genera',
           (SELECT COUNT(*) FROM ros r
            JOIN caso_investigacion c ON c.caso_id = r.caso_id
            LEFT JOIN cat_disposicion d ON d.disposicion_cod = c.disposicion_cod
            WHERE d.genera_ros IS DISTINCT FROM TRUE)
    UNION ALL
    SELECT 'CAL-05', 'Consistencia', 'Toda alerta ESCALADA esta vinculada a un caso',
           (SELECT COUNT(*) FROM alerta WHERE estado_alerta_cod = 'ESCALADA' AND caso_id IS NULL)
    UNION ALL
    SELECT 'CAL-06', 'Consistencia', 'Ninguna alerta no escalada tiene caso',
           (SELECT COUNT(*) FROM alerta WHERE estado_alerta_cod <> 'ESCALADA' AND caso_id IS NOT NULL)
    UNION ALL
    SELECT 'CAL-07', 'Logica de regla', 'Fraccionamiento: ninguna operacion supera el umbral por si sola',
           (SELECT COUNT(*) FROM alerta a
            WHERE a.regla_cod = 'R02-FRACC'
              AND (a.detalle ->> 'operacion_mayor')::NUMERIC
                  >= (a.detalle ->> 'umbral_individual')::NUMERIC)
    UNION ALL
    SELECT 'CAL-08', 'Parametros', 'Umbrales sin vigencias solapadas para la misma combinacion',
           (SELECT COUNT(*) FROM par_umbral a
            JOIN par_umbral b ON b.umbral_cod = a.umbral_cod
                             AND b.tipo_op_cod = a.tipo_op_cod
                             AND b.moneda_cod  = a.moneda_cod
                             AND b.fecha_desde > a.fecha_desde
                             AND b.fecha_desde <= a.fecha_hasta)
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'Un solo perfil vigente por cliente',
           (SELECT COUNT(*) FROM (
                SELECT cliente_id FROM cliente_perfil WHERE fecha_hasta = DATE '9999-12-31'
                GROUP BY cliente_id HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-10', 'Regulatoria', 'Toda operacion sobre umbral esta en el Registro de Operaciones',
           (SELECT COUNT(*) FROM operacion o
            JOIN cat_tipo_operacion t ON t.tipo_op_cod = o.tipo_op_cod AND t.sujeta_a_ro
            JOIN par_umbral u ON u.tipo_op_cod = o.tipo_op_cod AND u.moneda_cod = 'PEN'
                             AND u.ventana_dias = 1
                             AND o.fecha_contable BETWEEN u.fecha_desde AND u.fecha_hasta
            WHERE o.monto_mn >= u.monto_umbral
              AND NOT EXISTS (SELECT 1 FROM registro_operacion ro
                              WHERE ro.operacion_id = o.operacion_id))
    UNION ALL
    SELECT 'CAL-11', 'Auditoria', 'Todo ROS tiene al menos un registro en la bitacora de acceso',
           (SELECT COUNT(*) FROM ros r
            WHERE NOT EXISTS (SELECT 1 FROM bitacora_acceso_ros b WHERE b.ros_id = r.ros_id))
    UNION ALL
    SELECT 'CAL-12', 'Cuadre', 'monto_total del caso = suma de sus alertas',
           (SELECT COUNT(*) FROM caso_investigacion c
            JOIN (SELECT caso_id, SUM(monto_involucrado) AS s, COUNT(*) AS n
                  FROM alerta WHERE caso_id IS NOT NULL GROUP BY caso_id) a
                 ON a.caso_id = c.caso_id
            WHERE c.monto_total <> a.s OR c.cant_alertas <> a.n)
    UNION ALL
    SELECT 'CAL-13', 'Regulatoria', 'Todo cliente PEP tiene nivel de riesgo ALTO',
           (SELECT COUNT(*) FROM cliente_perfil
            WHERE es_pep AND nivel_riesgo <> 'ALTO' AND fecha_hasta = DATE '9999-12-31')
    UNION ALL
    SELECT 'CAL-14', 'Seguridad', 'La tabla ROS tiene seguridad a nivel de fila activa',
           (SELECT COUNT(*) FROM (SELECT 1 WHERE NOT EXISTS (
                SELECT 1 FROM pg_class
                WHERE relname = 'ros' AND relnamespace = 'caso07'::REGNAMESPACE
                  AND relrowsecurity)) z)
    UNION ALL
    SELECT 'CAL-15', 'Completitud', 'Toda alerta conserva la evidencia que la genero (detalle no vacio)',
           (SELECT COUNT(*) FROM alerta WHERE detalle = '{}'::JSONB OR detalle IS NULL)
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
