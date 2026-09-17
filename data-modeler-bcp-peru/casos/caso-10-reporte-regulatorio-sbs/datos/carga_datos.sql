-- =====================================================================================
-- CASO 10 - Carga de datos y generación del reporte regulatorio
-- =====================================================================================
-- ⚠️ REQUISITO: el esquema caso02 debe existir y estar cargado.
--    El reporte NO inventa datos: los EXTRAE del sistema de créditos. Eso es lo que hace
--    un reporte regulatorio real, y por eso el linaje importa tanto.
--
-- ⚠️ La estructura del reporte es una SIMPLIFICACIÓN EDUCATIVA. La estructura real del
--    Reporte Crediticio de Deudores la define la SBS: https://www.sbs.gob.pe/normativa
-- =====================================================================================

SET search_path TO caso10, public;

-- COMPROBACION DE PRERREQUISITOS
-- Que la tabla exista NO basta: si esta vacia, el reporte se genera sin deudores y se
-- remite un archivo vacio dentro del plazo. Para el supervisor eso es peor que un envio
-- tardio, y ninguna regla de calidad lo detectaria: cero filas son cero incumplimientos.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = 'caso02' AND table_name = 'deudor_clasificacion_mes')
    THEN RAISE EXCEPTION 'Falta el esquema caso02. Ejecute primero el caso 02 completo.'; END IF;

    IF (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes) = 0
    THEN RAISE EXCEPTION 'El esquema caso02 existe pero esta VACIO: no hay deudores que reportar.'; END IF;
END $$;

TRUNCATE cuadre_reporte, reporte_error, reporte_detalle, reporte_envio,
         reporte_linaje, reporte_validacion, reporte_campo, reporte_definicion
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. DEFINICIÓN DEL REPORTE (dos versiones: la SBS cambió la estructura)
-- =====================================================================================

INSERT INTO reporte_definicion (reporte_cod, version, reporte_nombre, periodicidad,
                                dias_plazo, base_legal, fecha_desde, fecha_hasta) VALUES
    ('RCD', 1, 'Reporte Crediticio de Deudores (estructura educativa v1)', 'MENSUAL', 15,
     'Referencial - basado en la estructura conceptual del RCD (SBS)', DATE '2024-01-01', DATE '2026-06-30'),
    ('RCD', 2, 'Reporte Crediticio de Deudores (estructura educativa v2)', 'MENSUAL', 15,
     'Referencial - version con campo de garantia agregado', DATE '2026-07-01', DATE '9999-12-31');

-- 1.1 Campos de la versión 2 (la vigente)
INSERT INTO reporte_campo (reporte_cod, version, posicion, campo_cod, campo_nombre,
                           tipo_dato, longitud, decimales, es_obligatorio, dominio, base_legal) VALUES
    ('RCD',2, 1,'TIPO_DOC',       'Tipo de documento de identidad',     'TEXTO',  2,0,TRUE,
     '01=DNI, 04=CE, 06=RUC, 07=Pasaporte', 'Dominio de tipos de documento'),
    ('RCD',2, 2,'NUM_DOC',        'Número de documento',                'TEXTO', 20,0,TRUE,
     'Numérico para DNI (8) y RUC (11)', 'Identificación del deudor'),
    ('RCD',2, 3,'NOMBRE_DEUDOR',  'Nombre o razón social del deudor',   'TEXTO',160,0,TRUE,
     NULL, NULL),
    ('RCD',2, 4,'TIPO_CREDITO',   'Tipo de crédito',                    'TEXTO',  1,0,TRUE,
     '1 a 8 según Res. SBS 11356-2008', 'Res. SBS 11356-2008 (referencial)'),
    ('RCD',2, 5,'CLASIFICACION',  'Clasificación del deudor',           'TEXTO',  1,0,TRUE,
     '0=Normal 1=CPP 2=Deficiente 3=Dudoso 4=Pérdida', 'Res. SBS 11356-2008 (referencial)'),
    ('RCD',2, 6,'DIAS_ATRASO',    'Días de atraso',                     'ENTERO', 5,0,TRUE,
     'Mayor o igual a 0', NULL),
    ('RCD',2, 7,'MONEDA',         'Moneda',                             'TEXTO',  3,0,TRUE,
     'PEN, USD (ISO 4217)', NULL),
    ('RCD',2, 8,'SALDO_CAPITAL',  'Saldo de capital',                   'NUMERO',18,2,TRUE,
     'Mayor o igual a 0', NULL),
    ('RCD',2, 9,'PROVISION',      'Provisión constituida',              'NUMERO',18,2,TRUE,
     'Menor o igual al saldo de capital', 'Res. SBS 11356-2008 (referencial)'),
    ('RCD',2,10,'GARANTIA',       'Indicador de garantía preferida',    'TEXTO',  1,0,TRUE,
     'S=Sí, N=No', 'Campo agregado en la version 2'),
    ('RCD',2,11,'FECHA_CORTE',    'Fecha de corte del reporte',         'FECHA',  8,0,TRUE,
     'AAAAMMDD, último día del mes', NULL);

-- 1.2 Versión 1: la misma estructura SIN el campo de garantía.
--     Conservarla permite reproducir exactamente los envíos anteriores a julio de 2026.
INSERT INTO reporte_campo (reporte_cod, version, posicion, campo_cod, campo_nombre,
                           tipo_dato, longitud, decimales, es_obligatorio, dominio, base_legal)
SELECT 'RCD', 1,
       CASE WHEN posicion > 10 THEN posicion - 1 ELSE posicion END,
       campo_cod, campo_nombre, tipo_dato, longitud, decimales, es_obligatorio, dominio, base_legal
FROM   reporte_campo
WHERE  reporte_cod = 'RCD' AND version = 2 AND campo_cod <> 'GARANTIA';

-- =====================================================================================
-- 2. VALIDACIONES QUE APLICA EL SUPERVISOR
--    Se guardan como DATOS: agregar una validación nueva no requiere desplegar código.
-- =====================================================================================

INSERT INTO reporte_validacion (reporte_cod, version, validacion_cod, descripcion,
                                severidad, expresion_sql, base_legal) VALUES
    ('RCD',2,'V01-DOC-FORMATO', 'El DNI debe tener 8 dígitos y el RUC 11', 'BLOQUEA',
     '(tipo_doc_cod = ''01'' AND num_doc !~ ''^[0-9]{8}$'') OR (tipo_doc_cod = ''06'' AND num_doc !~ ''^[0-9]{11}$'')',
     'Validacion de formato de identificacion'),
    ('RCD',2,'V02-CLASIF-DOM',  'La clasificación debe estar entre 0 y 4', 'BLOQUEA',
     'clasificacion_cod NOT IN (''0'',''1'',''2'',''3'',''4'')',
     'Res. SBS 11356-2008 (referencial)'),
    ('RCD',2,'V03-PROV-SALDO',  'La provisión no puede superar el saldo de capital', 'BLOQUEA',
     'monto_provision > saldo_capital', 'Coherencia aritmetica'),
    ('RCD',2,'V04-SALDO-CERO',  'Un deudor reportado con saldo cero debe revisarse', 'ADVIERTE',
     'saldo_capital = 0', 'Control de razonabilidad'),
    ('RCD',2,'V05-ATRASO-CLAS', 'Un deudor Normal no debería tener más de 8 días de atraso', 'ADVIERTE',
     'clasificacion_cod = ''0'' AND dias_atraso > 8', 'Res. SBS 11356-2008 (referencial)'),
    ('RCD',2,'V06-NOMBRE-VACIO','El nombre del deudor es obligatorio', 'BLOQUEA',
     'nombre_deudor IS NULL OR TRIM(nombre_deudor) = ''''', 'Campo obligatorio');

-- =====================================================================================
-- 3. LINAJE CAMPO A CAMPO
--    Este es el entregable que se presenta ante una observación del supervisor.
-- =====================================================================================

INSERT INTO reporte_linaje (reporte_cod, version, campo_cod, esquema_origen, tabla_origen,
                            columna_origen, transformacion, responsable) VALUES
    ('RCD',2,'TIPO_DOC',      'caso02','deudor','tipo_doc_cod',
     'Directo, sin transformacion',                                     'Arquitectura de Datos'),
    ('RCD',2,'NUM_DOC',       'caso02','deudor','num_doc',
     'TRIM y relleno a la izquierda con ceros segun longitud del tipo', 'Arquitectura de Datos'),
    ('RCD',2,'NOMBRE_DEUDOR', 'caso02','deudor',NULL,
     'Concatenacion: ape_paterno + ape_materno + nombres',              'Arquitectura de Datos'),
    ('RCD',2,'TIPO_CREDITO',  'caso02','deudor_clasificacion_mes','tipo_credito_cod',
     'Directo. Dominio validado contra cat_tipo_credito',               'Riesgos'),
    ('RCD',2,'CLASIFICACION', 'caso02','deudor_clasificacion_mes','clasificacion_cod',
     'Derivado de dias_atraso mediante fn_clasificar() con la norma vigente a la fecha de corte',
     'Riesgos'),
    ('RCD',2,'DIAS_ATRASO',   'caso02','deudor_clasificacion_mes','dias_atraso',
     'Directo. Calculado como fecha_corte menos vencimiento de la cuota impaga mas antigua',
     'Riesgos'),
    ('RCD',2,'MONEDA',        'caso02','credito','moneda_cod',
     'Moneda del credito. Si el deudor tiene varios, se reporta la de mayor saldo',
     'Contabilidad'),
    ('RCD',2,'SALDO_CAPITAL', 'caso02','deudor_clasificacion_mes','saldo_capital',
     'Suma del capital vigente del deudor a la fecha de corte',         'Contabilidad'),
    ('RCD',2,'PROVISION',     'caso02','deudor_clasificacion_mes','monto_provision',
     'saldo_capital x tasa_provision vigente segun clasificacion y garantia',
     'Contabilidad'),
    ('RCD',2,'GARANTIA',      'caso02','deudor_clasificacion_mes','tiene_garantia',
     'Booleano convertido a S/N',                                       'Riesgos'),
    ('RCD',2,'FECHA_CORTE',   'caso02','deudor_clasificacion_mes','fecha_corte',
     'Ultimo dia calendario del periodo, formato AAAAMMDD',             'Arquitectura de Datos');

-- 3.1 La version 1 tambien tiene sus validaciones y su linaje.
--
--     Esto no es relleno: 5 de los 8 envios usan la version 1, porque su fecha de corte es
--     anterior a julio. Sin estas filas, cualquier consulta que una un envio con las reglas
--     que se le aplicaron devuelve VACIO para esos cinco envios -- y una regla de calidad que
--     solo mire la version vigente dara OK sin haber revisado nada.
--
--     Versionar una estructura obliga a versionar TODO lo que cuelga de ella.
INSERT INTO reporte_validacion (reporte_cod, version, validacion_cod, descripcion,
                                severidad, expresion_sql, base_legal)
SELECT 'RCD', 1, validacion_cod, descripcion, severidad, expresion_sql, base_legal
FROM   reporte_validacion WHERE reporte_cod = 'RCD' AND version = 2;

INSERT INTO reporte_linaje (reporte_cod, version, campo_cod, esquema_origen, tabla_origen,
                            columna_origen, transformacion, responsable)
SELECT 'RCD', 1, campo_cod, esquema_origen, tabla_origen, columna_origen,
       transformacion, responsable
FROM   reporte_linaje
WHERE  reporte_cod = 'RCD' AND version = 2
  AND  campo_cod <> 'GARANTIA';   -- ese campo no existia en la version 1

-- =====================================================================================
-- 4. GENERACIÓN DE LOS ENVÍOS (periodos 202603 a 202609)
-- =====================================================================================

INSERT INTO reporte_envio (reporte_cod, version, periodo, fecha_corte, fecha_limite,
                           num_envio, tipo_envio, estado, fecha_generacion, fecha_envio)
SELECT  'RCD',
        CASE WHEN p.fecha_corte >= DATE '2026-07-01' THEN 2 ELSE 1 END,
        TO_CHAR(p.fecha_corte, 'YYYYMM'),
        p.fecha_corte,
        p.fecha_corte + 15,
        1,
        'ORIGINAL',
        CASE WHEN p.fecha_corte <= DATE '2026-08-31' THEN 'ACEPTADO' ELSE 'VALIDADO' END,
        (p.fecha_corte + 3)::TIMESTAMP + INTERVAL '22 hour',
        CASE WHEN p.fecha_corte <= DATE '2026-08-31'
             THEN (p.fecha_corte + 5)::TIMESTAMP + INTERVAL '10 hour' END
FROM   (SELECT DISTINCT fecha_corte FROM caso02.deudor_clasificacion_mes) AS p;

-- 4.1 Detalle: se EXTRAE del sistema de créditos
INSERT INTO reporte_detalle (envio_id, num_linea, tipo_doc_cod, num_doc, nombre_deudor,
                             tipo_credito_cod, clasificacion_cod, dias_atraso, moneda_cod,
                             saldo_capital, monto_provision, tiene_garantia, fecha_corte)
SELECT  e.envio_id,
        ROW_NUMBER() OVER (PARTITION BY e.envio_id
                           ORDER BY d.num_doc, dcm.tipo_credito_cod, dcm.moneda_cod)::INTEGER,
        d.tipo_doc_cod,
        d.num_doc,
        d.ape_paterno || ' ' || COALESCE(d.ape_materno, '') || ', ' || d.nombres,
        dcm.tipo_credito_cod,
        dcm.clasificacion_cod,
        dcm.dias_atraso,
        dcm.moneda_cod,          -- viene del origen, ya no va fija a 'PEN'
        dcm.saldo_capital,
        dcm.monto_provision,
        CASE WHEN dcm.tiene_garantia THEN 'S' ELSE 'N' END,
        dcm.fecha_corte
FROM    reporte_envio e
JOIN    caso02.deudor_clasificacion_mes dcm ON dcm.fecha_corte = e.fecha_corte
JOIN    caso02.deudor d ON d.deudor_id = dcm.deudor_id
WHERE   e.num_envio = 1;

-- =====================================================================================
-- 4.2 EL ERROR QUE ORIGINA LA OBSERVACIÓN DE LA SBS
--     El proceso de junio usó una versión desactualizada de los tramos de clasificación
--     y reportó como NORMAL a deudores con atraso alto. Es un error REAL y frecuente:
--     ninguna restricción de la base lo impide, porque estructuralmente es un dato válido.
--     Solo una REGLA DE VALIDACIÓN puede detectarlo.
-- =====================================================================================

UPDATE reporte_detalle d
SET    clasificacion_cod = '0'
FROM   reporte_envio e
WHERE  e.envio_id = d.envio_id
  AND  e.periodo  = '202606'
  AND  e.num_envio = 1
  AND  d.dias_atraso > 30
  AND  d.num_linea % 3 = 0;

-- Y un deudor quedó con saldo cero por un error de corte
UPDATE reporte_detalle d
SET    saldo_capital = 0, monto_provision = 0
FROM   reporte_envio e
WHERE  e.envio_id = d.envio_id
  AND  e.periodo  = '202606'
  AND  e.num_envio = 1
  AND  d.num_linea = 7;

-- 4.3 Totales del envío (derivados del detalle, nunca digitados)
--     Se calculan DESPUES de la corrupcion: el envio observado reporta sus cifras reales,
--     erroneas incluidas. Por eso su cuadre contable no cierra y la SBS lo observa.
UPDATE reporte_envio e
SET    cant_registros = t.n,
       monto_total    = t.saldo,
       hash_archivo   = MD5(e.reporte_cod || e.periodo || t.n::TEXT || t.saldo::TEXT)
FROM  (SELECT envio_id, COUNT(*) AS n, SUM(saldo_capital) AS saldo
       FROM   reporte_detalle GROUP BY envio_id) t
WHERE  t.envio_id = e.envio_id;

-- =====================================================================================
-- 5. EJECUCIÓN DE LAS VALIDACIONES
--    Se aplican las reglas guardadas como datos. Aquí se implementan explícitamente
--    para mantener el script seguro; en producción se usaría SQL dinámico controlado.
-- =====================================================================================

-- V01: formato de documento
INSERT INTO reporte_error (envio_id, validacion_cod, num_linea, campo_cod, severidad, detalle)
SELECT  d.envio_id, 'V01-DOC-FORMATO', d.num_linea, 'NUM_DOC', 'BLOQUEA',
        'Documento con formato invalido: ' || d.num_doc || ' (tipo ' || d.tipo_doc_cod || ')'
FROM    reporte_detalle d
WHERE  (d.tipo_doc_cod = '01' AND d.num_doc !~ '^[0-9]{8}$')
   OR  (d.tipo_doc_cod = '06' AND d.num_doc !~ '^[0-9]{11}$');

-- V04: saldo cero (advertencia)
INSERT INTO reporte_error (envio_id, validacion_cod, num_linea, campo_cod, severidad, detalle)
SELECT  d.envio_id, 'V04-SALDO-CERO', d.num_linea, 'SALDO_CAPITAL', 'ADVIERTE',
        'Deudor reportado con saldo de capital cero'
FROM    reporte_detalle d
WHERE   d.saldo_capital = 0;

-- V05: clasificación Normal con atraso alto (advertencia)
INSERT INTO reporte_error (envio_id, validacion_cod, num_linea, campo_cod, severidad, detalle)
SELECT  d.envio_id, 'V05-ATRASO-CLAS', d.num_linea, 'CLASIFICACION', 'ADVIERTE',
        'Clasificacion Normal con ' || d.dias_atraso || ' dias de atraso'
FROM    reporte_detalle d
WHERE   d.clasificacion_cod = '0' AND d.dias_atraso > 8;

-- =====================================================================================
-- 6. CUADRE CONTABLE
--    El reporte se compara contra el saldo contable. Sin cuadre, no se envía.
-- =====================================================================================

INSERT INTO cuadre_reporte (envio_id, concepto, valor_reporte, valor_contable,
                            diferencia, tolerancia, esta_cuadrado)
SELECT  e.envio_id, 'SALDO_CAPITAL',
        r.saldo_reporte,
        c.saldo_contable,
        r.saldo_reporte - c.saldo_contable,
        1.00,
        ABS(r.saldo_reporte - c.saldo_contable) <= 1.00
FROM        reporte_envio e
JOIN       (SELECT envio_id, SUM(saldo_capital) AS saldo_reporte
            FROM   reporte_detalle GROUP BY envio_id) r ON r.envio_id = e.envio_id
JOIN       (SELECT fecha_corte, SUM(saldo_capital) AS saldo_contable
            FROM   caso02.deudor_clasificacion_mes GROUP BY fecha_corte) c
            ON c.fecha_corte = e.fecha_corte;

INSERT INTO cuadre_reporte (envio_id, concepto, valor_reporte, valor_contable,
                            diferencia, tolerancia, esta_cuadrado)
SELECT  e.envio_id, 'PROVISIONES',
        r.prov_reporte,
        c.prov_contable,
        r.prov_reporte - c.prov_contable,
        1.00,
        ABS(r.prov_reporte - c.prov_contable) <= 1.00
FROM        reporte_envio e
JOIN       (SELECT envio_id, SUM(monto_provision) AS prov_reporte
            FROM   reporte_detalle GROUP BY envio_id) r ON r.envio_id = e.envio_id
JOIN       (SELECT fecha_corte, SUM(monto_provision) AS prov_contable
            FROM   caso02.deudor_clasificacion_mes GROUP BY fecha_corte) c
            ON c.fecha_corte = e.fecha_corte;

-- =====================================================================================
-- 7. UNA RECTIFICACIÓN REAL
--    La SBS observa el envío de junio: dos deudores fueron clasificados con la norma
--    equivocada. Se corrige y se remite un RECTIFICATORIO. El original NO se borra.
-- =====================================================================================

UPDATE reporte_envio
SET    estado = 'OBSERVADO',
       observacion_sbs = 'Se observan registros con clasificacion inconsistente respecto '
                      || 'de los dias de atraso reportados. Remitir rectificatorio.'
WHERE  reporte_cod = 'RCD' AND periodo = '202606' AND num_envio = 1;

INSERT INTO reporte_envio (reporte_cod, version, periodo, fecha_corte, fecha_limite,
                           num_envio, tipo_envio, estado, fecha_generacion, fecha_envio,
                           observacion_sbs)
SELECT  e.reporte_cod, e.version, e.periodo, e.fecha_corte, e.fecha_limite + 10,
        2, 'RECTIFICATORIO', 'ACEPTADO',
        (e.fecha_corte + 25)::TIMESTAMP + INTERVAL '20 hour',
        (e.fecha_corte + 26)::TIMESTAMP + INTERVAL '09 hour',
        'Rectificatorio en atencion a la observacion del envio original'
FROM    reporte_envio e
WHERE   e.reporte_cod = 'RCD' AND e.periodo = '202606' AND e.num_envio = 1;

-- El detalle del rectificatorio: igual al original, con la corrección aplicada
INSERT INTO reporte_detalle (envio_id, num_linea, tipo_doc_cod, num_doc, nombre_deudor,
                             tipo_credito_cod, clasificacion_cod, dias_atraso, moneda_cod,
                             saldo_capital, monto_provision, tiene_garantia, fecha_corte)
-- LA CORRECCIÓN: el rectificatorio NO copia el detalle observado, lo RE-EXTRAE del
-- sistema origen. Copiar el archivo erróneo y parchearlo a mano es el antipatrón que
-- produce un segundo envío tan observable como el primero.
SELECT  r.envio_id, d.num_linea, d.tipo_doc_cod, d.num_doc, d.nombre_deudor,
        d.tipo_credito_cod,
        -- Se reclasifica con la norma vigente a la fecha de corte
        COALESCE(caso02.fn_clasificar(d.tipo_credito_cod, dcm.dias_atraso, dcm.fecha_corte),
                 dcm.clasificacion_cod),
        dcm.dias_atraso, d.moneda_cod,
        dcm.saldo_capital,      -- <- valor correcto del origen, no el corrupto
        dcm.monto_provision,    -- <- idem
        CASE WHEN dcm.tiene_garantia THEN 'S' ELSE 'N' END,
        dcm.fecha_corte
FROM    reporte_detalle d
JOIN    reporte_envio   o ON o.envio_id = d.envio_id
                         AND o.periodo = '202606' AND o.num_envio = 1
JOIN    reporte_envio   r ON r.periodo = '202606' AND r.num_envio = 2
JOIN    caso02.deudor   de  ON de.tipo_doc_cod = d.tipo_doc_cod AND de.num_doc = d.num_doc
-- El JOIN va al GRANO COMPLETO: deudor + fecha + tipo de credito + moneda.
-- Unir solo por deudor y fecha multiplicaba las filas en cuanto un deudor tiene dos
-- creditos, y el rectificatorio salia con lineas duplicadas: peor que el original.
JOIN    caso02.deudor_clasificacion_mes dcm ON dcm.deudor_id        = de.deudor_id
                                           AND dcm.fecha_corte      = d.fecha_corte
                                           AND dcm.tipo_credito_cod = d.tipo_credito_cod
                                           AND dcm.moneda_cod       = d.moneda_cod;

UPDATE reporte_envio e
SET    cant_registros = t.n, monto_total = t.saldo,
       hash_archivo = MD5(e.reporte_cod || e.periodo || '2' || t.n::TEXT || t.saldo::TEXT)
FROM  (SELECT envio_id, COUNT(*) AS n, SUM(saldo_capital) AS saldo
       FROM   reporte_detalle GROUP BY envio_id) t
WHERE  t.envio_id = e.envio_id AND e.num_envio = 2;

INSERT INTO cuadre_reporte (envio_id, concepto, valor_reporte, valor_contable,
                            diferencia, tolerancia, esta_cuadrado)
SELECT  e.envio_id, 'SALDO_CAPITAL', r.saldo, c.saldo_contable,
        r.saldo - c.saldo_contable, 1.00, ABS(r.saldo - c.saldo_contable) <= 1.00
FROM        reporte_envio e
JOIN       (SELECT envio_id, SUM(saldo_capital) AS saldo
            FROM reporte_detalle GROUP BY envio_id) r ON r.envio_id = e.envio_id
JOIN       (SELECT fecha_corte, SUM(saldo_capital) AS saldo_contable
            FROM caso02.deudor_clasificacion_mes GROUP BY fecha_corte) c
            ON c.fecha_corte = e.fecha_corte
WHERE       e.num_envio = 2;

-- =====================================================================================
-- 8. RESUMEN
-- =====================================================================================

SELECT 'definiciones (versiones)' AS entidad, COUNT(*) AS filas FROM reporte_definicion
UNION ALL SELECT 'campos definidos',    COUNT(*) FROM reporte_campo
UNION ALL SELECT 'validaciones',        COUNT(*) FROM reporte_validacion
UNION ALL SELECT 'trazas de linaje',    COUNT(*) FROM reporte_linaje
UNION ALL SELECT 'envios',              COUNT(*) FROM reporte_envio
UNION ALL SELECT '  rectificatorios',   COUNT(*) FROM reporte_envio WHERE tipo_envio = 'RECTIFICATORIO'
UNION ALL SELECT 'lineas de detalle',   COUNT(*) FROM reporte_detalle
UNION ALL SELECT 'errores detectados',  COUNT(*) FROM reporte_error
UNION ALL SELECT 'cuadres',             COUNT(*) FROM cuadre_reporte
ORDER BY 1;
