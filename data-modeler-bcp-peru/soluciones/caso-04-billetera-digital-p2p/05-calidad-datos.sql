-- =====================================================================================
-- CASO 04 - Reglas de calidad de datos
-- =====================================================================================

SET search_path TO caso04;

\echo '-- CAL-08 (detalle): filas en la particion DEFAULT'
\echo '   Si esta tabla tiene filas, faltan particiones y hay que crearlas YA.'
SELECT COUNT(*) AS filas_en_default FROM transferencia_default;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 04'
\echo '=============================================================='

WITH resultados AS (
    SELECT 'CAL-01' AS regla, 'Dominio' AS familia,
           'Ninguna billetera con saldo negativo' AS descripcion,
           (SELECT COUNT(*) FROM saldo_billetera WHERE saldo < 0) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Cuadre', 'Saldo = suma de movimientos del libro mayor',
           (SELECT COUNT(*) FROM saldo_billetera s
            JOIN (SELECT usuario_id, SUM(monto_con_signo) AS m
                  FROM movimiento_billetera GROUP BY usuario_id) t USING (usuario_id)
            WHERE s.saldo <> t.m)
    UNION ALL
    SELECT 'CAL-03', 'Partida doble', 'Toda transferencia P2P confirmada genera exactamente 2 movimientos',
           (SELECT COUNT(*) FROM (
                SELECT t.transferencia_id
                FROM   transferencia t
                JOIN   movimiento_billetera m ON m.transferencia_id = t.transferencia_id
                                             AND m.fecha_operacion  = t.fecha_operacion
                WHERE  t.tipo_op_cod IN ('ENVIO','PAGO_QR') AND t.estado_cod = 'CONFIRMADA'
                GROUP  BY t.transferencia_id
                HAVING COUNT(*) <> 2) x)
    UNION ALL
    SELECT 'CAL-04', 'Partida doble', 'Los dos movimientos de una P2P suman cero',
           (SELECT COUNT(*) FROM (
                SELECT transferencia_id FROM movimiento_billetera
                WHERE  tipo_op_cod <> 'CARGA'
                GROUP  BY transferencia_id HAVING SUM(monto_con_signo) <> 0) x)
    UNION ALL
    SELECT 'CAL-05', 'Consistencia', 'Una transferencia no confirmada NO mueve dinero',
           (SELECT COUNT(*) FROM transferencia t
            JOIN movimiento_billetera m ON m.transferencia_id = t.transferencia_id
            WHERE t.estado_cod <> 'CONFIRMADA')
    UNION ALL
    SELECT 'CAL-06', 'Dominio', 'Nadie se transfiere a si mismo',
           (SELECT COUNT(*) FROM transferencia WHERE usuario_destino_id = usuario_origen_id)
    UNION ALL
    SELECT 'CAL-07', 'Unicidad', 'Clave de idempotencia unica a nivel global',
           (SELECT COUNT(*) - COUNT(DISTINCT clave_idempotencia) FROM idempotencia)
    UNION ALL
    SELECT 'CAL-08', 'Particionamiento', 'La particion DEFAULT esta vacia',
           (SELECT COUNT(*) FROM transferencia_default)
    UNION ALL
    SELECT 'CAL-09', 'Consistencia', 'Todo rechazo tiene motivo y ningun exito lo tiene',
           (SELECT COUNT(*) FROM transferencia
            WHERE (estado_cod = 'RECHAZADA' AND motivo_cod IS NULL)
               OR (estado_cod <> 'RECHAZADA' AND motivo_cod IS NOT NULL))
    UNION ALL
    SELECT 'CAL-10', 'Consistencia', 'Un solo dispositivo activo por usuario',
           (SELECT COUNT(*) FROM (
                SELECT usuario_id FROM dispositivo WHERE esta_activo
                GROUP BY usuario_id HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-11', 'Dominio', 'Celular peruano valido (9 digitos empezando en 9)',
           (SELECT COUNT(*) FROM usuario_billetera WHERE num_celular !~ '^9[0-9]{8}$')
    UNION ALL
    SELECT 'CAL-12', 'Regulatoria', 'Ninguna operacion confirmada excede el limite por operacion',
           (SELECT COUNT(*) FROM transferencia t
            JOIN usuario_billetera u ON u.usuario_id = t.usuario_origen_id
            JOIN par_limite pl ON pl.segmento_cod = CASE WHEN u.es_negocio THEN 'NEGOCIO' ELSE 'PERSONA_NATURAL' END
                              AND t.fecha_operacion::DATE BETWEEN pl.fecha_desde AND pl.fecha_hasta
            WHERE t.estado_cod = 'CONFIRMADA'
              AND t.tipo_op_cod IN ('ENVIO','PAGO_QR')
              AND t.monto > pl.monto_max_operacion)
    UNION ALL
    SELECT 'CAL-13', 'Integridad referencial', 'Toda transferencia tiene su clave de idempotencia registrada',
           (SELECT COUNT(*) FROM transferencia t
            WHERE NOT EXISTS (SELECT 1 FROM idempotencia i
                              WHERE i.clave_idempotencia = t.clave_idempotencia))
    UNION ALL
    SELECT 'CAL-14', 'Consistencia', 'Todo movimiento cae en la particion de su fecha',
           (SELECT COUNT(*) FROM movimiento_billetera_default)
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
