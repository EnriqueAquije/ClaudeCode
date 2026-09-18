-- =====================================================================================
-- CASO 07 - PRUEBAS NEGATIVAS
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

SET search_path TO caso07, public;

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
    -- PN-01: Alerta con severidad fuera del rango 1-5
    BEGIN
        UPDATE alerta SET severidad = 9 WHERE alerta_id = (SELECT MIN(alerta_id) FROM alerta);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Alerta con severidad fuera del rango 1-5',
        'severidad entre 1 y 5', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Alerta con monto involucrado cero
    BEGIN
        UPDATE alerta SET monto_involucrado = 0 WHERE alerta_id = (SELECT MIN(alerta_id) FROM alerta);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Alerta con monto involucrado cero',
        'monto estrictamente positivo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Alerta cuyo periodo termina antes de empezar
    BEGIN
        UPDATE alerta SET fecha_hasta_eval = fecha_desde_eval - 1 WHERE alerta_id = (SELECT MIN(alerta_id) FROM alerta);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Alerta cuyo periodo termina antes de empezar',
        'periodo de evaluacion coherente', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Caso cerrado sin disposicion
    BEGIN
        UPDATE caso_investigacion SET disposicion_cod = NULL WHERE caso_id = (SELECT MIN(caso_id) FROM caso_investigacion WHERE fecha_cierre IS NOT NULL);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Caso cerrado sin disposicion',
        'todo cierre lleva disposicion', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Caso que cierra antes de abrirse
    BEGIN
        UPDATE caso_investigacion SET fecha_cierre = fecha_apertura - 1 WHERE caso_id = (SELECT MIN(caso_id) FROM caso_investigacion WHERE fecha_cierre IS NOT NULL);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Caso que cierra antes de abrirse',
        'cierre posterior a la apertura', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Dos numeros de caso iguales
    BEGIN
        UPDATE caso_investigacion SET num_caso = (SELECT num_caso FROM caso_investigacion ORDER BY caso_id LIMIT 1)
        WHERE caso_id = (SELECT MAX(caso_id) FROM caso_investigacion);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Dos numeros de caso iguales',
        'unicidad del numero de caso', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 07'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
