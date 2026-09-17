-- =====================================================================================
-- CASO 02 - Reglas de calidad de datos
-- Cada regla devuelve las filas QUE INCUMPLEN. Cero filas = regla cumplida.
-- =====================================================================================

SET search_path TO caso02;

\echo '-- CAL-03 (detalle): clasificacion incoherente con los dias de atraso'
SELECT  dcm.deudor_id, dcm.periodo, dcm.tipo_credito_cod, dcm.dias_atraso,
        dcm.clasificacion_cod                                              AS clasif_registrada,
        fn_clasificar(dcm.tipo_credito_cod, dcm.dias_atraso, dcm.fecha_corte) AS clasif_esperada
FROM    deudor_clasificacion_mes dcm
WHERE   dcm.clasificacion_cod <> fn_clasificar(dcm.tipo_credito_cod, dcm.dias_atraso, dcm.fecha_corte)
LIMIT 20;

\echo '-- CAL-08 (detalle): solapamiento o hueco en los tramos de dias por tipo de credito'
WITH tramos AS (
    SELECT  tipo_credito_cod, clasificacion_cod, dias_desde, dias_hasta,
            LEAD(dias_desde) OVER (PARTITION BY tipo_credito_cod ORDER BY dias_desde) AS sig_desde
    FROM    par_clasificacion_dias
    WHERE   fecha_hasta = DATE '9999-12-31'
)
SELECT tipo_credito_cod, clasificacion_cod, dias_desde, dias_hasta, sig_desde,
       CASE WHEN sig_desde <= dias_hasta THEN 'SOLAPAMIENTO' ELSE 'HUECO' END AS problema
FROM   tramos
WHERE  sig_desde IS NOT NULL
  AND  sig_desde <> dias_hasta + 1;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 02'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: cuotas de credito' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM cronograma_cuota) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Unicidad',
           'Deudor unico por tipo+numero de documento',
           (SELECT COUNT(*) FROM (SELECT 1 FROM deudor GROUP BY tipo_doc_cod, num_doc HAVING COUNT(*) > 1) t) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Consistencia', 'Toda solicitud rechazada tiene motivo (y solo ella)',
           (SELECT COUNT(*) FROM solicitud_credito
            WHERE (estado_sol_cod = 'RECHAZADA' AND motivo_cod IS NULL)
               OR (estado_sol_cod <> 'RECHAZADA' AND motivo_cod IS NOT NULL))
    UNION ALL
    SELECT 'CAL-03', 'Regulatoria', 'Clasificacion SBS coherente con dias de atraso y norma vigente',
           (SELECT COUNT(*) FROM deudor_clasificacion_mes dcm
            WHERE dcm.clasificacion_cod
                  <> fn_clasificar(dcm.tipo_credito_cod, dcm.dias_atraso, dcm.fecha_corte))
    UNION ALL
    SELECT 'CAL-04', 'Cuadre', 'Provision = saldo capital x tasa de provision',
           (SELECT COUNT(*) FROM deudor_clasificacion_mes
            WHERE monto_provision <> ROUND(saldo_capital * tasa_provision, 2))
    UNION ALL
    SELECT 'CAL-05', 'Cuadre', 'Cuota = capital + interes + seguro',
           (SELECT COUNT(*) FROM cronograma_cuota
            WHERE monto_cuota <> monto_capital + monto_interes + monto_seguro)
    UNION ALL
    SELECT 'CAL-06', 'Integridad referencial', 'Todo credito proviene de una solicitud desembolsada',
           (SELECT COUNT(*) FROM credito c JOIN solicitud_credito s ON s.solicitud_id = c.solicitud_id
            WHERE s.estado_sol_cod <> 'DESEMBOLSADA')
    UNION ALL
    SELECT 'CAL-07', 'Cuadre', 'Suma del capital del cronograma = monto desembolsado',
           (SELECT COUNT(*) FROM (
                SELECT c.credito_id
                FROM   credito c
                JOIN   cronograma_cuota cu ON cu.credito_id = c.credito_id
                GROUP  BY c.credito_id, c.monto_desembolsado
                HAVING SUM(cu.monto_capital) <> c.monto_desembolsado) t)
    UNION ALL
    SELECT 'CAL-08', 'Parametros', 'Tramos de dias sin solapamientos ni huecos',
           (SELECT COUNT(*) FROM (
                SELECT tipo_credito_cod, dias_hasta,
                       LEAD(dias_desde) OVER (PARTITION BY tipo_credito_cod ORDER BY dias_desde) AS sig
                FROM   par_clasificacion_dias WHERE fecha_hasta = DATE '9999-12-31') t
            WHERE sig IS NOT NULL AND sig <> dias_hasta + 1)
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'El estado actual coincide con el ultimo de la historia',
           (SELECT COUNT(*) FROM solicitud_credito s
            JOIN LATERAL (SELECT h.estado_sol_cod FROM solicitud_estado_hist h
                          WHERE h.solicitud_id = s.solicitud_id
                          ORDER BY h.secuencia DESC LIMIT 1) ult ON TRUE
            WHERE ult.estado_sol_cod <> s.estado_sol_cod
              AND NOT (s.estado_sol_cod = 'EN_EVAL' AND ult.estado_sol_cod = 'EN_EVAL'))
    UNION ALL
    SELECT 'CAL-10', 'Dominio', 'Score dentro del rango 0-1000 y ratio no negativo',
           (SELECT COUNT(*) FROM evaluacion_crediticia
            WHERE score NOT BETWEEN 0 AND 1000 OR ratio_cuota_ingreso < 0)
    UNION ALL
    SELECT 'CAL-11', 'Completitud', 'Todo credito vigente tiene al menos una clasificacion mensual',
           (SELECT COUNT(*) FROM credito c
            WHERE c.estado_credito = 'VIGENTE'
              AND NOT EXISTS (SELECT 1 FROM deudor_clasificacion_mes d
                              WHERE d.deudor_id = c.deudor_id))
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
