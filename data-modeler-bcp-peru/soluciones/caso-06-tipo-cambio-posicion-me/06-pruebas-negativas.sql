-- =====================================================================================
-- CASO 06 - PRUEBAS NEGATIVAS
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

SET search_path TO caso06, public;

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
    -- PN-01: Tipo de cambio publicado con valor cero
    BEGIN
        UPDATE tipo_cambio_publicado SET valor = 0 WHERE (fecha, moneda_cod, tipo_tc_cod) = (SELECT fecha, moneda_cod, tipo_tc_cod FROM tipo_cambio_publicado LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Tipo de cambio publicado con valor cero',
        'cotizacion estrictamente positiva', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Valor marcado PUBLICADO pero con dias de arrastre
    BEGIN
        UPDATE tipo_cambio_vigente SET origen_valor = 'PUBLICADO'
        WHERE (fecha, moneda_cod, tipo_tc_cod) = (SELECT fecha, moneda_cod, tipo_tc_cod FROM tipo_cambio_vigente WHERE origen_valor='ARRASTRE' LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Valor marcado PUBLICADO pero con dias de arrastre',
        'coherencia entre origen y arrastre', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Posicion que no cuadra con activos menos pasivos
    BEGIN
        UPDATE posicion_cambio_dia SET posicion_me = posicion_me + 1000 WHERE (fecha, moneda_cod) = (SELECT fecha, moneda_cod FROM posicion_cambio_dia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Posicion que no cuadra con activos menos pasivos',
        'posicion = activos - pasivos', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Feriado sin nombre de feriado
    BEGIN
        UPDATE cat_calendario SET nombre_feriado = NULL WHERE es_feriado;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Feriado sin nombre de feriado',
        'todo feriado tiene nombre', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Naturaleza de saldo fuera del dominio
    BEGIN
        UPDATE saldo_me_dia SET naturaleza = 'NEUTRO' WHERE (fecha, moneda_cod, naturaleza) = (SELECT fecha, moneda_cod, naturaleza FROM saldo_me_dia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Naturaleza de saldo fuera del dominio',
        'ACTIVO o PASIVO', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Origen del valor fuera del dominio
    BEGIN
        UPDATE tipo_cambio_vigente SET origen_valor = 'INVENTADO' WHERE (fecha, moneda_cod, tipo_tc_cod) = (SELECT fecha, moneda_cod, tipo_tc_cod FROM tipo_cambio_vigente LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Origen del valor fuera del dominio',
        'PUBLICADO o ARRASTRE', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 06'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
