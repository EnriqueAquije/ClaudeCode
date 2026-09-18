-- =====================================================================================
-- CASO 08 - Reglas de calidad del proceso MDM
-- =====================================================================================

SET search_path TO caso08, public;

\echo '-- CAL-09 (detalle): homonimos que NO deben estar fusionados'
SELECT mc.candidato_id,
       mc.evidencia ->> 'nombre' AS nombre,
       mc.evidencia ->> 'doc_a'  AS doc_a,
       mc.evidencia ->> 'doc_b'  AS doc_b,
       xa.cliente_maestro_id     AS maestro_a,
       xb.cliente_maestro_id     AS maestro_b,
       CASE WHEN xa.cliente_maestro_id = xb.cliente_maestro_id
            THEN 'FUSIONADOS POR ERROR' ELSE 'correctamente separados' END AS situacion
FROM   match_candidato mc
JOIN   cliente_xref xa ON xa.fuente_cod = mc.fuente_a AND xa.id_origen = mc.id_origen_a
JOIN   cliente_xref xb ON xb.fuente_cod = mc.fuente_b AND xb.id_origen = mc.id_origen_b
WHERE  mc.decision = 'REVISION'
  AND  xa.cliente_maestro_id = xb.cliente_maestro_id;

\echo ''
\echo '=============================================================='
\echo '   RESUMEN DE CALIDAD - CASO 08 (MDM)'
\echo '=============================================================='

WITH resultados AS (
    -- CAL-00 es una regla de VOLUMEN, y es distinta de todas las demas.
    -- Las otras cuentan filas que INCUMPLEN: sobre una base vacia dan cero, es decir OK.
    -- Por eso un laboratorio sin datos pasaba el control de calidad entero. Esta regla
    -- comprueba lo contrario: que HAYA datos. Es el incidente mas frecuente en produccion
    -- -- el proceso no cargo nada -- y el unico que una suite de "contar violaciones"
    -- no puede ver nunca.
    SELECT 'CAL-00' AS regla, 'Volumen' AS familia,
           'Hay datos cargados: registros de los sistemas fuente' AS descripcion,
           (SELECT CASE WHEN COUNT(*) = 0 THEN 1 ELSE 0 END FROM cliente_fuente) AS incumple
    UNION ALL
    SELECT 'CAL-01', 'Integridad',
           'Todo registro fuente esta vinculado a un registro maestro',
           (SELECT COUNT(*) FROM cliente_fuente f
            WHERE f.num_doc IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM cliente_xref x
                              WHERE x.fuente_cod = f.fuente_cod AND x.id_origen = f.id_origen)) AS incumple
    UNION ALL
    SELECT 'CAL-02', 'Integridad', 'Todo registro maestro tiene al menos una referencia cruzada',
           (SELECT COUNT(*) FROM cliente_maestro m
            WHERE NOT EXISTS (SELECT 1 FROM cliente_xref x WHERE x.cliente_maestro_id = m.cliente_maestro_id))
    UNION ALL
    SELECT 'CAL-03', 'Cuadre', 'cant_fuentes del maestro = fuentes distintas en su xref',
           (SELECT COUNT(*) FROM cliente_maestro m
            JOIN (SELECT cliente_maestro_id, COUNT(DISTINCT fuente_cod) AS n
                  FROM cliente_xref GROUP BY cliente_maestro_id) x
                 ON x.cliente_maestro_id = m.cliente_maestro_id
            WHERE m.cant_fuentes <> x.n)
    UNION ALL
    SELECT 'CAL-04', 'Unicidad', 'Documento unico entre registros maestros',
           (SELECT COUNT(*) FROM (
                SELECT tipo_doc_cod, num_doc FROM cliente_maestro
                GROUP BY tipo_doc_cod, num_doc HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-05', 'Trazabilidad', 'Todo atributo no nulo del maestro tiene su linaje registrado',
           (SELECT COUNT(*) FROM cliente_maestro m
            WHERE NOT EXISTS (SELECT 1 FROM cliente_maestro_linaje l
                              WHERE l.cliente_maestro_id = m.cliente_maestro_id
                                AND l.atributo = 'nombre_completo'))
    UNION ALL
    SELECT 'CAL-06', 'Trazabilidad', 'El linaje apunta a un registro que pertenece al mismo maestro',
           (SELECT COUNT(*) FROM cliente_maestro_linaje l
            WHERE NOT EXISTS (SELECT 1 FROM cliente_xref x
                              WHERE x.cliente_maestro_id = l.cliente_maestro_id
                                AND x.fuente_cod = l.fuente_cod
                                AND x.id_origen  = l.id_origen))
    UNION ALL
    SELECT 'CAL-07', 'Supervivencia', 'La actividad economica viene de SUNAT cuando esa fuente aporta el dato',
           (SELECT COUNT(*) FROM cliente_maestro_linaje l
            WHERE l.atributo = 'ciiu_cod'
              AND l.fuente_cod <> 'PADRON_SUNAT'
              AND EXISTS (SELECT 1 FROM cliente_xref x
                          JOIN cliente_fuente f ON f.fuente_cod = x.fuente_cod AND f.id_origen = x.id_origen
                          WHERE x.cliente_maestro_id = l.cliente_maestro_id
                            AND x.fuente_cod = 'PADRON_SUNAT'
                            AND f.ciiu_cod IS NOT NULL))
    UNION ALL
    SELECT 'CAL-08', 'Matching', 'Ningun AUTO_MATCH por debajo del umbral de su regla',
           (SELECT COUNT(*) FROM match_candidato mc
            JOIN cat_regla_match rm ON rm.regla_cod = mc.regla_cod
            WHERE mc.decision = 'AUTO_MATCH' AND mc.score < rm.umbral_auto)
    UNION ALL
    SELECT 'CAL-09', 'Matching', 'Los candidatos en REVISION NO fueron fusionados',
           (SELECT COUNT(*) FROM match_candidato mc
            JOIN cliente_xref xa ON xa.fuente_cod = mc.fuente_a AND xa.id_origen = mc.id_origen_a
            JOIN cliente_xref xb ON xb.fuente_cod = mc.fuente_b AND xb.id_origen = mc.id_origen_b
            WHERE mc.decision = 'REVISION'
              AND xa.cliente_maestro_id = xb.cliente_maestro_id)
    UNION ALL
    SELECT 'CAL-10', 'Gobierno', 'Precedencia unica entre fuentes (sin empates)',
           (SELECT COUNT(*) FROM (
                SELECT precedencia FROM cat_fuente GROUP BY precedencia HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-11', 'Dominio', 'Scores de calidad y confianza dentro del rango 0-100',
           (SELECT COUNT(*) FROM calidad_registro WHERE score_calidad NOT BETWEEN 0 AND 100)
         + (SELECT COUNT(*) FROM cliente_maestro  WHERE score_confianza NOT BETWEEN 0 AND 100)
    UNION ALL
    SELECT 'CAL-12', 'Cuadre', 'registros fuente = maestros + duplicados resueltos',
           (SELECT COUNT(*) FROM (SELECT 1 WHERE
                (SELECT COUNT(*) FROM cliente_xref)
             <> (SELECT COUNT(*) FROM cliente_fuente WHERE num_doc IS NOT NULL)) z)
    UNION ALL
    SELECT 'CAL-13', 'Integridad', 'Cada registro de origen pertenece a UN solo maestro',
           (SELECT COUNT(*) FROM (
                SELECT fuente_cod, id_origen FROM cliente_xref
                GROUP BY fuente_cod, id_origen HAVING COUNT(*) > 1) x)
    UNION ALL
    SELECT 'CAL-14', 'Consistencia', 'Todo vinculo PROBABILISTICO tiene score menor a 100',
           (SELECT COUNT(*) FROM cliente_xref
            WHERE tipo_vinculo = 'PROBABILISTICO' AND score_vinculo >= 100)
    UNION ALL
    SELECT 'CAL-15', 'Completitud', 'Ningun maestro sin nombre',
           (SELECT COUNT(*) FROM cliente_maestro
            WHERE nombre_completo IS NULL OR TRIM(nombre_completo) = '')
)
SELECT  regla, familia, descripcion, incumple AS filas_que_incumplen,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;
