-- =====================================================================================
-- CASO 05 - PRUEBAS NEGATIVAS
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

SET search_path TO caso05, public;

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
    -- PN-01: Hecho que apunta a un dia inexistente del calendario
    BEGIN
        UPDATE fact_movimiento SET tiempo_sk = 19000101 WHERE movimiento_id_origen = (SELECT MIN(movimiento_id_origen) FROM fact_movimiento);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-01', 'Hecho que apunta a un dia inexistente del calendario',
        'integridad referencial contra dim_tiempo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-02: Version del SCD2 que termina antes de empezar
    BEGIN
        UPDATE dim_cliente SET fecha_hasta = fecha_desde - 1 WHERE cliente_sk = (SELECT MIN(cliente_sk) FROM dim_cliente WHERE cliente_sk > 0);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-02', 'Version del SCD2 que termina antes de empezar',
        'vigencia coherente', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-03: Segmento fuera del dominio acordado
    BEGIN
        UPDATE dim_cliente SET segmento_cod = 'INVENTADO' WHERE cliente_sk = (SELECT MIN(cliente_sk) FROM dim_cliente WHERE cliente_sk > 0);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-03', 'Segmento fuera del dominio acordado',
        'segmento dentro del catalogo', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-04: Dos versiones vigentes del mismo cliente
    BEGIN
        UPDATE dim_cliente SET es_vigente = TRUE
        WHERE cliente_sk = (SELECT MIN(d1.cliente_sk) FROM dim_cliente d1
                            WHERE NOT d1.es_vigente
                              AND EXISTS (SELECT 1 FROM dim_cliente d2
                                          WHERE d2.es_vigente
                                            AND d2.tipo_doc_cod = d1.tipo_doc_cod
                                            AND d2.num_doc      = d1.num_doc));
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-04', 'Dos versiones vigentes del mismo cliente',
        'una sola version vigente por cliente', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-05: Producto de un negocio fuera del dominio
    BEGIN
        UPDATE dim_producto SET negocio_cod = 'OTRO' WHERE producto_sk = (SELECT MIN(producto_sk) FROM dim_producto WHERE producto_sk > 0);
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-05', 'Producto de un negocio fuera del dominio',
        'negocio CAPTACION o COLOCACION', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

    -- PN-06: Dos filas del hecho al mismo grano
    BEGIN
        INSERT INTO fact_colocacion_mes SELECT * FROM fact_colocacion_mes LIMIT 1;
        -- Si llegamos aqui, la base ACEPTO la operacion prohibida. Se lanza una excepcion
        -- propia para que el savepoint revierta el cambio: una prueba negativa que falla
        -- NO debe dejar el dato imposible dentro del laboratorio.
        RAISE EXCEPTION USING ERRCODE = 'ZZ001', MESSAGE = 'operacion prohibida aceptada';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_ok := FALSE;   -- la acepto: hueco en el modelo
        WHEN others          THEN v_ok := TRUE;    -- la rechazo: correcto
    END;
    INSERT INTO resultado_pn VALUES ('PN-06', 'Dos filas del hecho al mismo grano',
        'grano mes-deudor-producto-moneda', CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END);

END $$;

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS NEGATIVAS - CASO 05'
\echo '   OK = la base RECHAZO la operacion prohibida (correcto)'
\echo '   FALLA = la acepto, tu modelo tiene un hueco'
\echo '=============================================================='

SELECT prueba, descripcion, deberia AS deberia_impedirlo, estado
FROM   resultado_pn ORDER BY prueba;
