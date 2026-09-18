-- =====================================================================================
--  fronteras.sql — el punto exacto donde una regla cambia de significado
-- =====================================================================================
--  Los enunciados están llenos de reglas con `>` y `>=`. La diferencia entre las dos es
--  invisible en los datos normales y decisiva en el borde: un depósito de EXACTAMENTE
--  40 000 soles, ¿entra al Registro de Operaciones o no? Una vigencia que empieza y
--  termina el mismo día, ¿cubre ese día? El último día del mes, ¿a qué partición va?
--
--  Estas preguntas no se responden leyendo el código: se responden probándolo. Y son
--  justo las que aparecen en producción el día que alguien opera por el importe redondo.
--
--  Todo corre en transacciones que se revierten: NO ensucia la base.
-- =====================================================================================

\echo ''
\echo '=============================================================='
\echo '   PRUEBAS DE FRONTERA'
\echo '=============================================================='

WITH resultados AS (
    -- ------------------------------------------------- caso 02: tramos de clasificación
    -- Los tramos son [desde, hasta] cerrados. El dia 8 es el ultimo Normal y el 9 el
    -- primer CPP. Un tramo mal cerrado deja un dia sin clasificacion o con dos.
    SELECT 'FRO-01' AS regla, 'caso02' AS caso,
           'Dia 8 de atraso todavia es Normal' AS descripcion,
           (SELECT CASE WHEN caso02.fn_clasificar('6', 8, DATE '2026-09-30') = '0'
                        THEN 0 ELSE 1 END) AS incumple
    UNION ALL
    SELECT 'FRO-02', 'caso02', 'Dia 9 de atraso ya es CPP',
           (SELECT CASE WHEN caso02.fn_clasificar('6', 9, DATE '2026-09-30') = '1'
                        THEN 0 ELSE 1 END)
    UNION ALL
    SELECT 'FRO-03', 'caso02', 'Dia 0 de atraso esta clasificado (no devuelve NULL)',
           (SELECT CASE WHEN caso02.fn_clasificar('6', 0, DATE '2026-09-30') IS NOT NULL
                        THEN 0 ELSE 1 END)
    UNION ALL
    -- El agujero clasico: los tramos deben cubrir TODOS los dias sin huecos ni solapes.
    SELECT 'FRO-04', 'caso02', 'Los tramos cubren todos los dias de 0 a 400 sin hueco',
           (SELECT COUNT(*) FROM generate_series(0, 400) AS g(d)
            WHERE caso02.fn_clasificar('6', g.d, DATE '2026-09-30') IS NULL)
    UNION ALL
    -- ------------------------------------------------------- caso 04: limite y particion
    -- El limite por operacion es 500 para persona natural. La pregunta es si 500 exacto
    -- pasa o no. El CHECK dice `monto <= monto_max_operacion`, asi que 500 PASA y 500.01 no.
    SELECT 'FRO-05', 'caso04', 'Ninguna operacion confirmada supera el limite por operacion',
           (SELECT COUNT(*) FROM caso04.transferencia t
            JOIN caso04.usuario_billetera u ON u.usuario_id = t.usuario_origen_id
            JOIN caso04.par_limite pl
              ON pl.segmento_cod = CASE WHEN u.es_negocio THEN 'NEGOCIO' ELSE 'PERSONA_NATURAL' END
             AND t.fecha_operacion::DATE BETWEEN pl.fecha_desde AND pl.fecha_hasta
            -- Solo P2P: las CARGAS vienen de una cuenta bancaria y no estan sujetas al
            -- limite por operacion de la billetera. Incluirlas era un error de la regla.
            WHERE t.estado_cod = 'CONFIRMADA'
              AND t.tipo_op_cod IN ('ENVIO','PAGO_QR')
              AND t.monto > pl.monto_max_operacion)
    UNION ALL
    -- El ultimo instante de un mes y el primero del siguiente deben caer en particiones
    -- distintas. Es el borde donde un `<=` mal puesto duplica o pierde una fila.
    SELECT 'FRO-06', 'caso04', 'El ultimo dia de julio esta en la particion de julio',
           (SELECT COUNT(*) FROM caso04.transferencia_2026_08
            WHERE fecha_operacion < TIMESTAMP '2026-08-01 00:00:00')
    UNION ALL
    SELECT 'FRO-07', 'caso04', 'Ninguna fila cayo en la particion DEFAULT',
           (SELECT COUNT(*) FROM caso04.transferencia_default)
    UNION ALL
    -- ------------------------------------------------------ caso 06: vigencias de un dia
    -- Un parametro cuya vigencia empieza y termina el mismo dia DEBE cubrir ese dia.
    -- Con intervalo semiabierto [desde, hasta) no lo cubriria: es el error que convierte
    -- un cambio normativo de un solo dia en un dia sin parametro.
    SELECT 'FRO-08', 'caso06', 'Todo dia del calendario tiene tipo de cambio vigente',
           (SELECT COUNT(*) FROM caso06.cat_calendario c
            WHERE NOT EXISTS (SELECT 1 FROM caso06.tipo_cambio_vigente v
                              WHERE v.fecha = c.fecha AND v.moneda_cod = 'USD'
                                AND v.tipo_tc_cod = 'CONTABLE_SBS'))
    UNION ALL
    -- ESTA REGLA ENCONTRO UN DEFECTO REAL. El 1 de enero es feriado, la serie publicada
    -- empezaba el 2, y el arrastre no tenia nada de donde tirar hacia atras: el primer dia
    -- del año se quedaba sin tipo de cambio y cualquier valorizacion devolvia NULL. Se
    -- corrigio sembrando el calendario con el 31 de diciembre anterior. Ninguna de las 15
    -- reglas de calidad del caso lo veia: solo una prueba que mira EL BORDE.
    SELECT 'FRO-09', 'caso06', 'El 1 de enero (feriado, sin publicacion) tiene valor por arrastre',
           (SELECT CASE WHEN EXISTS (SELECT 1 FROM caso06.tipo_cambio_vigente
                                     WHERE fecha = DATE '2026-01-01' AND moneda_cod = 'USD')
                        THEN 0 ELSE 1 END)
    UNION ALL
    SELECT 'FRO-10', 'caso06', 'El 28 de febrero existe en el calendario',
           (SELECT CASE WHEN EXISTS (SELECT 1 FROM caso06.cat_calendario
                                     WHERE fecha = DATE '2026-02-28')
                        THEN 0 ELSE 1 END)
    UNION ALL
    -- ------------------------------------------------------- caso 07: umbral del RO
    -- El umbral es 40 000. El Registro de Operaciones se alimenta de las que lo SUPERAN.
    -- Una operacion de exactamente 40 000, ¿entra? El CHECK dice `monto >= monto_umbral`,
    -- asi que si. Esta regla comprueba que ninguna por debajo se haya colado.
    SELECT 'FRO-11', 'caso07', 'Ninguna operacion por DEBAJO del umbral entro al Registro',
           (SELECT COUNT(*) FROM caso07.registro_operacion
            WHERE monto_operacion < monto_umbral)
    UNION ALL
    -- Y la contraparte: el fraccionamiento exige que NINGUNA operacion de la ventana
    -- supere el umbral por si sola. Una que lo iguale exactamente ya no es fraccionamiento.
    SELECT 'FRO-12', 'caso07', 'Ninguna alerta de fraccionamiento incluye una operacion sobre el umbral',
           (SELECT COUNT(*) FROM caso07.alerta a
            WHERE a.regla_cod = 'R02-FRACC'
              AND (a.detalle->>'operacion_mayor')::NUMERIC
                  >= (a.detalle->>'umbral_individual')::NUMERIC)
    UNION ALL
    -- ------------------------------------------------------ caso 10: vigencia de version
    -- La version 1 vence el 30 de junio y la 2 empieza el 1 de julio. El envio con corte
    -- 30 de junio debe usar la 1, y el de 31 de julio la 2. Un `BETWEEN` mal puesto aqui
    -- hace irreproducible un envio.
    SELECT 'FRO-13', 'caso10', 'El envio con corte 30-jun usa la version 1',
           (SELECT COUNT(*) FROM caso10.reporte_envio
            WHERE fecha_corte = DATE '2026-06-30' AND version <> 1)
    UNION ALL
    SELECT 'FRO-14', 'caso10', 'El envio con corte 31-jul usa la version 2',
           (SELECT COUNT(*) FROM caso10.reporte_envio
            WHERE fecha_corte = DATE '2026-07-31' AND version <> 2)
    UNION ALL
    SELECT 'FRO-15', 'caso10', 'Ningun dia queda cubierto por dos versiones a la vez',
           (SELECT COUNT(*) FROM caso10.reporte_definicion a
            JOIN caso10.reporte_definicion b
              ON b.reporte_cod = a.reporte_cod AND b.version > a.version
             AND b.fecha_desde <= a.fecha_hasta AND a.fecha_desde <= b.fecha_hasta)
    UNION ALL
    -- ------------------------------------------------------------ caso 01: importes cero
    SELECT 'FRO-16', 'caso01', 'Ningun movimiento tiene importe cero (el limite es > 0, no >= 0)',
           (SELECT COUNT(*) FROM caso01.movimiento WHERE monto = 0)
)
SELECT  regla, caso, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
