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
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: movimientos de billetera' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM movimiento_billetera) AS incumple
    UNION ALL
    -- La identidad contable de la billetera: lo que el banco puso en la cuenta puente es
    -- exactamente lo que tienen los usuarios. Si no cuadra, el dinero se creo o se destruyo.
    SELECT 'CAL-16' AS regla, 'Partida doble' AS familia,
           'La posicion de la cuenta puente es menos la suma de saldos de usuario' AS descripcion,
           (SELECT CASE WHEN COALESCE((SELECT SUM(monto_con_signo) FROM movimiento_billetera WHERE usuario_id = 0), 0)
                      + COALESCE((SELECT SUM(saldo) FROM saldo_billetera), 0) = 0
                   THEN 0 ELSE 1 END) AS incumple
    UNION ALL
    SELECT 'CAL-17', 'Partida doble', 'Toda operacion confirmada genera exactamente 2 movimientos',
           (SELECT COUNT(*) FROM (
                SELECT t.transferencia_id, t.fecha_operacion
                FROM   transferencia t
                JOIN   movimiento_billetera m ON m.transferencia_id = t.transferencia_id
                                             AND m.fecha_operacion  = t.fecha_operacion
                WHERE  t.estado_cod = 'CONFIRMADA'
                GROUP BY 1,2 HAVING COUNT(*) <> 2) x)
    UNION ALL
    -- RN-10 estaba cubierta en un tercio: solo se verificaba el limite POR OPERACION.
    -- El limite DIARIO por monto y por cantidad no lo miraba nadie, y es el que de verdad
    -- se excede: cada operacion es legal y la suma del dia no.
    SELECT 'CAL-18' AS regla, 'Regulatoria' AS familia,
           'Las operaciones que exceden el limite diario estan identificadas' AS descripcion,
           (SELECT COUNT(*) FROM (
                SELECT t.usuario_origen_id, t.fecha_operacion::DATE AS dia,
                       SUM(t.monto) AS monto_dia, COUNT(*) AS ops
                FROM   transferencia t
                WHERE  t.estado_cod = 'CONFIRMADA' AND t.tipo_op_cod IN ('ENVIO','PAGO_QR')
                GROUP BY 1,2) a
            JOIN usuario_billetera u ON u.usuario_id = a.usuario_origen_id
            JOIN par_limite pl ON pl.segmento_cod = CASE WHEN u.es_negocio THEN 'NEGOCIO' ELSE 'PERSONA_NATURAL' END
                              AND a.dia BETWEEN pl.fecha_desde AND pl.fecha_hasta
            WHERE a.ops > pl.num_max_dia) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Dominio',
           'Ninguna billetera con saldo negativo',
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
    -- SIN EXCEPCIONES. La version anterior excluia las CARGAS (`tipo_op_cod <> 'CARGA'`)
    -- porque no cuadraban: tenian una sola pata. Excluir de una regla de cuadre justo lo
    -- que no cuadra es como tachar la pregunta que no sabes responder. Con la cuenta puente
    -- modelada, la excepcion sobra y la regla dice lo que siempre debio decir.
    SELECT 'CAL-04', 'Partida doble', 'Los movimientos de TODA transferencia suman cero',
           (SELECT COUNT(*) FROM (
                SELECT transferencia_id FROM movimiento_billetera
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
