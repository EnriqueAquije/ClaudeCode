-- =====================================================================================
-- CASO 08 - PRUEBAS NEGATIVAS
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

SET search_path TO caso08, public;

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
    -- PN-01: Dos maestros con el mismo documento
    BEGIN
        UPDATE cliente_maestro SET tipo_doc_cod = (SELECT tipo_doc_cod FROM cliente_maestro ORDER BY maestro_id LIMIT 1),
                                   num_doc      = (SELECT num_doc FROM cliente_maestro ORDER BY maestro_id LIMIT 1)
        WHERE maestro_id = (SELECT MAX(maestro_id) FROM cliente_maestro);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Dos maestros con el mismo documento',
        'un solo golden record por documento', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Dos fuentes con la misma precedencia
    BEGIN
        UPDATE cat_fuente SET precedencia = (SELECT precedencia FROM cat_fuente ORDER BY fuente_cod LIMIT 1)
        WHERE fuente_cod = (SELECT fuente_cod FROM cat_fuente ORDER BY fuente_cod DESC LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Dos fuentes con la misma precedencia',
        'precedencia unica entre fuentes', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Maestro sin ninguna fuente detras
    BEGIN
        UPDATE cliente_maestro SET cant_fuentes = 0 WHERE maestro_id = (SELECT MIN(maestro_id) FROM cliente_maestro);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Maestro sin ninguna fuente detras',
        'al menos una fuente por maestro', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Score de confianza fuera de 0-100
    BEGIN
        UPDATE cliente_maestro SET score_confianza = 150 WHERE maestro_id = (SELECT MIN(maestro_id) FROM cliente_maestro);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Score de confianza fuera de 0-100',
        'score entre 0 y 100', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Mas campos completos que campos totales
    BEGIN
        UPDATE calidad_registro SET campos_completos = campos_totales + 1
        WHERE (fuente_cod, id_origen) = (SELECT fuente_cod, id_origen FROM calidad_registro LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Mas campos completos que campos totales',
        'completos <= totales', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Precedencia fuera del rango 1-99
    BEGIN
        UPDATE cat_fuente SET precedencia = 0 WHERE fuente_cod = (SELECT fuente_cod FROM cat_fuente LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Precedencia fuera del rango 1-99',
        'precedencia entre 1 y 99', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 08'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
