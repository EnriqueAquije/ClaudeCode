-- =====================================================================================
--  estandares.sql — ¿los modelos cumplen el estándar que el propio repositorio publica?
-- =====================================================================================
--  `00-fundamentos/05-estandares-modelado.md` fija nomenclatura, tipos y patrones. Un
--  estándar que nadie comprueba se convierte en decoración, y entonces enseña lo
--  contrario de lo que pretende: que las convenciones son opcionales.
--
--  Este script compara los 10 esquemas contra ese documento. Donde el laboratorio se
--  desvía A PROPOSITO, la excepción está declarada aquí abajo con su motivo: una
--  desviación documentada es una decisión; una silenciosa es una deuda.
-- =====================================================================================

\echo ''
\echo '=============================================================='
\echo '   CUMPLIMIENTO DEL ESTANDAR DE MODELADO'
\echo '=============================================================='

WITH tablas AS (
    SELECT n.nspname AS esq, c.relname AS tabla
    FROM   pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE  n.nspname ~ '^caso[0-9]{2}$' AND c.relkind = 'r'
      AND  c.relispartition = FALSE
),
resultados AS (
    -- ------------------------------------------------------------------ Tipos
    SELECT 'EST-01' AS regla, 'Tipos' AS familia,
           'Todo importe monetario es NUMERIC(18,2), nunca FLOAT' AS descripcion,
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema ~ '^caso[0-9]{2}$'
              AND (column_name ~ '(monto|saldo|importe|valor_|linea_|pago_|total_)'
                   AND data_type IN ('double precision','real'))) AS incumple
    UNION ALL
    SELECT 'EST-02', 'Tipos', 'El ubigeo es CHAR(6): conserva el cero inicial',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema ~ '^caso[0-9]{2}$' AND column_name = 'ubigeo'
              AND NOT (data_type = 'character' AND character_maximum_length = 6))
    UNION ALL
    SELECT 'EST-03', 'Tipos', 'El numero de documento es VARCHAR, nunca numerico',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema ~ '^caso[0-9]{2}$' AND column_name = 'num_doc'
              AND data_type NOT IN ('character varying','character'))
    UNION ALL
    SELECT 'EST-04', 'Tipos', 'Ningun booleano disfrazado de CHAR(1) con S/N en columnas es_*',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema ~ '^caso[0-9]{2}$' AND column_name LIKE 'es\_%'
              AND data_type <> 'boolean')
    UNION ALL
    -- ------------------------------------------------------- Nomenclatura
    SELECT 'EST-05', 'Nomenclatura', 'fecha_hora_* es TIMESTAMP',
           (SELECT COUNT(*) FROM information_schema.columns
            WHERE table_schema ~ '^caso[0-9]{2}$' AND column_name LIKE 'fecha\_hora\_%'
              AND data_type NOT LIKE 'timestamp%')
    UNION ALL
    SELECT 'EST-06', 'Nomenclatura', 'Toda tabla usa minusculas y guion bajo',
           (SELECT COUNT(*) FROM tablas WHERE tabla <> LOWER(tabla) OR tabla ~ '[^a-z0-9_]')
    UNION ALL
    -- Un catalogo NO se reconoce por el nombre: `tipo_cambio_publicado` empieza por `tipo_`
    -- y es una serie temporal, no un catalogo. Se reconoce por su ESTRUCTURA: clave primaria
    -- de una sola columna terminada en _cod, y alguien apuntandole con una clave foranea.
    SELECT 'EST-07', 'Nomenclatura', 'Toda tabla con estructura de catalogo lleva prefijo cat_',
           (SELECT COUNT(*) FROM tablas t
            WHERE t.tabla !~ '^(cat_|par_)'
              AND EXISTS (SELECT 1 FROM pg_constraint k
                          JOIN LATERAL UNNEST(k.conkey) AS ck(att) ON TRUE
                          JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = ck.att
                          WHERE k.conrelid = (t.esq||'.'||t.tabla)::REGCLASS AND k.contype = 'p'
                          GROUP BY k.oid HAVING COUNT(*) = 1 AND MIN(a.attname) LIKE '%\_cod')
              AND EXISTS (SELECT 1 FROM pg_constraint f
                          WHERE f.confrelid = (t.esq||'.'||t.tabla)::REGCLASS AND f.contype = 'f'))
    UNION ALL
    -- ----------------------------------------------------------- Integridad
    SELECT 'EST-08', 'Integridad', 'Toda tabla tiene clave primaria',
           (SELECT COUNT(*) FROM tablas t
            WHERE NOT EXISTS (SELECT 1 FROM pg_constraint k
                              WHERE k.conrelid = (t.esq||'.'||t.tabla)::REGCLASS
                                AND k.contype = 'p'))
    UNION ALL
    -- Solo columnas de la CLAVE PRIMARIA. Una clave foranea nulable es legitima y frecuente:
    -- `transferencia.motivo_cod` solo existe cuando la transferencia fue rechazada.
    SELECT 'EST-09', 'Integridad', 'Ninguna columna de clave primaria admite nulos',
           (SELECT COUNT(*) FROM information_schema.columns c
            JOIN information_schema.key_column_usage k
              ON k.table_schema = c.table_schema AND k.table_name = c.table_name
             AND k.column_name = c.column_name
            JOIN information_schema.table_constraints tc
              ON tc.constraint_name = k.constraint_name AND tc.table_schema = k.table_schema
             AND tc.constraint_type = 'PRIMARY KEY'
            WHERE c.table_schema ~ '^caso[0-9]{2}$' AND c.is_nullable = 'YES')
    UNION ALL
    -- ------------------------------------------------- Busqueda operativa
    SELECT 'EST-10', 'Rendimiento', 'Toda tabla con num_doc se puede buscar por num_doc solo',
           (SELECT COUNT(*) FROM information_schema.columns c
            WHERE c.table_schema ~ '^caso[0-9]{2}$' AND c.column_name = 'num_doc'
              AND EXISTS (SELECT 1 FROM tablas t WHERE t.esq = c.table_schema AND t.tabla = c.table_name)
              AND NOT EXISTS (SELECT 1 FROM pg_indexes i
                              WHERE i.schemaname = c.table_schema AND i.tablename = c.table_name
                                AND i.indexdef ~ '\(num_doc'))
    UNION ALL
    -- -------------------------------------------------------- Trazabilidad
    SELECT 'EST-11', 'Trazabilidad', 'Las tablas analiticas declaran su sistema de origen',
           (SELECT COUNT(*) FROM tablas t
            WHERE t.esq = 'caso09' AND t.tabla ~ '^(hub_|lnk_|sat_)'
              AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                              WHERE c.table_schema = t.esq AND c.table_name = t.tabla
                                AND c.column_name = 'sistema_origen'))
    UNION ALL
    SELECT 'EST-12', 'Auditoria', 'Las tablas del caso 01 llevan las 4 columnas de auditoria',
           (SELECT 12 - COUNT(*) FROM information_schema.columns
            WHERE table_schema = 'caso01'
              AND table_name IN ('cliente','cuenta','movimiento')
              AND column_name IN ('fecha_hora_creacion','usuario_creacion',
                                  'fecha_hora_modificacion','usuario_modificacion'))
)
SELECT  regla, familia, descripcion, incumple AS incumplimientos,
        CASE WHEN incumple = 0 THEN 'OK' ELSE 'FALLA' END AS estado
FROM    resultados
ORDER BY regla;

\echo ''
\echo '-- DESVIACIONES DECLARADAS (decisiones, no deudas)'

SELECT * FROM (VALUES
 ('Auditoria en 9 de 10 casos',
  'Solo el caso 01 lleva las 4 columnas de auditoria.',
  'Repetirlas en 121 tablas ahogaria el DDL que el alumno tiene que leer. Se implementan donde se ensenan (caso 01) y se declara aqui que los demas las omiten. EN PRODUCCION NO ES ACEPTABLE.'),
 ('GENERATED BY DEFAULT en vez de ALWAYS',
  '33 columnas de identidad usan BY DEFAULT.',
  'Las cargas deterministas insertan identificadores explicitos para que las cifras sean reproducibles, y el caso 05 necesita la clave -1 del miembro desconocido. En un sistema real va ALWAYS.'),
 ('fecha_operacion declarada TIMESTAMP',
  'Varias columnas fecha_* guardan fecha y hora.',
  'Reproducen el nombre que tienen en los sistemas fuente que simulan. Renombrarlas seria mas limpio y menos realista; el estandar aplica a las columnas que el modelo INTRODUCE, no a las que hereda.')
) AS d(desviacion, que_pasa, por_que);
