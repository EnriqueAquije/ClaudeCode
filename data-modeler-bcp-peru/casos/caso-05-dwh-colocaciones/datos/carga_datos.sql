-- =====================================================================================
-- CASO 05 - Carga del data warehouse (proceso ETL completo)
-- =====================================================================================
-- ⚠️ REQUISITO: los esquemas caso01 y caso02 deben existir y estar cargados.
--    Este script NO inventa datos: los EXTRAE de los sistemas transaccionales,
--    los TRANSFORMA y los CARGA en el modelo dimensional. Es un ETL real.
--
-- Ejecución:
--    psql -d bcp_lab -f soluciones/caso-01-.../03-modelo-fisico.sql
--    psql -d bcp_lab -f casos/caso-01-.../datos/carga_datos.sql
--    psql -d bcp_lab -f soluciones/caso-02-.../03-modelo-fisico.sql
--    psql -d bcp_lab -f casos/caso-02-.../datos/carga_datos.sql
--    psql -d bcp_lab -f soluciones/caso-05-.../03-modelo-fisico.sql
--    psql -d bcp_lab -f casos/caso-05-.../datos/carga_datos.sql    <-- este archivo
-- =====================================================================================

SET search_path TO caso05, public;

-- ---------------------------------------------------------------------------------
-- 0. VERIFICACIÓN DE PRERREQUISITOS
--    Un ETL nunca debe arrancar si sus fuentes no están disponibles.
-- ---------------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'caso01' AND table_name = 'movimiento') THEN
        RAISE EXCEPTION 'Falta el esquema caso01. Ejecute primero el caso 01 completo.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'caso02' AND table_name = 'deudor_clasificacion_mes') THEN
        RAISE EXCEPTION 'Falta el esquema caso02. Ejecute primero el caso 02 completo.';
    END IF;
    IF (SELECT COUNT(*) FROM caso01.movimiento) = 0 THEN
        RAISE EXCEPTION 'El esquema caso01 existe pero esta VACIO.';
    END IF;
    IF (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes) = 0 THEN
        RAISE EXCEPTION 'El esquema caso02 existe pero esta VACIO.';
    END IF;
END $$;

TRUNCATE fact_colocacion_mes, fact_saldo_captacion_mes, fact_movimiento,
         dim_cliente, dim_canal, dim_producto, dim_oficina, dim_ubigeo, dim_tiempo
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. DIM_TIEMPO (se genera, no se extrae: el calendario no vive en ningún sistema fuente)
-- =====================================================================================

INSERT INTO dim_tiempo (tiempo_sk, fecha, anio, trimestre, mes, nombre_mes, dia,
                        dia_semana, nombre_dia, periodo, es_fin_semana, es_fin_mes)
SELECT  TO_CHAR(d, 'YYYYMMDD')::INTEGER,
        d::DATE,
        EXTRACT(YEAR    FROM d)::SMALLINT,
        EXTRACT(QUARTER FROM d)::SMALLINT,
        EXTRACT(MONTH   FROM d)::SMALLINT,
        (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
               'Agosto','Setiembre','Octubre','Noviembre','Diciembre'])[EXTRACT(MONTH FROM d)::INT],
        EXTRACT(DAY     FROM d)::SMALLINT,
        EXTRACT(ISODOW  FROM d)::SMALLINT,
        (ARRAY['Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo'])[EXTRACT(ISODOW FROM d)::INT],
        TO_CHAR(d, 'YYYYMM'),
        EXTRACT(ISODOW FROM d) >= 6,
        d::DATE = (DATE_TRUNC('month', d) + INTERVAL '1 month - 1 day')::DATE
FROM generate_series(DATE '2025-01-01', DATE '2027-12-31', INTERVAL '1 day') AS d;

-- Miembro DESCONOCIDO: permite que un hecho con fecha invalida no se pierda.
INSERT INTO dim_tiempo (tiempo_sk, fecha, anio, trimestre, mes, nombre_mes, dia,
                        dia_semana, nombre_dia, periodo, es_fin_semana, es_fin_mes)
VALUES (-1, DATE '1900-01-01', 1900, 1, 1, 'Desconocido', 1, 1, 'Desconocido', '190001', FALSE, FALSE);

-- =====================================================================================
-- 2. DIM_UBIGEO  (extraída de caso01 + enriquecida con macro región)
-- =====================================================================================

INSERT INTO dim_ubigeo (ubigeo_sk, ubigeo, departamento, provincia, distrito, macro_region)
VALUES (-1, '000000', 'DESCONOCIDO', 'DESCONOCIDO', 'DESCONOCIDO', 'DESCONOCIDO');

INSERT INTO dim_ubigeo (ubigeo, departamento, provincia, distrito, macro_region)
SELECT  u.ubigeo, u.departamento, u.provincia, u.distrito,
        -- Enriquecimiento: atributo que NO existe en el origen y el negocio pide
        CASE
            WHEN u.departamento IN ('Lima','Callao','Ica')                      THEN 'CENTRO'
            WHEN u.departamento IN ('La Libertad','Lambayeque','Piura','Cajamarca') THEN 'NORTE'
            WHEN u.departamento IN ('Arequipa','Cusco','Puno')                  THEN 'SUR'
            WHEN u.departamento IN ('Loreto')                                   THEN 'ORIENTE'
            ELSE 'CENTRO'
        END
FROM    caso01.cat_ubigeo u;

-- =====================================================================================
-- 3. DIM_OFICINA
-- =====================================================================================

INSERT INTO dim_oficina (oficina_sk, oficina_cod, oficina_nombre, ubigeo_sk, fecha_apertura)
VALUES (-1, 'N/A', 'OFICINA DESCONOCIDA', -1, NULL);

INSERT INTO dim_oficina (oficina_cod, oficina_nombre, ubigeo_sk, fecha_apertura)
SELECT  o.oficina_cod, o.oficina_nombre, du.ubigeo_sk, o.fecha_apertura
FROM    caso01.oficina o
JOIN    dim_ubigeo du ON du.ubigeo = o.ubigeo;

-- =====================================================================================
-- 4. DIM_PRODUCTO  (dimensión CONFORMADA: dos orígenes, una sola jerarquía)
-- =====================================================================================

INSERT INTO dim_producto (producto_sk, producto_cod, producto_nombre, familia_cod, negocio_cod, moneda_cod)
VALUES (-1, 'N/A', 'PRODUCTO DESCONOCIDO', 'DESCONOCIDO', 'NO_APLICA', 'PEN');

-- Origen 1: productos de captación (caso01)
INSERT INTO dim_producto (producto_cod, producto_nombre, familia_cod, negocio_cod, moneda_cod)
SELECT  p.producto_cod, p.producto_nombre, p.familia_cod, 'CAPTACION', p.moneda_cod
FROM    caso01.producto p;

-- Origen 2: tipos de crédito SBS (caso02)
INSERT INTO dim_producto (producto_cod, producto_nombre, familia_cod, negocio_cod, moneda_cod)
SELECT  'CRED-' || tc.tipo_credito_cod,
        tc.tipo_credito_desc,
        CASE WHEN tc.es_minorista THEN 'MINORISTA' ELSE 'NO_MINORISTA' END,
        'COLOCACION',
        'PEN'
FROM    caso02.cat_tipo_credito tc;

-- =====================================================================================
-- 5. DIM_CANAL
-- =====================================================================================

INSERT INTO dim_canal (canal_sk, canal_cod, canal_desc, es_presencial, es_digital)
VALUES (-1, 'DESC', 'DESCONOCIDO', FALSE, FALSE);

INSERT INTO dim_canal (canal_cod, canal_desc, es_presencial, es_digital)
SELECT  c.canal_cod, c.canal_desc, c.es_presencial, NOT c.es_presencial
FROM    caso01.cat_canal c;

-- =====================================================================================
-- 6. DIM_CLIENTE (SCD TIPO 2)
--    Se integran DOS sistemas fuente (captaciones y créditos) en una sola dimensión,
--    usando el documento como clave natural de negocio.
--    El segmento cambia el 2026-06-01 para una parte de los clientes: eso genera la
--    segunda versión del SCD2.
-- =====================================================================================

INSERT INTO dim_cliente (cliente_sk, cliente_id_origen, sistema_origen, tipo_doc_cod, num_doc,
                         nombre_completo, rango_edad, segmento_cod, ubigeo_sk,
                         fecha_alta, fecha_desde, fecha_hasta, es_vigente, version)
VALUES (-1, -1, 'NO_APLICA', '00', 'DESCONOCIDO', 'CLIENTE DESCONOCIDO', 'DESCONOCIDO',
        'DESCONOCIDO', -1, NULL, DATE '1900-01-01', DATE '9999-12-31', FALSE, 1);

-- 6.1 Versión 1 (vigente desde el alta del cliente)
INSERT INTO dim_cliente (cliente_id_origen, sistema_origen, tipo_doc_cod, num_doc,
                         nombre_completo, rango_edad, segmento_cod, ubigeo_sk,
                         fecha_alta, fecha_desde, fecha_hasta, es_vigente, version)
SELECT  c.cliente_id,
        'CORE_CAPTACIONES',
        c.tipo_doc_cod,
        c.num_doc,
        c.ape_paterno || ' ' || COALESCE(c.ape_materno, '') || ', ' || c.nombres,
        CASE
            WHEN c.fecha_nacimiento IS NULL THEN 'DESCONOCIDO'
            WHEN AGE(DATE '2026-09-30', c.fecha_nacimiento) < INTERVAL '30 year' THEN '18-29'
            WHEN AGE(DATE '2026-09-30', c.fecha_nacimiento) < INTERVAL '45 year' THEN '30-44'
            WHEN AGE(DATE '2026-09-30', c.fecha_nacimiento) < INTERVAL '60 year' THEN '45-59'
            ELSE '60+'
        END,
        (ARRAY['MASIVO','MASIVO','CONSUMO','PREFERENTE'])[1 + (c.cliente_id % 4)],
        COALESCE(du.ubigeo_sk, -1),
        c.fecha_alta,
        c.fecha_alta,
        CASE WHEN c.cliente_id % 5 = 0 THEN DATE '2026-05-31' ELSE DATE '9999-12-31' END,
        (c.cliente_id % 5 <> 0),
        1
FROM        caso01.cliente c
LEFT JOIN   dim_ubigeo du ON du.ubigeo = c.ubigeo;

-- 6.2 Versión 2: los clientes que cambiaron de segmento el 2026-06-01
INSERT INTO dim_cliente (cliente_id_origen, sistema_origen, tipo_doc_cod, num_doc,
                         nombre_completo, rango_edad, segmento_cod, ubigeo_sk,
                         fecha_alta, fecha_desde, fecha_hasta, es_vigente, version)
SELECT  v1.cliente_id_origen, v1.sistema_origen, v1.tipo_doc_cod, v1.num_doc,
        v1.nombre_completo, v1.rango_edad,
        CASE v1.segmento_cod
            WHEN 'MASIVO'     THEN 'CONSUMO'
            WHEN 'CONSUMO'    THEN 'PREFERENTE'
            WHEN 'PREFERENTE' THEN 'BANCA_EXCLUSIVA'
            ELSE v1.segmento_cod
        END,
        v1.ubigeo_sk, v1.fecha_alta,
        DATE '2026-06-01', DATE '9999-12-31', TRUE, 2
FROM    dim_cliente v1
WHERE   v1.cliente_sk <> -1
  AND   v1.fecha_hasta = DATE '2026-05-31';

-- 6.3 Deudores del caso02 que NO existen en captaciones (segundo sistema fuente)
INSERT INTO dim_cliente (cliente_id_origen, sistema_origen, tipo_doc_cod, num_doc,
                         nombre_completo, rango_edad, segmento_cod, ubigeo_sk,
                         fecha_alta, fecha_desde, fecha_hasta, es_vigente, version)
SELECT  d.deudor_id,
        'CORE_CREDITOS',
        d.tipo_doc_cod,
        d.num_doc,
        d.ape_paterno || ' ' || COALESCE(d.ape_materno, '') || ', ' || d.nombres,
        CASE
            WHEN d.fecha_nacimiento IS NULL THEN 'DESCONOCIDO'
            WHEN AGE(DATE '2026-09-30', d.fecha_nacimiento) < INTERVAL '30 year' THEN '18-29'
            WHEN AGE(DATE '2026-09-30', d.fecha_nacimiento) < INTERVAL '45 year' THEN '30-44'
            WHEN AGE(DATE '2026-09-30', d.fecha_nacimiento) < INTERVAL '60 year' THEN '45-59'
            ELSE '60+'
        END,
        CASE WHEN d.ingreso_declarado > 8000 THEN 'PREFERENTE'
             WHEN d.ingreso_declarado > 4000 THEN 'CONSUMO'
             ELSE 'MASIVO' END,
        -1,
        d.fecha_alta,
        d.fecha_alta,
        DATE '9999-12-31',
        TRUE,
        1
FROM    caso02.deudor d
WHERE   NOT EXISTS (SELECT 1 FROM dim_cliente dc
                    WHERE dc.tipo_doc_cod = d.tipo_doc_cod AND dc.num_doc = d.num_doc);

-- =====================================================================================
-- 7. FACT_MOVIMIENTO (hecho transaccional)
--    LECCIÓN CENTRAL: el JOIN a la dimensión SCD2 debe hacerse por la VIGENCIA A LA
--    FECHA DEL HECHO, no por la versión vigente hoy. Si se hace mal, el análisis
--    histórico atribuye las ventas del pasado al segmento actual del cliente.
-- =====================================================================================

INSERT INTO fact_movimiento (tiempo_sk, cliente_sk, producto_sk, oficina_sk, canal_sk,
                             num_operacion, tipo_mov_cod, monto, monto_con_signo, cantidad_mov)
SELECT  TO_CHAR(m.fecha_contable, 'YYYYMMDD')::INTEGER,
        COALESCE(dc.cliente_sk, -1),
        COALESCE(dp.producto_sk, -1),
        COALESCE(dof.oficina_sk, -1),
        COALESCE(dcan.canal_sk, -1),
        m.num_operacion,
        m.tipo_mov_cod,
        m.monto,
        m.monto_con_signo,
        1
FROM        caso01.movimiento m
JOIN        caso01.cuenta cta ON cta.cuenta_id = m.cuenta_id
JOIN        caso01.producto p ON p.producto_id = cta.producto_id
LEFT JOIN   caso01.cuenta_titular ct ON ct.cuenta_id = cta.cuenta_id
                                    AND ct.rol_cod = 'TITULAR'
                                    AND ct.fecha_hasta IS NULL
LEFT JOIN   caso01.cliente cli ON cli.cliente_id = ct.cliente_id
-- >>> JOIN SCD2 POR VIGENCIA A LA FECHA DEL HECHO <<<
LEFT JOIN   dim_cliente  dc  ON dc.tipo_doc_cod = cli.tipo_doc_cod
                            AND dc.num_doc      = cli.num_doc
                            AND m.fecha_contable BETWEEN dc.fecha_desde AND dc.fecha_hasta
LEFT JOIN   dim_producto dp  ON dp.producto_cod = p.producto_cod
LEFT JOIN   caso01.oficina ofi ON ofi.oficina_id = cta.oficina_id
LEFT JOIN   dim_oficina  dof ON dof.oficina_cod = ofi.oficina_cod
LEFT JOIN   dim_canal    dcan ON dcan.canal_cod = m.canal_cod;

-- =====================================================================================
-- 8. FACT_SALDO_CAPTACION_MES (snapshot periódico, grano cuenta-mes)
-- =====================================================================================

INSERT INTO fact_saldo_captacion_mes (tiempo_sk, cliente_sk, producto_sk, oficina_sk,
                                      cuenta_id_origen, saldo_fin_mes, saldo_promedio,
                                      cant_movimientos, monto_abonos, monto_cargos)
WITH cierre_mes AS (
    -- Último saldo conocido de cada cuenta en cada mes
    SELECT DISTINCT ON (m.cuenta_id, DATE_TRUNC('month', m.fecha_contable))
           m.cuenta_id,
           (DATE_TRUNC('month', m.fecha_contable) + INTERVAL '1 month - 1 day')::DATE AS fin_mes,
           m.saldo_posterior
    FROM   caso01.movimiento m
    ORDER  BY m.cuenta_id, DATE_TRUNC('month', m.fecha_contable),
              m.fecha_contable DESC, m.fecha_operacion DESC, m.movimiento_id DESC
),
agregado_mes AS (
    SELECT  m.cuenta_id,
            (DATE_TRUNC('month', m.fecha_contable) + INTERVAL '1 month - 1 day')::DATE AS fin_mes,
            COUNT(*)                                                       AS cant_movimientos,
            SUM(m.monto) FILTER (WHERE m.monto_con_signo > 0)              AS monto_abonos,
            SUM(m.monto) FILTER (WHERE m.monto_con_signo < 0)              AS monto_cargos,
            ROUND(AVG(m.saldo_posterior), 2)                               AS saldo_promedio
    FROM    caso01.movimiento m
    GROUP BY m.cuenta_id, DATE_TRUNC('month', m.fecha_contable)
)
SELECT  TO_CHAR(a.fin_mes, 'YYYYMMDD')::INTEGER,
        COALESCE(dc.cliente_sk, -1),
        COALESCE(dp.producto_sk, -1),
        COALESCE(dof.oficina_sk, -1),
        a.cuenta_id,
        c.saldo_posterior,
        a.saldo_promedio,
        a.cant_movimientos,
        COALESCE(a.monto_abonos, 0),
        COALESCE(a.monto_cargos, 0)
FROM        agregado_mes a
JOIN        cierre_mes   c   ON c.cuenta_id = a.cuenta_id AND c.fin_mes = a.fin_mes
JOIN        caso01.cuenta cta ON cta.cuenta_id = a.cuenta_id
JOIN        caso01.producto p ON p.producto_id = cta.producto_id
LEFT JOIN   caso01.cuenta_titular ct ON ct.cuenta_id = cta.cuenta_id
                                    AND ct.rol_cod = 'TITULAR' AND ct.fecha_hasta IS NULL
LEFT JOIN   caso01.cliente cli ON cli.cliente_id = ct.cliente_id
LEFT JOIN   dim_cliente  dc  ON dc.tipo_doc_cod = cli.tipo_doc_cod
                            AND dc.num_doc      = cli.num_doc
                            AND a.fin_mes BETWEEN dc.fecha_desde AND dc.fecha_hasta
LEFT JOIN   dim_producto dp  ON dp.producto_cod = p.producto_cod
LEFT JOIN   caso01.oficina ofi ON ofi.oficina_id = cta.oficina_id
LEFT JOIN   dim_oficina  dof ON dof.oficina_cod = ofi.oficina_cod
WHERE       a.fin_mes <= DATE '2027-12-31';

-- =====================================================================================
-- 9. FACT_COLOCACION_MES (snapshot periódico, grano deudor-mes)
-- =====================================================================================

INSERT INTO fact_colocacion_mes (tiempo_sk, cliente_sk, producto_sk, deudor_id_origen,
                                 clasificacion_cod, dias_atraso, saldo_capital,
                                 monto_provision, cant_creditos)
SELECT  TO_CHAR(dcm.fecha_corte, 'YYYYMMDD')::INTEGER,
        COALESCE(dc.cliente_sk, -1),
        COALESCE(dp.producto_sk, -1),
        dcm.deudor_id,
        dcm.clasificacion_cod,
        dcm.dias_atraso,
        dcm.saldo_capital,
        dcm.monto_provision,
        (SELECT COUNT(*) FROM caso02.credito cr
         WHERE cr.deudor_id = dcm.deudor_id AND cr.estado_credito = 'VIGENTE')
FROM        caso02.deudor_clasificacion_mes dcm
JOIN        caso02.deudor d ON d.deudor_id = dcm.deudor_id
LEFT JOIN   dim_cliente  dc ON dc.tipo_doc_cod = d.tipo_doc_cod
                           AND dc.num_doc      = d.num_doc
                           AND dcm.fecha_corte BETWEEN dc.fecha_desde AND dc.fecha_hasta
LEFT JOIN   dim_producto dp ON dp.producto_cod = 'CRED-' || dcm.tipo_credito_cod;

-- =====================================================================================
-- 10. ESTADÍSTICAS Y RESUMEN
-- =====================================================================================

ANALYZE dim_cliente;
ANALYZE fact_movimiento;
ANALYZE fact_saldo_captacion_mes;
ANALYZE fact_colocacion_mes;

SELECT 'dim_tiempo'  AS tabla, COUNT(*) AS filas FROM dim_tiempo
UNION ALL SELECT 'dim_ubigeo',   COUNT(*) FROM dim_ubigeo
UNION ALL SELECT 'dim_oficina',  COUNT(*) FROM dim_oficina
UNION ALL SELECT 'dim_producto', COUNT(*) FROM dim_producto
UNION ALL SELECT 'dim_canal',    COUNT(*) FROM dim_canal
UNION ALL SELECT 'dim_cliente',  COUNT(*) FROM dim_cliente
UNION ALL SELECT '  de los cuales version 2', COUNT(*) FROM dim_cliente WHERE version = 2
UNION ALL SELECT 'fact_movimiento',          COUNT(*) FROM fact_movimiento
UNION ALL SELECT 'fact_saldo_captacion_mes', COUNT(*) FROM fact_saldo_captacion_mes
UNION ALL SELECT 'fact_colocacion_mes',      COUNT(*) FROM fact_colocacion_mes
ORDER BY 1;
