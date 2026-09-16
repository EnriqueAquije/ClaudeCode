-- =====================================================================================
-- CASO 03 - Carga de datos
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS. Requisito previo: 03-modelo-fisico.sql
-- Volumen: 350 titulares, 400 cuentas de tarjeta, ~500 plásticos, 2 400 ciclos,
--          ~30 000 transacciones, ~2 400 estados de cuenta
-- =====================================================================================

SET search_path TO caso03;

TRUNCATE estado_cuenta, transaccion_cuota, transaccion, ciclo_facturacion,
         linea_credito_hist, plastico, cuenta_tarjeta, titular,
         cat_rubro, cat_tipo_transaccion, cat_estado_tarjeta, cat_marca, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc) VALUES
    ('PEN', 'Sol peruano'), ('USD', 'Dólar estadounidense');

INSERT INTO cat_marca (marca_cod, marca_desc) VALUES
    ('VISA', 'Visa'), ('MC', 'Mastercard'), ('AMEX', 'American Express');

INSERT INTO cat_estado_tarjeta (estado_tj_cod, estado_tj_desc, permite_consumo) VALUES
    ('ACT', 'Activa',                 TRUE),
    ('BLQ', 'Bloqueada temporalmente', FALSE),
    ('MOR', 'Bloqueada por mora',      FALSE),
    ('CAN', 'Cancelada',               FALSE);

INSERT INTO cat_tipo_transaccion (tipo_trx_cod, tipo_trx_desc, signo, es_consumo, genera_cuotas) VALUES
    ('CON', 'Consumo al contado',            1, TRUE,  FALSE),
    ('CUO', 'Consumo en cuotas',             1, TRUE,  TRUE),
    ('DISP','Disposición de efectivo',       1, TRUE,  FALSE),
    ('INT', 'Intereses revolventes',         1, FALSE, FALSE),
    ('COM', 'Comisión de membresía',         1, FALSE, FALSE),
    ('PAG', 'Pago del cliente',             -1, FALSE, FALSE),
    ('EXT', 'Extorno de consumo',           -1, FALSE, FALSE);

INSERT INTO cat_rubro (rubro_cod, rubro_desc) VALUES
    ('SUPERMERC',  'Supermercados'),
    ('RESTAURANT', 'Restaurantes'),
    ('COMBUSTIBLE','Grifos y combustible'),
    ('VESTIMENTA', 'Vestimenta y calzado'),
    ('TECNOLOGIA', 'Tecnología y electrodomésticos'),
    ('SALUD',      'Farmacias y salud'),
    ('EDUCACION',  'Educación'),
    ('VIAJES',     'Viajes y transporte'),
    ('ONLINE',     'Comercio electrónico'),
    ('OTROS',      'Otros rubros');

-- =====================================================================================
-- 2. TITULARES Y CUENTAS
-- =====================================================================================

INSERT INTO titular (titular_id, tipo_doc_cod, num_doc, ape_paterno, nombres, fecha_alta)
SELECT  n, '01', LPAD((72000000 + n * 23)::TEXT, 8, '0'),
        (ARRAY['QUISPE','MAMANI','FLORES','HUAMAN','ROJAS','VASQUEZ','CHAVEZ','SANCHEZ',
               'RAMOS','CASTILLO','GUTIERREZ','MENDOZA'])[1 + (n % 12)],
        (ARRAY['MARIA','JOSE','ROSA','CARLOS','ANA','LUIS','CARMEN','JORGE'])[1 + ((n * 5) % 8)],
        DATE '2017-01-01' + ((n * 7) % 2900)
FROM generate_series(1, 350) AS n;

INSERT INTO cuenta_tarjeta (cuenta_tj_id, num_cuenta_tj, titular_id, marca_cod, moneda_cod,
                            estado_tj_cod, dia_facturacion, linea_aprobada,
                            tea_revolvente, tea_cuotas, fecha_apertura)
SELECT  n,
        'TJ' || LPAD(n::TEXT, 12, '0'),
        1 + ((n * 7) % 350),
        (ARRAY['VISA','MC','VISA','AMEX'])[1 + (n % 4)],
        'PEN',
        CASE WHEN n % 31 = 0 THEN 'BLQ' WHEN n % 43 = 0 THEN 'MOR' ELSE 'ACT' END,
        (1 + (n % 28))::SMALLINT,
        ROUND((6000 + ((n * 311) % 54000))::NUMERIC, 2),
        ROUND((0.30 + ((n % 40)::NUMERIC / 200))::NUMERIC, 6),
        ROUND((0.20 + ((n % 30)::NUMERIC / 200))::NUMERIC, 6),
        DATE '2020-01-01' + ((n * 5) % 2000)
FROM generate_series(1, 400) AS n;

-- Plásticos: uno TITULAR por cuenta, más adicionales en algunas.
INSERT INTO plastico (cuenta_tj_id, num_plastico_enmasc, tipo_plastico, nombre_impreso,
                      fecha_emision, fecha_expiracion, esta_activo)
SELECT  ct.cuenta_tj_id,
        CASE ct.marca_cod WHEN 'VISA' THEN '411111******' WHEN 'MC' THEN '535522******'
                          ELSE '378282******' END || LPAD((1000 + ct.cuenta_tj_id)::TEXT, 4, '0')
        || '   ',
        'TITULAR',
        t.nombres || ' ' || t.ape_paterno,
        ct.fecha_apertura,
        (ct.fecha_apertura + INTERVAL '4 year')::DATE,
        TRUE
FROM    cuenta_tarjeta ct
JOIN    titular t ON t.titular_id = ct.titular_id;

INSERT INTO plastico (cuenta_tj_id, num_plastico_enmasc, tipo_plastico, nombre_impreso,
                      fecha_emision, fecha_expiracion, esta_activo)
SELECT  ct.cuenta_tj_id,
        CASE ct.marca_cod WHEN 'VISA' THEN '411111******' WHEN 'MC' THEN '535522******'
                          ELSE '378282******' END || LPAD((5000 + ct.cuenta_tj_id)::TEXT, 4, '0')
        || '   ',
        'ADICIONAL',
        (ARRAY['ROSA','LUIS','ANA','PEDRO'])[1 + (ct.cuenta_tj_id % 4)] || ' ' || t.ape_paterno,
        ct.fecha_apertura + 90,
        (ct.fecha_apertura + INTERVAL '4 year')::DATE,
        TRUE
FROM    cuenta_tarjeta ct
JOIN    titular t ON t.titular_id = ct.titular_id
WHERE   ct.cuenta_tj_id % 4 = 0;

-- Historia de línea de crédito (SCD2): apertura + aumentos.
INSERT INTO linea_credito_hist (cuenta_tj_id, fecha_desde, fecha_hasta, linea_anterior, linea_nueva, motivo)
SELECT  ct.cuenta_tj_id, ct.fecha_apertura,
        CASE WHEN ct.cuenta_tj_id % 6 = 0 THEN DATE '2026-02-28' ELSE DATE '9999-12-31' END,
        NULL,
        CASE WHEN ct.cuenta_tj_id % 6 = 0 THEN ROUND(ct.linea_aprobada * 0.70, 2) ELSE ct.linea_aprobada END,
        'APERTURA'
FROM    cuenta_tarjeta ct
UNION ALL
SELECT  ct.cuenta_tj_id, DATE '2026-03-01', DATE '9999-12-31',
        ROUND(ct.linea_aprobada * 0.70, 2), ct.linea_aprobada, 'AUMENTO_POR_COMPORTAMIENTO'
FROM    cuenta_tarjeta ct
WHERE   ct.cuenta_tj_id % 6 = 0;

-- =====================================================================================
-- 3. CICLOS DE FACTURACIÓN (6 periodos: 202604 a 202609)
--    El ciclo NO es el mes calendario: cierra el día de facturación de cada cuenta.
-- =====================================================================================

INSERT INTO ciclo_facturacion (cuenta_tj_id, periodo, fecha_inicio, fecha_cierre, fecha_vencimiento)
SELECT  ct.cuenta_tj_id,
        TO_CHAR(MAKE_DATE(p.anio, p.mes, 1), 'YYYYMM'),
        (MAKE_DATE(p.anio, p.mes, ct.dia_facturacion) - INTERVAL '1 month' + INTERVAL '1 day')::DATE,
        MAKE_DATE(p.anio, p.mes, ct.dia_facturacion),
        MAKE_DATE(p.anio, p.mes, ct.dia_facturacion) + 18
FROM        cuenta_tarjeta ct
CROSS JOIN (VALUES (1, 2026, 4), (2, 2026, 5), (3, 2026, 6),
                   (4, 2026, 7), (5, 2026, 8), (6, 2026, 9)) AS p(idx, anio, mes);

-- =====================================================================================
-- 4. TRANSACCIONES DE CONSUMO
-- =====================================================================================

INSERT INTO transaccion (cuenta_tj_id, plastico_id, num_operacion, fecha_operacion, fecha_proceso,
                         periodo_cargo, tipo_trx_cod, rubro_cod, comercio, moneda_cod,
                         monto, monto_con_signo, num_cuotas)
SELECT  c.cuenta_tj_id,
        pl.plastico_id,
        'CN-' || c.cuenta_tj_id || '-' || c.periodo || '-' || g.j,
        c.fecha_inicio + ((c.cuenta_tj_id * 3 + g.j * 5) % GREATEST((c.fecha_cierre - c.fecha_inicio), 1))::INTEGER
            + INTERVAL '10 hour',
        c.fecha_inicio + ((c.cuenta_tj_id * 3 + g.j * 5) % GREATEST((c.fecha_cierre - c.fecha_inicio), 1))::INTEGER,
        c.periodo,
        d.tipo_trx_cod,
        d.rubro_cod,
        d.comercio,
        'PEN',
        d.monto,
        d.monto,
        d.num_cuotas
FROM        ciclo_facturacion c
JOIN        cuenta_tarjeta   ct ON ct.cuenta_tj_id = c.cuenta_tj_id
CROSS JOIN LATERAL generate_series(1, 3 + ((c.cuenta_tj_id + LENGTH(c.periodo) + CAST(RIGHT(c.periodo,2) AS INT)) % 12)) AS g(j)
CROSS JOIN LATERAL (
        SELECT  CASE WHEN (c.cuenta_tj_id + CAST(RIGHT(c.periodo,2) AS INT) + g.j) % 11 = 0 THEN 'CUO'
                     WHEN (c.cuenta_tj_id + g.j) % 37 = 0                                    THEN 'DISP'
                     ELSE 'CON' END                                                 AS tipo_trx_cod,
                (ARRAY['SUPERMERC','RESTAURANT','COMBUSTIBLE','VESTIMENTA','TECNOLOGIA',
                       'SALUD','EDUCACION','VIAJES','ONLINE','OTROS'])[1 + ((c.cuenta_tj_id + g.j * 3) % 10)] AS rubro_cod,
                (ARRAY['MERCADO CENTRAL','RESTAURANTE EL SOL','GRIFO PRIMAX','TIENDA MODA',
                       'TECNO STORE','BOTICA SALUD','INSTITUTO TEC','AGENCIA VIAJES',
                       'TIENDA ONLINE','COMERCIO VARIOS'])[1 + ((c.cuenta_tj_id + g.j * 3) % 10)] AS comercio,
                ROUND((20 + ((c.cuenta_tj_id * 37 + g.j * 71 + CAST(RIGHT(c.periodo,2) AS INT) * 13) % 900))::NUMERIC, 2) AS monto,
                CASE WHEN (c.cuenta_tj_id + CAST(RIGHT(c.periodo,2) AS INT) + g.j) % 11 = 0
                     THEN (ARRAY[3,6,12])[1 + (c.cuenta_tj_id % 3)]
                     ELSE 1 END::SMALLINT                                           AS num_cuotas
) AS d
JOIN LATERAL (SELECT plastico_id FROM plastico p
              WHERE p.cuenta_tj_id = c.cuenta_tj_id
              ORDER BY (CASE WHEN (c.cuenta_tj_id + g.j) % 5 = 0 THEN p.tipo_plastico END) NULLS LAST,
                       p.plastico_id
              LIMIT 1) AS pl ON TRUE;

-- =====================================================================================
-- 5. PLAN DE CUOTAS DE LAS COMPRAS FRACCIONADAS
--    La última cuota absorbe el redondeo: SUM(capital) = monto exacto.
-- =====================================================================================

INSERT INTO transaccion_cuota (transaccion_id, num_cuota, periodo_cargo,
                               monto_capital, monto_interes, monto_cuota)
SELECT  t.transaccion_id,
        k.i::SMALLINT,
        TO_CHAR((TO_DATE(t.periodo_cargo, 'YYYYMM') + ((k.i - 1) || ' month')::INTERVAL), 'YYYYMM'),
        cap.capital,
        cap.interes,
        cap.capital + cap.interes
FROM        transaccion t
JOIN        cuenta_tarjeta ct ON ct.cuenta_tj_id = t.cuenta_tj_id
CROSS JOIN LATERAL generate_series(1, t.num_cuotas) AS k(i)
CROSS JOIN LATERAL (
        SELECT  CASE WHEN k.i < t.num_cuotas
                     THEN ROUND(t.monto / t.num_cuotas, 2)
                     ELSE t.monto - ROUND(t.monto / t.num_cuotas, 2) * (t.num_cuotas - 1)
                END AS capital,
                ROUND(t.monto / t.num_cuotas * (ct.tea_cuotas / 12), 2) AS interes
) AS cap
WHERE   t.tipo_trx_cod = 'CUO';

-- =====================================================================================
-- 6. ESTADOS DE CUENTA
--    Encadenamiento recursivo: el saldo anterior de un ciclo es el saldo actual del previo.
--    Perfiles de pago: 40% pagador total, 40% revolvente, 10% pago mínimo, 10% incumplido.
-- =====================================================================================

INSERT INTO estado_cuenta (cuenta_tj_id, periodo, fecha_cierre, fecha_vencimiento,
                           saldo_anterior, total_consumos, total_cargos, total_pagos,
                           saldo_actual, pago_minimo, linea_aprobada, linea_disponible)
WITH RECURSIVE
periodos AS (
    SELECT * FROM (VALUES (1,'202604'),(2,'202605'),(3,'202606'),
                          (4,'202607'),(5,'202608'),(6,'202609')) AS v(idx, periodo)
),
-- Consumo cargado en cada ciclo: contado/disposición al 100% + la cuota que vence ese ciclo
consumo_ciclo AS (
    SELECT cuenta_tj_id, periodo_cargo AS periodo, SUM(monto) AS consumos
    FROM   transaccion
    WHERE  tipo_trx_cod IN ('CON','DISP')
    GROUP  BY cuenta_tj_id, periodo_cargo
    UNION ALL
    SELECT t.cuenta_tj_id, tc.periodo_cargo, SUM(tc.monto_cuota)
    FROM   transaccion_cuota tc
    JOIN   transaccion t ON t.transaccion_id = tc.transaccion_id
    GROUP  BY t.cuenta_tj_id, tc.periodo_cargo
),
consumo AS (
    SELECT cuenta_tj_id, periodo, SUM(consumos) AS consumos
    FROM   consumo_ciclo GROUP BY cuenta_tj_id, periodo
),
cadena AS (
    -- Ciclo 1: sin saldo anterior
    SELECT  ct.cuenta_tj_id,
            1                                       AS idx,
            '202604'::CHAR(6)                       AS periodo,
            0.00::NUMERIC(18,2)                     AS saldo_anterior,
            COALESCE(co.consumos, 0)::NUMERIC(18,2) AS total_consumos,
            0.00::NUMERIC(18,2)                     AS total_cargos,
            0.00::NUMERIC(18,2)                     AS total_pagos,
            COALESCE(co.consumos, 0)::NUMERIC(18,2) AS saldo_actual
    FROM        cuenta_tarjeta ct
    LEFT JOIN   consumo co ON co.cuenta_tj_id = ct.cuenta_tj_id AND co.periodo = '202604'
    UNION ALL
    -- Ciclos 2..6
    SELECT  ch.cuenta_tj_id,
            p.idx,
            p.periodo::CHAR(6),
            ch.saldo_actual,
            COALESCE(co.consumos, 0)::NUMERIC(18,2),
            calc.cargos::NUMERIC(18,2),
            calc.pagos::NUMERIC(18,2),
            (ch.saldo_actual + COALESCE(co.consumos, 0) + calc.cargos - calc.pagos)::NUMERIC(18,2)
    FROM        cadena ch
    JOIN        periodos p        ON p.idx = ch.idx + 1
    JOIN        cuenta_tarjeta ct ON ct.cuenta_tj_id = ch.cuenta_tj_id
    LEFT JOIN   consumo co        ON co.cuenta_tj_id = ch.cuenta_tj_id AND co.periodo = p.periodo
    CROSS JOIN LATERAL (
        SELECT  f.frac,
                ROUND(ch.saldo_actual * f.frac, 2)                                  AS pagos,
                CASE WHEN f.frac >= 1 THEN 0.00
                     ELSE ROUND(ch.saldo_actual * (ct.tea_revolvente / 12), 2) END
                + CASE WHEN ch.cuenta_tj_id % 5 = 0 THEN 12.00 ELSE 0.00 END        AS cargos
        FROM (SELECT CASE
                        WHEN ch.cuenta_tj_id % 10 <= 3 THEN 1.00
                        WHEN ch.cuenta_tj_id % 10 <= 7 THEN 0.20
                        WHEN ch.cuenta_tj_id % 10 = 8  THEN 0.05
                        ELSE CASE WHEN p.idx % 3 = 0 THEN 0.00 ELSE 0.10 END
                     END::NUMERIC AS frac) AS f
    ) AS calc
)
SELECT  ch.cuenta_tj_id,
        ch.periodo,
        cf.fecha_cierre,
        cf.fecha_vencimiento,
        ch.saldo_anterior,
        ch.total_consumos,
        ch.total_cargos,
        ch.total_pagos,
        ch.saldo_actual,
        ROUND(GREATEST(ch.saldo_actual * 0.05, LEAST(ch.saldo_actual, 20.00)), 2),
        ct.linea_aprobada,
        ct.linea_aprobada - ch.saldo_actual
FROM    cadena ch
JOIN    cuenta_tarjeta    ct ON ct.cuenta_tj_id = ch.cuenta_tj_id
JOIN    ciclo_facturacion cf ON cf.cuenta_tj_id = ch.cuenta_tj_id AND cf.periodo = ch.periodo;

-- =====================================================================================
-- 7. TRANSACCIONES DERIVADAS DEL ESTADO DE CUENTA (intereses, comisiones y pagos)
--    Se insertan DESPUÉS porque dependen del saldo encadenado.
-- =====================================================================================

-- Intereses revolventes
INSERT INTO transaccion (cuenta_tj_id, num_operacion, fecha_operacion, fecha_proceso,
                         periodo_cargo, tipo_trx_cod, moneda_cod, monto, monto_con_signo)
SELECT  ec.cuenta_tj_id,
        'IN-' || ec.cuenta_tj_id || '-' || ec.periodo,
        ec.fecha_cierre::TIMESTAMP + INTERVAL '23 hour',
        ec.fecha_cierre,
        ec.periodo,
        'INT',
        'PEN',
        ec.total_cargos - CASE WHEN ec.cuenta_tj_id % 5 = 0 THEN 12.00 ELSE 0.00 END,
        ec.total_cargos - CASE WHEN ec.cuenta_tj_id % 5 = 0 THEN 12.00 ELSE 0.00 END
FROM    estado_cuenta ec
WHERE   ec.total_cargos - CASE WHEN ec.cuenta_tj_id % 5 = 0 THEN 12.00 ELSE 0.00 END > 0;

-- Comisión de membresía
INSERT INTO transaccion (cuenta_tj_id, num_operacion, fecha_operacion, fecha_proceso,
                         periodo_cargo, tipo_trx_cod, moneda_cod, monto, monto_con_signo)
SELECT  ec.cuenta_tj_id,
        'CM-' || ec.cuenta_tj_id || '-' || ec.periodo,
        ec.fecha_cierre::TIMESTAMP + INTERVAL '22 hour',
        ec.fecha_cierre,
        ec.periodo,
        'COM',
        'PEN',
        12.00,
        12.00
FROM    estado_cuenta ec
WHERE   ec.cuenta_tj_id % 5 = 0
  AND   ec.periodo <> '202604';

-- Pagos del cliente
INSERT INTO transaccion (cuenta_tj_id, num_operacion, fecha_operacion, fecha_proceso,
                         periodo_cargo, tipo_trx_cod, moneda_cod, monto, monto_con_signo)
SELECT  ec.cuenta_tj_id,
        'PG-' || ec.cuenta_tj_id || '-' || ec.periodo,
        (ec.fecha_cierre - 3)::TIMESTAMP + INTERVAL '16 hour',
        ec.fecha_cierre - 3,
        ec.periodo,
        'PAG',
        'PEN',
        ec.total_pagos,
        -ec.total_pagos
FROM    estado_cuenta ec
WHERE   ec.total_pagos > 0;

-- =====================================================================================
-- 8. COMPORTAMIENTO DE PAGO DEL ESTADO DE CUENTA
--    El pago de un estado de cuenta se aplica en el ciclo SIGUIENTE: hay que mirar hacia
--    adelante para saber si el cliente cumplió.
-- =====================================================================================

WITH pago_siguiente AS (
    SELECT  ec.cuenta_tj_id,
            ec.periodo,
            LEAD(ec.total_pagos) OVER (PARTITION BY ec.cuenta_tj_id ORDER BY ec.periodo) AS pago_prox,
            LEAD(ec.fecha_cierre) OVER (PARTITION BY ec.cuenta_tj_id ORDER BY ec.periodo) AS cierre_prox
    FROM    estado_cuenta ec
)
UPDATE estado_cuenta ec
SET    monto_pagado = COALESCE(ps.pago_prox, 0),
       fecha_pago   = CASE WHEN COALESCE(ps.pago_prox, 0) > 0 THEN ps.cierre_prox - 3 END,
       dias_atraso  = CASE
                          WHEN COALESCE(ps.pago_prox, 0) >= ec.pago_minimo THEN 0
                          WHEN ec.pago_minimo = 0                          THEN 0
                          ELSE 5 + (ec.cuenta_tj_id % 60)
                      END
FROM   pago_siguiente ps
WHERE  ps.cuenta_tj_id = ec.cuenta_tj_id
  AND  ps.periodo      = ec.periodo;

-- =====================================================================================
-- 9. SECUENCIAS Y RESUMEN
-- =====================================================================================

SELECT setval(pg_get_serial_sequence('caso03.titular',        'titular_id'),     (SELECT MAX(titular_id)     FROM titular));
SELECT setval(pg_get_serial_sequence('caso03.cuenta_tarjeta', 'cuenta_tj_id'),   (SELECT MAX(cuenta_tj_id)   FROM cuenta_tarjeta));
SELECT setval(pg_get_serial_sequence('caso03.plastico',       'plastico_id'),    (SELECT MAX(plastico_id)    FROM plastico));
SELECT setval(pg_get_serial_sequence('caso03.transaccion',    'transaccion_id'), (SELECT MAX(transaccion_id) FROM transaccion));

SELECT 'titulares' AS entidad, COUNT(*) AS filas FROM titular
UNION ALL SELECT 'cuentas tarjeta', COUNT(*) FROM cuenta_tarjeta
UNION ALL SELECT 'plasticos',       COUNT(*) FROM plastico
UNION ALL SELECT 'ciclos',          COUNT(*) FROM ciclo_facturacion
UNION ALL SELECT 'transacciones',   COUNT(*) FROM transaccion
UNION ALL SELECT 'cuotas',          COUNT(*) FROM transaccion_cuota
UNION ALL SELECT 'estados cuenta',  COUNT(*) FROM estado_cuenta
ORDER BY 1;
