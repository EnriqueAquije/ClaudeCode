-- =====================================================================================
-- CASO 08 - Consultas de negocio
-- =====================================================================================

SET search_path TO caso08, public;

\echo '== PN-01: LA CIFRA QUE CAMBIA LA CONVERSACION =='
SELECT  (SELECT COUNT(*) FROM cliente_fuente)                          AS registros_en_sistemas,
        (SELECT COUNT(*) FROM cliente_maestro)                         AS clientes_reales,
        (SELECT COUNT(*) FROM cliente_fuente)
      - (SELECT COUNT(*) FROM cliente_maestro)                         AS duplicados_resueltos,
        ROUND(100.0 * ((SELECT COUNT(*) FROM cliente_fuente)
                     - (SELECT COUNT(*) FROM cliente_maestro))
              / (SELECT COUNT(*) FROM cliente_fuente), 2)              AS pct_duplicacion;

\echo ''
\echo '   ^ El banco creia tener tantos clientes como registros. Tiene menos.'
\echo '     Toda metrica por cliente (rentabilidad, penetracion, riesgo) estaba mal calculada.'

\echo ''
\echo '== PN-02: duplicados detectados por regla =='
SELECT  mc.regla_cod,
        rm.regla_nombre,
        rm.tipo_match,
        mc.decision,
        COUNT(*)                     AS pares,
        ROUND(MIN(mc.score), 2)      AS score_min,
        ROUND(AVG(mc.score), 2)      AS score_promedio,
        rm.umbral_auto
FROM    match_candidato mc
JOIN    regla_match     rm ON rm.regla_cod = mc.regla_cod
GROUP BY mc.regla_cod, rm.regla_nombre, rm.tipo_match, mc.decision, rm.umbral_auto
ORDER BY mc.regla_cod;

\echo ''
\echo '== PN-03: HOMONIMOS a revision manual (lo que NO se debe fusionar) =='
SELECT  mc.candidato_id,
        mc.evidencia ->> 'nombre'             AS nombre,
        (mc.evidencia ->> 'fecha_nac')::DATE  AS fecha_nacimiento,
        mc.evidencia ->> 'doc_a'              AS documento_a,
        mc.evidencia ->> 'doc_b'              AS documento_b,
        (mc.evidencia ->> 'distancia_edicion')::INT AS distancia,
        mc.score,
        mc.decision
FROM    match_candidato mc
WHERE   mc.decision = 'REVISION'
ORDER BY mc.candidato_id
LIMIT 12;

\echo ''
\echo '   ^ Mismo nombre y misma fecha de nacimiento, pero documentos totalmente distintos.'
\echo '     Fusionarlos mezclaria el historial de DOS personas: el peor error posible del MDM.'
\echo '     Por eso van a revision humana, no a fusion automatica.'

\echo ''
\echo '== PN-04: vision 360 - en cuantos sistemas existe cada cliente =='
SELECT  cant_fuentes,
        COUNT(*)                                           AS clientes,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
        ROUND(AVG(score_confianza), 1)                     AS confianza_promedio
FROM    cliente_maestro
GROUP BY cant_fuentes
ORDER BY cant_fuentes DESC;

\echo ''
\echo '== PN-05: LINAJE - de que fuente salio cada atributo del maestro =='
SELECT  l.atributo,
        l.criterio_aplicado,
        l.fuente_cod,
        COUNT(*)                                           AS veces_gano,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY l.atributo), 1) AS pct_del_atributo
FROM    cliente_maestro_linaje l
GROUP BY l.atributo, l.criterio_aplicado, l.fuente_cod
ORDER BY l.atributo, veces_gano DESC;

\echo ''
\echo '   ^ Note que ubigeo/direccion/telefono los gana la fuente MAS RECIENTE (billetera, CRM)'
\echo '     mientras que nombre y fecha de nacimiento los gana la de mayor PRECEDENCIA.'
\echo '     Cada atributo tiene su propio criterio: esa es la esencia de la supervivencia.'

\echo ''
\echo '== PN-06: calidad de datos por sistema fuente =='
SELECT  cf.fuente_cod,
        cf.precedencia,
        cf.es_externa,
        COUNT(*)                                  AS registros,
        ROUND(AVG(cr.pct_completitud), 1)         AS completitud_promedio,
        COUNT(*) FILTER (WHERE cr.doc_valido)     AS docs_validos,
        COUNT(*) FILTER (WHERE NOT cr.doc_valido) AS docs_invalidos,
        ROUND(AVG(cr.score_calidad), 1)           AS score_calidad
FROM    calidad_registro cr
JOIN    cat_fuente       cf ON cf.fuente_cod = cr.fuente_cod
GROUP BY cf.fuente_cod, cf.precedencia, cf.es_externa
ORDER BY cf.precedencia;

\echo ''
\echo '== PN-07: contribucion de cada fuente al registro maestro =='
SELECT  l.fuente_cod,
        COUNT(*)                                            AS atributos_aportados,
        COUNT(DISTINCT l.cliente_maestro_id)                AS clientes_en_que_aporta,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_del_total,
        STRING_AGG(DISTINCT l.atributo, ', ' ORDER BY l.atributo) AS atributos
FROM    cliente_maestro_linaje l
GROUP BY l.fuente_cod
ORDER BY atributos_aportados DESC;

\echo ''
\echo '== PN-08: clientes presentes en 3 o mas sistemas (los mas valiosos) =='
SELECT  c.cliente_maestro_id,
        c.tipo_doc_cod,
        c.num_doc,
        c.nombre_completo,
        c.cant_fuentes,
        c.score_confianza,
        v.fuentes
FROM    cliente_maestro c
JOIN    vw_cliente_360  v ON v.cliente_maestro_id = c.cliente_maestro_id
WHERE   c.cant_fuentes >= 3
ORDER BY c.cant_fuentes DESC, c.score_confianza DESC
LIMIT 15;

\echo ''
\echo '== PN-09: ANATOMIA DE UNA FUSION - un cliente antes y despues =='
\echo '-- (a) Lo que tenia cada sistema por separado:'
WITH ejemplo AS (
    SELECT m.cliente_maestro_id
    FROM   cliente_maestro m
    JOIN   cliente_xref x ON x.cliente_maestro_id = m.cliente_maestro_id
    WHERE  x.tipo_vinculo = 'PROBABILISTICO'
    ORDER BY m.cant_fuentes DESC, m.cliente_maestro_id
    LIMIT 1
)
SELECT  x.fuente_cod,
        cf.precedencia,
        x.tipo_vinculo,
        f.num_doc,
        f.nombre_normalizado,
        f.fecha_nacimiento,
        f.ubigeo,
        f.telefono,
        f.fecha_actualizacion
FROM    ejemplo e
JOIN    cliente_xref   x  ON x.cliente_maestro_id = e.cliente_maestro_id
JOIN    cliente_fuente f  ON f.fuente_cod = x.fuente_cod AND f.id_origen = x.id_origen
JOIN    cat_fuente     cf ON cf.fuente_cod = x.fuente_cod
ORDER BY cf.precedencia;

\echo ''
\echo '-- (b) El registro maestro resultante:'
WITH ejemplo AS (
    SELECT m.cliente_maestro_id
    FROM   cliente_maestro m
    JOIN   cliente_xref x ON x.cliente_maestro_id = m.cliente_maestro_id
    WHERE  x.tipo_vinculo = 'PROBABILISTICO'
    ORDER BY m.cant_fuentes DESC, m.cliente_maestro_id
    LIMIT 1
)
SELECT  m.num_doc, m.nombre_completo, m.fecha_nacimiento, m.ubigeo,
        m.telefono, m.correo, m.cant_fuentes, m.score_confianza
FROM    ejemplo e JOIN cliente_maestro m ON m.cliente_maestro_id = e.cliente_maestro_id;

\echo ''
\echo '-- (c) De donde salio cada dato del maestro:'
WITH ejemplo AS (
    SELECT m.cliente_maestro_id
    FROM   cliente_maestro m
    JOIN   cliente_xref x ON x.cliente_maestro_id = m.cliente_maestro_id
    WHERE  x.tipo_vinculo = 'PROBABILISTICO'
    ORDER BY m.cant_fuentes DESC, m.cliente_maestro_id
    LIMIT 1
)
SELECT  l.atributo, l.criterio_aplicado, l.fuente_cod, l.id_origen
FROM    ejemplo e JOIN cliente_maestro_linaje l ON l.cliente_maestro_id = e.cliente_maestro_id
ORDER BY l.atributo;

\echo ''
\echo '== PN-10: cobertura cruzada de productos (el valor comercial del MDM) =='
SELECT  tiene_captaciones,
        tiene_creditos,
        tiene_billetera,
        COUNT(*)                                           AS clientes,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM    vw_cliente_360
GROUP BY tiene_captaciones, tiene_creditos, tiene_billetera
ORDER BY clientes DESC;

\echo ''
\echo '   ^ Esta tabla es imposible de construir sin MDM: cada sistema usa su propio id de cliente.'
