-- =====================================================================================
-- CASO 10 - PRUEBAS NEGATIVAS
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

SET search_path TO caso10, public;

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
    -- PN-01: Dos campos en la misma posicion del archivo
    BEGIN
        UPDATE reporte_campo SET posicion = (SELECT MIN(posicion) FROM reporte_campo WHERE reporte_cod='RCD' AND version=2)
        WHERE reporte_cod='RCD' AND version=2 AND posicion = (SELECT MAX(posicion) FROM reporte_campo WHERE reporte_cod='RCD' AND version=2);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Dos campos en la misma posicion del archivo',
        'una posicion, un campo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Provision mayor que el saldo de capital
    BEGIN
        UPDATE reporte_detalle SET monto_provision = saldo_capital + 1
        WHERE (envio_id, num_linea) = (SELECT envio_id, num_linea FROM reporte_detalle LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Provision mayor que el saldo de capital',
        'provision <= saldo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Marcar como cuadrado algo que no cuadra
    BEGIN
        UPDATE cuadre_reporte SET esta_cuadrado = TRUE WHERE NOT esta_cuadrado;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Marcar como cuadrado algo que no cuadra',
        'el cuadre se deriva, no se digita', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Un rectificatorio con numero de envio 1
    BEGIN
        UPDATE reporte_envio SET tipo_envio = 'RECTIFICATORIO' WHERE num_envio = 1 AND envio_id = (SELECT MIN(envio_id) FROM reporte_envio);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Un rectificatorio con numero de envio 1',
        'el envio 1 es siempre el original', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Campo con mas decimales que longitud total
    BEGIN
        UPDATE reporte_campo SET decimales = longitud + 1
        WHERE (reporte_cod, version, campo_cod) = (SELECT reporte_cod, version, campo_cod FROM reporte_campo LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Campo con mas decimales que longitud total',
        'decimales <= longitud', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Clasificacion fuera del dominio SBS
    BEGIN
        UPDATE reporte_detalle SET clasificacion_cod = '9'
        WHERE (envio_id, num_linea) = (SELECT envio_id, num_linea FROM reporte_detalle LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Clasificacion fuera del dominio SBS',
        'clasificacion entre 0 y 4', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-07: Dos lineas del mismo deudor, tipo de credito y moneda
    BEGIN
        INSERT INTO reporte_detalle SELECT envio_id, 99999, tipo_doc_cod, num_doc, nombre_deudor,
               tipo_credito_cod, clasificacion_cod, dias_atraso, moneda_cod, saldo_capital,
               monto_provision, tiene_garantia, fecha_corte FROM reporte_detalle LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-07', 'Dos lineas del mismo deudor, tipo de credito y moneda',
        'grano del RCD', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 10'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
