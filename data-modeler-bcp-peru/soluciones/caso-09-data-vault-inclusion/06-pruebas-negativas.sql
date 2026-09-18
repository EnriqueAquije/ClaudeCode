-- =====================================================================================
-- CASO 09 - PRUEBAS NEGATIVAS
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

SET search_path TO caso09, public;

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
    -- PN-01: Dos hubs con la misma llave de negocio
    BEGIN
        UPDATE hub_persona SET tipo_doc_bk = (SELECT tipo_doc_bk FROM hub_persona ORDER BY persona_hk LIMIT 1),
                               num_doc_bk  = (SELECT num_doc_bk FROM hub_persona ORDER BY persona_hk LIMIT 1)
        WHERE persona_hk = (SELECT persona_hk FROM hub_persona ORDER BY persona_hk DESC LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Dos hubs con la misma llave de negocio',
        'una llave de negocio, un hub', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: El mismo link repetido
    BEGIN
        INSERT INTO lnk_persona_producto (persona_producto_hk, persona_hk, producto_hk, fecha_carga, sistema_origen)
        SELECT MD5(persona_producto_hk || 'x'), persona_hk, producto_hk, fecha_carga, sistema_origen
        FROM   lnk_persona_producto LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'El mismo link repetido',
        'una relacion, un link', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Satelite sin sistema de origen
    BEGIN
        UPDATE sat_persona_demografia SET sistema_origen = NULL
        WHERE (persona_hk, fecha_carga) = (SELECT persona_hk, fecha_carga FROM sat_persona_demografia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Satelite sin sistema de origen',
        'toda fila declara de donde viene', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Satelite sin fecha de carga
    BEGIN
        UPDATE sat_persona_demografia SET fecha_carga = NULL
        WHERE (persona_hk, fecha_carga) = (SELECT persona_hk, fecha_carga FROM sat_persona_demografia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Satelite sin fecha de carga',
        'toda version esta fechada', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Satelite que cuelga de un hub inexistente
    BEGIN
        UPDATE sat_persona_demografia SET persona_hk = MD5('no-existe')
        WHERE (persona_hk, fecha_carga) = (SELECT persona_hk, fecha_carga FROM sat_persona_demografia LIMIT 1);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Satelite que cuelga de un hub inexistente',
        'integridad referencial contra el hub', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Dos versiones del satelite con la misma fecha
    BEGIN
        INSERT INTO sat_persona_demografia SELECT * FROM sat_persona_demografia LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Dos versiones del satelite con la misma fecha',
        'una version por hub y fecha de carga', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 09'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
