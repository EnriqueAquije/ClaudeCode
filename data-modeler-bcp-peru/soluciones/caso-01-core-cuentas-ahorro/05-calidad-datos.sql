-- =====================================================================================
-- CASO 01 - Reglas de calidad de datos
-- =====================================================================================
-- Convención: cada regla devuelve las filas QUE INCUMPLEN. Cero filas = regla cumplida.
-- El resumen final marca OK / FALLA por regla: es lo que revisa validacion/validar.sh
-- =====================================================================================

SET search_path TO caso01;

\echo '== Detalle de incumplimientos (lo ideal es que todo venga vacio) =='

\echo '-- CAL-01: clientes duplicados por tipo y numero de documento'
SELECT tipo_doc_cod, num_doc, COUNT(*) AS veces
FROM   cliente
GROUP  BY tipo_doc_cod, num_doc
HAVING COUNT(*) > 1;

\echo '-- CAL-02: cuentas sin exactamente un titular principal vigente'
SELECT c.cuenta_id, c.num_cuenta, COUNT(ct.cliente_id) AS titulares_vigentes
FROM        cuenta c
LEFT JOIN   cuenta_titular ct ON ct.cuenta_id = c.cuenta_id
                             AND ct.rol_cod = 'TITULAR'
                             AND ct.fecha_hasta IS NULL
GROUP BY    c.cuenta_id, c.num_cuenta
HAVING      COUNT(ct.cliente_id) <> 1;

\echo '-- CAL-03: movimientos huerfanos (cuenta inexistente)'
SELECT m.movimiento_id, m.cuenta_id
FROM        movimiento m
LEFT JOIN   cuenta c ON c.cuenta_id = m.cuenta_id
WHERE       c.cuenta_id IS NULL;

\echo '-- CAL-04: descuadre entre saldo contable y suma de movimientos'
SELECT  c.cuenta_id, c.num_cuenta, c.saldo_contable,
        COALESCE(m.suma, 0) AS suma_movimientos,
        c.saldo_contable - COALESCE(m.suma, 0) AS diferencia
FROM        cuenta c
LEFT JOIN  (SELECT cuenta_id, SUM(monto_con_signo) AS suma FROM movimiento GROUP BY cuenta_id) m
            ON m.cuenta_id = c.cuenta_id
WHERE       c.saldo_contable <> COALESCE(m.suma, 0);

\echo '-- CAL-05: saldo negativo en productos que no lo permiten'
SELECT c.cuenta_id, c.num_cuenta, p.producto_cod, c.saldo_contable
FROM   cuenta   c
JOIN   producto p ON p.producto_id = c.producto_id
WHERE  p.permite_saldo_negativo = FALSE
  AND  c.saldo_contable < 0;

\echo '-- CAL-06: fecha contable anterior a la fecha de operacion'
SELECT movimiento_id, fecha_operacion, fecha_contable
FROM   movimiento
WHERE  fecha_contable < fecha_operacion::DATE;

\echo '-- CAL-07 (adicional): moneda del movimiento distinta de la moneda de la cuenta'
SELECT m.movimiento_id, m.moneda_cod AS moneda_mov, c.moneda_cod AS moneda_cta
FROM   movimiento m
JOIN   cuenta c ON c.cuenta_id = m.cuenta_id
WHERE  m.moneda_cod <> c.moneda_cod;

\echo '-- CAL-08 (adicional): cuentas cerradas con saldo distinto de cero'
SELECT cuenta_id, num_cuenta, estado_cta_cod, saldo_contable
FROM   cuenta
WHERE  estado_cta_cod = 'CER'
  AND  saldo_contable <> 0;

\echo '-- CAL-09 (adicional): extornos mal formados'
SELECT movimiento_id, es_extorno, movimiento_extornado_id
FROM   movimiento
WHERE  (es_extorno = TRUE  AND movimiento_extornado_id IS NULL)
   OR  (es_extorno = FALSE AND movimiento_extornado_id IS NOT NULL);

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 01'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: movimientos' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM movimiento) AS incumple
    UNION ALL
    SELECT 'CAL-01' AS regla, 'Unicidad'        AS familia,
           'Cliente unico por tipo+numero de documento' AS descripcion,
           (SELECT COUNT(*) FROM (SELECT 1 FROM cliente GROUP BY tipo_doc_cod, num_doc HAVING COUNT(*) > 1) t) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Consistencia', 'Exactamente un titular principal vigente por cuenta',
           (SELECT COUNT(*) FROM (
                SELECT c.cuenta_id FROM cuenta c
                LEFT JOIN cuenta_titular ct ON ct.cuenta_id = c.cuenta_id
                     AND ct.rol_cod = 'TITULAR' AND ct.fecha_hasta IS NULL
                GROUP BY c.cuenta_id HAVING COUNT(ct.cliente_id) <> 1) t)
    UNION ALL
    SELECT 'CAL-03', 'Integridad referencial', 'Todo movimiento apunta a una cuenta existente',
           (SELECT COUNT(*) FROM movimiento m LEFT JOIN cuenta c ON c.cuenta_id = m.cuenta_id
            WHERE c.cuenta_id IS NULL)
    UNION ALL
    SELECT 'CAL-04', 'Cuadre', 'saldo_contable = suma de movimientos',
           (SELECT COUNT(*) FROM cuenta c
            LEFT JOIN (SELECT cuenta_id, SUM(monto_con_signo) s FROM movimiento GROUP BY cuenta_id) m
                   ON m.cuenta_id = c.cuenta_id
            WHERE c.saldo_contable <> COALESCE(m.s, 0))
    UNION ALL
    SELECT 'CAL-05', 'Dominio', 'Sin saldo negativo en productos que no lo permiten',
           (SELECT COUNT(*) FROM cuenta c JOIN producto p ON p.producto_id = c.producto_id
            WHERE p.permite_saldo_negativo = FALSE AND c.saldo_contable < 0)
    UNION ALL
    SELECT 'CAL-06', 'Consistencia', 'fecha_contable >= fecha_operacion',
           (SELECT COUNT(*) FROM movimiento WHERE fecha_contable < fecha_operacion::DATE)
    UNION ALL
    SELECT 'CAL-07', 'Consistencia', 'Moneda del movimiento = moneda de la cuenta',
           (SELECT COUNT(*) FROM movimiento m JOIN cuenta c ON c.cuenta_id = m.cuenta_id
            WHERE m.moneda_cod <> c.moneda_cod)
    UNION ALL
    SELECT 'CAL-08', 'Consistencia', 'Cuenta cerrada con saldo cero',
           (SELECT COUNT(*) FROM cuenta WHERE estado_cta_cod = 'CER' AND saldo_contable <> 0)
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'Extornos bien formados',
           (SELECT COUNT(*) FROM movimiento
            WHERE (es_extorno AND movimiento_extornado_id IS NULL)
               OR (NOT es_extorno AND movimiento_extornado_id IS NOT NULL))
)
SELECT  regla,
        familia,
        descripcion,
        incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
