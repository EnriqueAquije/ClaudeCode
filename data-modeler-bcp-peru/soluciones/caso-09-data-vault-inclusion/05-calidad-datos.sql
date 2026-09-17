-- =====================================================================================
-- CASO 09 - Reglas de calidad del Data Vault
-- =====================================================================================

SET search_path TO caso09, public;

\echo '-- CAL-01 (detalle): hash de hub que no corresponde a su llave de negocio'
SELECT persona_hk, tipo_doc_bk, num_doc_bk, fn_hash_key(tipo_doc_bk, num_doc_bk) AS hash_esperado
FROM   hub_persona
WHERE  persona_hk <> fn_hash_key(tipo_doc_bk, num_doc_bk)
LIMIT 10;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 09 (DATA VAULT)'
\echo '=============================================================='

WITH resultados AS (
    SELECT 'CAL-01' AS regla, 'Integridad del hash' AS familia,
           'El hash de cada hub corresponde a su llave de negocio' AS descripcion,
           (SELECT COUNT(*) FROM hub_persona  WHERE persona_hk  <> fn_hash_key(tipo_doc_bk, num_doc_bk))
         + (SELECT COUNT(*) FROM hub_distrito WHERE distrito_hk <> fn_hash_key(ubigeo_bk))
         + (SELECT COUNT(*) FROM hub_producto WHERE producto_hk <> fn_hash_key(producto_bk))
         + (SELECT COUNT(*) FROM hub_hogar
            WHERE hogar_hk <> fn_hash_key(conglomerado_bk, vivienda_bk, hogar_bk, anio_bk)) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Integridad del hash', 'El hash de cada link corresponde a sus hubs',
           (SELECT COUNT(*) FROM lnk_persona_hogar
            WHERE persona_hogar_hk <> fn_hash_key(persona_hk, hogar_hk))
         + (SELECT COUNT(*) FROM lnk_hogar_distrito
            WHERE hogar_distrito_hk <> fn_hash_key(hogar_hk, distrito_hk))
         + (SELECT COUNT(*) FROM lnk_persona_producto
            WHERE persona_producto_hk <> fn_hash_key(persona_hk, producto_hk))
    UNION ALL
    SELECT 'CAL-03', 'Unicidad', 'Llave de negocio unica en cada hub',
           (SELECT COUNT(*) FROM (SELECT tipo_doc_bk, num_doc_bk FROM hub_persona
                                  GROUP BY 1,2 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-04', 'Satelites', 'Una sola version vigente por satelite y llave',
           (SELECT COUNT(*) FROM (SELECT persona_hk FROM sat_persona_demografia
                                  WHERE fecha_fin_carga IS NULL GROUP BY 1 HAVING COUNT(*) > 1) x)
         + (SELECT COUNT(*) FROM (SELECT persona_hk FROM sat_persona_ingreso
                                  WHERE fecha_fin_carga IS NULL GROUP BY 1 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-05', 'Satelites', 'Vigencias sin solapamiento en los satelites',
           (SELECT COUNT(*) FROM sat_persona_ingreso a
            JOIN sat_persona_ingreso b ON b.persona_hk = a.persona_hk
                                      AND b.fecha_carga > a.fecha_carga
                                      AND (a.fecha_fin_carga IS NULL OR b.fecha_carga < a.fecha_fin_carga))
    UNION ALL
    SELECT 'CAL-06', 'Trazabilidad', 'Toda fila declara su sistema origen',
           (SELECT COUNT(*) FROM hub_persona WHERE sistema_origen IS NULL OR sistema_origen = '')
         + (SELECT COUNT(*) FROM sat_persona_ingreso WHERE sistema_origen IS NULL OR sistema_origen = '')
         + (SELECT COUNT(*) FROM lnk_persona_producto WHERE sistema_origen IS NULL OR sistema_origen = '')
    UNION ALL
    SELECT 'CAL-07', 'Metodologia', 'Ningun HUB contiene atributos descriptivos',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'caso09' AND table_name LIKE 'hub_%'
              AND column_name NOT LIKE '%_hk'
              AND column_name NOT LIKE '%_bk'
              AND column_name NOT IN ('fecha_carga','sistema_origen'))
    UNION ALL
    SELECT 'CAL-08', 'Metodologia', 'Ningun LINK contiene atributos descriptivos',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'caso09' AND table_name LIKE 'lnk_%'
              AND column_name NOT LIKE '%_hk'
              AND column_name NOT IN ('fecha_carga','sistema_origen'))
    UNION ALL
    SELECT 'CAL-09', 'Eficiencia', 'No hay versiones consecutivas con el mismo hash_diff',
           (SELECT COUNT(*) FROM (
                SELECT persona_hk, hash_diff,
                       LAG(hash_diff) OVER (PARTITION BY persona_hk ORDER BY fecha_carga) AS ant
                FROM   sat_persona_ingreso) t
            WHERE ant IS NOT NULL AND ant = hash_diff)
    UNION ALL
    SELECT 'CAL-10', 'Integridad referencial', 'Todo satelite cuelga de un hub o link existente',
           (SELECT COUNT(*) FROM sat_persona_ingreso s
            WHERE NOT EXISTS (SELECT 1 FROM hub_persona h WHERE h.persona_hk = s.persona_hk))
         + (SELECT COUNT(*) FROM sat_persona_producto s
            WHERE NOT EXISTS (SELECT 1 FROM lnk_persona_producto l
                              WHERE l.persona_producto_hk = s.persona_producto_hk))
    UNION ALL
    SELECT 'CAL-11', 'Completitud', 'Todo hub_persona tiene al menos un satelite demografico',
           (SELECT COUNT(*) FROM hub_persona h
            WHERE NOT EXISTS (SELECT 1 FROM sat_persona_demografia s WHERE s.persona_hk = h.persona_hk)
              AND h.sistema_origen = 'ENAHO_2025')
    UNION ALL
    SELECT 'CAL-12', 'Consistencia', 'fecha_fin_carga siempre posterior a fecha_carga',
           (SELECT COUNT(*) FROM sat_persona_ingreso
            WHERE fecha_fin_carga IS NOT NULL AND fecha_fin_carga <= fecha_carga)
         + (SELECT COUNT(*) FROM sat_persona_demografia
            WHERE fecha_fin_carga IS NOT NULL AND fecha_fin_carga <= fecha_carga)
    UNION ALL
    SELECT 'CAL-13', 'Unicidad', 'Los links no duplican la combinacion de hubs',
           (SELECT COUNT(*) FROM (SELECT persona_hk, producto_hk FROM lnk_persona_producto
                                  GROUP BY 1,2 HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-14', 'Dominio', 'Atributos demograficos dentro de dominio',
           (SELECT COUNT(*) FROM sat_persona_demografia
            WHERE (sexo IS NOT NULL AND sexo NOT IN ('M','F'))
               OR (edad IS NOT NULL AND edad NOT BETWEEN 0 AND 120))
    UNION ALL
    SELECT 'CAL-15', 'Auditoria', 'Toda fila tiene fecha de carga',
           (SELECT COUNT(*) FROM sat_persona_ingreso    WHERE fecha_carga IS NULL)
         + (SELECT COUNT(*) FROM sat_persona_demografia WHERE fecha_carga IS NULL)
         + (SELECT COUNT(*) FROM hub_persona            WHERE fecha_carga IS NULL)
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
