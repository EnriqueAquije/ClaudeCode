-- =====================================================================================
-- CASO 01 - Carga de datos
-- =====================================================================================
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS: no usan random(), por lo que dos ejecuciones
-- producen exactamente el mismo resultado. Ninguna persona real está representada.
--
-- Requisito previo: haber ejecutado 03-modelo-fisico.sql (crea el esquema caso01).
-- Ejecución:        psql -d bcp_lab -f carga_datos.sql
-- Volumen:          ~12 catálogos, 20 oficinas, 500 clientes, 800 cuentas, ~28 000 movimientos
-- =====================================================================================

SET search_path TO caso01;

TRUNCATE movimiento, cuenta_titular, cuenta, cliente, producto, oficina,
         cat_tipo_movimiento, cat_estado_cuenta, cat_canal, cat_ubigeo,
         cat_tipo_documento, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc, simbolo) VALUES
    ('PEN', 'Sol peruano',          'S/'),
    ('USD', 'Dólar estadounidense', 'US$');

INSERT INTO cat_tipo_documento (tipo_doc_cod, tipo_doc_desc, longitud_esperada, es_persona_juridica) VALUES
    ('01', 'DNI',                 8,  FALSE),
    ('04', 'Carné de extranjería', 12, FALSE),
    ('06', 'RUC',                 11, TRUE),
    ('07', 'Pasaporte',           12, FALSE);

-- Muestra de ubigeos oficiales INEI (distritos capitales de provincia).
-- El catálogo completo (~1 890 distritos) se descarga del INEI: ver FUENTES.md
INSERT INTO cat_ubigeo (ubigeo, departamento, provincia, distrito) VALUES
    ('150101', 'Lima',        'Lima',        'Lima'),
    ('070101', 'Callao',      'Callao',      'Callao'),
    ('040101', 'Arequipa',    'Arequipa',    'Arequipa'),
    ('130101', 'La Libertad', 'Trujillo',    'Trujillo'),
    ('140101', 'Lambayeque',  'Chiclayo',    'Chiclayo'),
    ('080101', 'Cusco',       'Cusco',       'Cusco'),
    ('200101', 'Piura',       'Piura',       'Piura'),
    ('120101', 'Junín',       'Huancayo',    'Huancayo'),
    ('210101', 'Puno',        'Puno',        'Puno'),
    ('110101', 'Ica',         'Ica',         'Ica'),
    ('060101', 'Cajamarca',   'Cajamarca',   'Cajamarca'),
    ('160101', 'Loreto',      'Maynas',      'Iquitos');

INSERT INTO cat_canal (canal_cod, canal_desc, es_presencial, es_cliente) VALUES
    ('OFI', 'Oficina / ventanilla',     TRUE,  TRUE),
    ('ATM', 'Cajero automático',        TRUE,  TRUE),
    ('AGE', 'Agente corresponsal',      TRUE,  TRUE),
    ('APP', 'Aplicativo móvil',         FALSE, TRUE),
    ('WEB', 'Banca por internet',       FALSE, TRUE),
    ('BAT', 'Proceso batch del banco',  FALSE, FALSE);

INSERT INTO cat_estado_cuenta (estado_cta_cod, estado_cta_desc, permite_movimiento, es_final) VALUES
    ('ACT', 'Activa',     TRUE,  FALSE),
    ('INA', 'Inactiva',   FALSE, FALSE),
    ('BLQ', 'Bloqueada',  FALSE, FALSE),
    ('CER', 'Cerrada',    FALSE, TRUE);

INSERT INTO cat_tipo_movimiento (tipo_mov_cod, tipo_mov_desc, signo, es_operacion_cliente, cuenta_contable) VALUES
    ('DEP',    'Depósito en efectivo',            1, TRUE,  '211101'),
    ('RET',    'Retiro en efectivo',             -1, TRUE,  '211101'),
    ('TRFR',   'Transferencia recibida',          1, TRUE,  '211102'),
    ('TRFE',   'Transferencia enviada',          -1, TRUE,  '211102'),
    ('COM',    'Comisión por mantenimiento',     -1, FALSE, '511201'),
    ('INT',    'Abono de intereses',              1, FALSE, '411101'),
    ('ITF',    'Impuesto a transacciones (ITF)', -1, FALSE, '271301'),
    ('EXTCOM', 'Extorno de comisión',             1, FALSE, '511201'),
    ('CIE',    'Retiro por cierre de cuenta',    -1, TRUE,  '211101');

-- =====================================================================================
-- 2. OFICINAS (20)
-- =====================================================================================

INSERT INTO oficina (oficina_id, oficina_cod, oficina_nombre, ubigeo, fecha_apertura)
SELECT  n,
        'OF' || LPAD(n::TEXT, 4, '0'),
        'Agencia ' || (ARRAY['Centro','Norte','Sur','Este','Oeste','Plaza','Mercado',
                             'Real','Comercio','Industrial'])[1 + (n % 10)]
                  || ' ' || u.distrito,
        u.ubigeo,
        DATE '2005-01-01' + ((n * 211) % 5000)
FROM        generate_series(1, 20) AS n
CROSS JOIN LATERAL (
        SELECT ubigeo, distrito
        FROM   cat_ubigeo
        ORDER  BY ubigeo
        OFFSET (n % 12) LIMIT 1
) AS u;

-- =====================================================================================
-- 3. PRODUCTOS (6)
-- =====================================================================================

INSERT INTO producto (producto_id, producto_cod, producto_nombre, familia_cod, moneda_cod,
                      monto_apertura_min, trea_pct, permite_saldo_negativo) VALUES
    (1, 'AHO-PEN-CLA', 'Cuenta de Ahorro Clásica Soles',    'AHORRO',    'PEN',   0.00, 0.005000, FALSE),
    (2, 'AHO-PEN-DIG', 'Cuenta de Ahorro Digital Soles',    'AHORRO',    'PEN',   0.00, 0.010000, FALSE),
    (3, 'SUE-PEN-STD', 'Cuenta Sueldo Soles',               'SUELDO',    'PEN',   0.00, 0.002500, FALSE),
    (4, 'AHO-USD-CLA', 'Cuenta de Ahorro Clásica Dólares',  'AHORRO',    'USD',   0.00, 0.001000, FALSE),
    (5, 'CTS-PEN-STD', 'Cuenta CTS Soles',                  'CTS',       'PEN',   0.00, 0.020000, FALSE),
    (6, 'CTE-USD-EMP', 'Cuenta Corriente Empresa Dólares',  'CORRIENTE', 'USD', 500.00, 0.000000, TRUE);

-- =====================================================================================
-- 4. CLIENTES (500)
--    Documentos sintéticos en rango reservado: NO corresponden a personas reales.
-- =====================================================================================

INSERT INTO cliente (cliente_id, tipo_doc_cod, num_doc, ape_paterno, ape_materno, nombres,
                     fecha_nacimiento, ubigeo, fecha_alta, es_vigente)
SELECT  n,
        CASE WHEN n % 50 = 0 THEN '06' WHEN n % 37 = 0 THEN '04' ELSE '01' END,
        CASE WHEN n % 50 = 0 THEN '20' || LPAD((100000000 + n * 7)::TEXT, 9, '0')
             WHEN n % 37 = 0 THEN 'CE' || LPAD((900000 + n * 11)::TEXT, 9, '0')
             ELSE LPAD((70000000 + n * 13)::TEXT, 8, '0')
        END,
        (ARRAY['QUISPE','MAMANI','FLORES','HUAMAN','ROJAS','VASQUEZ','CHAVEZ','SANCHEZ',
               'RAMOS','CASTILLO','GUTIERREZ','MENDOZA','PEREZ','TORRES','DIAZ','SILVA'])[1 + (n % 16)],
        (ARRAY['CONDORI','APAZA','SALAZAR','VILCA','PAREDES','MEZA','LOPEZ','AGUILAR',
               'CRUZ','PINEDO','ZAPATA','ORTIZ'])[1 + ((n * 3) % 12)],
        (ARRAY['MARIA','JOSE','ROSA','CARLOS','ANA','LUIS','CARMEN','JORGE','ELENA','MIGUEL',
               'LUCIA','PEDRO','SOFIA','VICTOR','NOEMI','RAUL'])[1 + ((n * 5) % 16)],
        DATE '1960-01-01' + ((n * 37) % 13800),
        (SELECT ubigeo FROM cat_ubigeo ORDER BY ubigeo OFFSET ((n * 7) % 12) LIMIT 1),
        DATE '2015-01-01' + ((n * 3) % 3000),
        (n % 53 <> 0)
FROM generate_series(1, 500) AS n;

-- =====================================================================================
-- 5. CUENTAS (800)
-- =====================================================================================

INSERT INTO cuenta (cuenta_id, num_cuenta, cci, producto_id, moneda_cod, oficina_id,
                    estado_cta_cod, fecha_apertura, fecha_cierre, saldo_contable, saldo_retenido)
SELECT  n,
        '191' || LPAD(n::TEXT, 10, '0'),
        LPAD((19100000000000 + n)::TEXT, 20, '0'),
        p.producto_id,
        p.moneda_cod,
        1 + (n % 20),
        est.estado_cta_cod,
        DATE '2018-01-01' + ((n * 5) % 2800),
        CASE WHEN est.estado_cta_cod = 'CER' THEN DATE '2026-08-15' END,
        0.00,
        0.00
FROM        generate_series(1, 800) AS n
CROSS JOIN LATERAL (SELECT producto_id, moneda_cod FROM producto WHERE producto_id = 1 + (n % 6)) AS p
CROSS JOIN LATERAL (SELECT CASE
                               WHEN n % 37 = 0 THEN 'CER'
                               WHEN n % 23 = 0 THEN 'INA'
                               WHEN n % 41 = 0 THEN 'BLQ'
                               ELSE 'ACT'
                           END AS estado_cta_cod) AS est;

-- =====================================================================================
-- 6. TITULARES  (1 titular principal por cuenta + mancomunados)
-- =====================================================================================

INSERT INTO cuenta_titular (cuenta_id, cliente_id, rol_cod, fecha_desde, fecha_hasta)
SELECT  c.cuenta_id,
        1 + ((c.cuenta_id * 7) % 500),
        'TITULAR',
        c.fecha_apertura,
        NULL
FROM cuenta c;

INSERT INTO cuenta_titular (cuenta_id, cliente_id, rol_cod, fecha_desde, fecha_hasta)
SELECT  c.cuenta_id,
        1 + ((c.cuenta_id * 13) % 500),
        'MANCOMUNADO',
        c.fecha_apertura,
        NULL
FROM cuenta c
WHERE  c.cuenta_id % 11 = 0
  AND  1 + ((c.cuenta_id * 13) % 500) <> 1 + ((c.cuenta_id * 7) % 500);

-- =====================================================================================
-- 7. MOVIMIENTOS
--    Diseño de la generación:
--      - i = 1  -> depósito de apertura entre 20 000 y 50 000 (garantiza saldo positivo)
--      - i > 1  -> hasta 60 movimientos; todo cargo está acotado a 300
--        => cargos máximos 60 x 300 = 18 000 < 20 000  => el saldo nunca se vuelve negativo
-- =====================================================================================

INSERT INTO movimiento (cuenta_id, num_operacion, fecha_operacion, fecha_contable,
                        tipo_mov_cod, canal_cod, oficina_id, moneda_cod,
                        monto, monto_con_signo, saldo_posterior, glosa)
SELECT  m.cuenta_id,
        'OP-' || m.cuenta_id || '-' || m.i,
        m.fecha_operacion,
        m.fecha_operacion::DATE + m.dias_contable,
        m.tipo_mov_cod,
        m.canal_cod,
        CASE WHEN m.canal_cod IN ('OFI','ATM','AGE') THEN 1 + (m.cuenta_id % 20) END,
        m.moneda_cod,
        m.monto,
        m.monto * tm.signo,
        0.00,
        m.glosa
FROM (
    SELECT  c.cuenta_id,
            c.moneda_cod,
            g.i,
            TIMESTAMP '2026-01-02 08:00:00'
                + ((g.i - 1) * 3 + (c.cuenta_id % 3)) * INTERVAL '1 day'
                + ((c.cuenta_id * 7 + g.i * 11) % 12) * INTERVAL '1 hour'   AS fecha_operacion,
            CASE WHEN (c.cuenta_id + g.i) % 9 = 0 THEN 2 ELSE 0 END          AS dias_contable,
            t.tipo_mov_cod,
            t.canal_cod,
            t.monto,
            t.glosa
    FROM        cuenta c
    CROSS JOIN LATERAL generate_series(1, 10 + (c.cuenta_id % 51)) AS g(i)
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN g.i = 1                                    THEN 'DEP'
                WHEN g.i % 17 = 0                               THEN 'INT'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 IN (0,1,2) THEN 'DEP'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 IN (3,4)   THEN 'TRFR'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 IN (5,6)   THEN 'RET'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 = 7        THEN 'TRFE'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 = 8        THEN 'COM'
                ELSE 'ITF'
            END AS tipo_mov_cod,
            CASE
                WHEN g.i = 1                THEN 'OFI'
                WHEN g.i % 17 = 0           THEN 'BAT'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 = 8 THEN 'BAT'
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 = 9 THEN 'BAT'
                ELSE (ARRAY['APP','ATM','AGE','WEB','OFI'])[1 + ((c.cuenta_id + g.i) % 5)]
            END AS canal_cod,
            CASE
                WHEN g.i = 1      THEN 20000.00 + ((c.cuenta_id * 137) % 30000)
                WHEN g.i % 17 = 0 THEN ROUND((5 + ((c.cuenta_id * 3 + g.i) % 40))::NUMERIC, 2)
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 IN (0,1,2,3,4)
                                  THEN ROUND((100 + ((c.cuenta_id * 53 + g.i * 29) % 800))::NUMERIC, 2)
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 IN (5,6,7)
                                  THEN ROUND((50 + ((c.cuenta_id * 47 + g.i * 23) % 250))::NUMERIC, 2)
                WHEN (c.cuenta_id * 31 + g.i * 17) % 10 = 8
                                  THEN ROUND((5 + ((c.cuenta_id + g.i) % 15))::NUMERIC, 2)
                ELSE                   ROUND((0.50 + ((c.cuenta_id + g.i) % 5))::NUMERIC, 2)
            END AS monto,
            CASE WHEN g.i = 1 THEN 'Deposito de apertura' ELSE NULL END AS glosa
    ) AS t
) AS m
JOIN cat_tipo_movimiento tm ON tm.tipo_mov_cod = m.tipo_mov_cod;

-- 7.1 Extornos: se anula 1 de cada 97 comisiones cobradas (RN-12: nunca se borra, se revierte).
INSERT INTO movimiento (cuenta_id, num_operacion, fecha_operacion, fecha_contable,
                        tipo_mov_cod, canal_cod, oficina_id, moneda_cod,
                        monto, monto_con_signo, saldo_posterior, glosa,
                        es_extorno, movimiento_extornado_id)
SELECT  o.cuenta_id,
        'EX-' || o.movimiento_id,
        o.fecha_operacion + INTERVAL '2 day',
        (o.fecha_operacion + INTERVAL '2 day')::DATE,
        'EXTCOM',
        'BAT',
        NULL,
        o.moneda_cod,
        o.monto,
        o.monto,                     -- EXTCOM tiene signo +1
        0.00,
        'Extorno de comision op. ' || o.num_operacion,
        TRUE,
        o.movimiento_id
FROM   movimiento o
WHERE  o.tipo_mov_cod = 'COM'
  AND  o.movimiento_id % 97 = 0;

-- 7.2 Cierre de cuentas: una cuenta cerrada no puede quedar con saldo.
--     Se calcula el saldo acumulado y se registra el retiro de cierre.
WITH saldo_actual AS (
    SELECT m.cuenta_id, SUM(m.monto_con_signo) AS saldo
    FROM   movimiento m
    GROUP  BY m.cuenta_id
)
INSERT INTO movimiento (cuenta_id, num_operacion, fecha_operacion, fecha_contable,
                        tipo_mov_cod, canal_cod, oficina_id, moneda_cod,
                        monto, monto_con_signo, saldo_posterior, glosa)
SELECT  c.cuenta_id,
        'CI-' || c.cuenta_id,
        (c.fecha_cierre - 1)::TIMESTAMP + INTERVAL '11 hour',
        c.fecha_cierre,
        'CIE',
        'OFI',
        c.oficina_id,
        c.moneda_cod,
        s.saldo,
        -s.saldo,
        0.00,
        'Retiro total por cierre de cuenta'
FROM   cuenta c
JOIN   saldo_actual s ON s.cuenta_id = c.cuenta_id
WHERE  c.estado_cta_cod = 'CER'
  AND  s.saldo > 0;

-- =====================================================================================
-- 8. RECÁLCULO DE SALDOS
--    El saldo NO se inventa: se deriva de los movimientos. Así se cumple RN-10 por diseño.
-- =====================================================================================

WITH running AS (
    SELECT  movimiento_id,
            SUM(monto_con_signo) OVER (
                PARTITION BY cuenta_id
                ORDER BY fecha_operacion, movimiento_id
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS saldo_acumulado
    FROM movimiento
)
UPDATE movimiento m
SET    saldo_posterior = r.saldo_acumulado
FROM   running r
WHERE  r.movimiento_id = m.movimiento_id;

UPDATE cuenta c
SET    saldo_contable = t.saldo
FROM  (SELECT cuenta_id, SUM(monto_con_signo) AS saldo FROM movimiento GROUP BY cuenta_id) t
WHERE  t.cuenta_id = c.cuenta_id;

-- Retenciones judiciales / cheques en canje sobre algunas cuentas activas.
UPDATE cuenta
SET    saldo_retenido = LEAST(500.00, ROUND(saldo_contable * 0.10, 2))
WHERE  cuenta_id % 29 = 0
  AND  estado_cta_cod = 'ACT'
  AND  saldo_contable > 0;

-- =====================================================================================
-- 9. SINCRONIZAR SECUENCIAS
--    Obligatorio tras insertar IDs explícitos, o el primer INSERT de la aplicación falla.
-- =====================================================================================

SELECT setval(pg_get_serial_sequence('caso01.oficina',    'oficina_id'),    (SELECT MAX(oficina_id)    FROM oficina));
SELECT setval(pg_get_serial_sequence('caso01.producto',   'producto_id'),   (SELECT MAX(producto_id)   FROM producto));
SELECT setval(pg_get_serial_sequence('caso01.cliente',    'cliente_id'),    (SELECT MAX(cliente_id)    FROM cliente));
SELECT setval(pg_get_serial_sequence('caso01.cuenta',     'cuenta_id'),     (SELECT MAX(cuenta_id)     FROM cuenta));
SELECT setval(pg_get_serial_sequence('caso01.movimiento', 'movimiento_id'), (SELECT MAX(movimiento_id) FROM movimiento));

-- =====================================================================================
-- 10. RESUMEN DE LA CARGA
-- =====================================================================================

SELECT 'clientes'      AS entidad, COUNT(*) AS filas FROM cliente
UNION ALL SELECT 'cuentas',        COUNT(*) FROM cuenta
UNION ALL SELECT 'titulares',      COUNT(*) FROM cuenta_titular
UNION ALL SELECT 'movimientos',    COUNT(*) FROM movimiento
UNION ALL SELECT 'extornos',       COUNT(*) FROM movimiento WHERE es_extorno
ORDER BY 1;
