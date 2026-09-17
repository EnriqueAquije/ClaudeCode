-- =====================================================================================
-- CASO 10 - Reglas de calidad del proceso regulatorio
-- =====================================================================================

SET search_path TO caso10, public;

\echo '-- CAL-04 (detalle): envios remitidos con errores BLOQUEANTES sin resolver'
SELECT e.periodo, e.num_envio, e.estado, COUNT(*) AS errores_bloqueantes
FROM   reporte_envio e
JOIN   reporte_error r ON r.envio_id = e.envio_id AND r.severidad = 'BLOQUEA'
WHERE  e.estado IN ('ENVIADO','ACEPTADO')
GROUP BY e.periodo, e.num_envio, e.estado;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 10 (REPORTE REGULATORIO)'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: lineas de detalle del reporte' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM reporte_detalle) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Integridad',
           'Todo detalle pertenece a un envio existente',
           (SELECT COUNT(*) FROM reporte_detalle d
            WHERE NOT EXISTS (SELECT 1 FROM reporte_envio e WHERE e.envio_id = d.envio_id)) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Trazabilidad', 'Todo campo de la version vigente tiene linaje documentado',
           (SELECT COUNT(*) FROM reporte_campo c
            WHERE c.reporte_cod = 'RCD' AND c.version = 2
              AND NOT EXISTS (SELECT 1 FROM reporte_linaje l
                              WHERE l.reporte_cod = c.reporte_cod AND l.version = c.version
                                AND l.campo_cod = c.campo_cod))
    UNION ALL
    SELECT 'CAL-03', 'Cuadre', 'El indicador de cuadre coincide con diferencia y tolerancia',
           (SELECT COUNT(*) FROM cuadre_reporte
            WHERE esta_cuadrado <> (ABS(diferencia) <= tolerancia)
               OR diferencia <> valor_reporte - valor_contable)
    UNION ALL
    SELECT 'CAL-04', 'Regulatoria', 'Ningun envio remitido con errores BLOQUEANTES',
           (SELECT COUNT(*) FROM reporte_envio e
            WHERE e.estado IN ('ENVIADO','ACEPTADO')
              AND EXISTS (SELECT 1 FROM reporte_error r
                          WHERE r.envio_id = e.envio_id AND r.severidad = 'BLOQUEA'))
    UNION ALL
    SELECT 'CAL-05', 'Unicidad', 'Un deudor aparece una sola vez por envio',
           (SELECT COUNT(*) FROM (
                SELECT envio_id, tipo_doc_cod, num_doc FROM reporte_detalle
                GROUP BY 1,2,3 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-06', 'Coherencia', 'La provision nunca supera el saldo de capital',
           (SELECT COUNT(*) FROM reporte_detalle WHERE monto_provision > saldo_capital)
    UNION ALL
    SELECT 'CAL-07', 'Dominio', 'Clasificacion y tipo de credito dentro del dominio SBS',
           (SELECT COUNT(*) FROM reporte_detalle
            WHERE clasificacion_cod NOT IN ('0','1','2','3','4')
               OR tipo_credito_cod NOT IN ('1','2','3','4','5','6','7','8'))
    UNION ALL
    SELECT 'CAL-08', 'Consistencia', 'Todo rectificatorio tiene un envio original previo',
           (SELECT COUNT(*) FROM reporte_envio r
            WHERE r.tipo_envio = 'RECTIFICATORIO'
              AND NOT EXISTS (SELECT 1 FROM reporte_envio o
                              WHERE o.reporte_cod = r.reporte_cod AND o.periodo = r.periodo
                                AND o.num_envio = 1 AND o.tipo_envio = 'ORIGINAL'))
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'El envio 1 es ORIGINAL y los siguientes RECTIFICATORIOS',
           (SELECT COUNT(*) FROM reporte_envio
            WHERE (num_envio = 1 AND tipo_envio <> 'ORIGINAL')
               OR (num_envio > 1 AND tipo_envio <> 'RECTIFICATORIO'))
    UNION ALL
    SELECT 'CAL-10', 'Definicion', 'Las posiciones de los campos son correlativas sin huecos',
           (SELECT COUNT(*) FROM (
                SELECT reporte_cod, version,
                       COUNT(*) AS n, MAX(posicion) AS maxp, MIN(posicion) AS minp
                FROM   reporte_campo GROUP BY reporte_cod, version) t
            WHERE minp <> 1 OR maxp <> n)
    UNION ALL
    SELECT 'CAL-11', 'Consistencia', 'Todo envio remitido fue generado antes',
           (SELECT COUNT(*) FROM reporte_envio
            WHERE fecha_envio IS NOT NULL
              AND (fecha_generacion IS NULL OR fecha_envio < fecha_generacion))
    UNION ALL
    SELECT 'CAL-12', 'Cuadre', 'Los totales del envio coinciden con su detalle',
           (SELECT COUNT(*) FROM reporte_envio e
            JOIN (SELECT envio_id, COUNT(*) AS n, SUM(saldo_capital) AS s
                  FROM reporte_detalle GROUP BY envio_id) d ON d.envio_id = e.envio_id
            WHERE e.cant_registros <> d.n OR e.monto_total <> d.s)
    UNION ALL
    SELECT 'CAL-13', 'Definicion', 'La version usada esta vigente a la fecha de corte',
           (SELECT COUNT(*) FROM reporte_envio e
            JOIN reporte_definicion d ON d.reporte_cod = e.reporte_cod AND d.version = e.version
            WHERE e.fecha_corte NOT BETWEEN d.fecha_desde AND d.fecha_hasta)
    UNION ALL
    SELECT 'CAL-14', 'Regulatoria', 'Todo envio aceptado cuadra con contabilidad',
           (SELECT COUNT(*) FROM reporte_envio e
            JOIN cuadre_reporte c ON c.envio_id = e.envio_id
            WHERE e.estado = 'ACEPTADO' AND NOT c.esta_cuadrado)
    UNION ALL
    SELECT 'CAL-15', 'Completitud', 'Todo envio generado tiene al menos un registro de detalle',
           (SELECT COUNT(*) FROM reporte_envio e
            WHERE e.fecha_generacion IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM reporte_detalle d WHERE d.envio_id = e.envio_id))
    UNION ALL
    SELECT 'CAL-16', 'Trazabilidad', 'Todo envio remitido tiene hash del archivo',
           (SELECT COUNT(*) FROM reporte_envio
            WHERE fecha_envio IS NOT NULL AND hash_archivo IS NULL)
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
