-- =====================================================================================
-- CASO 07 - Carga de datos
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS. Requisito previo: 03-modelo-fisico.sql
-- Volumen: 800 clientes, ~40 000 operaciones, alertas generadas por 5 reglas.
--
-- Los patrones sospechosos (fraccionamiento, exceso de perfil, país de riesgo) están
-- INSERTADOS A PROPÓSITO para que las reglas tengan qué detectar. Ningún cliente,
-- operación o caso corresponde a una persona o hecho real.
-- =====================================================================================

SET search_path TO caso07;

TRUNCATE bitacora_acceso_ros, ros, alerta, caso_investigacion, registro_operacion, operacion,
         cliente_perfil, cliente, regla_monitoreo, par_umbral,
         cat_disposicion, cat_estado_alerta, cat_pais, cat_actividad_economica,
         cat_tipo_operacion, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc) VALUES
    ('PEN', 'Sol peruano'), ('USD', 'Dólar estadounidense');

INSERT INTO cat_tipo_operacion (tipo_op_cod, tipo_op_desc, es_efectivo, sujeta_a_ro) VALUES
    ('DEP_EFEC',  'Depósito en efectivo',            TRUE,  TRUE),
    ('RET_EFEC',  'Retiro en efectivo',              TRUE,  TRUE),
    ('TRF_NAC',   'Transferencia nacional',          FALSE, TRUE),
    ('TRF_INT',   'Transferencia internacional',     FALSE, TRUE),
    ('CAMBIO',    'Compra/venta de moneda extranjera', TRUE, TRUE),
    ('PAGO_SERV', 'Pago de servicios',               FALSE, FALSE);

INSERT INTO cat_actividad_economica (ciiu_cod, actividad_desc, nivel_riesgo) VALUES
    ('4711', 'Venta al por menor en comercios no especializados', 1),
    ('4922', 'Transporte de pasajeros por vía terrestre',          2),
    ('6820', 'Actividades inmobiliarias a cambio de retribución',  3),
    ('9200', 'Actividades de juegos de azar y apuestas',           3),
    ('4662', 'Venta al por mayor de metales y minerales',          3),
    ('8621', 'Actividades de médicos y odontólogos',               1),
    ('5610', 'Actividades de restaurantes',                        2),
    ('0111', 'Cultivo de cereales y legumbres',                    1),
    ('4520', 'Mantenimiento y reparación de vehículos',            2),
    ('6910', 'Actividades jurídicas',                              2);

INSERT INTO cat_pais (pais_cod, pais_desc, es_alto_riesgo) VALUES
    ('PE', 'Perú',           FALSE),
    ('US', 'Estados Unidos', FALSE),
    ('ES', 'España',         FALSE),
    ('CL', 'Chile',          FALSE),
    ('CO', 'Colombia',       FALSE),
    ('PA', 'Panamá',         TRUE),
    ('KY', 'Islas Caimán',   TRUE),
    ('VG', 'Islas Vírgenes Británicas', TRUE);

INSERT INTO cat_estado_alerta (estado_alerta_cod, estado_alerta_desc, es_final) VALUES
    ('GENERADA',   'Generada por el motor de reglas', FALSE),
    ('EN_ANALISIS','En análisis por el oficial',      FALSE),
    ('DESCARTADA', 'Descartada (falso positivo)',     TRUE),
    ('ESCALADA',   'Escalada a caso de investigación', TRUE);

INSERT INTO cat_disposicion (disposicion_cod, disposicion_desc, genera_ros) VALUES
    ('JUSTIFICADA',    'Operativa justificada por el cliente',       FALSE),
    ('PERFIL_ACTUALIZ','Se actualizó el perfil del cliente',         FALSE),
    ('SIN_MERITO',     'Sin mérito para reporte',                    FALSE),
    ('SOSPECHOSA',     'Operación sospechosa: se reporta a la UIF',  TRUE);

-- =====================================================================================
-- 2. UMBRALES
--    ⚠️ REFERENCIALES con fines educativos. Los umbrales de PLAFT los fija la norma
--    vigente de la SBS / UIF-Perú. Verificar antes de cualquier uso profesional.
-- =====================================================================================

INSERT INTO par_umbral (umbral_cod, tipo_op_cod, moneda_cod, monto_umbral, ventana_dias,
                        fecha_desde, base_legal) VALUES
    ('RO_EFECTIVO',     'DEP_EFEC', 'PEN', 40000.00, 1, DATE '2024-01-01', 'Umbral referencial de Registro de Operaciones'),
    ('RO_EFECTIVO',     'RET_EFEC', 'PEN', 40000.00, 1, DATE '2024-01-01', 'Umbral referencial de Registro de Operaciones'),
    ('RO_EFECTIVO',     'CAMBIO',   'PEN', 40000.00, 1, DATE '2024-01-01', 'Umbral referencial de Registro de Operaciones'),
    ('RO_TRANSFERENCIA','TRF_INT',  'PEN', 40000.00, 1, DATE '2024-01-01', 'Umbral referencial de Registro de Operaciones'),
    -- Umbral de FRACCIONAMIENTO: mismo monto, pero acumulado en 5 días
    ('FRACC_EFECTIVO',  'DEP_EFEC', 'PEN', 40000.00, 5, DATE '2024-01-01', 'Deteccion de fraccionamiento (referencial)'),
    ('FRACC_EFECTIVO',  'RET_EFEC', 'PEN', 40000.00, 5, DATE '2024-01-01', 'Deteccion de fraccionamiento (referencial)');

-- =====================================================================================
-- 3. REGLAS DE MONITOREO
-- =====================================================================================

INSERT INTO regla_monitoreo (regla_cod, regla_nombre, descripcion, tipo_regla, severidad,
                             parametros, fecha_desde, base_legal) VALUES
    ('R01-UMBRAL',  'Operación sobre umbral',
     'Operación individual en efectivo o transferencia internacional que supera el umbral de registro.',
     'UMBRAL', 3, '{"umbral_cod":"RO_EFECTIVO"}'::JSONB, DATE '2024-01-01',
     'Registro de Operaciones (referencial)'),

    ('R02-FRACC',   'Posible fraccionamiento',
     'Tres o más operaciones en efectivo en 5 días que SUMADAS superan el umbral, sin que ninguna lo supere individualmente.',
     'FRACCIONAMIENTO', 5, '{"ventana_dias":5,"min_operaciones":3}'::JSONB, DATE '2024-01-01',
     'Deteccion de fraccionamiento (referencial)'),

    ('R03-PERFIL',  'Exceso sobre perfil declarado',
     'El monto transado en el mes supera en más de 3 veces el monto esperado declarado en la debida diligencia.',
     'PERFIL', 4, '{"factor_exceso":3}'::JSONB, DATE '2024-01-01',
     'Conocimiento del cliente (referencial)'),

    ('R04-GEO',     'Operación con jurisdicción de alto riesgo',
     'Transferencia internacional con contraparte en país calificado de alto riesgo.',
     'GEOGRAFICA', 4, '{}'::JSONB, DATE '2024-01-01',
     'Debida diligencia reforzada (referencial)'),

    ('R05-PEP',     'PEP con alta operativa en efectivo',
     'Persona Expuesta Políticamente con operaciones en efectivo acumuladas sobre el umbral mensual.',
     'COMPORTAMIENTO', 5, '{"umbral_mes":25000}'::JSONB, DATE '2024-01-01',
     'Debida diligencia reforzada a PEP (referencial)');

-- =====================================================================================
-- 4. CLIENTES Y PERFILES (800)
-- =====================================================================================

INSERT INTO cliente (cliente_id, tipo_doc_cod, num_doc, nombre_completo, es_persona_juridica,
                     ciiu_cod, pais_residencia, fecha_vinculacion)
SELECT  n,
        CASE WHEN n % 9 = 0 THEN '06' ELSE '01' END,
        CASE WHEN n % 9 = 0 THEN '20' || LPAD((500000000 + n * 13)::TEXT, 9, '0')
             -- 1 de cada 5 monitoreados es tambien cliente de captaciones (caso 01):
             -- el monitoreo PLAFT no vigila a desconocidos, vigila a los propios clientes.
             WHEN n % 5 = 0 THEN LPAD((70000000 + ((n / 5) % 500 + 1) * 13)::TEXT, 8, '0')
             ELSE LPAD((74000000 + n * 17)::TEXT, 8, '0') END,
        CASE WHEN n % 9 = 0
             THEN 'EMPRESA ' || (ARRAY['ANDINA','PACIFICO','CENTRAL','DEL SUR','NORTE',
                                       'COMERCIAL','INDUSTRIAL','GLOBAL'])[1 + (n % 8)] || ' SAC'
             ELSE (ARRAY['MARIA','JOSE','ROSA','CARLOS','ANA','LUIS','CARMEN','JORGE'])[1 + (n % 8)]
                  || ' ' ||
                  (ARRAY['QUISPE','MAMANI','FLORES','HUAMAN','ROJAS','VASQUEZ'])[1 + ((n * 3) % 6)]
        END,
        (n % 9 = 0),
        (ARRAY['4711','4922','6820','9200','4662','8621','5610','0111','4520','6910'])[1 + (n % 10)],
        'PE',
        DATE '2018-01-01' + ((n * 11) % 2800)
FROM generate_series(1, 800) AS n;

INSERT INTO cliente_perfil (cliente_id, fecha_desde, ingreso_declarado, monto_esperado_mes,
                            num_op_esperadas_mes, es_pep, nivel_riesgo, fecha_ultima_dd)
SELECT  c.cliente_id,
        c.fecha_vinculacion,
        ROUND((2500 + ((c.cliente_id * 211) % 40000))::NUMERIC, 2),
        ROUND((20000 + ((c.cliente_id * 173) % 60000))::NUMERIC, 2),
        5 + (c.cliente_id % 25),
        (c.cliente_id % 79 = 0),                       -- ~10 PEP
        CASE WHEN a.nivel_riesgo = 3 OR c.cliente_id % 79 = 0 THEN 'ALTO'
             WHEN a.nivel_riesgo = 2                          THEN 'MEDIO'
             ELSE 'BAJO' END,
        DATE '2025-06-01' + ((c.cliente_id * 7) % 400)::INTEGER
FROM    cliente c
JOIN    cat_actividad_economica a ON a.ciiu_cod = c.ciiu_cod;

-- =====================================================================================
-- 5. OPERACIONES
--    5.1 Operativa normal (dentro del perfil)
-- =====================================================================================

INSERT INTO operacion (cliente_id, fecha_operacion, fecha_contable, tipo_op_cod, moneda_cod,
                       monto, monto_mn, pais_contraparte, canal_cod, num_operacion)
SELECT  c.cliente_id,
        d.fecha::TIMESTAMP + ((c.cliente_id + g.k) % 12 + 8) * INTERVAL '1 hour',
        d.fecha,
        d.tipo_op_cod,
        'PEN',
        d.monto,
        d.monto,
        d.pais,
        (ARRAY['OFI','ATM','AGE','APP','WEB'])[1 + ((c.cliente_id + g.k) % 5)],
        'OPN-' || c.cliente_id || '-' || g.k
FROM        cliente c
CROSS JOIN LATERAL generate_series(1, 20 + (c.cliente_id % 30)) AS g(k)
CROSS JOIN LATERAL (
    SELECT  DATE '2026-07-01' + ((c.cliente_id * 3 + g.k * 7) % 92)::INTEGER                   AS fecha,
            (ARRAY['DEP_EFEC','RET_EFEC','TRF_NAC','PAGO_SERV','CAMBIO',
                   'TRF_NAC','PAGO_SERV'])[1 + ((c.cliente_id + g.k * 3) % 7)]        AS tipo_op_cod,
            ROUND((200 + ((c.cliente_id * 37 + g.k * 131) % 9000))::NUMERIC, 2)       AS monto,
            CASE WHEN (c.cliente_id + g.k) % 61 = 0 THEN 'US' END                     AS pais
) AS d;

-- 5.2 Operaciones grandes: superan el umbral individualmente (dispara R01)
INSERT INTO operacion (cliente_id, fecha_operacion, fecha_contable, tipo_op_cod, moneda_cod,
                       monto, monto_mn, pais_contraparte, canal_cod, num_operacion)
SELECT  c.cliente_id,
        (DATE '2026-07-15' + ((c.cliente_id * 5) % 70)::INTEGER)::TIMESTAMP + INTERVAL '11 hour',
        DATE '2026-07-15' + ((c.cliente_id * 5) % 70)::INTEGER,
        (ARRAY['DEP_EFEC','RET_EFEC','CAMBIO'])[1 + (c.cliente_id % 3)],
        'PEN',
        ROUND((45000 + ((c.cliente_id * 313) % 120000))::NUMERIC, 2),
        ROUND((45000 + ((c.cliente_id * 313) % 120000))::NUMERIC, 2),
        NULL,
        'OFI',
        'OPG-' || c.cliente_id
FROM    cliente c
WHERE   c.cliente_id % 17 = 0;            -- ~47 clientes

-- 5.3 PATRÓN DE FRACCIONAMIENTO: 4 operaciones de ~35 000 en 5 días.
--     Ninguna supera el umbral de 40 000, pero juntas suman ~140 000.
INSERT INTO operacion (cliente_id, fecha_operacion, fecha_contable, tipo_op_cod, moneda_cod,
                       monto, monto_mn, pais_contraparte, canal_cod, num_operacion)
SELECT  c.cliente_id,
        (DATE '2026-08-10' + g.k)::TIMESTAMP + (9 + g.k) * INTERVAL '1 hour',
        DATE '2026-08-10' + g.k,
        'DEP_EFEC',
        'PEN',
        ROUND((33000 + ((c.cliente_id * 7 + g.k * 191) % 6000))::NUMERIC, 2),
        ROUND((33000 + ((c.cliente_id * 7 + g.k * 191) % 6000))::NUMERIC, 2),
        NULL,
        (ARRAY['AGE','ATM','OFI','AGE'])[1 + g.k],
        'OPF-' || c.cliente_id || '-' || g.k
FROM        cliente c
CROSS JOIN LATERAL generate_series(0, 3) AS g(k)
WHERE       c.cliente_id % 37 = 0;        -- ~21 clientes

-- 5.4 Transferencias internacionales a jurisdicciones de alto riesgo (dispara R04)
INSERT INTO operacion (cliente_id, fecha_operacion, fecha_contable, tipo_op_cod, moneda_cod,
                       monto, monto_mn, pais_contraparte, canal_cod, num_operacion)
SELECT  c.cliente_id,
        (DATE '2026-09-05' + ((c.cliente_id * 3) % 20)::INTEGER)::TIMESTAMP + INTERVAL '15 hour',
        DATE '2026-09-05' + ((c.cliente_id * 3) % 20)::INTEGER,
        'TRF_INT',
        'USD',
        ROUND((8000 + ((c.cliente_id * 97) % 25000))::NUMERIC, 2),
        ROUND(((8000 + ((c.cliente_id * 97) % 25000)) * 3.72)::NUMERIC, 2),
        (ARRAY['PA','KY','VG'])[1 + (c.cliente_id % 3)],
        'WEB',
        'OPI-' || c.cliente_id
FROM    cliente c
WHERE   c.cliente_id % 53 = 0;            -- ~15 clientes

-- =====================================================================================
-- 6. REGISTRO DE OPERACIONES (obligación normativa)
-- =====================================================================================

INSERT INTO registro_operacion (operacion_id, fecha_registro, umbral_cod, monto_umbral,
                                monto_operacion, base_legal)
SELECT  o.operacion_id,
        o.fecha_contable,
        u.umbral_cod,
        u.monto_umbral,
        o.monto_mn,
        u.base_legal
FROM    operacion o
JOIN    cat_tipo_operacion t ON t.tipo_op_cod = o.tipo_op_cod AND t.sujeta_a_ro
JOIN    par_umbral u ON u.tipo_op_cod = o.tipo_op_cod
                    AND u.moneda_cod  = 'PEN'
                    AND u.ventana_dias = 1
                    AND o.fecha_contable BETWEEN u.fecha_desde AND u.fecha_hasta
WHERE   o.monto_mn >= u.monto_umbral;

-- =====================================================================================
-- 7. MOTOR DE REGLAS: generación de alertas
-- =====================================================================================

-- R01 — Operación individual sobre umbral
INSERT INTO alerta (regla_cod, cliente_id, fecha_deteccion, fecha_desde_eval, fecha_hasta_eval,
                    cant_operaciones, monto_involucrado, severidad, estado_alerta_cod, detalle)
SELECT  'R01-UMBRAL',
        o.cliente_id,
        o.fecha_contable,
        o.fecha_contable,
        o.fecha_contable,
        1,
        o.monto_mn,
        3,
        'GENERADA',
        JSONB_BUILD_OBJECT(
            'operacion_id',  o.operacion_id,
            'num_operacion', o.num_operacion,
            'tipo_op',       o.tipo_op_cod,
            'monto_mn',      o.monto_mn,
            'umbral',        u.monto_umbral,
            'exceso',        ROUND(o.monto_mn - u.monto_umbral, 2))
FROM    operacion o
JOIN    par_umbral u ON u.tipo_op_cod = o.tipo_op_cod
                    AND u.moneda_cod   = 'PEN'
                    AND u.ventana_dias = 1
                    AND o.fecha_contable BETWEEN u.fecha_desde AND u.fecha_hasta
WHERE   o.monto_mn >= u.monto_umbral;

-- R02 — FRACCIONAMIENTO
-- Técnica: ventana deslizante con RANGE BETWEEN INTERVAL. Suma lo acumulado por el
-- cliente en los últimos 5 días y cuenta las operaciones de esa ventana.
INSERT INTO alerta (regla_cod, cliente_id, fecha_deteccion, fecha_desde_eval, fecha_hasta_eval,
                    cant_operaciones, monto_involucrado, severidad, estado_alerta_cod, detalle)
WITH ventana AS (
    SELECT  o.cliente_id,
            o.fecha_contable,
            o.monto_mn,
            SUM(o.monto_mn) OVER w   AS suma_ventana,
            COUNT(*)        OVER w   AS ops_ventana,
            MAX(o.monto_mn) OVER w   AS mayor_ventana
    FROM    operacion o
    JOIN    cat_tipo_operacion t ON t.tipo_op_cod = o.tipo_op_cod
    WHERE   t.es_efectivo
    WINDOW  w AS (PARTITION BY o.cliente_id ORDER BY o.fecha_contable
                  RANGE BETWEEN INTERVAL '4 days' PRECEDING AND CURRENT ROW)
),
detectado AS (
    SELECT  v.cliente_id,
            MAX(v.fecha_contable)   AS fecha_deteccion,
            MAX(v.ops_ventana)      AS ops,
            MAX(v.suma_ventana)     AS suma,
            MAX(v.mayor_ventana)    AS mayor
    FROM    ventana v
    JOIN    par_umbral u ON u.umbral_cod = 'FRACC_EFECTIVO'
                        AND u.tipo_op_cod = 'DEP_EFEC'
                        AND v.fecha_contable BETWEEN u.fecha_desde AND u.fecha_hasta
    WHERE   v.suma_ventana  >= u.monto_umbral      -- juntas superan el umbral
      AND   v.ops_ventana   >= 3                    -- son varias operaciones
      AND   v.mayor_ventana <  u.monto_umbral       -- pero NINGUNA lo supera sola
    GROUP BY v.cliente_id
)
SELECT  'R02-FRACC',
        d.cliente_id,
        d.fecha_deteccion,
        d.fecha_deteccion - 4,
        d.fecha_deteccion,
        d.ops::INTEGER,
        d.suma,
        5,
        'GENERADA',
        JSONB_BUILD_OBJECT(
            'ventana_dias',       5,
            'operaciones',        d.ops,
            'suma_ventana',       d.suma,
            'operacion_mayor',    d.mayor,
            'umbral_individual',  40000.00,
            'observacion',        'Ninguna operacion supera el umbral individualmente')
FROM    detectado d;

-- R03 — Exceso sobre el perfil declarado
INSERT INTO alerta (regla_cod, cliente_id, fecha_deteccion, fecha_desde_eval, fecha_hasta_eval,
                    cant_operaciones, monto_involucrado, severidad, estado_alerta_cod, detalle)
SELECT  'R03-PERFIL',
        cm.cliente_id,
        (TO_DATE(cm.periodo, 'YYYYMM') + INTERVAL '1 month - 1 day')::DATE,
        TO_DATE(cm.periodo, 'YYYYMM'),
        (TO_DATE(cm.periodo, 'YYYYMM') + INTERVAL '1 month - 1 day')::DATE,
        cm.cant_operaciones,
        cm.monto_total_mn,
        4,
        'GENERADA',
        JSONB_BUILD_OBJECT(
            'periodo',            cm.periodo,
            'monto_real',         cm.monto_total_mn,
            'monto_esperado',     p.monto_esperado_mes,
            'factor_exceso',      ROUND(cm.monto_total_mn / NULLIF(p.monto_esperado_mes, 0), 2),
            'ops_reales',         cm.cant_operaciones,
            'ops_esperadas',      p.num_op_esperadas_mes)
FROM    vw_comportamiento_mes cm
JOIN    cliente_perfil p ON p.cliente_id = cm.cliente_id
                        AND p.fecha_hasta = DATE '9999-12-31'
WHERE   cm.monto_total_mn > p.monto_esperado_mes * 3;

-- R04 — Jurisdicción de alto riesgo
INSERT INTO alerta (regla_cod, cliente_id, fecha_deteccion, fecha_desde_eval, fecha_hasta_eval,
                    cant_operaciones, monto_involucrado, severidad, estado_alerta_cod, detalle)
SELECT  'R04-GEO',
        o.cliente_id,
        o.fecha_contable,
        o.fecha_contable,
        o.fecha_contable,
        1,
        o.monto_mn,
        4,
        'GENERADA',
        JSONB_BUILD_OBJECT(
            'operacion_id',  o.operacion_id,
            'pais',          o.pais_contraparte,
            'pais_desc',     pa.pais_desc,
            'monto_me',      o.monto,
            'moneda',        o.moneda_cod,
            'monto_mn',      o.monto_mn)
FROM    operacion o
JOIN    cat_pais pa ON pa.pais_cod = o.pais_contraparte
WHERE   pa.es_alto_riesgo;

-- R05 — PEP con alta operativa en efectivo
INSERT INTO alerta (regla_cod, cliente_id, fecha_deteccion, fecha_desde_eval, fecha_hasta_eval,
                    cant_operaciones, monto_involucrado, severidad, estado_alerta_cod, detalle)
SELECT  'R05-PEP',
        cm.cliente_id,
        (TO_DATE(cm.periodo, 'YYYYMM') + INTERVAL '1 month - 1 day')::DATE,
        TO_DATE(cm.periodo, 'YYYYMM'),
        (TO_DATE(cm.periodo, 'YYYYMM') + INTERVAL '1 month - 1 day')::DATE,
        cm.cant_operaciones,
        cm.monto_efectivo_mn,
        5,
        'GENERADA',
        JSONB_BUILD_OBJECT(
            'periodo',           cm.periodo,
            'monto_efectivo',    cm.monto_efectivo_mn,
            'umbral_mes',        25000,
            'condicion_cliente', 'PEP')
FROM    vw_comportamiento_mes cm
JOIN    cliente_perfil p ON p.cliente_id = cm.cliente_id
                        AND p.fecha_hasta = DATE '9999-12-31'
WHERE   p.es_pep
  AND   cm.monto_efectivo_mn > 25000;

-- =====================================================================================
-- 8. CASOS DE INVESTIGACIÓN
--    Se escalan las alertas de severidad 5, agrupadas por cliente.
-- =====================================================================================

INSERT INTO caso_investigacion (num_caso, cliente_id, fecha_apertura, fecha_cierre, analista,
                                disposicion_cod, monto_total, cant_alertas)
SELECT  'CASO-2026-' || LPAD(ROW_NUMBER() OVER (ORDER BY a.cliente_id)::TEXT, 5, '0'),
        a.cliente_id,
        MIN(a.fecha_deteccion) + 2,
        CASE WHEN a.cliente_id % 3 <> 0 THEN MIN(a.fecha_deteccion) + 2 + (10 + a.cliente_id % 25)::INTEGER END,
        (ARRAY['analista.uno','analista.dos','analista.tres','analista.cuatro'])[1 + (a.cliente_id % 4)],
        CASE WHEN a.cliente_id % 3 <> 0 THEN
            CASE WHEN a.cliente_id % 7 = 0 THEN 'SOSPECHOSA'
                 WHEN a.cliente_id % 5 = 0 THEN 'PERFIL_ACTUALIZ'
                 WHEN a.cliente_id % 2 = 0 THEN 'JUSTIFICADA'
                 ELSE 'SIN_MERITO' END
        END,
        SUM(a.monto_involucrado),
        COUNT(*)::INTEGER
FROM    alerta a
WHERE   a.severidad = 5
GROUP BY a.cliente_id;

-- Vincular las alertas escaladas a su caso
UPDATE alerta a
SET    caso_id = c.caso_id,
       estado_alerta_cod = 'ESCALADA'
FROM   caso_investigacion c
WHERE  c.cliente_id = a.cliente_id
  AND  a.severidad = 5;

-- Las alertas de menor severidad se resuelven sin caso
UPDATE alerta
SET    estado_alerta_cod = CASE WHEN alerta_id % 4 = 0 THEN 'EN_ANALISIS' ELSE 'DESCARTADA' END
WHERE  severidad < 5;

-- =====================================================================================
-- 9. REPORTES DE OPERACIONES SOSPECHOSAS
-- =====================================================================================

INSERT INTO ros (num_ros, caso_id, fecha_reporte, monto_reportado, oficial_cumplimiento, fecha_envio_uif)
SELECT  'ROS-2026-' || LPAD(ROW_NUMBER() OVER (ORDER BY c.caso_id)::TEXT, 5, '0'),
        c.caso_id,
        c.fecha_cierre,
        c.monto_total,
        'oficial.cumplimiento',
        c.fecha_cierre + 3
FROM    caso_investigacion c
JOIN    cat_disposicion d ON d.disposicion_cod = c.disposicion_cod
WHERE   d.genera_ros;

INSERT INTO bitacora_acceso_ros (ros_id, usuario_bd, fecha_hora, tipo_acceso, motivo)
SELECT  r.ros_id, 'oficial.cumplimiento', r.fecha_reporte::TIMESTAMP + INTERVAL '10 hour',
        'CREACION', 'Registro inicial del reporte'
FROM    ros r
UNION ALL
SELECT  r.ros_id, 'oficial.cumplimiento', r.fecha_envio_uif::TIMESTAMP + INTERVAL '9 hour',
        'ENVIO', 'Remision a la UIF'
FROM    ros r WHERE r.fecha_envio_uif IS NOT NULL;

-- =====================================================================================
-- 10. RESUMEN
-- =====================================================================================

SELECT 'clientes' AS entidad, COUNT(*) AS filas FROM cliente
UNION ALL SELECT 'operaciones',            COUNT(*) FROM operacion
UNION ALL SELECT 'registro de operaciones', COUNT(*) FROM registro_operacion
UNION ALL SELECT 'alertas',                COUNT(*) FROM alerta
UNION ALL SELECT 'casos',                  COUNT(*) FROM caso_investigacion
UNION ALL SELECT 'ROS',                    COUNT(*) FROM ros
ORDER BY 1;

\echo ''
\echo '-- Alertas por regla --'
SELECT regla_cod, COUNT(*) AS alertas, ROUND(AVG(severidad), 1) AS severidad_prom
FROM   alerta GROUP BY regla_cod ORDER BY regla_cod;
