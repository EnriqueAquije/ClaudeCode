-- =====================================================================================
-- CASO 02 - PRUEBAS NEGATIVAS
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

SET search_path TO caso02, public;

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
    -- PN-01: Credito con monto desembolsado cero
    BEGIN
        UPDATE credito SET monto_desembolsado = 0 WHERE credito_id = (SELECT MIN(credito_id) FROM credito);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Credito con monto desembolsado cero',
        'monto estrictamente positivo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Credito que vence antes de desembolsarse
    BEGIN
        UPDATE credito SET fecha_vencimiento = fecha_desembolso - 1 WHERE credito_id = (SELECT MIN(credito_id) FROM credito);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Credito que vence antes de desembolsarse',
        'vencimiento posterior al desembolso', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Dos creditos con el mismo numero
    BEGIN
        UPDATE credito SET num_credito = (SELECT num_credito FROM credito ORDER BY credito_id LIMIT 1)
        WHERE credito_id = (SELECT MAX(credito_id) FROM credito);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Dos creditos con el mismo numero',
        'unicidad del numero de credito', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Cuota cuyo total no es la suma de sus partes
    BEGIN
        UPDATE cronograma_cuota SET monto_cuota = monto_cuota + 100 WHERE cuota_id = (SELECT MIN(cuota_id) FROM cronograma_cuota);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Cuota cuyo total no es la suma de sus partes',
        'cuota = capital + interes + seguro', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Clasificacion alineada MEJOR que la propia
    BEGIN
        UPDATE deudor_clasificacion_mes SET clasificacion_cod = '0'
        WHERE (deudor_id, periodo, tipo_credito_cod, moneda_cod) =
              (SELECT deudor_id, periodo, tipo_credito_cod, moneda_cod FROM deudor_clasificacion_mes
               WHERE clasificacion_propia_cod > '0' LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Clasificacion alineada MEJOR que la propia',
        'el alineamiento solo puede empeorar', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Dos deudores con el mismo documento
    BEGIN
        UPDATE deudor SET tipo_doc_cod = (SELECT tipo_doc_cod FROM deudor ORDER BY deudor_id LIMIT 1),
                          num_doc      = (SELECT num_doc FROM deudor ORDER BY deudor_id LIMIT 1)
        WHERE deudor_id = (SELECT MAX(deudor_id) FROM deudor);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Dos deudores con el mismo documento',
        'unicidad de (tipo_doc, num_doc)', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-07: Tasa de interes negativa
    BEGIN
        UPDATE credito SET tea_pct = -0.5 WHERE credito_id = (SELECT MIN(credito_id) FROM credito);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-07', 'Tasa de interes negativa',
        'TEA dentro de un rango razonable', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 02'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
