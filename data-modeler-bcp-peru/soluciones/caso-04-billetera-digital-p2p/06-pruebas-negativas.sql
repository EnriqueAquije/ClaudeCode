-- =====================================================================================
-- CASO 04 - PRUEBAS NEGATIVAS
-- =====================================================================================
--  Las reglas de 05-calidad-datos.sql comprueban los DATOS. Estas comprueban el MODELO.
--
--  Si quitas una restriccion de tu DDL, las reglas de calidad pueden seguir dando OK:
--  no hay filas que la incumplan en la carga, asi que no hay nada que contar. El hueco
--  solo aparece el dia que alguien inserta el dato imposible, en produccion.
--
--  Una prueba negativa intenta la operacion PROHIBIDA y exige que la base la rechace.
--  Se comprueba por COMPORTAMIENTO, no por nombre de restriccion: da igual como hayas
--  llamado tus constraints, lo que importa es que el dato imposible no entre.
--
--  Todo corre con captura de excepcion y ROLLBACK implicito: NO ensucia la base.
-- =====================================================================================

SET search_path TO caso04, public;

DROP TABLE IF EXISTS pg_temp.resultado_pn;
CREATE TEMP TABLE resultado_pn (
    prueba      TEXT,
    descripcion TEXT,
    deberia     TEXT,
    estado      TEXT
);

DO $$
DECLARE
    v_ok BOOLEAN;
BEGIN
    -- PN-01: Transferencia de un usuario a si mismo
    BEGIN
        UPDATE transferencia SET usuario_destino_id = usuario_origen_id
        WHERE (transferencia_id, fecha_operacion) = (SELECT transferencia_id, fecha_operacion FROM transferencia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Transferencia de un usuario a si mismo',
        'origen distinto de destino', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Saldo de billetera negativo
    BEGIN
        UPDATE saldo_billetera SET saldo_disponible = -100 WHERE usuario_id = (SELECT MIN(usuario_id) FROM saldo_billetera);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Saldo de billetera negativo',
        'saldo mayor o igual a cero', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Movimiento de importe cero
    BEGIN
        UPDATE movimiento_billetera SET monto = 0
        WHERE (movimiento_id, fecha_operacion) = (SELECT movimiento_id, fecha_operacion FROM movimiento_billetera LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Movimiento de importe cero',
        'monto estrictamente positivo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Movimiento cuyo signo no corresponde al importe
    BEGIN
        UPDATE movimiento_billetera SET monto_con_signo = monto + 1
        WHERE (movimiento_id, fecha_operacion) = (SELECT movimiento_id, fecha_operacion FROM movimiento_billetera LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Movimiento cuyo signo no corresponde al importe',
        'valor absoluto del importe con signo = importe', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Clave de idempotencia repetida en el registro
    BEGIN
        INSERT INTO idempotencia (clave_idempotencia, transferencia_id, fecha_registro)
        SELECT clave_idempotencia, transferencia_id, fecha_registro FROM idempotencia LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Clave de idempotencia repetida en el registro',
        'unicidad de la clave de idempotencia', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Transferencia confirmada con motivo de rechazo
    BEGIN
        UPDATE transferencia SET motivo_cod = 'SALDO_INSUF'
        WHERE (transferencia_id, fecha_operacion) = (SELECT transferencia_id, fecha_operacion FROM transferencia WHERE estado_cod='CONFIRMADA' LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Transferencia confirmada con motivo de rechazo',
        'motivo solo en transferencias rechazadas', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 04'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
