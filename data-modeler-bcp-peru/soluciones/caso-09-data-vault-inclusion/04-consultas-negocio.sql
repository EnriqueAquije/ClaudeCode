-- =====================================================================================
-- CASO 09 - Consultas de negocio sobre el Data Vault
-- =====================================================================================

SET search_path TO caso09, public;

\echo '== PN-01: tasa de inclusion financiera por departamento =='
SELECT  departamento,
        COUNT(*)                                                       AS personas,
        COUNT(*) FILTER (WHERE cant_productos > 0)                     AS con_algun_producto,
        ROUND(100.0 * COUNT(*) FILTER (WHERE cant_productos > 0) / COUNT(*), 1) AS pct_inclusion,
        ROUND(100.0 * COUNT(*) FILTER (WHERE tiene_ahorro)  / COUNT(*), 1)      AS pct_ahorro,
        ROUND(100.0 * COUNT(*) FILTER (WHERE tiene_credito) / COUNT(*), 1)      AS pct_credito,
        ROUND(100.0 * COUNT(*) FILTER (WHERE tiene_pagos)   / COUNT(*), 1)      AS pct_pagos
FROM    vw_inclusion_financiera
WHERE   departamento IS NOT NULL
GROUP BY departamento
ORDER BY pct_inclusion DESC;

\echo ''
\echo '== PN-02: inclusion por nivel educativo e ingreso =='
SELECT  nivel_educativo,
        COUNT(*)                                 AS personas,
        ROUND(AVG(ingreso_mensual), 2)           AS ingreso_promedio,
        ROUND(AVG(cant_productos), 2)            AS productos_promedio,
        ROUND(100.0 * COUNT(*) FILTER (WHERE cant_productos > 0) / COUNT(*), 1) AS pct_inclusion
FROM    vw_inclusion_financiera
WHERE   nivel_educativo IS NOT NULL
GROUP BY nivel_educativo
ORDER BY ingreso_promedio;

\echo ''
\echo '== PN-03: brecha urbano / rural =='
SELECT  CASE area_cod WHEN 'U' THEN 'Urbano' WHEN 'R' THEN 'Rural' ELSE 'Sin dato' END AS area,
        COUNT(*)                                                                  AS personas,
        ROUND(AVG(ingreso_mensual), 2)                                            AS ingreso_promedio,
        ROUND(100.0 * COUNT(*) FILTER (WHERE tiene_internet) / COUNT(*), 1)       AS pct_con_internet,
        ROUND(100.0 * COUNT(*) FILTER (WHERE cant_productos > 0) / COUNT(*), 1)   AS pct_inclusion,
        ROUND(AVG(cant_productos), 2)                                             AS productos_promedio
FROM    vw_inclusion_financiera
GROUP BY area_cod
ORDER BY area;

\echo ''
\echo '== PN-04: EVOLUCION DEL INGRESO entre las dos olas (la historia del satelite) =='
WITH ingreso_ola AS (
    SELECT  persona_hk,
            MAX(ingreso_mensual) FILTER (WHERE fecha_carga = TIMESTAMP '2025-06-30 02:00') AS ingreso_2025,
            MAX(ingreso_mensual) FILTER (WHERE fecha_carga = TIMESTAMP '2026-06-30 02:00') AS ingreso_2026
    FROM    sat_persona_ingreso
    GROUP BY persona_hk
)
SELECT  COUNT(*)                                                            AS personas_con_dos_olas,
        ROUND(AVG(ingreso_2025), 2)                                         AS promedio_2025,
        ROUND(AVG(ingreso_2026), 2)                                         AS promedio_2026,
        ROUND(AVG(ingreso_2026 - ingreso_2025), 2)                          AS variacion_promedio,
        ROUND(100.0 * AVG((ingreso_2026 - ingreso_2025) / NULLIF(ingreso_2025, 0)), 2) AS pct_variacion
FROM    ingreso_ola
WHERE   ingreso_2025 IS NOT NULL AND ingreso_2026 IS NOT NULL;

\echo ''
\echo '== PN-05: LA PROPIEDAD DEL DATA VAULT - el satelite crece por CAMBIOS, no por cargas =='
SELECT  'hub_persona'            AS tabla, 'HUB'       AS tipo,
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2025') AS ola_2025,
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2026') AS ola_2026,
        COUNT(*)                                              AS total
FROM    hub_persona
UNION ALL
SELECT  'sat_persona_demografia', 'SATELITE',
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2025'),
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2026'), COUNT(*)
FROM    sat_persona_demografia
UNION ALL
SELECT  'sat_persona_ingreso',    'SATELITE',
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2025'),
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2026'), COUNT(*)
FROM    sat_persona_ingreso
UNION ALL
SELECT  'sat_persona_canal_digital', 'SATELITE NUEVO',
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2025'),
        COUNT(*) FILTER (WHERE sistema_origen = 'ENAHO_2026'), COUNT(*)
FROM    sat_persona_canal_digital;

\echo ''
\echo '   ^ El HUB casi no crece: las llaves de negocio ya existian.'
\echo '     El satelite de INGRESO crecio solo con los que cambiaron.'
\echo '     El satelite de CANAL DIGITAL es NUEVO: la fuente agrego preguntas y el modelo'
\echo '     las absorbio SIN modificar una sola tabla existente.'

\echo ''
\echo '== PN-06: motivos de no uso de canales digitales (el satelite de la ola 2026) =='
SELECT  COALESCE(d.motivo_no_uso, 'USA CANALES DIGITALES')   AS situacion,
        COUNT(*)                                             AS personas,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)   AS pct,
        ROUND(AVG(i.ingreso_mensual), 2)                     AS ingreso_promedio
FROM        sat_persona_canal_digital d
LEFT JOIN   sat_persona_ingreso i ON i.persona_hk = d.persona_hk AND i.fecha_fin_carga IS NULL
WHERE       d.fecha_fin_carga IS NULL
GROUP BY    d.motivo_no_uso
ORDER BY    personas DESC;

\echo ''
\echo '== PN-07: VIAJE EN EL TIEMPO - la foto de una persona en una fecha pasada =='
\echo '-- Como se veia esta persona el 2025-12-31 (usando SOLO lo que se sabia entonces):'
WITH persona AS (
    SELECT persona_hk FROM sat_persona_ingreso
    WHERE  fecha_fin_carga IS NOT NULL
    ORDER BY persona_hk LIMIT 1
)
SELECT  'foto al 2025-12-31' AS momento,
        h.num_doc_bk,
        d.edad, d.situacion_laboral, i.ingreso_mensual,
        d.fecha_carga AS version_demografia,
        i.fecha_carga AS version_ingreso
FROM        persona p
JOIN        hub_persona h ON h.persona_hk = p.persona_hk
LEFT JOIN   sat_persona_demografia d ON d.persona_hk = p.persona_hk
        AND TIMESTAMP '2025-12-31' >= d.fecha_carga
        AND (d.fecha_fin_carga IS NULL OR TIMESTAMP '2025-12-31' < d.fecha_fin_carga)
LEFT JOIN   sat_persona_ingreso i ON i.persona_hk = p.persona_hk
        AND TIMESTAMP '2025-12-31' >= i.fecha_carga
        AND (i.fecha_fin_carga IS NULL OR TIMESTAMP '2025-12-31' < i.fecha_fin_carga)
UNION ALL
SELECT  'foto de hoy',
        h.num_doc_bk, d.edad, d.situacion_laboral, i.ingreso_mensual,
        d.fecha_carga, i.fecha_carga
FROM        persona p
JOIN        hub_persona h ON h.persona_hk = p.persona_hk
LEFT JOIN   sat_persona_demografia d ON d.persona_hk = p.persona_hk AND d.fecha_fin_carga IS NULL
LEFT JOIN   sat_persona_ingreso    i ON i.persona_hk = p.persona_hk AND i.fecha_fin_carga IS NULL;

\echo ''
\echo '   ^ El Data Vault permite reconstruir cualquier fecha SIN reprocesar nada:'
\echo '     la historia esta completa porque nunca se borra ni se sobrescribe.'

\echo ''
\echo '== PN-08: tenencia de productos por categoria =='
SELECT  pd.categoria,
        pd.producto_desc,
        COUNT(*) FILTER (WHERE sp.tiene_producto)          AS personas_con_producto,
        ROUND(AVG(sp.antiguedad_meses), 1)                 AS antiguedad_promedio_meses,
        MODE() WITHIN GROUP (ORDER BY sp.frecuencia_uso)   AS frecuencia_mas_comun
FROM    lnk_persona_producto lpp
JOIN    sat_persona_producto sp ON sp.persona_producto_hk = lpp.persona_producto_hk
                               AND sp.fecha_fin_carga IS NULL
JOIN    sat_producto_descripcion pd ON pd.producto_hk = lpp.producto_hk
GROUP BY pd.categoria, pd.producto_desc
ORDER BY pd.categoria, personas_con_producto DESC;

\echo ''
\echo '== PN-09: el COSTO del Data Vault - cuantos JOINs cuesta una pregunta simple =='
SELECT  'Data Vault (normalizado)' AS enfoque,
        'hub_persona + sat_demografia + sat_ingreso + lnk_persona_hogar + sat_hogar '
        '+ lnk_hogar_distrito + sat_distrito + lnk_persona_producto + sat_producto' AS ruta,
        8 AS joins_necesarios
UNION ALL
SELECT  'Modelo estrella (caso 05)',
        'fact + dim_cliente + dim_ubigeo', 2;

\echo ''
\echo '   ^ Por eso el Data Vault NO se consulta directamente: se construyen vistas'
\echo '     (como vw_inclusion_financiera) o data marts dimensionales sobre el.'
\echo '     El Data Vault optimiza la CARGA y la AUDITORIA; la estrella, la CONSULTA.'

\echo ''
\echo '== PN-10: TRAZABILIDAD - que sistema origen aporto cada dato =='
SELECT  'hub_persona'               AS tabla, sistema_origen, COUNT(*) AS filas
FROM    hub_persona GROUP BY sistema_origen
UNION ALL
SELECT  'sat_persona_demografia', sistema_origen, COUNT(*) FROM sat_persona_demografia GROUP BY sistema_origen
UNION ALL
SELECT  'sat_persona_ingreso',    sistema_origen, COUNT(*) FROM sat_persona_ingreso    GROUP BY sistema_origen
UNION ALL
SELECT  'sat_distrito_geografia', sistema_origen, COUNT(*) FROM sat_distrito_geografia GROUP BY sistema_origen
ORDER BY 1, 2;

\echo ''
\echo '   ^ Toda fila del Data Vault sabe de donde vino. No hay excepciones.'
