-- =====================================================================================
-- CASO 02 - Carga de datos
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS (sin random()).
-- Requisito previo: 03-modelo-fisico.sql
-- Volumen: 900 deudores, 1 400 solicitudes, ~700 créditos, ~17 000 cuotas,
--          ~4 200 clasificaciones mensuales (7 periodos)
-- =====================================================================================

SET search_path TO caso02;

TRUNCATE deudor_clasificacion_mes, cronograma_cuota, credito, evaluacion_crediticia,
         solicitud_estado_hist, solicitud_credito, deudor,
         par_provision, par_clasificacion_dias,
         cat_canal_venta, cat_motivo_rechazo, cat_estado_solicitud,
         cat_clasificacion, cat_tipo_credito, cat_tipo_documento, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc) VALUES
    ('PEN', 'Sol peruano'), ('USD', 'Dólar estadounidense');

INSERT INTO cat_tipo_documento (tipo_doc_cod, tipo_doc_desc) VALUES
    ('01', 'DNI'), ('04', 'Carné de extranjería'), ('06', 'RUC'), ('07', 'Pasaporte');

-- Res. SBS 11356-2008: ocho tipos de crédito
INSERT INTO cat_tipo_credito (tipo_credito_cod, tipo_credito_desc, es_minorista) VALUES
    ('1', 'Corporativo',                  FALSE),
    ('2', 'Grandes empresas',             FALSE),
    ('3', 'Medianas empresas',            FALSE),
    ('4', 'Pequeñas empresas',            TRUE),
    ('5', 'Microempresas (MES)',          TRUE),
    ('6', 'Consumo revolvente',           TRUE),
    ('7', 'Consumo no revolvente',        TRUE),
    ('8', 'Hipotecario para vivienda',    TRUE);

INSERT INTO cat_clasificacion (clasificacion_cod, clasificacion_desc, orden_riesgo) VALUES
    ('0', 'Normal',                   0),
    ('1', 'Con Problemas Potenciales', 1),
    ('2', 'Deficiente',               2),
    ('3', 'Dudoso',                   3),
    ('4', 'Pérdida',                  4);

INSERT INTO cat_estado_solicitud (estado_sol_cod, estado_sol_desc, es_final) VALUES
    ('INGRESADA',    'Solicitud ingresada',              FALSE),
    ('EN_EVAL',      'En evaluación crediticia',         FALSE),
    ('APROBADA',     'Aprobada, pendiente de desembolso', FALSE),
    ('DESEMBOLSADA', 'Desembolsada',                     TRUE),
    ('RECHAZADA',    'Rechazada',                        TRUE),
    ('DESISTIDA',    'Desistida por el cliente',         TRUE);

INSERT INTO cat_motivo_rechazo (motivo_cod, motivo_desc) VALUES
    ('SCORE_BAJO',   'Puntaje crediticio por debajo del mínimo'),
    ('SOBREENDEUDA', 'Ratio cuota/ingreso excede el límite'),
    ('CLASIF_SIST',  'Clasificación desfavorable en el sistema financiero'),
    ('ING_NO_VERIF', 'Ingresos no verificables'),
    ('DOC_INCOMPL',  'Documentación incompleta');

INSERT INTO cat_canal_venta (canal_cod, canal_desc, es_digital) VALUES
    ('OFI',  'Oficina',              FALSE),
    ('FFVV', 'Fuerza de venta',      FALSE),
    ('APP',  'Aplicativo móvil',     TRUE),
    ('WEB',  'Banca por internet',   TRUE),
    ('CALL', 'Centro de contacto',   FALSE);

-- =====================================================================================
-- 2. PARÁMETROS NORMATIVOS
--    REFERENCIAL con fines educativos. Verificar la norma vigente en sbs.gob.pe.
-- =====================================================================================

-- Tramos para créditos MINORISTAS (pequeña empresa, MES, consumo, hipotecario)
INSERT INTO par_clasificacion_dias
    (tipo_credito_cod, clasificacion_cod, dias_desde, dias_hasta, fecha_desde, base_legal)
SELECT t.tipo_credito_cod, v.clasificacion_cod, v.dias_desde, v.dias_hasta,
       DATE '2009-01-01', 'Res. SBS 11356-2008 (referencial)'
FROM   (VALUES ('4'),('5'),('6'),('7'),('8')) AS t(tipo_credito_cod)
CROSS JOIN (VALUES
        ('0',   0,     8),
        ('1',   9,    30),
        ('2',  31,    60),
        ('3',  61,   120),
        ('4', 121, 99999)
) AS v(clasificacion_cod, dias_desde, dias_hasta);

-- Tramos para créditos NO minoristas (corporativo, grandes y medianas empresas)
INSERT INTO par_clasificacion_dias
    (tipo_credito_cod, clasificacion_cod, dias_desde, dias_hasta, fecha_desde, base_legal)
SELECT t.tipo_credito_cod, v.clasificacion_cod, v.dias_desde, v.dias_hasta,
       DATE '2009-01-01', 'Res. SBS 11356-2008 (referencial)'
FROM   (VALUES ('1'),('2'),('3')) AS t(tipo_credito_cod)
CROSS JOIN (VALUES
        ('0',   0,     8),
        ('1',   9,    60),
        ('2',  61,   120),
        ('3', 121,   365),
        ('4', 366, 99999)
) AS v(clasificacion_cod, dias_desde, dias_hasta);

INSERT INTO par_provision (clasificacion_cod, tiene_garantia, tasa_provision, fecha_desde, base_legal) VALUES
    ('0', FALSE, 0.010000, DATE '2009-01-01', 'Referencial - provisión genérica'),
    ('0', TRUE,  0.010000, DATE '2009-01-01', 'Referencial - provisión genérica'),
    ('1', FALSE, 0.050000, DATE '2009-01-01', 'Referencial'),
    ('1', TRUE,  0.025000, DATE '2009-01-01', 'Referencial - con garantía preferida'),
    ('2', FALSE, 0.250000, DATE '2009-01-01', 'Referencial'),
    ('2', TRUE,  0.125000, DATE '2009-01-01', 'Referencial - con garantía preferida'),
    ('3', FALSE, 0.600000, DATE '2009-01-01', 'Referencial'),
    ('3', TRUE,  0.300000, DATE '2009-01-01', 'Referencial - con garantía preferida'),
    ('4', FALSE, 1.000000, DATE '2009-01-01', 'Referencial'),
    ('4', TRUE,  0.600000, DATE '2009-01-01', 'Referencial - con garantía preferida');

-- =====================================================================================
-- 3. DEUDORES (900)
-- =====================================================================================

INSERT INTO deudor (deudor_id, tipo_doc_cod, num_doc, ape_paterno, ape_materno, nombres,
                    fecha_nacimiento, ingreso_declarado, situacion_laboral, antiguedad_meses, fecha_alta)
SELECT  n,
        CASE WHEN n % 60 = 0 THEN '04' ELSE '01' END,
        CASE WHEN n % 60 = 0 THEN 'CE' || LPAD((800000 + n * 17)::TEXT, 9, '0')
             ELSE LPAD((71000000 + n * 19)::TEXT, 8, '0') END,
        (ARRAY['QUISPE','MAMANI','FLORES','HUAMAN','ROJAS','VASQUEZ','CHAVEZ','SANCHEZ',
               'RAMOS','CASTILLO','GUTIERREZ','MENDOZA','PEREZ','TORRES','DIAZ','SILVA'])[1 + (n % 16)],
        (ARRAY['CONDORI','APAZA','SALAZAR','VILCA','PAREDES','MEZA','LOPEZ','AGUILAR'])[1 + ((n * 3) % 8)],
        (ARRAY['MARIA','JOSE','ROSA','CARLOS','ANA','LUIS','CARMEN','JORGE','ELENA','MIGUEL',
               'LUCIA','PEDRO'])[1 + ((n * 5) % 12)],
        DATE '1965-01-01' + ((n * 41) % 12000),
        ROUND((1200 + ((n * 137) % 11000))::NUMERIC, 2),
        (ARRAY['DEPENDIENTE','DEPENDIENTE','DEPENDIENTE','INDEPENDIENTE','PENSIONISTA'])[1 + (n % 5)],
        6 + ((n * 7) % 180),
        DATE '2019-01-01' + ((n * 3) % 2400)
FROM generate_series(1, 900) AS n;

-- =====================================================================================
-- 4. SOLICITUDES (1 400)
--    Distribución de desenlaces: 30% rechazadas, 10% desistidas, 10% en evaluación,
--    50% desembolsadas.
-- =====================================================================================

INSERT INTO solicitud_credito (solicitud_id, num_solicitud, deudor_id, tipo_credito_cod, moneda_cod,
                               canal_cod, monto_solicitado, plazo_meses, proposito_cod,
                               fecha_solicitud, estado_sol_cod, fecha_estado, motivo_cod)
SELECT  n,
        'SOL-2026-' || LPAD(n::TEXT, 6, '0'),
        1 + ((n * 11) % 900),
        CASE WHEN n % 13 = 0 THEN '6' ELSE '7' END,
        'PEN',
        (ARRAY['OFI','FFVV','APP','WEB','CALL'])[1 + (n % 5)],
        ROUND((1500 + ((n * 173) % 43500))::NUMERIC, 2),
        (ARRAY[6,12,18,24,36,48,60])[1 + (n % 7)],
        (ARRAY['LIBRE_DISP','CONSOLIDACION','ESTUDIOS','VEHICULO','MEJORA_HOGAR',
               'SALUD','VIAJE'])[1 + ((n * 3) % 7)],
        DATE '2025-10-01' + ((n * 7) % 300),
        est.estado_sol_cod,
        DATE '2025-10-01' + ((n * 7) % 300) + (2 + (n % 10)),
        CASE WHEN est.estado_sol_cod = 'RECHAZADA'
             THEN (ARRAY['SCORE_BAJO','SOBREENDEUDA','CLASIF_SIST','ING_NO_VERIF',
                         'DOC_INCOMPL'])[1 + ((n * 7) % 5)] END
FROM        generate_series(1, 1400) AS n
CROSS JOIN LATERAL (SELECT CASE
        WHEN n % 10 IN (0,1,2) THEN 'RECHAZADA'
        WHEN n % 10 = 3        THEN 'DESISTIDA'
        WHEN n % 10 = 4        THEN 'EN_EVAL'
        ELSE 'DESEMBOLSADA'
    END AS estado_sol_cod) AS est;

-- 4.1 Historia de estados (máquina de estados)
INSERT INTO solicitud_estado_hist (solicitud_id, secuencia, estado_sol_cod, fecha_hora, usuario)
SELECT  s.solicitud_id, 1, 'INGRESADA',
        s.fecha_solicitud::TIMESTAMP + INTERVAL '9 hour', 'sys_originacion'
FROM    solicitud_credito s
UNION ALL
SELECT  s.solicitud_id, 2, 'EN_EVAL',
        s.fecha_solicitud::TIMESTAMP + INTERVAL '1 day 10 hour', 'motor_riesgos'
FROM    solicitud_credito s
UNION ALL
SELECT  s.solicitud_id, 3,
        CASE WHEN s.estado_sol_cod = 'DESEMBOLSADA' THEN 'APROBADA' ELSE s.estado_sol_cod END,
        s.fecha_estado::TIMESTAMP + INTERVAL '11 hour',
        CASE WHEN s.estado_sol_cod = 'RECHAZADA' THEN 'motor_riesgos' ELSE 'analista_credito' END
FROM    solicitud_credito s
WHERE   s.estado_sol_cod <> 'EN_EVAL'
UNION ALL
SELECT  s.solicitud_id, 4, 'DESEMBOLSADA',
        s.fecha_estado::TIMESTAMP + INTERVAL '2 day 15 hour', 'sys_desembolso'
FROM    solicitud_credito s
WHERE   s.estado_sol_cod = 'DESEMBOLSADA';

-- =====================================================================================
-- 5. EVALUACIÓN CREDITICIA
-- =====================================================================================

INSERT INTO evaluacion_crediticia (solicitud_id, fecha_evaluacion, score, ingreso_verificado,
                                   deuda_sistema, cuota_estimada, ratio_cuota_ingreso,
                                   peor_clasif_sistema, resultado)
SELECT  s.solicitud_id,
        s.fecha_solicitud + 1,
        ev.score,
        ev.ingreso_verificado,
        ev.deuda_sistema,
        ev.cuota_estimada,
        ROUND(ev.cuota_estimada / ev.ingreso_verificado, 6),
        CASE WHEN s.estado_sol_cod = 'RECHAZADA' AND s.motivo_cod = 'CLASIF_SIST'
             THEN (ARRAY['2','3','4'])[1 + (s.solicitud_id % 3)]
             WHEN s.solicitud_id % 17 = 0 THEN '1'
             ELSE '0' END,
        CASE WHEN s.estado_sol_cod = 'RECHAZADA' THEN 'RECHAZADO' ELSE 'APROBADO' END
FROM        solicitud_credito s
CROSS JOIN LATERAL (
        SELECT  CASE WHEN s.estado_sol_cod = 'RECHAZADA'
                     THEN 250 + ((s.solicitud_id * 13) % 300)
                     ELSE 560 + ((s.solicitud_id * 13) % 420) END                AS score,
                ROUND((d.ingreso_declarado * (0.85 + ((s.solicitud_id % 30)::NUMERIC / 100)))::NUMERIC, 2) AS ingreso_verificado,
                ROUND(((s.solicitud_id * 211) % 25000)::NUMERIC, 2)              AS deuda_sistema,
                ROUND((s.monto_solicitado / s.plazo_meses * 1.28)::NUMERIC, 2)   AS cuota_estimada
        FROM deudor d WHERE d.deudor_id = s.deudor_id
) AS ev
WHERE   s.estado_sol_cod <> 'EN_EVAL';

-- =====================================================================================
-- 6. CRÉDITOS DESEMBOLSADOS
-- =====================================================================================

INSERT INTO credito (credito_id, num_credito, solicitud_id, deudor_id, tipo_credito_cod, moneda_cod,
                     monto_desembolsado, tea_pct, plazo_meses, fecha_desembolso, fecha_vencimiento,
                     estado_credito, tiene_garantia)
SELECT  ROW_NUMBER() OVER (ORDER BY s.solicitud_id),
        'CRE-2026-' || LPAD(ROW_NUMBER() OVER (ORDER BY s.solicitud_id)::TEXT, 6, '0'),
        s.solicitud_id,
        s.deudor_id,
        s.tipo_credito_cod,
        s.moneda_cod,
        s.monto_solicitado,
        ROUND((0.14 + ((s.solicitud_id % 45)::NUMERIC / 100))::NUMERIC, 6),
        s.plazo_meses,
        s.fecha_estado + 2,
        (s.fecha_estado + 2 + (s.plazo_meses || ' month')::INTERVAL)::DATE,
        CASE WHEN s.solicitud_id % 53 = 0 THEN 'CANCELADO' ELSE 'VIGENTE' END,
        (s.solicitud_id % 9 = 0)
FROM    solicitud_credito s
WHERE   s.estado_sol_cod = 'DESEMBOLSADA';

-- =====================================================================================
-- 7. CRONOGRAMA DE CUOTAS
--    Método de capital constante (sistema alemán): el capital es fijo y el interés
--    decrece. Se eligió por claridad didáctica; ver README para el sistema francés.
--    monto_cuota se calcula como suma de componentes => el CHECK se cumple por diseño.
-- =====================================================================================

INSERT INTO cronograma_cuota (credito_id, num_cuota, fecha_vencimiento, monto_capital,
                              monto_interes, monto_seguro, monto_cuota, fecha_pago,
                              monto_pagado, estado_cuota)
SELECT  c.credito_id,
        k.i::SMALLINT,
        (c.fecha_desembolso + (k.i || ' month')::INTERVAL)::DATE,
        cap.monto_capital,
        cap.monto_interes,
        cap.monto_seguro,
        cap.monto_capital + cap.monto_interes + cap.monto_seguro,
        CASE WHEN est.estado_cuota = 'PAGADA'
             THEN (c.fecha_desembolso + (k.i || ' month')::INTERVAL)::DATE
                  - (c.credito_id % 4)::INTEGER
        END,
        CASE WHEN est.estado_cuota = 'PAGADA'
             THEN cap.monto_capital + cap.monto_interes + cap.monto_seguro
             ELSE 0 END,
        est.estado_cuota
FROM        credito c
CROSS JOIN LATERAL generate_series(1, c.plazo_meses) AS k(i)
CROSS JOIN LATERAL (
        SELECT  CASE WHEN k.i < c.plazo_meses
                     THEN ROUND(c.monto_desembolsado / c.plazo_meses, 2)
                     ELSE c.monto_desembolsado
                          - ROUND(c.monto_desembolsado / c.plazo_meses, 2) * (c.plazo_meses - 1)
                END AS monto_capital,
                ROUND((c.monto_desembolsado
                       - ROUND(c.monto_desembolsado / c.plazo_meses, 2) * (k.i - 1))
                      * (c.tea_pct / 12), 2) AS monto_interes,
                ROUND(c.monto_desembolsado * 0.0005, 2) AS monto_seguro
) AS cap
CROSS JOIN LATERAL (
        SELECT CASE
                 WHEN (c.fecha_desembolso + (k.i || ' month')::INTERVAL)::DATE > DATE '2026-09-16'
                      THEN 'PENDIENTE'
                 WHEN c.credito_id % 11 = 0 AND k.i > 3 THEN 'VENCIDA'
                 ELSE 'PAGADA'
               END AS estado_cuota
) AS est;

-- =====================================================================================
-- 8. CLASIFICACIÓN MENSUAL DEL DEUDOR (7 periodos: 2026-03 a 2026-09)
--    La clasificación NO se inventa: se deriva de los días de atraso mediante la
--    función parametrizada fn_clasificar(). Lo mismo con la provisión.
-- =====================================================================================

-- El GRANO es (deudor, periodo, tipo de credito, moneda). Un deudor con credito de consumo
-- y credito hipotecario produce DOS filas por periodo, no una.
--
-- Y sobre esas filas se aplica el ALINEAMIENTO (RN-06): la clasificacion que se reporta y
-- con la que se provisiona es la PEOR del deudor en el periodo, no la de cada credito por
-- separado. Un deudor al dia en su hipoteca pero con 90 dias de atraso en su tarjeta se
-- reporta como Dudoso en AMBOS creditos. Es contraintuitivo y es lo que manda la norma:
-- el riesgo es de la persona, no del producto.
WITH base AS (
    SELECT  c.deudor_id,
            TO_CHAR(p.fecha_corte, 'YYYYMM')                      AS periodo,
            p.fecha_corte,
            c.tipo_credito_cod,
            c.moneda_cod,
            -- El atraso depende del deudor Y DEL TIPO DE CREDITO. No es un adorno: sin esa
            -- variacion todos los creditos de una persona tendrian los mismos dias, y el
            -- alineamiento nunca se notaria. En la realidad la gente prioriza: paga la
            -- hipoteca y deja de pagar la tarjeta.
            MAX(CASE
                  WHEN c.deudor_id % 20 = 0 THEN   9 + ((c.deudor_id * 3 + p.idx) % 22)
                  WHEN c.deudor_id % 33 = 0 THEN  31 + ((c.deudor_id + p.idx) % 30)
                  WHEN c.deudor_id % 47 = 0 THEN  61 + ((c.deudor_id + p.idx) % 60)
                  WHEN c.deudor_id % 61 = 0 THEN 121 + ((c.deudor_id + p.idx * 7) % 200)
                  ELSE (c.deudor_id + p.idx) % 9
                END
                -- El credito de consumo revolvente (tipo 6, la tarjeta) es el primero
                -- que se deja de pagar: se le suma atraso. El hipotecario (8), el ultimo.
                + CASE c.tipo_credito_cod
                      WHEN '6' THEN 25 + ((c.deudor_id + p.idx) % 40)
                      WHEN '7' THEN  5 + ((c.deudor_id + p.idx) % 10)
                      ELSE 0
                  END)::INTEGER                                   AS dias_atraso,
            ROUND(SUM(c.monto_desembolsado
                  * GREATEST(1 - (p.idx::NUMERIC / GREATEST(c.plazo_meses, 1)), 0.05)), 2) AS saldo_capital,
            BOOL_OR(c.tiene_garantia)                             AS tiene_garantia
    FROM    credito c
    CROSS JOIN (VALUES
            (1, DATE '2026-03-31'), (2, DATE '2026-04-30'), (3, DATE '2026-05-31'),
            (4, DATE '2026-06-30'), (5, DATE '2026-07-31'), (6, DATE '2026-08-31'),
            (7, DATE '2026-09-30')
    ) AS p(idx, fecha_corte)
    WHERE   c.estado_credito = 'VIGENTE'
      AND   c.fecha_desembolso <= p.fecha_corte
    GROUP BY c.deudor_id, p.fecha_corte, p.idx, c.tipo_credito_cod, c.moneda_cod
),
con_propia AS (
    SELECT  b.*,
            fn_clasificar(b.tipo_credito_cod, b.dias_atraso, b.fecha_corte) AS clasif_propia
    FROM    base b
),
alineada AS (
    -- La peor del deudor en el periodo. Los codigos van de '0' (Normal) a '4' (Perdida),
    -- asi que "la peor" es literalmente MAX() sobre el codigo.
    SELECT  cp.*,
            MAX(cp.clasif_propia) OVER (PARTITION BY cp.deudor_id, cp.periodo) AS clasif_alineada
    FROM    con_propia cp
)
INSERT INTO deudor_clasificacion_mes (deudor_id, periodo, fecha_corte, tipo_credito_cod,
                                      moneda_cod, dias_atraso, clasificacion_propia_cod,
                                      clasificacion_cod, saldo_capital,
                                      tiene_garantia, tasa_provision, monto_provision)
SELECT  a.deudor_id,
        a.periodo,
        a.fecha_corte,
        a.tipo_credito_cod,
        a.moneda_cod,
        a.dias_atraso,
        a.clasif_propia,
        a.clasif_alineada,
        a.saldo_capital,
        a.tiene_garantia,
        pp.tasa_provision,
        -- La provision se calcula sobre la clasificacion ALINEADA, no sobre la propia.
        -- Ese es el efecto economico del alineamiento y la razon de que exista la regla.
        ROUND(a.saldo_capital * pp.tasa_provision, 2)
FROM    alineada a
JOIN    par_provision pp
      ON pp.clasificacion_cod = a.clasif_alineada
     AND pp.tiene_garantia    = a.tiene_garantia
     AND a.fecha_corte BETWEEN pp.fecha_desde AND pp.fecha_hasta;

-- =====================================================================================
-- 9. SINCRONIZAR SECUENCIAS
-- =====================================================================================

SELECT setval(pg_get_serial_sequence('caso02.deudor',            'deudor_id'),    (SELECT MAX(deudor_id)    FROM deudor));
SELECT setval(pg_get_serial_sequence('caso02.solicitud_credito', 'solicitud_id'), (SELECT MAX(solicitud_id) FROM solicitud_credito));
SELECT setval(pg_get_serial_sequence('caso02.credito',           'credito_id'),   (SELECT MAX(credito_id)   FROM credito));
SELECT setval(pg_get_serial_sequence('caso02.evaluacion_crediticia', 'evaluacion_id'), (SELECT MAX(evaluacion_id) FROM evaluacion_crediticia));

-- =====================================================================================
-- 10. RESUMEN
-- =====================================================================================

SELECT 'deudores' AS entidad, COUNT(*) AS filas FROM deudor
UNION ALL SELECT 'solicitudes',         COUNT(*) FROM solicitud_credito
UNION ALL SELECT 'evaluaciones',        COUNT(*) FROM evaluacion_crediticia
UNION ALL SELECT 'creditos',            COUNT(*) FROM credito
UNION ALL SELECT 'cuotas',              COUNT(*) FROM cronograma_cuota
UNION ALL SELECT 'clasificaciones mes', COUNT(*) FROM deudor_clasificacion_mes
ORDER BY 1;
