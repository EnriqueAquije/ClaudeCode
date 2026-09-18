-- =====================================================================================
-- CASO 08 - Carga de datos y proceso MDM completo
-- =====================================================================================
-- ⚠️ REQUISITO: esquemas caso01, caso02, caso04 y caso07 cargados.
--    Este caso INTEGRA los clientes de cuatro sistemas distintos del repositorio, que es
--    exactamente el problema real: la misma persona existe en varios sistemas, con
--    identificadores distintos y datos que no coinciden.
-- =====================================================================================

SET search_path TO caso08, public;

-- COMPROBACION DE PRERREQUISITOS
-- Dos condiciones, no una: que el esquema EXISTA y que TENGA DATOS.
-- Comprobar solo la existencia de la tabla es el error clasico, y es peor que no comprobar
-- nada: un MDM que arranca sobre fuentes vacias termina con 0 golden records, sin un solo
-- error, y con todas sus reglas de calidad en verde. Nadie se entera de que esta vacio.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='caso01' AND table_name='cliente')
    THEN RAISE EXCEPTION 'Falta el esquema caso01. Ejecute primero el caso 01.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='caso02' AND table_name='deudor')
    THEN RAISE EXCEPTION 'Falta el esquema caso02. Ejecute primero el caso 02.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='caso04' AND table_name='usuario_billetera')
    THEN RAISE EXCEPTION 'Falta el esquema caso04. Ejecute primero el caso 04.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='caso07' AND table_name='cliente')
    THEN RAISE EXCEPTION 'Falta el esquema caso07. Ejecute primero el caso 07.'; END IF;

    IF (SELECT COUNT(*) FROM caso01.cliente) = 0
    THEN RAISE EXCEPTION 'El esquema caso01 existe pero esta VACIO. Cargue sus datos antes de continuar.'; END IF;
    IF (SELECT COUNT(*) FROM caso02.deudor) = 0
    THEN RAISE EXCEPTION 'El esquema caso02 existe pero esta VACIO. Cargue sus datos antes de continuar.'; END IF;
    IF (SELECT COUNT(*) FROM caso04.usuario_billetera) = 0
    THEN RAISE EXCEPTION 'El esquema caso04 existe pero esta VACIO. Cargue sus datos antes de continuar.'; END IF;
    IF (SELECT COUNT(*) FROM caso07.cliente) = 0
    THEN RAISE EXCEPTION 'El esquema caso07 existe pero esta VACIO. Cargue sus datos antes de continuar.'; END IF;
END $$;

TRUNCATE cliente_xref, cliente_maestro_linaje, cliente_maestro, match_candidato,
         regla_supervivencia, cat_regla_match, calidad_registro, cliente_fuente, cat_fuente
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. SISTEMAS FUENTE Y SU PRECEDENCIA
-- =====================================================================================

INSERT INTO cat_fuente (fuente_cod, fuente_nombre, precedencia, es_externa,
                        es_autoritativa_doc, descripcion) VALUES
    ('PADRON_SUNAT',     'Padrón reducido del RUC - SUNAT', 1, TRUE,  TRUE,
     'Fuente externa oficial. Autoritativa para razón social y actividad económica de personas jurídicas.'),
    ('CORE_CAPTACIONES', 'Core bancario - captaciones',     2, FALSE, FALSE,
     'Datos validados en la apertura de cuenta con documento físico.'),
    ('CORE_CREDITOS',    'Core bancario - créditos',        3, FALSE, FALSE,
     'Datos validados en la evaluación crediticia.'),
    ('MONITOREO',        'Sistema de monitoreo PLAFT',      4, FALSE, FALSE,
     'Datos de la debida diligencia.'),
    ('BILLETERA',        'Billetera digital',               5, FALSE, FALSE,
     'Alta digital con validación mínima: alta cobertura, menor calidad.'),
    ('CRM',              'CRM comercial',                   6, FALSE, FALSE,
     'Carga manual por la fuerza de ventas. Es la fuente con más errores de digitación.');

-- =====================================================================================
-- 2. REGISTROS DE CADA FUENTE
-- =====================================================================================

-- 2.1 Core de captaciones (caso 01)
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, ape_paterno,
                            ape_materno, nombres, fecha_nacimiento, ubigeo, telefono,
                            correo, fecha_actualizacion)
SELECT  'CORE_CAPTACIONES', c.cliente_id::TEXT, c.tipo_doc_cod, c.num_doc,
        c.ape_paterno, c.ape_materno, c.nombres, c.fecha_nacimiento, c.ubigeo,
        CASE WHEN c.cliente_id % 3 <> 0 THEN '9' || LPAD((20000000 + c.cliente_id * 31)::TEXT, 8, '0') END,
        CASE WHEN c.cliente_id % 4 <> 0 THEN LOWER(c.nombres) || '.' || LOWER(c.ape_paterno) || '@correo.pe' END,
        DATE '2026-06-30'
FROM    caso01.cliente c;

-- 2.2 Core de créditos (caso 02)
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, ape_paterno,
                            ape_materno, nombres, fecha_nacimiento, telefono,
                            fecha_actualizacion)
SELECT  'CORE_CREDITOS', d.deudor_id::TEXT, d.tipo_doc_cod, d.num_doc,
        d.ape_paterno, d.ape_materno, d.nombres, d.fecha_nacimiento,
        CASE WHEN d.deudor_id % 2 = 0 THEN '9' || LPAD((30000000 + d.deudor_id * 17)::TEXT, 8, '0') END,
        DATE '2026-08-31'
FROM    caso02.deudor d;

-- 2.3 Billetera digital (caso 04) - alta cobertura, poca información
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, nombres,
                            ubigeo, telefono, fecha_actualizacion)
SELECT  'BILLETERA', u.usuario_id::TEXT, u.tipo_doc_cod, u.num_doc,
        u.nombre_mostrado, u.ubigeo, u.num_celular, DATE '2026-09-30'
FROM    caso04.usuario_billetera u
-- LAS CUENTAS TECNICAS NO SON CLIENTES.
-- El usuario 0 de la billetera es la cuenta puente del banco. Existe en el sistema fuente,
-- tiene RUC y nombre, y si nadie la excluye entra al maestro como un cliente mas -- con su
-- golden record, su score de confianza y su linaje. Es un error clasico de MDM: la fuente
-- tiene filas tecnicas, y el maestro se contamina con ellas.
WHERE   u.usuario_id <> 0;

-- 2.4 Monitoreo PLAFT (caso 07)
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, razon_social,
                            nombres, ape_paterno, ciiu_cod, fecha_actualizacion)
SELECT  'MONITOREO', c.cliente_id::TEXT, c.tipo_doc_cod, c.num_doc,
        CASE WHEN c.es_persona_juridica THEN c.nombre_completo END,
        CASE WHEN NOT c.es_persona_juridica THEN SPLIT_PART(c.nombre_completo, ' ', 1) END,
        CASE WHEN NOT c.es_persona_juridica THEN SPLIT_PART(c.nombre_completo, ' ', 2) END,
        c.ciiu_cod, DATE '2026-09-15'
FROM    caso07.cliente c;

-- 2.5 CRM comercial: DUPLICADOS con errores de digitación.
--     Se transponen dos dígitos del documento y se agregan espacios dobles al nombre.
--     Es el escenario clásico: el mismo cliente, cargado a mano, con el documento mal tipeado.
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, ape_paterno,
                            ape_materno, nombres, fecha_nacimiento, direccion, telefono,
                            correo, fecha_actualizacion)
SELECT  'CRM',
        'CRM-' || c.cliente_id,
        c.tipo_doc_cod,
        -- DOS errores distintos, y esa es la gracia del caso:
        --   3 de cada 4: TRANSPOSICIÓN de los dos últimos dígitos (70000013 -> 70000031).
        --                Los dígitos son los mismos: es un error de tecleo demostrable.
        --   1 de cada 4: un dígito DISTINTO (70000013 -> 70000093).
        --                Misma distancia de edición para LEVENSHTEIN, pero puede ser OTRA
        --                PERSONA. En el Perú, hermanos con documentos correlativos y
        --                homónimos son frecuentes.
        -- Solo el primero se puede fusionar automáticamente. El segundo va a revisión.
        CASE WHEN (c.cliente_id / 4) % 4 = 0
             THEN SUBSTRING(c.num_doc, 1, LENGTH(c.num_doc) - 2)
                  || ((SUBSTRING(c.num_doc, LENGTH(c.num_doc) - 1, 1)::INT + 8) % 10)::TEXT
                  || SUBSTRING(c.num_doc, LENGTH(c.num_doc), 1)
             ELSE SUBSTRING(c.num_doc, 1, LENGTH(c.num_doc) - 2)
                  || SUBSTRING(c.num_doc, LENGTH(c.num_doc), 1)
                  || SUBSTRING(c.num_doc, LENGTH(c.num_doc) - 1, 1)
        END,
        -- TILDES: el core es un sistema legado que guarda ASCII; el CRM es moderno y
        -- guarda el apellido como se escribe de verdad. Es el escenario mas comun en un
        -- banco peruano, y el que rompe el matching por nombre si la normalizacion no
        -- quita las tildes. Con nombre_normalizado bien construido, HUAMAN y HUAMAN con
        -- tilde producen la MISMA clave y el par se une igual.
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(c.ape_paterno,
            'PEREZ','PÉREZ'), 'HUAMAN','HUAMÁN'), 'VASQUEZ','VÁSQUEZ'),
            'CHAVEZ','CHÁVEZ'), 'SANCHEZ','SÁNCHEZ'), 'LOPEZ','LÓPEZ'),
            'RAMIREZ','RAMÍREZ'),
        c.ape_materno, c.nombres, c.fecha_nacimiento,
        'AV. PRINCIPAL ' || (100 + c.cliente_id % 900) || ' - LIMA',
        '9' || LPAD((40000000 + c.cliente_id * 13)::TEXT, 8, '0'),
        LOWER(c.nombres) || LOWER(c.ape_paterno) || '@empresa.com.pe',
        DATE '2026-09-20'
FROM    caso01.cliente c
WHERE   c.cliente_id % 4 = 0
  AND   c.tipo_doc_cod = '01'
  AND   SUBSTRING(c.num_doc, LENGTH(c.num_doc), 1) <> SUBSTRING(c.num_doc, LENGTH(c.num_doc) - 1, 1);

-- 2.5b HOMONIMOS: personas DISTINTAS con el mismo nombre y la misma fecha de nacimiento.
--      Sus documentos no se parecen en nada. NO deben fusionarse automaticamente:
--      en el Peru los homonimos son frecuentes y fusionarlos es el peor error del MDM.
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, ape_paterno,
                            ape_materno, nombres, fecha_nacimiento, direccion, telefono,
                            fecha_actualizacion)
SELECT  'CRM',
        'CRM-HOM-' || c.cliente_id,
        '01',
        LPAD((61000000 + c.cliente_id * 7)::TEXT, 8, '0'),   -- documento totalmente distinto
        c.ape_paterno, c.ape_materno, c.nombres, c.fecha_nacimiento,
        'JR. SEGUNDO ' || (200 + c.cliente_id % 700) || ' - AREQUIPA',
        '9' || LPAD((50000000 + c.cliente_id * 19)::TEXT, 8, '0'),
        DATE '2026-09-25'
FROM    caso01.cliente c
WHERE   c.cliente_id % 41 = 0
  AND   c.tipo_doc_cod = '01';

-- 2.6 Padrón SUNAT (sintético, con formato del padrón reducido real)
INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, razon_social,
                            ubigeo, direccion, ciiu_cod, fecha_actualizacion)
SELECT  'PADRON_SUNAT', c.num_doc, '06', c.num_doc,
        c.nombre_completo,
        (ARRAY['150101','070101','040101','130101'])[1 + (c.cliente_id % 4)],
        'CAL. COMERCIO NRO. ' || (100 + c.cliente_id % 800),
        c.ciiu_cod,
        DATE '2026-09-01'
FROM    caso07.cliente c
WHERE   c.es_persona_juridica;

-- =====================================================================================
-- 3. CALIDAD DE CADA REGISTRO
-- =====================================================================================

INSERT INTO calidad_registro (fuente_cod, id_origen, campos_totales, campos_completos,
                              pct_completitud, doc_valido, antiguedad_dias, score_calidad)
SELECT  f.fuente_cod, f.id_origen,
        8 AS campos_totales,
        comp.n,
        ROUND(100.0 * comp.n / 8, 2),
        val.ok,
        (DATE '2026-09-30' - f.fecha_actualizacion),
        -- Score compuesto: 60% completitud + 25% validez del documento + 15% frescura
        ROUND(  0.60 * (100.0 * comp.n / 8)
              + 0.25 * (CASE WHEN val.ok THEN 100 ELSE 0 END)
              + 0.15 * GREATEST(0, 100 - (DATE '2026-09-30' - f.fecha_actualizacion)), 2)
FROM        cliente_fuente f
CROSS JOIN LATERAL (
        SELECT  (f.num_doc IS NOT NULL)::INT + (f.nombre_normalizado IS NOT NULL)::INT
              + (f.fecha_nacimiento IS NOT NULL)::INT + (f.ubigeo IS NOT NULL)::INT
              + (f.direccion IS NOT NULL)::INT + (f.telefono IS NOT NULL)::INT
              + (f.correo IS NOT NULL)::INT + (f.ciiu_cod IS NOT NULL)::INT AS n
) AS comp
CROSS JOIN LATERAL (
        SELECT CASE
                 WHEN f.tipo_doc_cod = '01' THEN f.num_doc ~ '^[0-9]{8}$'
                 WHEN f.tipo_doc_cod = '06' THEN f.num_doc ~ '^[0-9]{11}$'
                 ELSE f.num_doc IS NOT NULL
               END AS ok
) AS val;

-- =====================================================================================
-- 4. REGLAS DE MATCHING
-- =====================================================================================

INSERT INTO cat_regla_match (regla_cod, regla_nombre, tipo_match, descripcion,
                         score_asignado, umbral_auto) VALUES
    ('M01-DOC-EXACTO', 'Documento idéntico', 'DETERMINISTA',
     'Mismo tipo y número de documento en dos sistemas distintos. Es el match más confiable.',
     100.00, 100.00),
    ('M02-DOC-TIPEO',  'Documento con error de digitación', 'PROBABILISTICO',
     'Mismo nombre y fecha de nacimiento, y documento que es una TRANSPOSICIÓN (mismos dígitos, dos intercambiados). Cualquier otra discrepancia va a revisión humana.',
     85.00, 80.00),
    ('M03-NOMBRE-FECHA','Nombre y fecha de nacimiento', 'PROBABILISTICO',
     'Mismo nombre y misma fecha de nacimiento, sin coincidencia de documento. Requiere revisión manual.',
     60.00, 80.00);

-- 4.1 M01 — Match determinista por documento
INSERT INTO match_candidato (fuente_a, id_origen_a, fuente_b, id_origen_b, regla_cod,
                             score, decision, evidencia)
SELECT  a.fuente_cod, a.id_origen, b.fuente_cod, b.id_origen,
        'M01-DOC-EXACTO', 100.00, 'AUTO_MATCH',
        JSONB_BUILD_OBJECT('tipo_doc', a.tipo_doc_cod, 'num_doc', a.num_doc,
                           'criterio', 'documento identico')
FROM    cliente_fuente a
JOIN    cliente_fuente b ON b.tipo_doc_cod = a.tipo_doc_cod
                        AND b.num_doc      = a.num_doc
                        AND b.fuente_cod  <> a.fuente_cod
JOIN    cat_fuente fa ON fa.fuente_cod = a.fuente_cod
JOIN    cat_fuente fb ON fb.fuente_cod = b.fuente_cod
WHERE   fa.precedencia < fb.precedencia      -- cada par una sola vez, el mejor primero
  AND   a.num_doc IS NOT NULL;

-- 4.2 M02 — Match probabilístico: error de digitación en el documento.
--     Se restringe al CRM (la fuente con errores conocidos) para evitar un producto
--     cartesiano: sin esa restricción, comparar todos contra todos es inviable.
INSERT INTO match_candidato (fuente_a, id_origen_a, fuente_b, id_origen_b, regla_cod,
                             score, decision, evidencia)
SELECT  b.fuente_cod, b.id_origen, a.fuente_cod, a.id_origen,
        'M02-DOC-TIPEO',
        ROUND(85.00 - (LEVENSHTEIN(a.num_doc, b.num_doc) * 2.0), 2),
        -- LA POLITICA, y es lo que este paso enseña: solo se fusiona sola una TRANSPOSICION,
        -- que es un error de tecleo demostrable porque los digitos son los mismos. Cualquier
        -- otra discrepancia en el documento va a revision humana, aunque la distancia sea la
        -- misma. La asimetria de costos no admite otra cosa: un falso positivo mezcla dos
        -- historiales crediticios y termina en un reclamo ante Indecopi; un falso negativo
        -- deja un cliente duplicado, que se corrige mañana.
        CASE WHEN fn_es_transposicion(a.num_doc, b.num_doc)
             THEN 'AUTO_MATCH' ELSE 'REVISION' END,
        JSONB_BUILD_OBJECT(
            'doc_crm',        a.num_doc,
            'doc_core',       b.num_doc,
            'distancia_edicion', LEVENSHTEIN(a.num_doc, b.num_doc),
            'nombre',         a.nombre_normalizado,
            'fecha_nac',      a.fecha_nacimiento,
            'criterio',       'nombre y fecha de nacimiento identicos, documento con transposicion')
FROM    cliente_fuente a
JOIN    cliente_fuente b ON b.fuente_cod          = 'CORE_CAPTACIONES'
                        AND b.nombre_normalizado  = a.nombre_normalizado
                        AND b.fecha_nacimiento    = a.fecha_nacimiento
                        AND b.num_doc            <> a.num_doc
                        AND LEVENSHTEIN(a.num_doc, b.num_doc) <= 2
WHERE   a.fuente_cod = 'CRM';

-- 4.3 M03 - Homonimos: mismo nombre y misma fecha de nacimiento, pero documentos que NO
--     se parecen. NO es evidencia suficiente: en el Peru los homonimos son frecuentes.
--     Estos casos van a REVISION MANUAL, nunca a fusion automatica.
INSERT INTO match_candidato (fuente_a, id_origen_a, fuente_b, id_origen_b, regla_cod,
                             score, decision, evidencia)
SELECT  a.fuente_cod, a.id_origen, b.fuente_cod, b.id_origen,
        'M03-NOMBRE-FECHA', 60.00, 'REVISION',
        JSONB_BUILD_OBJECT(
            'nombre',     a.nombre_normalizado,
            'fecha_nac',  a.fecha_nacimiento,
            'doc_a',      a.num_doc,
            'doc_b',      b.num_doc,
            'distancia_edicion', LEVENSHTEIN(a.num_doc, b.num_doc),
            'criterio',   'homonimo con misma fecha de nacimiento: requiere verificacion humana')
FROM    cliente_fuente a
JOIN    cliente_fuente b ON b.nombre_normalizado = a.nombre_normalizado
                        AND b.fecha_nacimiento   = a.fecha_nacimiento
                        AND b.num_doc           <> a.num_doc
                        AND LEVENSHTEIN(a.num_doc, b.num_doc) > 2
JOIN    cat_fuente fa ON fa.fuente_cod = a.fuente_cod
JOIN    cat_fuente fb ON fb.fuente_cod = b.fuente_cod
WHERE   fa.precedencia < fb.precedencia
  AND   a.fecha_nacimiento IS NOT NULL
  AND   a.nombre_normalizado IS NOT NULL;

-- =====================================================================================
-- 5. REGLAS DE SUPERVIVENCIA
-- =====================================================================================

INSERT INTO regla_supervivencia (atributo, criterio, fuente_preferida, descripcion) VALUES
    ('nombre_completo',  'PRECEDENCIA',  NULL,
     'Gana la fuente de mayor autoridad que tenga el dato.'),
    ('fecha_nacimiento', 'PRECEDENCIA',  NULL,
     'Gana la fuente de mayor autoridad; los cores validan contra documento físico.'),
    ('ubigeo',           'MAS_RECIENTE', NULL,
     'Gana el dato actualizado más recientemente: la dirección cambia.'),
    ('direccion',        'MAS_RECIENTE', NULL,
     'Igual que el ubigeo: prima la frescura sobre la autoridad.'),
    ('telefono',         'MAS_RECIENTE', NULL,
     'El teléfono cambia con frecuencia; el dato más nuevo es el útil.'),
    ('correo',           'MAS_RECIENTE', NULL,
     'Igual que el teléfono.'),
    ('ciiu_cod',         'FUENTE_FIJA',  'PADRON_SUNAT',
     'La actividad económica la determina SUNAT: es la fuente autoritativa, sin importar la frescura.');

-- =====================================================================================
-- 6. CONSTRUCCIÓN DEL REGISTRO MAESTRO
--    Paso 1: resolver a qué documento CANÓNICO pertenece cada registro.
--            Los matches probabilísticos aceptados redirigen el documento del CRM
--            (menor precedencia) al del core (mayor precedencia).
-- =====================================================================================

CREATE TEMP TABLE tmp_doc_canonico AS
SELECT  a.tipo_doc_cod AS tipo_doc_origen,
        a.num_doc      AS num_doc_origen,
        b.tipo_doc_cod AS tipo_doc_canon,
        b.num_doc      AS num_doc_canon
FROM    match_candidato mc
JOIN    cliente_fuente a ON a.fuente_cod = mc.fuente_a AND a.id_origen = mc.id_origen_a
JOIN    cliente_fuente b ON b.fuente_cod = mc.fuente_b AND b.id_origen = mc.id_origen_b
WHERE   mc.regla_cod = 'M02-DOC-TIPEO'
  AND   mc.decision  = 'AUTO_MATCH';

-- Cada registro fuente con su documento canónico y la precedencia de su fuente
CREATE TEMP TABLE tmp_registro_cluster AS
SELECT  f.fuente_cod,
        f.id_origen,
        COALESCE(dc.tipo_doc_canon, f.tipo_doc_cod) AS tipo_doc_canon,
        COALESCE(dc.num_doc_canon,  f.num_doc)      AS num_doc_canon,
        cf.precedencia,
        f.fecha_actualizacion
FROM        cliente_fuente f
JOIN        cat_fuente cf ON cf.fuente_cod = f.fuente_cod
LEFT JOIN   tmp_doc_canonico dc ON dc.tipo_doc_origen = f.tipo_doc_cod
                               AND dc.num_doc_origen  = f.num_doc
WHERE       f.num_doc IS NOT NULL;

CREATE INDEX ix_tmp_cluster ON tmp_registro_cluster (tipo_doc_canon, num_doc_canon);

-- Paso 2: un registro maestro por documento canónico, aplicando supervivencia.
INSERT INTO cliente_maestro (tipo_doc_cod, num_doc, nombre_completo, es_persona_juridica,
                             fecha_nacimiento, ubigeo, direccion, telefono, correo,
                             ciiu_cod, cant_fuentes, score_confianza)
SELECT  cl.tipo_doc_canon,
        cl.num_doc_canon,
        sv_nombre.valor,
        (cl.tipo_doc_canon = '06'),
        sv_fnac.valor::DATE,
        sv_ubigeo.valor,
        sv_dir.valor,
        sv_tel.valor,
        sv_mail.valor,
        sv_ciiu.valor,
        cl.cant_fuentes,
        cl.score
FROM (
    SELECT  rc.tipo_doc_canon, rc.num_doc_canon,
            COUNT(DISTINCT rc.fuente_cod)::SMALLINT AS cant_fuentes,
            ROUND(AVG(cr.score_calidad), 2)      AS score
    FROM    tmp_registro_cluster rc
    JOIN    calidad_registro cr ON cr.fuente_cod = rc.fuente_cod AND cr.id_origen = rc.id_origen
    GROUP BY rc.tipo_doc_canon, rc.num_doc_canon
) AS cl
-- PRECEDENCIA: gana la fuente de mayor autoridad que tenga el dato
CROSS JOIN LATERAL (
    SELECT f.nombre_normalizado AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
      AND  f.nombre_normalizado IS NOT NULL
    ORDER BY rc.precedencia LIMIT 1
) AS sv_nombre
CROSS JOIN LATERAL (
    SELECT f.fecha_nacimiento::TEXT AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.fecha_nacimiento IS NULL), rc.precedencia LIMIT 1
) AS sv_fnac
-- MAS_RECIENTE: gana el dato actualizado más recientemente
CROSS JOIN LATERAL (
    SELECT f.ubigeo AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.ubigeo IS NULL), rc.fecha_actualizacion DESC LIMIT 1
) AS sv_ubigeo
CROSS JOIN LATERAL (
    SELECT f.direccion AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.direccion IS NULL), rc.fecha_actualizacion DESC LIMIT 1
) AS sv_dir
CROSS JOIN LATERAL (
    SELECT f.telefono AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.telefono IS NULL), rc.fecha_actualizacion DESC LIMIT 1
) AS sv_tel
CROSS JOIN LATERAL (
    SELECT f.correo AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.correo IS NULL), rc.fecha_actualizacion DESC LIMIT 1
) AS sv_mail
-- FUENTE_FIJA: la actividad económica SIEMPRE viene de SUNAT si existe
CROSS JOIN LATERAL (
    SELECT f.ciiu_cod AS valor
    FROM   tmp_registro_cluster rc JOIN cliente_fuente f USING (fuente_cod, id_origen)
    WHERE  rc.tipo_doc_canon = cl.tipo_doc_canon AND rc.num_doc_canon = cl.num_doc_canon
    ORDER BY (f.ciiu_cod IS NULL), (rc.fuente_cod <> 'PADRON_SUNAT'), rc.precedencia LIMIT 1
) AS sv_ciiu;

-- Paso 3: referencia cruzada
INSERT INTO cliente_xref (cliente_maestro_id, fuente_cod, id_origen, tipo_vinculo, score_vinculo)
SELECT  m.cliente_maestro_id,
        rc.fuente_cod,
        rc.id_origen,
        CASE WHEN EXISTS (SELECT 1 FROM tmp_doc_canonico dc
                          JOIN cliente_fuente f ON f.fuente_cod = rc.fuente_cod
                                               AND f.id_origen  = rc.id_origen
                          WHERE dc.num_doc_origen = f.num_doc
                            AND dc.num_doc_canon  <> f.num_doc)
             THEN 'PROBABILISTICO' ELSE 'DETERMINISTA' END,
        CASE WHEN EXISTS (SELECT 1 FROM tmp_doc_canonico dc
                          JOIN cliente_fuente f ON f.fuente_cod = rc.fuente_cod
                                               AND f.id_origen  = rc.id_origen
                          WHERE dc.num_doc_origen = f.num_doc
                            AND dc.num_doc_canon  <> f.num_doc)
             THEN 85.00 ELSE 100.00 END
FROM    tmp_registro_cluster rc
JOIN    cliente_maestro m ON m.tipo_doc_cod = rc.tipo_doc_canon
                         AND m.num_doc      = rc.num_doc_canon;

-- Paso 4: linaje de cada atributo (de qué fuente salió)
INSERT INTO cliente_maestro_linaje (cliente_maestro_id, atributo, fuente_cod, id_origen, criterio_aplicado)
SELECT DISTINCT ON (m.cliente_maestro_id, at.atributo)
        m.cliente_maestro_id, at.atributo, x.fuente_cod, x.id_origen, at.criterio
FROM        cliente_maestro m
JOIN        cliente_xref   x ON x.cliente_maestro_id = m.cliente_maestro_id
JOIN        cliente_fuente f ON f.fuente_cod = x.fuente_cod AND f.id_origen = x.id_origen
JOIN        cat_fuente    cf ON cf.fuente_cod = f.fuente_cod
CROSS JOIN LATERAL (VALUES
        ('nombre_completo',  'PRECEDENCIA',  f.nombre_normalizado),
        ('fecha_nacimiento', 'PRECEDENCIA',  f.fecha_nacimiento::TEXT),
        ('ubigeo',           'MAS_RECIENTE', f.ubigeo),
        ('direccion',        'MAS_RECIENTE', f.direccion),
        ('telefono',         'MAS_RECIENTE', f.telefono),
        ('correo',           'MAS_RECIENTE', f.correo),
        ('ciiu_cod',         'FUENTE_FIJA',  f.ciiu_cod)
) AS at(atributo, criterio, valor)
WHERE   at.valor IS NOT NULL
ORDER BY m.cliente_maestro_id, at.atributo,
         CASE at.criterio
              WHEN 'FUENTE_FIJA'  THEN (f.fuente_cod <> 'PADRON_SUNAT')::INT
              ELSE 0 END,
         CASE at.criterio WHEN 'MAS_RECIENTE' THEN 0 ELSE 1 END * cf.precedencia,
         CASE at.criterio WHEN 'MAS_RECIENTE' THEN f.fecha_actualizacion END DESC NULLS LAST,
         cf.precedencia;

-- =====================================================================================
-- 7. RESUMEN
-- =====================================================================================

SELECT 'registros fuente' AS entidad, COUNT(*) AS filas FROM cliente_fuente
UNION ALL SELECT 'candidatos de match',  COUNT(*) FROM match_candidato
UNION ALL SELECT '  auto-match',         COUNT(*) FROM match_candidato WHERE decision = 'AUTO_MATCH'
UNION ALL SELECT '  a revision manual',  COUNT(*) FROM match_candidato WHERE decision = 'REVISION'
UNION ALL SELECT 'clientes maestros',    COUNT(*) FROM cliente_maestro
UNION ALL SELECT 'referencias cruzadas', COUNT(*) FROM cliente_xref
UNION ALL SELECT 'trazas de linaje',     COUNT(*) FROM cliente_maestro_linaje
ORDER BY 1;

\echo ''
\echo '-- Registros por fuente --'
SELECT f.fuente_cod, cf.precedencia, COUNT(*) AS registros,
       ROUND(AVG(cr.score_calidad), 1) AS calidad_promedio
FROM   cliente_fuente f
JOIN   cat_fuente cf ON cf.fuente_cod = f.fuente_cod
JOIN   calidad_registro cr ON cr.fuente_cod = f.fuente_cod AND cr.id_origen = f.id_origen
GROUP  BY f.fuente_cod, cf.precedencia
ORDER  BY cf.precedencia;
