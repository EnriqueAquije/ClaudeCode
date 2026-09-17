-- =====================================================================================
-- CASO 05 - Reglas de calidad del data warehouse
-- =====================================================================================

SET search_path TO caso05;

\echo '-- CAL-03 (detalle): vigencias solapadas en el SCD2'
SELECT a.tipo_doc_cod, a.num_doc, a.cliente_sk AS sk_a, a.fecha_desde, a.fecha_hasta,
       b.cliente_sk AS sk_b, b.fecha_desde AS b_desde
FROM   dim_cliente a
JOIN   dim_cliente b ON b.tipo_doc_cod = a.tipo_doc_cod
                    AND b.num_doc      = a.num_doc
                    AND b.cliente_sk  <> a.cliente_sk
                    AND b.fecha_desde  > a.fecha_desde
                    AND b.fecha_desde <= a.fecha_hasta
LIMIT 20;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 05 (DATA WAREHOUSE)'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: hechos de movimiento' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM fact_movimiento) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Kimball',
           'Toda dimension tiene su miembro DESCONOCIDO (sk = -1)',
           ((SELECT COUNT(*) FROM dim_tiempo   WHERE tiempo_sk   = -1) <> 1)::INT
         + ((SELECT COUNT(*) FROM dim_ubigeo   WHERE ubigeo_sk   = -1) <> 1)::INT
         + ((SELECT COUNT(*) FROM dim_oficina  WHERE oficina_sk  = -1) <> 1)::INT
         + ((SELECT COUNT(*) FROM dim_producto WHERE producto_sk = -1) <> 1)::INT
         + ((SELECT COUNT(*) FROM dim_canal    WHERE canal_sk    = -1) <> 1)::INT
         + ((SELECT COUNT(*) FROM dim_cliente  WHERE cliente_sk  = -1) <> 1)::INT AS incumple
    UNION ALL
    SELECT 'CAL-02', 'SCD2', 'Una sola version vigente por clave natural',
           (SELECT COUNT(*) FROM (
                SELECT tipo_doc_cod, num_doc FROM dim_cliente WHERE es_vigente
                GROUP BY 1, 2 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-03', 'SCD2', 'Vigencias sin solapamiento',
           (SELECT COUNT(*) FROM dim_cliente a
            JOIN dim_cliente b ON b.tipo_doc_cod = a.tipo_doc_cod AND b.num_doc = a.num_doc
                              AND b.cliente_sk <> a.cliente_sk
                              AND b.fecha_desde > a.fecha_desde
                              AND b.fecha_desde <= a.fecha_hasta)
    UNION ALL
    SELECT 'CAL-04', 'SCD2', 'Cadena de vigencias sin huecos',
           (SELECT COUNT(*) FROM (
                SELECT a.cliente_sk,
                       LEAD(a.fecha_desde) OVER (PARTITION BY a.tipo_doc_cod, a.num_doc
                                                 ORDER BY a.fecha_desde) AS sig_desde,
                       a.fecha_hasta
                FROM dim_cliente a WHERE a.cliente_sk <> -1) t
            WHERE sig_desde IS NOT NULL AND sig_desde <> fecha_hasta + 1)
    UNION ALL
    SELECT 'CAL-05', 'Cuadre ETL', 'Cantidad de movimientos DWH = origen',
           (SELECT ABS((SELECT COUNT(*) FROM caso01.movimiento)
                     - (SELECT COUNT(*) FROM fact_movimiento)))
    UNION ALL
    SELECT 'CAL-06', 'Cuadre ETL', 'Suma de montos DWH = origen',
           (SELECT COUNT(*) FROM (SELECT 1 WHERE
                (SELECT SUM(monto) FROM caso01.movimiento)
             <> (SELECT SUM(monto) FROM fact_movimiento)) z)
    UNION ALL
    SELECT 'CAL-07', 'Cuadre ETL', 'Colocaciones DWH = origen (cantidad y provision)',
           (SELECT COUNT(*) FROM (SELECT 1 WHERE
                (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes)
             <> (SELECT COUNT(*) FROM fact_colocacion_mes)
             OR (SELECT SUM(monto_provision) FROM caso02.deudor_clasificacion_mes)
             <> (SELECT SUM(monto_provision) FROM fact_colocacion_mes)) z)
    UNION ALL
    SELECT 'CAL-08', 'Dimension tiempo', 'dim_tiempo sin fechas faltantes en su rango',
           (SELECT (MAX(fecha) - MIN(fecha) + 1) - COUNT(*)
            FROM dim_tiempo WHERE tiempo_sk <> -1)
    UNION ALL
    SELECT 'CAL-09', 'Grano', 'Snapshot de captacion sin duplicados (cuenta-mes)',
           (SELECT COUNT(*) FROM (
                SELECT tiempo_sk, cuenta_id_origen FROM fact_saldo_captacion_mes
                GROUP BY 1, 2 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-10', 'Grano', 'Snapshot de colocacion sin duplicados (deudor-mes)',
           (SELECT COUNT(*) FROM (
                SELECT tiempo_sk, deudor_id_origen FROM fact_colocacion_mes
                GROUP BY 1, 2 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-11', 'Conformidad', 'dim_producto cubre captacion y colocacion',
           (SELECT COUNT(*) FROM (SELECT 1 WHERE
                (SELECT COUNT(*) FROM dim_producto WHERE negocio_cod = 'CAPTACION') = 0
             OR (SELECT COUNT(*) FROM dim_producto WHERE negocio_cod = 'COLOCACION') = 0) z)
    UNION ALL
    SELECT 'CAL-12', 'Integridad', 'Ningun hecho quedo con cliente DESCONOCIDO',
           (SELECT COUNT(*) FROM fact_movimiento WHERE cliente_sk = -1)
    UNION ALL
    SELECT 'CAL-13', 'Integridad', 'Ningun hecho quedo con producto DESCONOCIDO',
           (SELECT COUNT(*) FROM fact_movimiento WHERE producto_sk = -1)
    UNION ALL
    SELECT 'CAL-14', 'Dominio', 'Clasificacion de colocaciones dentro del dominio SBS',
           (SELECT COUNT(*) FROM fact_colocacion_mes
            WHERE clasificacion_cod NOT IN ('0','1','2','3','4'))
    UNION ALL
    SELECT 'CAL-15', 'Linaje', 'Toda fila de dim_cliente declara su sistema origen',
           (SELECT COUNT(*) FROM dim_cliente
            WHERE cliente_sk <> -1 AND (sistema_origen IS NULL OR sistema_origen = ''))
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
