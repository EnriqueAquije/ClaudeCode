-- =====================================================================================
-- CASO 01 - PRUEBAS NEGATIVAS
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

SET search_path TO caso01, public;

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
    -- PN-01: Dos clientes con el mismo documento
    BEGIN
        INSERT INTO cliente (tipo_doc_cod, num_doc, ape_paterno, nombres, fecha_alta)
        SELECT tipo_doc_cod, num_doc, 'PRUEBA', 'DUPLICADO', CURRENT_DATE FROM cliente LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Dos clientes con el mismo documento',
        'unicidad de (tipo_doc, num_doc)', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Movimiento de importe cero
    BEGIN
        INSERT INTO movimiento (cuenta_id, fecha_operacion, fecha_contable, tipo_mov_cod,
               canal_cod, moneda_cod, monto, monto_con_signo, saldo_posterior, num_operacion)
        VALUES (1, CURRENT_TIMESTAMP, CURRENT_DATE, 'DEP', 'APP', 'PEN', 0, 0, 0, 'PN-CERO');
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Movimiento de importe cero',
        'monto estrictamente positivo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Dos titulares principales en una cuenta
    BEGIN
        INSERT INTO cuenta_titular (cuenta_id, cliente_id, rol_cod, fecha_desde)
        VALUES (1, 2, 'TITULAR', CURRENT_DATE);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Dos titulares principales en una cuenta',
        'un solo titular vigente por cuenta', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Numero de operacion repetido
    BEGIN
        INSERT INTO movimiento (cuenta_id, fecha_operacion, fecha_contable, tipo_mov_cod,
               canal_cod, moneda_cod, monto, monto_con_signo, saldo_posterior, num_operacion)
        SELECT cuenta_id, fecha_operacion, fecha_contable, tipo_mov_cod, canal_cod,
               moneda_cod, monto, monto_con_signo, saldo_posterior, num_operacion
        FROM   movimiento LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Numero de operacion repetido',
        'unicidad del numero de operacion', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Movimiento sobre una cuenta inexistente
    BEGIN
        INSERT INTO movimiento (cuenta_id, fecha_operacion, fecha_contable, tipo_mov_cod,
               canal_cod, moneda_cod, monto, monto_con_signo, saldo_posterior, num_operacion)
        VALUES (999999999, CURRENT_TIMESTAMP, CURRENT_DATE, 'DEP', 'APP', 'PEN', 10, 10, 10, 'PN-HUERFANO');
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Movimiento sobre una cuenta inexistente',
        'integridad referencial contra cuenta', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Fecha contable anterior a la de operacion
    BEGIN
        INSERT INTO movimiento (cuenta_id, fecha_operacion, fecha_contable, tipo_mov_cod,
               canal_cod, moneda_cod, monto, monto_con_signo, saldo_posterior, num_operacion)
        VALUES (1, CURRENT_TIMESTAMP, CURRENT_DATE - 30, 'DEP', 'APP', 'PEN', 10, 10, 10, 'PN-FECHAS');
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Fecha contable anterior a la de operacion',
        'coherencia entre las dos fechas', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 01'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
