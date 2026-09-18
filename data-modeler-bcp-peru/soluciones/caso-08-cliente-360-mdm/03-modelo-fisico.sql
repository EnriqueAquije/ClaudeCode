-- =====================================================================================
-- CASO 08 - MDM / Cliente 360: registro maestro único a partir de múltiples sistemas
-- Modelo FÍSICO - PostgreSQL 14+
-- =====================================================================================
-- REQUISITO: los esquemas caso01, caso02, caso04 y caso07 deben existir y estar cargados.
-- Extensiones: fuzzystrmatch y pg_trgm (requieren postgresql-contrib y permiso para
-- ejecutar CREATE EXTENSION). Si no están disponibles, ver la nota del README.
-- =====================================================================================

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
-- unaccent se instala para poder usarla en consultas ad hoc y en el arranque exploratorio.
-- OJO: NO se puede usar en la columna generada de mas abajo, porque es STABLE y no IMMUTABLE.
-- Ver la nota en la seccion 2.
CREATE EXTENSION IF NOT EXISTS unaccent;

DROP SCHEMA IF EXISTS caso08 CASCADE;
CREATE SCHEMA caso08;
SET search_path TO caso08, public;

-- =====================================================================================
-- 1. CATÁLOGO DE SISTEMAS FUENTE
--    La PRECEDENCIA es la decisión de gobierno más importante del MDM:
--    cuando dos sistemas discrepan, ¿cuál gana?
-- =====================================================================================

CREATE TABLE cat_fuente (
    fuente_cod       VARCHAR(20)  NOT NULL,
    fuente_nombre    VARCHAR(80)  NOT NULL,
    precedencia      SMALLINT     NOT NULL,   -- 1 = mayor autoridad
    es_externa       BOOLEAN      NOT NULL DEFAULT FALSE,
    es_autoritativa_doc BOOLEAN   NOT NULL DEFAULT FALSE,
    descripcion      VARCHAR(200),
    CONSTRAINT pk_cat_fuente        PRIMARY KEY (fuente_cod),
    CONSTRAINT uq_cat_fuente_prec   UNIQUE (precedencia),
    CONSTRAINT ck_cat_fuente_prec   CHECK (precedencia BETWEEN 1 AND 99)
);
COMMENT ON COLUMN cat_fuente.precedencia IS
    'Orden de autoridad. UNIQUE a proposito: dos fuentes no pueden empatar, porque el empate '
    'dejaria la decision al azar del plan de ejecucion.';

-- =====================================================================================
-- 2. REGISTROS TAL COMO LLEGAN DE CADA FUENTE
--    Esta tabla NO se limpia ni se corrige: es la foto de lo que cada sistema tiene.
-- =====================================================================================

CREATE TABLE cliente_fuente (
    fuente_cod       VARCHAR(20)  NOT NULL,
    id_origen        VARCHAR(40)  NOT NULL,
    tipo_doc_cod     CHAR(2),
    num_doc          VARCHAR(20),
    ape_paterno      VARCHAR(60),
    ape_materno      VARCHAR(60),
    nombres          VARCHAR(80),
    razon_social     VARCHAR(160),
    fecha_nacimiento DATE,
    ubigeo           CHAR(6),
    direccion        VARCHAR(160),
    telefono         VARCHAR(20),
    correo           VARCHAR(80),
    ciiu_cod         CHAR(4),
    fecha_actualizacion DATE      NOT NULL,
    CONSTRAINT pk_cliente_fuente    PRIMARY KEY (fuente_cod, id_origen),
    CONSTRAINT fk_cliente_fuente_f  FOREIGN KEY (fuente_cod) REFERENCES cat_fuente (fuente_cod)
);
COMMENT ON TABLE cliente_fuente IS
    'Registros crudos de cada sistema. Los duplicados, los errores de digitacion y los datos '
    'faltantes SE CONSERVAN: son el insumo del proceso de matching, no un problema a ocultar.';

-- Clave de comparación normalizada (columna generada): quita tildes, espacios y mayúsculas.
--
-- POR QUÉ `TRANSLATE` Y NO `unaccent()`:
-- `unaccent()` es la función obvia, y NO se puede usar aquí: depende de un diccionario
-- configurable, así que PostgreSQL la declara STABLE, y una columna generada exige
-- IMMUTABLE. `TRANSLATE` sí es IMMUTABLE porque el mapeo va escrito en la propia expresión.
--
-- Y el orden importa: primero se quitan las tildes, DESPUÉS se pasa a mayúsculas. Al revés
-- no funciona, porque `UPPER('ñ')` devuelve 'ñ' sin tocarla cuando la base usa la
-- intercalación C. Con `TRANSLATE` delante, 'Muñóz José' y 'MUNOZ JOSE' generan la misma
-- clave — que es justamente lo que un MDM de apellidos peruanos necesita.
ALTER TABLE cliente_fuente
    ADD COLUMN nombre_normalizado VARCHAR(200)
    GENERATED ALWAYS AS (
        UPPER(TRANSLATE(TRIM(REGEXP_REPLACE(
            COALESCE(razon_social, COALESCE(ape_paterno,'') || ' ' ||
                                   COALESCE(ape_materno,'') || ' ' ||
                                   COALESCE(nombres,'')),
            '\s+', ' ', 'g')),
            'áéíóúüñÁÉÍÓÚÜÑ',
            'aeiouunAEIOUUN'))
    ) STORED;
COMMENT ON COLUMN cliente_fuente.nombre_normalizado IS
    'Clave de comparacion: sin tildes, sin espacios repetidos, en mayusculas. '
    'Es lo unico que se compara al hacer matching por nombre; el nombre original NO se toca.';

-- =====================================================================================
-- DETECCION DE TRANSPOSICION
--
-- La distancia de edicion NO distingue dos errores muy distintos:
--   71000031 vs 71000013  -> transposicion: los MISMOS digitos, dos de ellos intercambiados
--   71000031 vs 71000097  -> digitos DISTINTOS: puede ser otra persona
-- Ambos dan distancia 2, y fusionarlos automaticamente por igual es el error mas grave
-- que puede cometer un MDM. En el Peru los homonimos y los hermanos con documentos
-- correlativos son frecuentes.
-- =====================================================================================
CREATE FUNCTION fn_es_transposicion(p_a TEXT, p_b TEXT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$
    SELECT LENGTH(p_a) = LENGTH(p_b)
       AND LEVENSHTEIN(p_a, p_b) = 2
       AND (SELECT STRING_AGG(c, '' ORDER BY c) FROM REGEXP_SPLIT_TO_TABLE(p_a, '') AS c)
         = (SELECT STRING_AGG(c, '' ORDER BY c) FROM REGEXP_SPLIT_TO_TABLE(p_b, '') AS c);
$$;
COMMENT ON FUNCTION fn_es_transposicion IS
    'TRUE si los dos documentos tienen exactamente los mismos digitos con dos intercambiados. '
    'Es la unica forma de error de digitacion que se puede fusionar sin intervencion humana.';

-- =====================================================================================
-- 3. CALIDAD DE CADA REGISTRO
--    No todas las fuentes tienen la misma calidad. Medirlo permite decidir con criterio.
-- =====================================================================================

CREATE TABLE calidad_registro (
    fuente_cod        VARCHAR(20)  NOT NULL,
    id_origen         VARCHAR(40)  NOT NULL,
    campos_totales    SMALLINT     NOT NULL,
    campos_completos  SMALLINT     NOT NULL,
    pct_completitud   NUMERIC(5,2) NOT NULL,
    doc_valido        BOOLEAN      NOT NULL,
    antiguedad_dias   INTEGER      NOT NULL,
    score_calidad     NUMERIC(5,2) NOT NULL,
    CONSTRAINT pk_calidad_registro  PRIMARY KEY (fuente_cod, id_origen),
    CONSTRAINT fk_calidad_registro  FOREIGN KEY (fuente_cod, id_origen)
                                    REFERENCES cliente_fuente (fuente_cod, id_origen),
    CONSTRAINT ck_calidad_score     CHECK (score_calidad BETWEEN 0 AND 100),
    CONSTRAINT ck_calidad_completos CHECK (campos_completos <= campos_totales)
);

-- =====================================================================================
-- 4. REGLAS DE MATCHING
-- =====================================================================================

CREATE TABLE cat_regla_match (
    regla_cod      VARCHAR(20)  NOT NULL,
    regla_nombre   VARCHAR(80)  NOT NULL,
    tipo_match     VARCHAR(20)  NOT NULL,
    descripcion    VARCHAR(250) NOT NULL,
    score_asignado NUMERIC(5,2) NOT NULL,
    umbral_auto    NUMERIC(5,2) NOT NULL,
    esta_activa    BOOLEAN      NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_cat_regla_match   PRIMARY KEY (regla_cod),
    CONSTRAINT ck_regla_tipo    CHECK (tipo_match IN ('DETERMINISTA','PROBABILISTICO')),
    CONSTRAINT ck_regla_score   CHECK (score_asignado BETWEEN 0 AND 100),
    CONSTRAINT ck_regla_umbral  CHECK (umbral_auto BETWEEN 0 AND 100)
);
COMMENT ON COLUMN cat_regla_match.umbral_auto IS
    'Score a partir del cual el match se acepta automaticamente. Por debajo va a REVISION MANUAL. '
    'Bajarlo aumenta los falsos positivos (fusionar dos personas distintas): el error mas grave del MDM.';

CREATE TABLE match_candidato (
    candidato_id   BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    fuente_a       VARCHAR(20)  NOT NULL,
    id_origen_a    VARCHAR(40)  NOT NULL,
    fuente_b       VARCHAR(20)  NOT NULL,
    id_origen_b    VARCHAR(40)  NOT NULL,
    regla_cod      VARCHAR(20)  NOT NULL,
    score          NUMERIC(5,2) NOT NULL,
    decision       VARCHAR(15)  NOT NULL,
    evidencia      JSONB        NOT NULL DEFAULT '{}'::JSONB,
    CONSTRAINT pk_match_candidato  PRIMARY KEY (candidato_id),
    CONSTRAINT fk_match_a          FOREIGN KEY (fuente_a, id_origen_a) REFERENCES cliente_fuente (fuente_cod, id_origen),
    CONSTRAINT fk_match_b          FOREIGN KEY (fuente_b, id_origen_b) REFERENCES cliente_fuente (fuente_cod, id_origen),
    CONSTRAINT fk_match_regla      FOREIGN KEY (regla_cod) REFERENCES cat_regla_match (regla_cod),
    CONSTRAINT ck_match_decision   CHECK (decision IN ('AUTO_MATCH','REVISION','NO_MATCH')),
    CONSTRAINT ck_match_distintos  CHECK (fuente_a <> fuente_b OR id_origen_a <> id_origen_b),
    CONSTRAINT uq_match_par        UNIQUE (fuente_a, id_origen_a, fuente_b, id_origen_b, regla_cod)
);

-- =====================================================================================
-- 5. REGLAS DE SUPERVIVENCIA
--    Qué valor gana cuando dos fuentes discrepan, atributo por atributo.
-- =====================================================================================

CREATE TABLE regla_supervivencia (
    atributo        VARCHAR(40)  NOT NULL,
    criterio        VARCHAR(20)  NOT NULL,
    fuente_preferida VARCHAR(20),
    descripcion     VARCHAR(200) NOT NULL,
    CONSTRAINT pk_regla_superv   PRIMARY KEY (atributo),
    CONSTRAINT fk_regla_superv_f FOREIGN KEY (fuente_preferida) REFERENCES cat_fuente (fuente_cod),
    CONSTRAINT ck_regla_superv   CHECK (criterio IN ('PRECEDENCIA','MAS_RECIENTE','MAS_COMPLETO','FUENTE_FIJA'))
);
COMMENT ON TABLE regla_supervivencia IS
    'Cada atributo puede tener un criterio distinto: la direccion conviene tomarla del sistema '
    'mas reciente, pero la actividad economica, de la fuente autoritativa (SUNAT).';

-- =====================================================================================
-- 6. REGISTRO MAESTRO (GOLDEN RECORD)
--    Nunca se digita: SIEMPRE se deriva aplicando las reglas de supervivencia.
-- =====================================================================================

CREATE TABLE cliente_maestro (
    cliente_maestro_id BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    tipo_doc_cod       CHAR(2)      NOT NULL,
    num_doc            VARCHAR(20)  NOT NULL,
    nombre_completo    VARCHAR(200) NOT NULL,
    es_persona_juridica BOOLEAN     NOT NULL,
    fecha_nacimiento   DATE,
    ubigeo             CHAR(6),
    direccion          VARCHAR(160),
    telefono           VARCHAR(20),
    correo             VARCHAR(80),
    ciiu_cod           CHAR(4),
    cant_fuentes       SMALLINT     NOT NULL,
    score_confianza    NUMERIC(5,2) NOT NULL,
    fecha_construccion TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cliente_maestro   PRIMARY KEY (cliente_maestro_id),
    CONSTRAINT uq_cliente_maestro   UNIQUE (tipo_doc_cod, num_doc),
    CONSTRAINT ck_cliente_maestro_f CHECK (cant_fuentes >= 1),
    CONSTRAINT ck_cliente_maestro_s CHECK (score_confianza BETWEEN 0 AND 100)
);
COMMENT ON TABLE cliente_maestro IS
    'Golden record. DERIVADO, nunca digitado. Si alguien necesita corregirlo, se corrige en la '
    'FUENTE y se reconstruye: de otro modo el proximo proceso sobrescribe la correccion.';

-- Trazabilidad de la supervivencia: de qué fuente salió CADA atributo.
CREATE TABLE cliente_maestro_linaje (
    cliente_maestro_id BIGINT      NOT NULL,
    atributo           VARCHAR(40) NOT NULL,
    fuente_cod         VARCHAR(20) NOT NULL,
    id_origen          VARCHAR(40) NOT NULL,
    criterio_aplicado  VARCHAR(20) NOT NULL,
    CONSTRAINT pk_cliente_linaje    PRIMARY KEY (cliente_maestro_id, atributo),
    CONSTRAINT fk_cliente_linaje_m  FOREIGN KEY (cliente_maestro_id) REFERENCES cliente_maestro (cliente_maestro_id),
    CONSTRAINT fk_cliente_linaje_f  FOREIGN KEY (fuente_cod, id_origen) REFERENCES cliente_fuente (fuente_cod, id_origen)
);
COMMENT ON TABLE cliente_maestro_linaje IS
    'Responde la pregunta que siempre llega: "por que el maestro dice esta direccion y no la mia?".';

-- Referencia cruzada: qué registros de origen componen cada maestro.
CREATE TABLE cliente_xref (
    cliente_maestro_id BIGINT       NOT NULL,
    fuente_cod         VARCHAR(20)  NOT NULL,
    id_origen          VARCHAR(40)  NOT NULL,
    tipo_vinculo       VARCHAR(15)  NOT NULL,
    score_vinculo      NUMERIC(5,2) NOT NULL,
    fecha_vinculo      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_cliente_xref    PRIMARY KEY (fuente_cod, id_origen),
    CONSTRAINT fk_cliente_xref_m  FOREIGN KEY (cliente_maestro_id) REFERENCES cliente_maestro (cliente_maestro_id),
    CONSTRAINT fk_cliente_xref_f  FOREIGN KEY (fuente_cod, id_origen) REFERENCES cliente_fuente (fuente_cod, id_origen),
    CONSTRAINT ck_cliente_xref_t  CHECK (tipo_vinculo IN ('DETERMINISTA','PROBABILISTICO','MANUAL'))
);
COMMENT ON TABLE cliente_xref IS
    'Un registro de origen pertenece a UN solo maestro: la PK sobre (fuente, id_origen) lo garantiza. '
    'Es la tabla que permite navegar del maestro a cada sistema y volver.';

-- =====================================================================================
-- 7. ÍNDICES
-- =====================================================================================


-- BUSQUEDA POR DOCUMENTO SIN EL TIPO
-- `UNIQUE (tipo_doc_cod, num_doc)` es la llave correcta, pero NO sirve para buscar solo por
-- numero: un indice compuesto solo se usa desde su primera columna. Y buscar por DNI a secas
-- es LA consulta del front-office peruano: ventanilla, centro de contacto, cruce con RENIEC,
-- cruce con centrales de riesgo. Sin este indice, cada una de esas busquedas es un seq scan
-- sobre la tabla de clientes.
CREATE INDEX ix_cliente_fuente_num_doc ON cliente_fuente (num_doc);
CREATE INDEX ix_cliente_maestro_num_doc ON cliente_maestro (num_doc);

CREATE INDEX ix_cliente_fuente_doc    ON cliente_fuente (tipo_doc_cod, num_doc);
CREATE INDEX ix_cliente_fuente_nombre ON cliente_fuente USING GIN (nombre_normalizado gin_trgm_ops);
CREATE INDEX ix_match_decision        ON match_candidato (decision);
CREATE INDEX ix_xref_maestro          ON cliente_xref (cliente_maestro_id);
CREATE INDEX ix_linaje_fuente         ON cliente_maestro_linaje (fuente_cod, id_origen);

COMMENT ON INDEX ix_cliente_fuente_nombre IS
    'Indice de trigramas: permite buscar nombres PARECIDOS con rendimiento razonable. '
    'Sin el, el matching probabilistico es un producto cartesiano.';

-- =====================================================================================
-- 8. VISTAS
-- =====================================================================================

CREATE VIEW vw_cliente_360 AS
SELECT  m.cliente_maestro_id,
        m.tipo_doc_cod,
        m.num_doc,
        m.nombre_completo,
        m.es_persona_juridica,
        m.ubigeo,
        m.telefono,
        m.correo,
        m.ciiu_cod,
        m.cant_fuentes,
        m.score_confianza,
        BOOL_OR(x.fuente_cod = 'CORE_CAPTACIONES') AS tiene_captaciones,
        BOOL_OR(x.fuente_cod = 'CORE_CREDITOS')    AS tiene_creditos,
        BOOL_OR(x.fuente_cod = 'BILLETERA')        AS tiene_billetera,
        BOOL_OR(x.fuente_cod = 'PADRON_SUNAT')     AS validado_sunat,
        STRING_AGG(x.fuente_cod, ', ' ORDER BY x.fuente_cod) AS fuentes
FROM    cliente_maestro m
JOIN    cliente_xref    x ON x.cliente_maestro_id = m.cliente_maestro_id
GROUP BY m.cliente_maestro_id, m.tipo_doc_cod, m.num_doc, m.nombre_completo,
         m.es_persona_juridica, m.ubigeo, m.telefono, m.correo, m.ciiu_cod,
         m.cant_fuentes, m.score_confianza;

COMMENT ON VIEW vw_cliente_360 IS
    'La vista 360: un cliente, todos los sistemas donde existe, en una sola fila.';
