-- =====================================================================================
-- CASO 06 - Reglas de calidad de datos
-- =====================================================================================

SET search_path TO caso06;

\echo '-- CAL-07 (detalle): variaciones diarias sospechosas (posible error de carga)'
-- Regla real de banca: una variación diaria mayor al 5% en el tipo de cambio es
-- posible pero excepcional. Si aparece, lo primero que se revisa es la carga, no el mercado.
SELECT fecha, moneda_cod, tc_anterior, tc_contable, variacion_pct
FROM   vw_variacion_cambiaria
WHERE  ABS(variacion_pct) > 5.0
ORDER BY ABS(variacion_pct) DESC
LIMIT 20;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 06'
\echo '=============================================================='

WITH resultados AS (
    SELECT 'CAL-01' AS regla, 'Completitud' AS familia,
           'Todo dia del calendario tiene tipo de cambio vigente para USD contable' AS descripcion,
           (SELECT COUNT(*) FROM cat_calendario c
            WHERE c.fecha > (SELECT MIN(fecha) FROM tipo_cambio_publicado WHERE moneda_cod = 'USD')
              AND NOT EXISTS (SELECT 1 FROM tipo_cambio_vigente v
                              WHERE v.fecha = c.fecha AND v.moneda_cod = 'USD'
                                AND v.tipo_tc_cod = 'CONTABLE_SBS')) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Consistencia', 'Ninguna cotizacion publicada en dia no habil',
           (SELECT COUNT(*) FROM tipo_cambio_publicado p
            JOIN cat_calendario c ON c.fecha = p.fecha
            WHERE NOT c.es_dia_habil)
    UNION ALL
    SELECT 'CAL-03', 'Trazabilidad', 'Coherencia entre origen_valor, dias_arrastre y fecha_cotizacion',
           (SELECT COUNT(*) FROM tipo_cambio_vigente
            WHERE (origen_valor = 'PUBLICADO' AND (dias_arrastre <> 0 OR fecha_cotizacion <> fecha))
               OR (origen_valor = 'ARRASTRE'  AND (dias_arrastre <= 0 OR fecha_cotizacion >= fecha)))
    UNION ALL
    SELECT 'CAL-04', 'Dominio', 'El tipo de cambio venta siempre es mayor que el de compra',
           (SELECT COUNT(*) FROM vw_tipo_cambio_diario
            WHERE tc_compra IS NOT NULL AND tc_venta IS NOT NULL AND tc_venta <= tc_compra)
    UNION ALL
    SELECT 'CAL-05', 'Cuadre', 'posicion_me = activos_me - pasivos_me',
           (SELECT COUNT(*) FROM posicion_cambio_dia
            WHERE posicion_me <> activos_me - pasivos_me)
    UNION ALL
    SELECT 'CAL-06', 'Cuadre', 'posicion_mn = posicion_me x tipo de cambio de cierre',
           (SELECT COUNT(*) FROM posicion_cambio_dia
            WHERE posicion_mn <> ROUND(posicion_me * tipo_cambio_cierre, 2))
    UNION ALL
    SELECT 'CAL-07', 'Razonabilidad', 'Sin variaciones diarias mayores al 5% (posible error de carga)',
           (SELECT COUNT(*) FROM vw_variacion_cambiaria WHERE ABS(variacion_pct) > 5.0)
    UNION ALL
    SELECT 'CAL-08', 'Trazabilidad', 'Toda fecha de cotizacion existe en la serie publicada',
           (SELECT COUNT(*) FROM tipo_cambio_vigente v
            WHERE NOT EXISTS (SELECT 1 FROM tipo_cambio_publicado p
                              WHERE p.fecha       = v.fecha_cotizacion
                                AND p.moneda_cod  = v.moneda_cod
                                AND p.tipo_tc_cod = v.tipo_tc_cod))
    UNION ALL
    SELECT 'CAL-09', 'Dominio', 'Existe exactamente una moneda local',
           (SELECT ABS(COUNT(*) - 1) FROM cat_moneda WHERE es_moneda_local)
    UNION ALL
    SELECT 'CAL-10', 'Consistencia', 'Todo feriado tiene nombre y ningun no feriado lo tiene',
           (SELECT COUNT(*) FROM cat_calendario
            WHERE (es_feriado AND nombre_feriado IS NULL)
               OR (NOT es_feriado AND nombre_feriado IS NOT NULL))
    UNION ALL
    SELECT 'CAL-11', 'Consistencia', 'Ningun dia habil es fin de semana o feriado',
           (SELECT COUNT(*) FROM cat_calendario
            WHERE es_dia_habil AND (es_fin_semana OR es_feriado))
    UNION ALL
    SELECT 'CAL-12', 'Razonabilidad', 'Arrastre no mayor a 6 dias (feriado largo maximo esperado)',
           (SELECT COUNT(*) FROM tipo_cambio_vigente WHERE dias_arrastre > 6)
    UNION ALL
    SELECT 'CAL-13', 'Completitud', 'Toda posicion diaria tiene su tipo de cambio de cierre',
           (SELECT COUNT(*) FROM posicion_cambio_dia WHERE tipo_cambio_cierre IS NULL)
    UNION ALL
    SELECT 'CAL-14', 'Consistencia', 'La funcion de conversion devuelve el mismo valor que la tabla',
           (SELECT COUNT(*) FROM saldo_me_dia s
            WHERE s.fecha = DATE '2026-09-15'
              AND fn_convertir_a_mn(s.saldo_me, s.moneda_cod, s.fecha)
                  <> ROUND(s.saldo_me * (SELECT v.valor FROM tipo_cambio_vigente v
                                         WHERE v.fecha = s.fecha AND v.moneda_cod = s.moneda_cod
                                           AND v.tipo_tc_cod = 'CONTABLE_SBS'), 2))
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
