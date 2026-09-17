-- =====================================================================================
-- CASO 04 - Carga de datos
-- Datos 100% SINTÉTICOS y DETERMINÍSTICOS. Requisito previo: 03-modelo-fisico.sql
-- Volumen: 3 000 usuarios, 3 000 dispositivos, ~150 000 transferencias,
--          ~290 000 movimientos (partida doble)
-- Tiempo aproximado de carga: 20 a 60 segundos.
-- =====================================================================================

SET search_path TO caso04;

TRUNCATE movimiento_billetera, idempotencia, transferencia, saldo_billetera,
         dispositivo, usuario_billetera, par_limite,
         cat_tipo_operacion, cat_motivo_rechazo, cat_estado_transferencia, cat_moneda
RESTART IDENTITY CASCADE;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

INSERT INTO cat_moneda (moneda_cod, moneda_desc) VALUES ('PEN', 'Sol peruano');

INSERT INTO cat_estado_transferencia (estado_cod, estado_desc, es_final, es_exitoso) VALUES
    ('INICIADA',   'Iniciada por el usuario',        FALSE, FALSE),
    ('CONFIRMADA', 'Confirmada y acreditada',        TRUE,  TRUE),
    ('RECHAZADA',  'Rechazada',                      TRUE,  FALSE),
    ('REVERSADA',  'Reversada tras confirmación',    TRUE,  FALSE);

INSERT INTO cat_motivo_rechazo (motivo_cod, motivo_desc, es_del_usuario) VALUES
    ('SALDO_INSUF',    'Saldo insuficiente',                         TRUE),
    ('LIMITE_MONTO',   'Excede el monto máximo por operación',       TRUE),
    ('LIMITE_DIARIO',  'Excede el límite acumulado diario',          TRUE),
    ('DEST_NO_EXISTE', 'El número de destino no está afiliado',      TRUE),
    ('USR_SUSPENDIDO', 'Usuario suspendido',                         FALSE),
    ('ERROR_TECNICO',  'Error técnico del sistema',                  FALSE);

INSERT INTO cat_tipo_operacion (tipo_op_cod, tipo_op_desc, signo) VALUES
    ('ENVIO',   'Envío de dinero P2P',            -1),
    ('RECEPCION','Recepción de dinero P2P',        1),
    ('CARGA',   'Carga desde cuenta bancaria',     1),
    ('RETIRO',  'Retiro hacia cuenta bancaria',   -1),
    ('PAGO_QR', 'Pago a comercio con QR',         -1),
    ('COBRO_QR','Cobro de comercio con QR',        1);

INSERT INTO par_limite (segmento_cod, monto_max_operacion, monto_max_dia, num_max_dia, fecha_desde, base_legal) VALUES
    ('PERSONA_NATURAL', 500.00,  2000.00, 20, DATE '2024-01-01', 'Política interna + límites PLAFT (referencial)'),
    ('NEGOCIO',        2000.00, 20000.00, 200, DATE '2024-01-01', 'Política interna (referencial)');

-- =====================================================================================
-- 2. USUARIOS Y DISPOSITIVOS (3 000)
-- =====================================================================================

INSERT INTO usuario_billetera (usuario_id, num_celular, tipo_doc_cod, num_doc, nombre_mostrado,
                               es_negocio, cuenta_vinculada, estado_usuario, fecha_alta, ubigeo)
SELECT  n,
        '9' || LPAD((10000000 + n * 7)::TEXT, 8, '0'),
        '01',
        -- MISMA PERSONA, DISTINTO SISTEMA.
        -- 1 de cada 6 usuarios de la billetera comparte documento con un cliente de
        -- captaciones (rango 70xxxxxx del caso 01), porque es la misma persona. Sin ese
        -- solape, cada sistema vive en su propio universo de documentos y el caso 08
        -- (Cliente 360) no puede consolidar nada: es un MDM sin nada que unificar.
        -- Los juegos de datos sinteticos fallan casi siempre por aqui.
        CASE WHEN n % 6 = 0
             THEN LPAD((70000000 + ((n / 6) % 500 + 1) * 13)::TEXT, 8, '0')
             ELSE LPAD((73000000 + n * 11)::TEXT, 8, '0')
        END,
        (ARRAY['MARIA','JOSE','ROSA','CARLOS','ANA','LUIS','CARMEN','JORGE','ELENA','MIGUEL'])[1 + (n % 10)]
            || ' ' ||
        (ARRAY['QUISPE','MAMANI','FLORES','HUAMAN','ROJAS','VASQUEZ','CHAVEZ','SANCHEZ'])[1 + ((n * 3) % 8)],
        (n % 25 = 0),
        CASE WHEN n % 3 <> 0 THEN '191' || LPAD(n::TEXT, 10, '0') END,
        CASE WHEN n % 97 = 0 THEN 'SUSPENDIDO' ELSE 'ACTIVO' END,
        DATE '2021-01-01' + ((n * 13) % 1900),
        (ARRAY['150101','070101','040101','130101','140101','080101','200101','120101'])[1 + (n % 8)]
FROM generate_series(1, 3000) AS n;

INSERT INTO dispositivo (dispositivo_id, usuario_id, id_dispositivo, sistema_operativo,
                         version_app, fecha_registro, esta_activo)
SELECT  n, n,
        'DEV-' || LPAD(MD5(n::TEXT), 32, '0'),
        (ARRAY['ANDROID','ANDROID','ANDROID','IOS'])[1 + (n % 4)],
        (ARRAY['4.12.0','4.11.3','4.10.8','4.9.2'])[1 + (n % 4)],
        (DATE '2021-01-01' + ((n * 13) % 1900))::TIMESTAMP + INTERVAL '9 hour',
        TRUE
FROM generate_series(1, 3000) AS n;

-- =====================================================================================
-- 3. CARGAS INICIALES (cada usuario carga saldo desde su cuenta bancaria)
--    Garantiza que ninguna billetera pueda quedar en negativo durante la simulación.
-- =====================================================================================

INSERT INTO transferencia (fecha_operacion, usuario_origen_id, usuario_destino_id, celular_destino,
                           tipo_op_cod, moneda_cod, monto, estado_cod, dispositivo_id,
                           clave_idempotencia, mensaje)
SELECT  TIMESTAMP '2026-07-01 07:00:00' + (u.usuario_id % 60) * INTERVAL '1 minute',
        u.usuario_id,
        NULL,
        u.num_celular,
        'CARGA',
        'PEN',
        ROUND((4000 + ((u.usuario_id * 173) % 8000))::NUMERIC, 2),
        'CONFIRMADA',
        u.usuario_id,
        'CARGA-INI-' || u.usuario_id,
        'Carga inicial'
FROM    usuario_billetera u;

-- =====================================================================================
-- 4. TRANSFERENCIAS P2P (julio a setiembre de 2026)
--    Cada usuario envía entre 30 y 69 transferencias de como máximo S/ 50.
--    Tope de gasto: 69 x 50 = 3 450 < 4 000 de carga inicial => saldo siempre positivo.
-- =====================================================================================

INSERT INTO transferencia (fecha_operacion, usuario_origen_id, usuario_destino_id, celular_destino,
                           tipo_op_cod, moneda_cod, monto, estado_cod, motivo_cod,
                           dispositivo_id, clave_idempotencia, mensaje)
SELECT  d.fecha_operacion,
        u.usuario_id,
        d.usuario_destino_id,
        dst.num_celular,
        d.tipo_op_cod,
        'PEN',
        d.monto,
        d.estado_cod,
        d.motivo_cod,
        u.usuario_id,
        'OP-' || u.usuario_id || '-' || g.k,
        (ARRAY['Gracias','Almuerzo','Pasaje','Compartido','Delivery',NULL,NULL])[1 + ((u.usuario_id + g.k) % 7)]
FROM        usuario_billetera u
CROSS JOIN LATERAL generate_series(1, 30 + (u.usuario_id % 40)) AS g(k)
CROSS JOIN LATERAL (
    SELECT
        TIMESTAMP '2026-07-01 00:00:00'
            -- Las transferencias de MONTO ALTO (ver mas abajo) se concentran en un mismo dia
            -- por usuario. Es lo que hace la gente: paga el alquiler, la cuota del colegio y
            -- le manda a un familiar, todo el dia que cobra. Y es lo que hace que el control
            -- de limite diario (PN-07) tenga algo que detectar: repartidas a lo largo de tres
            -- meses, ninguna suma diaria se acerca al limite y la pregunta no tiene respuesta.
            + CASE WHEN u.usuario_id % 10 = 0 AND (u.usuario_id * 11 + g.k) % 6 = 0
                   THEN ((u.usuario_id * 3) % 92)
                   ELSE ((u.usuario_id * 3 + g.k * 7) % 92) END * INTERVAL '1 day'
            + (6 + ((u.usuario_id + g.k * 5) % 16)) * INTERVAL '1 hour'
            + ((u.usuario_id * g.k) % 60) * INTERVAL '1 minute'                       AS fecha_operacion,
        -- EL CIRCULO DE CONTACTOS. Una persona no transfiere a 40 destinatarios distintos:
        -- le transfiere muchas veces a los mismos cinco -- pareja, madre, dos amigos, la
        -- bodega de la esquina -- y de vez en cuando a alguien nuevo.
        -- Si el destino se deriva de `k` a secas, NINGUN par origen-destino se repite jamas
        -- y la pregunta de negocio "red de contactos" (PN-06) no tiene respuesta posible.
        -- Un juego de datos sintetico tiene que reproducir la ESTRUCTURA del fenomeno,
        -- no solo su volumen.
        CASE WHEN g.k % 10 < 7
             THEN 1 + ((u.usuario_id * 37 + (g.k % 5) * 101) % 3000)   -- 70 %: su circulo
             ELSE 1 + ((u.usuario_id * 37 + g.k * 101) % 3000)         -- 30 %: esporadico
        END                                                                           AS usuario_destino_tmp,
        CASE WHEN (u.usuario_id + g.k) % 23 = 0 THEN 'PAGO_QR' ELSE 'ENVIO' END       AS tipo_op_cod,
        -- La mayoria de operaciones son pequenas (5 a 50 soles), el perfil real de una
        -- billetera movil. Pero 1 de cada 10 usuarios tiene un DIA DE PAGOS: concentra varias
        -- operaciones de monto alto -- alquiler, matricula, un pago entre conocidos -- en la
        -- misma jornada, tipicamente la que cobra.
        --
        -- IMPORTANTE: el monto alto se queda por DEBAJO del limite POR OPERACION (500 para
        -- persona natural). Cada transferencia es individualmente legal; lo que se excede es
        -- la SUMA del dia. Ese es el escenario que de verdad importa y el que un control
        -- operacion-a-operacion no ve: hay que acumular por usuario y por dia para detectarlo.
        -- Es tambien, en pequeno, el mismo razonamiento del fraccionamiento del caso 07.
        CASE WHEN u.usuario_id % 10 = 0 AND (u.usuario_id * 11 + g.k) % 6 = 0
             THEN ROUND((300 + ((u.usuario_id * 17 + g.k * 43) % 180))::NUMERIC, 2)
             ELSE ROUND((5 + ((u.usuario_id * 13 + g.k * 29) % 46))::NUMERIC, 2)
        END                                                                           AS monto,
        CASE
            WHEN (u.usuario_id * 7 + g.k) % 53 = 0 THEN 'RECHAZADA'
            ELSE 'CONFIRMADA'
        END                                                                            AS estado_cod,
        CASE WHEN (u.usuario_id * 7 + g.k) % 53 = 0
             -- DEST_NO_EXISTE se excluye a proposito: ese rechazo no tiene destino afiliado
             THEN (ARRAY['SALDO_INSUF','LIMITE_MONTO','LIMITE_DIARIO',
                         'USR_SUSPENDIDO','ERROR_TECNICO','SALDO_INSUF'])[1 + ((u.usuario_id + g.k) % 6)]
        END                                                                            AS motivo_cod
) AS pre
CROSS JOIN LATERAL (
    -- Evita la autotransferencia: si el destino calculado es el propio usuario, se corre uno.
    SELECT pre.fecha_operacion, pre.tipo_op_cod, pre.monto, pre.estado_cod, pre.motivo_cod,
           CASE WHEN pre.usuario_destino_tmp = u.usuario_id
                THEN 1 + (pre.usuario_destino_tmp % 3000)
                ELSE pre.usuario_destino_tmp END AS usuario_destino_id
) AS d
JOIN usuario_billetera dst ON dst.usuario_id = d.usuario_destino_id;

-- =====================================================================================
-- 5. REGISTRO DE IDEMPOTENCIA
--    Una fila por transferencia aceptada. La PK impide que un reintento de la app
--    genere una segunda transferencia con la misma clave.
-- =====================================================================================

INSERT INTO idempotencia (clave_idempotencia, usuario_id, transferencia_id, fecha_operacion,
                          fecha_hora_registro)
SELECT  t.clave_idempotencia, t.usuario_origen_id, t.transferencia_id, t.fecha_operacion,
        t.fecha_operacion
FROM    transferencia t;

-- =====================================================================================
-- 6. LIBRO MAYOR (partida doble)
--    Solo las transferencias CONFIRMADAS mueven dinero.
--      - CARGA:  un único movimiento de abono al usuario.
--      - ENVIO / PAGO_QR: dos movimientos (cargo al origen, abono al destino).
-- =====================================================================================

INSERT INTO movimiento_billetera (fecha_operacion, usuario_id, transferencia_id,
                                  tipo_op_cod, moneda_cod, monto, monto_con_signo)
SELECT  t.fecha_operacion, t.usuario_origen_id, t.transferencia_id,
        'CARGA', t.moneda_cod, t.monto, t.monto
FROM    transferencia t
WHERE   t.tipo_op_cod = 'CARGA' AND t.estado_cod = 'CONFIRMADA';

INSERT INTO movimiento_billetera (fecha_operacion, usuario_id, transferencia_id,
                                  tipo_op_cod, moneda_cod, monto, monto_con_signo)
SELECT  t.fecha_operacion, t.usuario_origen_id, t.transferencia_id,
        t.tipo_op_cod, t.moneda_cod, t.monto, -t.monto
FROM    transferencia t
WHERE   t.tipo_op_cod IN ('ENVIO','PAGO_QR') AND t.estado_cod = 'CONFIRMADA';

INSERT INTO movimiento_billetera (fecha_operacion, usuario_id, transferencia_id,
                                  tipo_op_cod, moneda_cod, monto, monto_con_signo)
SELECT  t.fecha_operacion, t.usuario_destino_id, t.transferencia_id,
        CASE WHEN t.tipo_op_cod = 'PAGO_QR' THEN 'COBRO_QR' ELSE 'RECEPCION' END,
        t.moneda_cod, t.monto, t.monto
FROM    transferencia t
WHERE   t.tipo_op_cod IN ('ENVIO','PAGO_QR')
  AND   t.estado_cod = 'CONFIRMADA'
  AND   t.usuario_destino_id IS NOT NULL;

-- =====================================================================================
-- 7. SALDOS (derivados del libro mayor, nunca inventados)
-- =====================================================================================

INSERT INTO saldo_billetera (usuario_id, moneda_cod, saldo)
SELECT  m.usuario_id, m.moneda_cod, SUM(m.monto_con_signo)
FROM    movimiento_billetera m
GROUP BY m.usuario_id, m.moneda_cod;

-- =====================================================================================
-- 8. ESTADÍSTICAS Y RESUMEN
-- =====================================================================================

ANALYZE transferencia;
ANALYZE movimiento_billetera;

SELECT setval(pg_get_serial_sequence('caso04.usuario_billetera', 'usuario_id'),    (SELECT MAX(usuario_id)    FROM usuario_billetera));
SELECT setval(pg_get_serial_sequence('caso04.dispositivo',       'dispositivo_id'),(SELECT MAX(dispositivo_id) FROM dispositivo));

SELECT 'usuarios' AS entidad, COUNT(*) AS filas FROM usuario_billetera
UNION ALL SELECT 'dispositivos',     COUNT(*) FROM dispositivo
UNION ALL SELECT 'transferencias',   COUNT(*) FROM transferencia
UNION ALL SELECT '  confirmadas',    COUNT(*) FROM transferencia WHERE estado_cod = 'CONFIRMADA'
UNION ALL SELECT '  rechazadas',     COUNT(*) FROM transferencia WHERE estado_cod = 'RECHAZADA'
UNION ALL SELECT 'movimientos',      COUNT(*) FROM movimiento_billetera
UNION ALL SELECT 'claves idempot.',  COUNT(*) FROM idempotencia
ORDER BY 1;

\echo ''
\echo '-- Distribucion por particion (la particion DEFAULT debe estar vacia) --'
SELECT 'transferencia_2026_07' AS particion, COUNT(*) AS filas FROM transferencia_2026_07
UNION ALL SELECT 'transferencia_2026_08', COUNT(*) FROM transferencia_2026_08
UNION ALL SELECT 'transferencia_2026_09', COUNT(*) FROM transferencia_2026_09
UNION ALL SELECT 'transferencia_default', COUNT(*) FROM transferencia_default
ORDER BY 1;
