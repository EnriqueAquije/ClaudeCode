-- =====================================================================================
-- CASO 09 - Data Vault 2.0: inclusión financiera con microdatos tipo ENAHO
-- Modelo FÍSICO - PostgreSQL 14+
-- =====================================================================================
-- Data Vault 2.0 se compone de tres tipos de tabla, y solo tres:
--   HUB       -> la LLAVE DE NEGOCIO y nada más
--   LINK      -> la RELACIÓN entre llaves de negocio
--   SATÉLITE  -> los ATRIBUTOS, con historia, colgando de un hub o de un link
--
-- Tres reglas que no se rompen nunca:
--   1. INSERT-ONLY: jamás se hace UPDATE ni DELETE. La historia es inmutable.
--   2. Toda fila lleva FECHA DE CARGA y SISTEMA ORIGEN.
--   3. La clave es un HASH de la llave de negocio: permite cargar en paralelo sin
--      depender de secuencias ni de búsquedas previas.
-- =====================================================================================

DROP SCHEMA IF EXISTS caso09 CASCADE;
CREATE SCHEMA caso09;
SET search_path TO caso09, public;

-- =====================================================================================
-- 1. FUNCIÓN DE HASH
--    MD5 es suficiente para claves de Data Vault: se usa por su distribución, no por
--    seguridad criptográfica.
-- =====================================================================================

CREATE FUNCTION fn_hash_key(VARIADIC p_partes TEXT[])
RETURNS CHAR(32)
LANGUAGE sql IMMUTABLE AS $$
    SELECT MD5(ARRAY_TO_STRING(
        ARRAY(SELECT UPPER(TRIM(COALESCE(x, '^^')))
              FROM UNNEST(p_partes) AS x), '||'))::CHAR(32);
$$;
COMMENT ON FUNCTION fn_hash_key IS
    'Hash de la llave de negocio. Normaliza (TRIM + UPPER) y usa ^^ para los nulos, de modo '
    'que la misma llave produzca SIEMPRE el mismo hash, la calcule quien la calcule.';

-- =====================================================================================
-- 2. HUBS — las llaves de negocio
--    Un hub NO tiene atributos descriptivos. Solo la llave, su hash y la trazabilidad.
-- =====================================================================================

CREATE TABLE hub_persona (
    persona_hk      CHAR(32)    NOT NULL,
    tipo_doc_bk     CHAR(2)     NOT NULL,
    num_doc_bk      VARCHAR(20) NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen  VARCHAR(30) NOT NULL,
    CONSTRAINT pk_hub_persona PRIMARY KEY (persona_hk),
    CONSTRAINT uq_hub_persona_bk UNIQUE (tipo_doc_bk, num_doc_bk)
);
COMMENT ON TABLE hub_persona IS
    'HUB: la persona existe. Nada mas. Sus atributos viven en los satelites.';

CREATE TABLE hub_hogar (
    hogar_hk        CHAR(32)    NOT NULL,
    conglomerado_bk CHAR(6)     NOT NULL,
    vivienda_bk     CHAR(3)     NOT NULL,
    hogar_bk        CHAR(2)     NOT NULL,
    anio_bk         CHAR(4)     NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen  VARCHAR(30) NOT NULL,
    CONSTRAINT pk_hub_hogar PRIMARY KEY (hogar_hk),
    CONSTRAINT uq_hub_hogar_bk UNIQUE (conglomerado_bk, vivienda_bk, hogar_bk, anio_bk)
);
COMMENT ON TABLE hub_hogar IS
    'HUB hogar. La llave de negocio es COMPUESTA, igual que en los microdatos de la ENAHO: '
    'conglomerado + vivienda + hogar + anio.';

CREATE TABLE hub_distrito (
    distrito_hk     CHAR(32)    NOT NULL,
    ubigeo_bk       CHAR(6)     NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen  VARCHAR(30) NOT NULL,
    CONSTRAINT pk_hub_distrito PRIMARY KEY (distrito_hk),
    CONSTRAINT uq_hub_distrito_bk UNIQUE (ubigeo_bk)
);

CREATE TABLE hub_producto (
    producto_hk     CHAR(32)    NOT NULL,
    producto_bk     VARCHAR(20) NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen  VARCHAR(30) NOT NULL,
    CONSTRAINT pk_hub_producto PRIMARY KEY (producto_hk),
    CONSTRAINT uq_hub_producto_bk UNIQUE (producto_bk)
);

-- =====================================================================================
-- 3. LINKS — las relaciones entre llaves de negocio
--    Un link tampoco tiene atributos descriptivos: solo relaciona hubs.
-- =====================================================================================

CREATE TABLE lnk_persona_hogar (
    persona_hogar_hk CHAR(32)   NOT NULL,
    persona_hk       CHAR(32)   NOT NULL,
    hogar_hk         CHAR(32)   NOT NULL,
    fecha_carga      TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen   VARCHAR(30) NOT NULL,
    CONSTRAINT pk_lnk_persona_hogar PRIMARY KEY (persona_hogar_hk),
    CONSTRAINT uq_lnk_persona_hogar UNIQUE (persona_hk, hogar_hk),
    CONSTRAINT fk_lnk_ph_persona FOREIGN KEY (persona_hk) REFERENCES hub_persona (persona_hk),
    CONSTRAINT fk_lnk_ph_hogar   FOREIGN KEY (hogar_hk)   REFERENCES hub_hogar (hogar_hk)
);

CREATE TABLE lnk_hogar_distrito (
    hogar_distrito_hk CHAR(32)   NOT NULL,
    hogar_hk          CHAR(32)   NOT NULL,
    distrito_hk       CHAR(32)   NOT NULL,
    fecha_carga       TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen    VARCHAR(30) NOT NULL,
    CONSTRAINT pk_lnk_hogar_distrito PRIMARY KEY (hogar_distrito_hk),
    CONSTRAINT uq_lnk_hogar_distrito UNIQUE (hogar_hk, distrito_hk),
    CONSTRAINT fk_lnk_hd_hogar    FOREIGN KEY (hogar_hk)    REFERENCES hub_hogar (hogar_hk),
    CONSTRAINT fk_lnk_hd_distrito FOREIGN KEY (distrito_hk) REFERENCES hub_distrito (distrito_hk)
);

CREATE TABLE lnk_persona_producto (
    persona_producto_hk CHAR(32)   NOT NULL,
    persona_hk          CHAR(32)   NOT NULL,
    producto_hk         CHAR(32)   NOT NULL,
    fecha_carga         TIMESTAMP  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    sistema_origen      VARCHAR(30) NOT NULL,
    CONSTRAINT pk_lnk_persona_producto PRIMARY KEY (persona_producto_hk),
    CONSTRAINT uq_lnk_persona_producto UNIQUE (persona_hk, producto_hk),
    CONSTRAINT fk_lnk_pp_persona  FOREIGN KEY (persona_hk)  REFERENCES hub_persona (persona_hk),
    CONSTRAINT fk_lnk_pp_producto FOREIGN KEY (producto_hk) REFERENCES hub_producto (producto_hk)
);

-- =====================================================================================
-- 4. SATÉLITES — los atributos, con historia
--    Cada satélite cuelga de UN hub o de UN link, y proviene de UNA fuente.
--    La PK incluye la fecha de carga: por eso es insert-only.
--    hash_diff detecta si el registro cambió sin comparar columna por columna.
-- =====================================================================================

CREATE TABLE sat_persona_demografia (
    persona_hk      CHAR(32)    NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL,
    fecha_fin_carga TIMESTAMP,
    hash_diff       CHAR(32)    NOT NULL,
    sistema_origen  VARCHAR(30) NOT NULL,
    edad            SMALLINT,
    sexo            CHAR(1),
    nivel_educativo VARCHAR(30),
    situacion_laboral VARCHAR(30),
    CONSTRAINT pk_sat_persona_demo  PRIMARY KEY (persona_hk, fecha_carga),
    CONSTRAINT fk_sat_persona_demo  FOREIGN KEY (persona_hk) REFERENCES hub_persona (persona_hk),
    CONSTRAINT ck_sat_persona_sexo  CHECK (sexo IN ('M','F') OR sexo IS NULL),
    CONSTRAINT ck_sat_persona_edad  CHECK (edad IS NULL OR edad BETWEEN 0 AND 120)
);
COMMENT ON COLUMN sat_persona_demografia.hash_diff IS
    'Hash de TODOS los atributos descriptivos. Si el hash_diff de la carga nueva es igual al '
    'ultimo, no hubo cambio y NO se inserta fila: asi el satelite no crece sin motivo.';
COMMENT ON COLUMN sat_persona_demografia.fecha_fin_carga IS
    'Se completa al insertar la version siguiente. Es la unica excepcion al insert-only, y '
    'muchos equipos prefieren evitarla usando una vista con LEAD().';

CREATE TABLE sat_persona_ingreso (
    persona_hk      CHAR(32)      NOT NULL,
    fecha_carga     TIMESTAMP     NOT NULL,
    fecha_fin_carga TIMESTAMP,
    hash_diff       CHAR(32)      NOT NULL,
    sistema_origen  VARCHAR(30)   NOT NULL,
    ingreso_mensual NUMERIC(18,2),
    fuente_ingreso  VARCHAR(30),
    es_formal       BOOLEAN,
    CONSTRAINT pk_sat_persona_ing PRIMARY KEY (persona_hk, fecha_carga),
    CONSTRAINT fk_sat_persona_ing FOREIGN KEY (persona_hk) REFERENCES hub_persona (persona_hk),
    CONSTRAINT ck_sat_persona_ing CHECK (ingreso_mensual IS NULL OR ingreso_mensual >= 0)
);
COMMENT ON TABLE sat_persona_ingreso IS
    'Satelite SEPARADO del demografico: el ingreso es DATO SENSIBLE (Ley 29733) y cambia con '
    'otra frecuencia. Separar satelites por sensibilidad y por ritmo de cambio es buena practica.';

CREATE TABLE sat_hogar_caracteristicas (
    hogar_hk        CHAR(32)    NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL,
    fecha_fin_carga TIMESTAMP,
    hash_diff       CHAR(32)    NOT NULL,
    sistema_origen  VARCHAR(30) NOT NULL,
    num_miembros    SMALLINT,
    tiene_agua      BOOLEAN,
    tiene_electricidad BOOLEAN,
    tiene_internet  BOOLEAN,
    area_cod        CHAR(1),
    CONSTRAINT pk_sat_hogar_carac PRIMARY KEY (hogar_hk, fecha_carga),
    CONSTRAINT fk_sat_hogar_carac FOREIGN KEY (hogar_hk) REFERENCES hub_hogar (hogar_hk),
    CONSTRAINT ck_sat_hogar_area  CHECK (area_cod IN ('U','R') OR area_cod IS NULL)
);

CREATE TABLE sat_persona_producto (
    persona_producto_hk CHAR(32)   NOT NULL,
    fecha_carga         TIMESTAMP  NOT NULL,
    fecha_fin_carga     TIMESTAMP,
    hash_diff           CHAR(32)   NOT NULL,
    sistema_origen      VARCHAR(30) NOT NULL,
    tiene_producto      BOOLEAN    NOT NULL,
    antiguedad_meses    INTEGER,
    frecuencia_uso      VARCHAR(20),
    CONSTRAINT pk_sat_persona_prod PRIMARY KEY (persona_producto_hk, fecha_carga),
    CONSTRAINT fk_sat_persona_prod FOREIGN KEY (persona_producto_hk)
                                   REFERENCES lnk_persona_producto (persona_producto_hk)
);
COMMENT ON TABLE sat_persona_producto IS
    'Satelite colgando de un LINK: los atributos de la RELACION persona-producto.';

-- SATÉLITE AGREGADO EN LA OLA 2026.
-- Demuestra la propiedad central del Data Vault: la fuente incorporó preguntas nuevas
-- sobre uso de canales digitales, y el modelo las absorbe AGREGANDO UNA TABLA.
-- Ninguna tabla existente se modificó. Ningún proceso de carga anterior se rompió.
CREATE TABLE sat_persona_canal_digital (
    persona_hk        CHAR(32)    NOT NULL,
    fecha_carga       TIMESTAMP   NOT NULL,
    fecha_fin_carga   TIMESTAMP,
    hash_diff         CHAR(32)    NOT NULL,
    sistema_origen    VARCHAR(30) NOT NULL,
    usa_banca_movil   BOOLEAN,
    usa_billetera     BOOLEAN,
    motivo_no_uso     VARCHAR(40),
    CONSTRAINT pk_sat_persona_digital PRIMARY KEY (persona_hk, fecha_carga),
    CONSTRAINT fk_sat_persona_digital FOREIGN KEY (persona_hk) REFERENCES hub_persona (persona_hk)
);
COMMENT ON TABLE sat_persona_canal_digital IS
    'Agregado en la ola 2026. En un modelo dimensional habria requerido ALTER TABLE sobre una '
    'dimension de millones de filas; aqui es una tabla nueva y cero impacto en lo existente.';

-- Satélite de referencia geográfica (cuelga del hub de distrito)
CREATE TABLE sat_distrito_geografia (
    distrito_hk     CHAR(32)    NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL,
    hash_diff       CHAR(32)    NOT NULL,
    sistema_origen  VARCHAR(30) NOT NULL,
    departamento    VARCHAR(40),
    provincia       VARCHAR(40),
    distrito        VARCHAR(40),
    es_urbano       BOOLEAN,
    CONSTRAINT pk_sat_distrito_geo PRIMARY KEY (distrito_hk, fecha_carga),
    CONSTRAINT fk_sat_distrito_geo FOREIGN KEY (distrito_hk) REFERENCES hub_distrito (distrito_hk)
);

CREATE TABLE sat_producto_descripcion (
    producto_hk     CHAR(32)    NOT NULL,
    fecha_carga     TIMESTAMP   NOT NULL,
    hash_diff       CHAR(32)    NOT NULL,
    sistema_origen  VARCHAR(30) NOT NULL,
    producto_desc   VARCHAR(80),
    categoria       VARCHAR(30),
    CONSTRAINT pk_sat_producto_desc PRIMARY KEY (producto_hk, fecha_carga),
    CONSTRAINT fk_sat_producto_desc FOREIGN KEY (producto_hk) REFERENCES hub_producto (producto_hk)
);

-- =====================================================================================
-- 5. ÍNDICES
-- =====================================================================================

CREATE INDEX ix_lnk_ph_persona   ON lnk_persona_hogar (persona_hk);
CREATE INDEX ix_lnk_ph_hogar     ON lnk_persona_hogar (hogar_hk);
CREATE INDEX ix_lnk_pp_persona   ON lnk_persona_producto (persona_hk);
CREATE INDEX ix_lnk_pp_producto  ON lnk_persona_producto (producto_hk);
CREATE INDEX ix_sat_demo_vigente ON sat_persona_demografia (persona_hk) WHERE fecha_fin_carga IS NULL;
CREATE INDEX ix_sat_ing_vigente  ON sat_persona_ingreso (persona_hk)    WHERE fecha_fin_carga IS NULL;
CREATE INDEX ix_sat_prod_vigente ON sat_persona_producto (persona_producto_hk) WHERE fecha_fin_carga IS NULL;
CREATE INDEX ix_sat_dig_vigente  ON sat_persona_canal_digital (persona_hk) WHERE fecha_fin_carga IS NULL;

-- =====================================================================================
-- 6. CAPA DE ENTREGA (Business Vault / Information Marts)
--    El Data Vault NO se consulta directamente por el usuario de negocio: es demasiado
--    fragmentado. Sobre él se construyen vistas que reconstruyen la foto.
-- =====================================================================================

CREATE VIEW vw_persona_vigente AS
SELECT  h.persona_hk,
        h.tipo_doc_bk,
        h.num_doc_bk,
        d.edad,
        d.sexo,
        d.nivel_educativo,
        d.situacion_laboral,
        i.ingreso_mensual,
        i.fuente_ingreso,
        i.es_formal,
        d.fecha_carga AS fecha_carga_demografia,
        i.fecha_carga AS fecha_carga_ingreso
FROM        hub_persona h
LEFT JOIN   sat_persona_demografia d ON d.persona_hk = h.persona_hk AND d.fecha_fin_carga IS NULL
LEFT JOIN   sat_persona_ingreso    i ON i.persona_hk = h.persona_hk AND i.fecha_fin_carga IS NULL;

COMMENT ON VIEW vw_persona_vigente IS
    'Reconstruye la foto actual de la persona uniendo sus satelites vigentes. Es el puente '
    'entre el Data Vault (fragmentado, historico) y el consumo (plano, actual).';

CREATE VIEW vw_inclusion_financiera AS
SELECT  hp.persona_hk,
        hp.num_doc_bk,
        pv.edad,
        pv.sexo,
        pv.nivel_educativo,
        pv.ingreso_mensual,
        pv.es_formal,
        g.departamento,
        g.provincia,
        g.distrito,
        sh.area_cod,
        sh.tiene_internet,
        sh.num_miembros,
        COUNT(*) FILTER (WHERE sp.tiene_producto)                    AS cant_productos,
        BOOL_OR(sp.tiene_producto AND pd.categoria = 'AHORRO')       AS tiene_ahorro,
        BOOL_OR(sp.tiene_producto AND pd.categoria = 'CREDITO')      AS tiene_credito,
        BOOL_OR(sp.tiene_producto AND pd.categoria = 'PAGOS')        AS tiene_pagos
FROM        hub_persona hp
LEFT JOIN   vw_persona_vigente pv ON pv.persona_hk = hp.persona_hk
LEFT JOIN   lnk_persona_hogar lph ON lph.persona_hk = hp.persona_hk
LEFT JOIN   sat_hogar_caracteristicas sh ON sh.hogar_hk = lph.hogar_hk AND sh.fecha_fin_carga IS NULL
LEFT JOIN   lnk_hogar_distrito lhd ON lhd.hogar_hk = lph.hogar_hk
LEFT JOIN   sat_distrito_geografia g ON g.distrito_hk = lhd.distrito_hk
LEFT JOIN   lnk_persona_producto lpp ON lpp.persona_hk = hp.persona_hk
LEFT JOIN   sat_persona_producto sp ON sp.persona_producto_hk = lpp.persona_producto_hk
                                   AND sp.fecha_fin_carga IS NULL
LEFT JOIN   sat_producto_descripcion pd ON pd.producto_hk = lpp.producto_hk
GROUP BY hp.persona_hk, hp.num_doc_bk, pv.edad, pv.sexo, pv.nivel_educativo,
         pv.ingreso_mensual, pv.es_formal, g.departamento, g.provincia, g.distrito,
         sh.area_cod, sh.tiene_internet, sh.num_miembros;

COMMENT ON VIEW vw_inclusion_financiera IS
    'Information Mart: la vista plana que responde las preguntas de inclusion financiera.';
