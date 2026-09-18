-- =====================================================================================
--  cifras-documentadas.sql — ¿los READMEs dicen la verdad?
-- =====================================================================================
--  Los datos del laboratorio son DETERMINISTAS: ningún generador usa random(). Por lo
--  tanto, cada cifra citada en un README es verificable y debe cumplirse siempre.
--
--  Este script compara lo DOCUMENTADO contra lo que la base realmente contiene.
--  Si alguien modifica un generador y olvida actualizar el README, esto falla.
--
--  Requiere los 10 casos cargados. Se ejecuta al final de validar.sh.
-- =====================================================================================

\echo ''
\echo '=============================================================='
\echo '   CIFRAS DOCUMENTADAS vs. BASE DE DATOS'
\echo '=============================================================='

WITH esperado (regla, familia, descripcion, documentado, real) AS (
    -- ---------------------------------------------------------------- caso 01
    SELECT 'DOC-0101','caso01','clientes = 500',                    500, (SELECT COUNT(*) FROM caso01.cliente)
    UNION ALL
    SELECT 'DOC-0102','caso01','cuentas = 800',                     800, (SELECT COUNT(*) FROM caso01.cuenta)
    UNION ALL
    SELECT 'DOC-0103','caso01','movimientos = 27807',            27807, (SELECT COUNT(*) FROM caso01.movimiento)
    -- ---------------------------------------------------------------- caso 02
    UNION ALL
    SELECT 'DOC-0201','caso02','deudores = 900',                    900, (SELECT COUNT(*) FROM caso02.deudor)
    UNION ALL
    SELECT 'DOC-0202','caso02','solicitudes = 1400',              1400, (SELECT COUNT(*) FROM caso02.solicitud_credito)
    UNION ALL
    SELECT 'DOC-0203','caso02','creditos = 700',                    700, (SELECT COUNT(*) FROM caso02.credito)
    UNION ALL
    SELECT 'DOC-0204','caso02','cuotas = 20400',                  20400, (SELECT COUNT(*) FROM caso02.cronograma_cuota)
    UNION ALL
    SELECT 'DOC-0205','caso02','snapshot mensual (deudor x tipo x moneda) = 2795', 2795, (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes)
    -- ---------------------------------------------------------------- caso 03
    UNION ALL
    SELECT 'DOC-0301','caso03','titulares = 350',                   350, (SELECT COUNT(*) FROM caso03.titular)
    UNION ALL
    SELECT 'DOC-0302','caso03','cuentas tarjeta = 400',             400, (SELECT COUNT(*) FROM caso03.cuenta_tarjeta)
    UNION ALL
    SELECT 'DOC-0303','caso03','plasticos = 500',                   500, (SELECT COUNT(*) FROM caso03.plastico)
    UNION ALL
    SELECT 'DOC-0304','caso03','ciclos = 2400',                    2400, (SELECT COUNT(*) FROM caso03.ciclo_facturacion)
    UNION ALL
    SELECT 'DOC-0305','caso03','transacciones = 23872',           23872, (SELECT COUNT(*) FROM caso03.transaccion)
    UNION ALL
    SELECT 'DOC-0306','caso03','cuotas = 12966',                  12966, (SELECT COUNT(*) FROM caso03.transaccion_cuota)
    UNION ALL
    SELECT 'DOC-0307','caso03','estados de cuenta = 2400',         2400, (SELECT COUNT(*) FROM caso03.estado_cuenta)
    -- ---------------------------------------------------------------- caso 04
    UNION ALL
    SELECT 'DOC-0401','caso04','usuarios = 3001 (3000 + la cuenta puente)', 3001, (SELECT COUNT(*) FROM caso04.usuario_billetera)
    UNION ALL
    SELECT 'DOC-0402','caso04','transferencias = 151500',        151500, (SELECT COUNT(*) FROM caso04.transferencia)
    UNION ALL
    SELECT 'DOC-0403','caso04','confirmadas = 148700',           148700, (SELECT COUNT(*) FROM caso04.transferencia WHERE estado_cod = 'CONFIRMADA')
    UNION ALL
    SELECT 'DOC-0404','caso04','rechazadas = 2800',                2800, (SELECT COUNT(*) FROM caso04.transferencia WHERE estado_cod = 'RECHAZADA')
    UNION ALL
    SELECT 'DOC-0405','caso04','movimientos = 297400',           297400, (SELECT COUNT(*) FROM caso04.movimiento_billetera)
    UNION ALL
    SELECT 'DOC-0406','caso04','particion DEFAULT vacia',             0, (SELECT COUNT(*) FROM caso04.movimiento_billetera_default)
    -- ---------------------------------------------------------------- caso 05
    UNION ALL
    SELECT 'DOC-0501','caso05','dim_tiempo = 1096',                1096, (SELECT COUNT(*) FROM caso05.dim_tiempo)
    UNION ALL
    SELECT 'DOC-0502','caso05','dim_cliente = 1501',               1501, (SELECT COUNT(*) FROM caso05.dim_cliente)
    UNION ALL
    SELECT 'DOC-0503','caso05','filas version 2 del SCD2 = 100',    100, (SELECT COUNT(*) FROM caso05.dim_cliente WHERE version = 2)
    UNION ALL
    SELECT 'DOC-0504','caso05','fact_movimiento = 27807',         27807, (SELECT COUNT(*) FROM caso05.fact_movimiento)
    UNION ALL
    SELECT 'DOC-0505','caso05','fact_saldo_captacion_mes = 3188',  3188, (SELECT COUNT(*) FROM caso05.fact_saldo_captacion_mes)
    UNION ALL
    SELECT 'DOC-0506','caso05','fact_colocacion_mes = 2795',       2795, (SELECT COUNT(*) FROM caso05.fact_colocacion_mes)
    -- ---------------------------------------------------------------- caso 06
    UNION ALL
    SELECT 'DOC-0601','caso06','dias de calendario = 366 (incluye la semilla del 31-dic)', 366, (SELECT COUNT(*) FROM caso06.cat_calendario)
    UNION ALL
    SELECT 'DOC-0602','caso06','dias habiles = 249',                249, (SELECT COUNT(*) FROM caso06.cat_calendario WHERE es_dia_habil)
    UNION ALL
    SELECT 'DOC-0603','caso06','feriados = 15',                      15, (SELECT COUNT(*) FROM caso06.cat_calendario WHERE es_feriado)
    UNION ALL
    SELECT 'DOC-0604','caso06','cotizaciones publicadas = 1245',   1245, (SELECT COUNT(*) FROM caso06.tipo_cambio_publicado)
    UNION ALL
    SELECT 'DOC-0605','caso06','valores vigentes = 1830',          1830, (SELECT COUNT(*) FROM caso06.tipo_cambio_vigente)
    UNION ALL
    SELECT 'DOC-0606','caso06','valores por ARRASTRE = 585',        585, (SELECT COUNT(*) FROM caso06.tipo_cambio_vigente WHERE origen_valor = 'ARRASTRE')
    UNION ALL
    SELECT 'DOC-0607','caso06','saldos ME = 2196',                 2196, (SELECT COUNT(*) FROM caso06.saldo_me_dia)
    UNION ALL
    SELECT 'DOC-0608','caso06','posiciones diarias = 732',          732, (SELECT COUNT(*) FROM caso06.posicion_cambio_dia)
    -- ---------------------------------------------------------------- caso 07
    UNION ALL
    SELECT 'DOC-0701','caso07','clientes monitoreados = 800',       800, (SELECT COUNT(*) FROM caso07.cliente)
    UNION ALL
    SELECT 'DOC-0702','caso07','operaciones = 27666',             27666, (SELECT COUNT(*) FROM caso07.operacion)
    UNION ALL
    SELECT 'DOC-0703','caso07','registro de operaciones = 59',       59, (SELECT COUNT(*) FROM caso07.registro_operacion)
    UNION ALL
    SELECT 'DOC-0704','caso07','alertas totales = 235',             235, (SELECT COUNT(*) FROM caso07.alerta)
    UNION ALL
    SELECT 'DOC-0705','caso07','R01-UMBRAL = 59 alertas',            59, (SELECT COUNT(*) FROM caso07.alerta WHERE regla_cod = 'R01-UMBRAL')
    UNION ALL
    SELECT 'DOC-0706','caso07','R02-FRACC = 21 alertas',             21, (SELECT COUNT(*) FROM caso07.alerta WHERE regla_cod = 'R02-FRACC')
    UNION ALL
    SELECT 'DOC-0707','caso07','R03-PERFIL = 126 alertas',          126, (SELECT COUNT(*) FROM caso07.alerta WHERE regla_cod = 'R03-PERFIL')
    UNION ALL
    SELECT 'DOC-0708','caso07','R04-GEO = 15 alertas',               15, (SELECT COUNT(*) FROM caso07.alerta WHERE regla_cod = 'R04-GEO')
    UNION ALL
    SELECT 'DOC-0709','caso07','R05-PEP = 14 alertas',               14, (SELECT COUNT(*) FROM caso07.alerta WHERE regla_cod = 'R05-PEP')
    -- ---------------------------------------------------------------- caso 08
    UNION ALL
    SELECT 'DOC-0801','caso08','registros en los 6 sistemas = 5407', 5407, (SELECT COUNT(*) FROM caso08.cliente_fuente)
    UNION ALL
    SELECT 'DOC-0802','caso08','clientes maestros = 4619',          4619, (SELECT COUNT(*) FROM caso08.cliente_maestro)
    UNION ALL
    SELECT 'DOC-0803','caso08','duplicados resueltos automaticamente = 925', 925, (SELECT COUNT(*) FROM caso08.match_candidato WHERE decision = 'AUTO_MATCH')
    UNION ALL
    SELECT 'DOC-0804','caso08','candidatos a revision humana = 40',   40, (SELECT COUNT(*) FROM caso08.match_candidato WHERE decision = 'REVISION')
    UNION ALL
    SELECT 'DOC-0805','caso08','referencias cruzadas = 5407',       5407, (SELECT COUNT(*) FROM caso08.cliente_xref)
    UNION ALL
    SELECT 'DOC-0806','caso08','trazas de linaje = 14161',         14161, (SELECT COUNT(*) FROM caso08.cliente_maestro_linaje)
    -- ---------------------------------------------------------------- caso 09
    UNION ALL
    SELECT 'DOC-0901','caso09','hub_persona = 1600',               1600, (SELECT COUNT(*) FROM caso09.hub_persona)
    UNION ALL
    SELECT 'DOC-0902','caso09','hub_hogar = 600',                    600, (SELECT COUNT(*) FROM caso09.hub_hogar)
    UNION ALL
    SELECT 'DOC-0903','caso09','lnk_persona_producto = 6442',       6442, (SELECT COUNT(*) FROM caso09.lnk_persona_producto)
    UNION ALL
    SELECT 'DOC-0904','caso09','sat_persona_demografia = 3000',     3000, (SELECT COUNT(*) FROM caso09.sat_persona_demografia)
    UNION ALL
    -- La cifra que justifica economicamente el hash_diff: 500, no 1500.
    SELECT 'DOC-0905','caso09','sat_persona_ingreso = 2000',        2000, (SELECT COUNT(*) FROM caso09.sat_persona_ingreso)
    UNION ALL
    SELECT 'DOC-0906','caso09','sat_persona_canal_digital = 1600',  1600, (SELECT COUNT(*) FROM caso09.sat_persona_canal_digital)
    -- ---------------------------------------------------------------- caso 10
    UNION ALL
    SELECT 'DOC-1001','caso10','definiciones del reporte = 2',         2, (SELECT COUNT(*) FROM caso10.reporte_definicion)
    UNION ALL
    SELECT 'DOC-1002','caso10','campos (v1 + v2) = 21',               21, (SELECT COUNT(*) FROM caso10.reporte_campo)
    UNION ALL
    SELECT 'DOC-1003','caso10','validaciones (v1 + v2) = 12',         12, (SELECT COUNT(*) FROM caso10.reporte_validacion)
    UNION ALL
    SELECT 'DOC-1004','caso10','linaje (v1 + v2) = 21',               21, (SELECT COUNT(*) FROM caso10.reporte_linaje)
    UNION ALL
    SELECT 'DOC-1005','caso10','envios = 8',                           8, (SELECT COUNT(*) FROM caso10.reporte_envio)
    UNION ALL
    SELECT 'DOC-1006','caso10','detalle del reporte = 3212',        3212, (SELECT COUNT(*) FROM caso10.reporte_detalle)
    UNION ALL
    SELECT 'DOC-1007','caso10','hallazgos de junio = 20',             20, (SELECT COUNT(*) FROM caso10.reporte_error)
    UNION ALL
    SELECT 'DOC-1008','caso10','filas de cuadre = 15',                15, (SELECT COUNT(*) FROM caso10.cuadre_reporte)
    UNION ALL
    SELECT 'DOC-1009','caso10','registros del envio de junio = 417',  417, (SELECT cant_registros FROM caso10.reporte_envio
                                                                            WHERE periodo = '202606' AND num_envio = 1)
    UNION ALL
    -- La identidad contable de la billetera: la cuenta puente debe tener exactamente
    -- menos lo que tienen todos los usuarios juntos.
    SELECT 'DOC-0408','caso04','la cuenta puente cuadra con los saldos de usuario',
           0, (SELECT (COALESCE((SELECT SUM(monto_con_signo) FROM caso04.movimiento_billetera WHERE usuario_id=0),0)
                    + COALESCE((SELECT SUM(saldo) FROM caso04.saldo_billetera),0))::BIGINT)
    UNION ALL
    -- Que el MDM tenga algo que consolidar: clientes presentes en 3 o mas sistemas.
    -- Antes era 0, porque cada sistema usaba su propio rango de documentos.
    SELECT 'DOC-0807','caso08','clientes en 3 o mas sistemas = 193',
           193, (SELECT COUNT(*) FROM caso08.cliente_maestro WHERE cant_fuentes >= 3)
    UNION ALL
    -- Que la red de contactos exista: pares origen-destino con 3+ transferencias.
    -- Antes era 0, porque ningun par se repetia nunca.
    SELECT 'DOC-0407','caso04','pares con 3 o mas transferencias = 14962',
           14962, (SELECT COUNT(*) FROM (SELECT usuario_origen_id, usuario_destino_id
                                         FROM caso04.transferencia WHERE estado_cod='CONFIRMADA'
                                         GROUP BY 1,2 HAVING COUNT(*) >= 3) x)
    UNION ALL
    -- El agujero que encontro la prueba de frontera FRO-09: ningun dia del calendario
    -- puede quedarse sin tipo de cambio vigente, ni siquiera el primero de la serie.
    SELECT 'DOC-0609','caso06','dias del calendario SIN tipo de cambio vigente = 0',
           0, (SELECT COUNT(*) FROM caso06.cat_calendario c
               WHERE NOT EXISTS (SELECT 1 FROM caso06.tipo_cambio_vigente v
                                 WHERE v.fecha = c.fecha AND v.moneda_cod = 'USD'
                                   AND v.tipo_tc_cod = 'CONTABLE_SBS'))
    UNION ALL
    -- EL GRANO. Estas tres cifras son la prueba de que el modelo admite lo que la realidad
    -- entrega: deudores con mas de un tipo de credito vivo. Con el grano anterior la primera
    -- era imposible de representar y las otras dos no existian.
    SELECT 'DOC-0206','caso02','deudores con >1 tipo de credito vivo = 37',
           37, (SELECT COUNT(*) FROM (SELECT deudor_id FROM caso02.credito
                                      WHERE estado_credito = 'VIGENTE'
                                      GROUP BY 1 HAVING COUNT(DISTINCT tipo_credito_cod) > 1) x)
    UNION ALL
    SELECT 'DOC-0207','caso02','filas que EMPEORAN por alineamiento (RN-06) = 172',
           172, (SELECT COUNT(*) FROM caso02.deudor_clasificacion_mes
                 WHERE clasificacion_cod <> clasificacion_propia_cod)
    UNION ALL
    SELECT 'DOC-0208','caso02','deudor-periodo con mas de una linea = 183',
           183, (SELECT COUNT(*) FROM (SELECT deudor_id, periodo
                                       FROM caso02.deudor_clasificacion_mes
                                       GROUP BY 1,2 HAVING COUNT(*) > 1) x)
    UNION ALL
    -- El rectificatorio tiene la MISMA cantidad de registros que el original:
    -- se regenero desde el origen, no se recorto el archivo observado.
    SELECT 'DOC-1010','caso10','registros del rectificatorio = 417',  417, (SELECT cant_registros FROM caso10.reporte_envio
                                                                            WHERE periodo = '202606' AND num_envio = 2)
)
SELECT  regla,
        familia,
        descripcion,
        documentado,
        real          AS en_la_base,
        real - documentado AS diferencia,
        CASE WHEN real = documentado THEN 'OK' ELSE 'FALLA' END AS estado
FROM    esperado
ORDER BY regla;
