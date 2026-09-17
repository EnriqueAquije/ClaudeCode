-- =====================================================================================
-- CASO 03 - Reglas de calidad de datos
-- =====================================================================================

SET search_path TO caso03;

\echo '-- CAL-02 (detalle): encadenamiento roto entre ciclos'
SELECT cuenta_tj_id, periodo, saldo_anterior, saldo_actual_previo
FROM (
    SELECT cuenta_tj_id, periodo, saldo_anterior,
           LAG(saldo_actual) OVER (PARTITION BY cuenta_tj_id ORDER BY periodo) AS saldo_actual_previo
    FROM   estado_cuenta
) t
WHERE saldo_actual_previo IS NOT NULL AND saldo_anterior <> saldo_actual_previo
LIMIT 20;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 03'
\echo '=============================================================='

WITH consumo_trx AS (
    SELECT cuenta_tj_id, periodo_cargo AS periodo, SUM(monto) AS monto
    FROM   transaccion WHERE tipo_trx_cod IN ('CON','DISP') GROUP BY 1, 2
    UNION ALL
    SELECT t.cuenta_tj_id, tc.periodo_cargo, SUM(tc.monto_cuota)
    FROM   transaccion_cuota tc JOIN transaccion t ON t.transaccion_id = tc.transaccion_id
    GROUP  BY 1, 2
),
consumo AS (SELECT cuenta_tj_id, periodo, SUM(monto) AS monto FROM consumo_trx GROUP BY 1, 2),
resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: transacciones de tarjeta' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM transaccion) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Cuadre',
           'Estado de cuenta: saldo_actual = anterior + consumos + cargos - pagos',
           (SELECT COUNT(*) FROM estado_cuenta
            WHERE saldo_actual <> saldo_anterior + total_consumos + total_cargos - total_pagos) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Cuadre', 'Encadenamiento: saldo anterior = saldo actual del ciclo previo',
           (SELECT COUNT(*) FROM (
                SELECT saldo_anterior,
                       LAG(saldo_actual) OVER (PARTITION BY cuenta_tj_id ORDER BY periodo) AS prev
                FROM estado_cuenta) t
            WHERE prev IS NOT NULL AND saldo_anterior <> prev)
    UNION ALL
    SELECT 'CAL-03', 'Cuadre', 'total_consumos coincide con las transacciones del ciclo',
           (SELECT COUNT(*) FROM estado_cuenta ec
            LEFT JOIN consumo c ON c.cuenta_tj_id = ec.cuenta_tj_id AND c.periodo = ec.periodo
            WHERE ec.total_consumos <> COALESCE(c.monto, 0))
    UNION ALL
    SELECT 'CAL-04', 'Cuadre', 'Suma de cuotas = monto de la compra fraccionada',
           (SELECT COUNT(*) FROM (
                SELECT t.transaccion_id FROM transaccion t
                JOIN transaccion_cuota tc ON tc.transaccion_id = t.transaccion_id
                WHERE t.tipo_trx_cod = 'CUO'
                GROUP BY t.transaccion_id, t.monto
                HAVING SUM(tc.monto_capital) <> t.monto) x)
    UNION ALL
    SELECT 'CAL-05', 'Consistencia', 'Cantidad de cuotas generadas = num_cuotas de la transaccion',
           (SELECT COUNT(*) FROM (
                SELECT t.transaccion_id FROM transaccion t
                JOIN transaccion_cuota tc ON tc.transaccion_id = t.transaccion_id
                GROUP BY t.transaccion_id, t.num_cuotas
                HAVING COUNT(*) <> t.num_cuotas) x)
    UNION ALL
    SELECT 'CAL-06', 'Dominio', 'Ninguna cuenta con saldo negativo (seria un saldo a favor no modelado)',
           (SELECT COUNT(*) FROM estado_cuenta WHERE saldo_actual < 0)
    UNION ALL
    SELECT 'CAL-07', 'Consistencia', 'Un solo plastico TITULAR activo por cuenta',
           (SELECT COUNT(*) FROM (
                SELECT cuenta_tj_id FROM plastico
                WHERE tipo_plastico = 'TITULAR' AND esta_activo
                GROUP BY cuenta_tj_id HAVING COUNT(*) <> 1) x)
    UNION ALL
    SELECT 'CAL-08', 'Consistencia', 'Toda transaccion cae dentro de un ciclo existente de su cuenta',
           (SELECT COUNT(*) FROM transaccion t
            WHERE NOT EXISTS (SELECT 1 FROM ciclo_facturacion c
                              WHERE c.cuenta_tj_id = t.cuenta_tj_id AND c.periodo = t.periodo_cargo))
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'Vigencias de linea de credito sin solapamiento',
           (SELECT COUNT(*) FROM linea_credito_hist a
            JOIN linea_credito_hist b ON b.cuenta_tj_id = a.cuenta_tj_id
                                     AND b.fecha_desde > a.fecha_desde
                                     AND b.fecha_desde <= a.fecha_hasta)
    UNION ALL
    SELECT 'CAL-10', 'Dominio', 'Pago minimo nunca mayor que el saldo facturado',
           (SELECT COUNT(*) FROM estado_cuenta WHERE pago_minimo > GREATEST(saldo_actual, 0))
    UNION ALL
    SELECT 'CAL-11', 'Seguridad', 'Ningun numero de tarjeta almacenado sin enmascarar',
           (SELECT COUNT(*) FROM plastico WHERE num_plastico_enmasc !~ '\*')
    UNION ALL
    SELECT 'CAL-12', 'Consistencia', 'Fecha de vencimiento posterior al cierre del ciclo',
           (SELECT COUNT(*) FROM ciclo_facturacion WHERE fecha_vencimiento <= fecha_cierre)
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
