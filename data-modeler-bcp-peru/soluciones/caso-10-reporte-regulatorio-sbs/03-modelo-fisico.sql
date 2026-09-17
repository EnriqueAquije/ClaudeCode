-- =====================================================================================
-- CASO 10 - Reporte regulatorio a la SBS: definición, generación, validación y linaje
-- Modelo FÍSICO - PostgreSQL 14+
-- =====================================================================================
-- REQUISITO: el esquema caso02 debe existir y estar cargado.
--
-- Idea central: LA DEFINICIÓN DEL REPORTE ES UN DATO, no un programa.
-- Los campos, sus posiciones, sus dominios, sus validaciones y su base legal viven en
-- tablas. Un cambio normativo es un INSERT con nueva vigencia, no un proyecto de TI.
-- =====================================================================================

DROP SCHEMA IF EXISTS caso10 CASCADE;
CREATE SCHEMA caso10;
SET search_path TO caso10, public;

-- =====================================================================================
-- 1. DEFINICIÓN DEL REPORTE (metadatos versionados)
-- =====================================================================================

CREATE TABLE reporte_definicion (
    reporte_cod     VARCHAR(20)  NOT NULL,
    version         SMALLINT     NOT NULL,
    reporte_nombre  VARCHAR(120) NOT NULL,
    periodicidad    VARCHAR(15)  NOT NULL,
    dias_plazo      SMALLINT     NOT NULL,
    base_legal      VARCHAR(200) NOT NULL,
    fecha_desde     DATE         NOT NULL,
    fecha_hasta     DATE         NOT NULL DEFAULT DATE '9999-12-31',
    CONSTRAINT pk_reporte_definicion PRIMARY KEY (reporte_cod, version),
    CONSTRAINT ck_reporte_period     CHECK (periodicidad IN ('DIARIA','MENSUAL','TRIMESTRAL','ANUAL')),
    CONSTRAINT ck_reporte_plazo      CHECK (dias_plazo > 0),
    CONSTRAINT ck_reporte_vig        CHECK (fecha_hasta >= fecha_desde)
);
COMMENT ON TABLE reporte_definicion IS
    'Definicion versionada del reporte. Cuando la SBS modifica la estructura, se crea una '
    'VERSION NUEVA: la anterior se conserva para poder reproducir envios pasados.';

CREATE TABLE reporte_campo (
    reporte_cod     VARCHAR(20)  NOT NULL,
    version         SMALLINT     NOT NULL,
    posicion        SMALLINT     NOT NULL,
    campo_cod       VARCHAR(40)  NOT NULL,
    campo_nombre    VARCHAR(120) NOT NULL,
    tipo_dato       VARCHAR(15)  NOT NULL,
    longitud        SMALLINT     NOT NULL,
    decimales       SMALLINT     NOT NULL DEFAULT 0,
    es_obligatorio  BOOLEAN      NOT NULL DEFAULT TRUE,
    dominio         VARCHAR(200),
    base_legal      VARCHAR(200),
    CONSTRAINT pk_reporte_campo     PRIMARY KEY (reporte_cod, version, campo_cod),
    CONSTRAINT uq_reporte_campo_pos UNIQUE (reporte_cod, version, posicion),
    CONSTRAINT fk_reporte_campo_def FOREIGN KEY (reporte_cod, version)
                                    REFERENCES reporte_definicion (reporte_cod, version),
    CONSTRAINT ck_reporte_campo_tipo CHECK (tipo_dato IN ('TEXTO','NUMERO','FECHA','ENTERO')),
    CONSTRAINT ck_reporte_campo_long CHECK (longitud > 0),
    CONSTRAINT ck_reporte_campo_dec  CHECK (decimales >= 0 AND decimales <= longitud)
);
COMMENT ON TABLE reporte_campo IS
    'Estructura campo a campo del archivo a remitir: posicion, tipo, longitud y dominio. '
    'Es lo que permite generar y validar el archivo sin programar la estructura.';

CREATE TABLE reporte_validacion (
    reporte_cod     VARCHAR(20)  NOT NULL,
    version         SMALLINT     NOT NULL,
    validacion_cod  VARCHAR(20)  NOT NULL,
    descripcion     VARCHAR(250) NOT NULL,
    severidad       VARCHAR(10)  NOT NULL,
    expresion_sql   TEXT         NOT NULL,
    base_legal      VARCHAR(200),
    CONSTRAINT pk_reporte_validacion PRIMARY KEY (reporte_cod, version, validacion_cod),
    CONSTRAINT fk_reporte_valid_def  FOREIGN KEY (reporte_cod, version)
                                     REFERENCES reporte_definicion (reporte_cod, version),
    CONSTRAINT ck_reporte_valid_sev  CHECK (severidad IN ('BLOQUEA','ADVIERTE'))
);
COMMENT ON COLUMN reporte_validacion.expresion_sql IS
    'Condicion SQL que identifica las filas QUE INCUMPLEN. Guardarla como dato permite '
    'agregar validaciones nuevas sin desplegar codigo.';
COMMENT ON COLUMN reporte_validacion.severidad IS
    'BLOQUEA impide el envio. ADVIERTE deja enviar pero queda registrado.';

-- =====================================================================================
-- 2. LINAJE: de dónde sale cada campo del reporte
--    Es lo que se exhibe cuando el supervisor pregunta "¿cómo calculó este campo?".
-- =====================================================================================

CREATE TABLE reporte_linaje (
    reporte_cod       VARCHAR(20)  NOT NULL,
    version           SMALLINT     NOT NULL,
    campo_cod         VARCHAR(40)  NOT NULL,
    esquema_origen    VARCHAR(30)  NOT NULL,
    tabla_origen      VARCHAR(60)  NOT NULL,
    columna_origen    VARCHAR(60),
    transformacion    VARCHAR(300) NOT NULL,
    responsable       VARCHAR(60)  NOT NULL,
    CONSTRAINT pk_reporte_linaje    PRIMARY KEY (reporte_cod, version, campo_cod),
    CONSTRAINT fk_reporte_linaje_c  FOREIGN KEY (reporte_cod, version, campo_cod)
                                    REFERENCES reporte_campo (reporte_cod, version, campo_cod)
);
COMMENT ON TABLE reporte_linaje IS
    'Linaje campo a campo hacia el sistema origen. Sin esto, responder a una observacion '
    'del supervisor exige arqueologia sobre el codigo del proceso.';

-- =====================================================================================
-- 3. ENVÍOS: un reporte se envía, se observa y se rectifica
-- =====================================================================================

CREATE TABLE reporte_envio (
    envio_id          BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    reporte_cod       VARCHAR(20)  NOT NULL,
    version           SMALLINT     NOT NULL,
    periodo           CHAR(6)      NOT NULL,
    fecha_corte       DATE         NOT NULL,
    fecha_limite      DATE         NOT NULL,
    num_envio         SMALLINT     NOT NULL,
    tipo_envio        VARCHAR(15)  NOT NULL,
    estado            VARCHAR(15)  NOT NULL,
    fecha_generacion  TIMESTAMP,
    fecha_envio       TIMESTAMP,
    cant_registros    INTEGER      NOT NULL DEFAULT 0,
    monto_total       NUMERIC(18,2) NOT NULL DEFAULT 0,
    hash_archivo      CHAR(32),
    observacion_sbs   VARCHAR(300),
    CONSTRAINT pk_reporte_envio     PRIMARY KEY (envio_id),
    CONSTRAINT uq_reporte_envio     UNIQUE (reporte_cod, periodo, num_envio),
    CONSTRAINT fk_reporte_envio_def FOREIGN KEY (reporte_cod, version)
                                    REFERENCES reporte_definicion (reporte_cod, version),
    CONSTRAINT ck_reporte_envio_tipo CHECK (tipo_envio IN ('ORIGINAL','RECTIFICATORIO')),
    CONSTRAINT ck_reporte_envio_est  CHECK (estado IN ('EN_PROCESO','VALIDADO','ENVIADO',
                                                        'OBSERVADO','ACEPTADO','RECHAZADO')),
    CONSTRAINT ck_reporte_envio_num  CHECK (num_envio >= 1),
    -- El primer envío es el original; los siguientes, rectificatorios
    CONSTRAINT ck_reporte_envio_coh  CHECK (
        (num_envio = 1 AND tipo_envio = 'ORIGINAL')
     OR (num_envio > 1 AND tipo_envio = 'RECTIFICATORIO')),
    CONSTRAINT ck_reporte_envio_fec  CHECK (fecha_envio IS NULL OR fecha_generacion IS NOT NULL),
    CONSTRAINT ck_reporte_envio_per  CHECK (periodo ~ '^[0-9]{6}$')
);
COMMENT ON TABLE reporte_envio IS
    'Cada remision al supervisor. El rectificatorio NO reemplaza al original: ambos se '
    'conservan, porque el supervisor puede pedir explicar la diferencia.';

-- =====================================================================================
-- 4. DETALLE DEL REPORTE
--    Estructura del Reporte Crediticio de Deudores (simplificada con fines educativos).
-- =====================================================================================

CREATE TABLE reporte_detalle (
    envio_id           BIGINT        NOT NULL,
    num_linea          INTEGER       NOT NULL,
    tipo_doc_cod       CHAR(2)       NOT NULL,
    num_doc            VARCHAR(20)   NOT NULL,
    nombre_deudor      VARCHAR(160)  NOT NULL,
    tipo_credito_cod   CHAR(1)       NOT NULL,
    clasificacion_cod  CHAR(1)       NOT NULL,
    dias_atraso        INTEGER       NOT NULL,
    moneda_cod         CHAR(3)       NOT NULL,
    saldo_capital      NUMERIC(18,2) NOT NULL,
    monto_provision    NUMERIC(18,2) NOT NULL,
    tiene_garantia     CHAR(1)       NOT NULL,
    fecha_corte        DATE          NOT NULL,
    CONSTRAINT pk_reporte_detalle    PRIMARY KEY (envio_id, num_linea),
    CONSTRAINT fk_reporte_detalle_e  FOREIGN KEY (envio_id) REFERENCES reporte_envio (envio_id),
    CONSTRAINT uq_reporte_detalle_d  UNIQUE (envio_id, tipo_doc_cod, num_doc),
    CONSTRAINT ck_reporte_det_clasif CHECK (clasificacion_cod IN ('0','1','2','3','4')),
    CONSTRAINT ck_reporte_det_tipo   CHECK (tipo_credito_cod IN ('1','2','3','4','5','6','7','8')),
    CONSTRAINT ck_reporte_det_gar    CHECK (tiene_garantia IN ('S','N')),
    CONSTRAINT ck_reporte_det_dias   CHECK (dias_atraso >= 0),
    CONSTRAINT ck_reporte_det_saldo  CHECK (saldo_capital >= 0 AND monto_provision >= 0),
    CONSTRAINT ck_reporte_det_prov   CHECK (monto_provision <= saldo_capital)
);
COMMENT ON CONSTRAINT uq_reporte_detalle_d ON reporte_detalle IS
    'Un deudor aparece UNA sola vez por envio. Un deudor duplicado es causal de observacion.';
COMMENT ON CONSTRAINT ck_reporte_det_prov ON reporte_detalle IS
    'La provision no puede superar el saldo: seria un error aritmetico evidente para el supervisor.';

-- =====================================================================================
-- 5. RESULTADO DE LAS VALIDACIONES
-- =====================================================================================

CREATE TABLE reporte_error (
    error_id        BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    envio_id        BIGINT       NOT NULL,
    validacion_cod  VARCHAR(20)  NOT NULL,
    num_linea       INTEGER,
    campo_cod       VARCHAR(40),
    severidad       VARCHAR(10)  NOT NULL,
    detalle         VARCHAR(300) NOT NULL,
    fecha_deteccion TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reporte_error   PRIMARY KEY (error_id),
    CONSTRAINT fk_reporte_error_e FOREIGN KEY (envio_id) REFERENCES reporte_envio (envio_id),
    CONSTRAINT ck_reporte_error_s CHECK (severidad IN ('BLOQUEA','ADVIERTE'))
);

-- =====================================================================================
-- 6. CUADRE CONTABLE
--    El reporte debe cuadrar con la contabilidad. Si no cuadra, no se envía.
-- =====================================================================================

CREATE TABLE cuadre_reporte (
    envio_id          BIGINT        NOT NULL,
    concepto          VARCHAR(40)   NOT NULL,
    valor_reporte     NUMERIC(18,2) NOT NULL,
    valor_contable    NUMERIC(18,2) NOT NULL,
    diferencia        NUMERIC(18,2) NOT NULL,
    tolerancia        NUMERIC(18,2) NOT NULL DEFAULT 0,
    esta_cuadrado     BOOLEAN       NOT NULL,
    CONSTRAINT pk_cuadre_reporte  PRIMARY KEY (envio_id, concepto),
    CONSTRAINT fk_cuadre_reporte  FOREIGN KEY (envio_id) REFERENCES reporte_envio (envio_id),
    CONSTRAINT ck_cuadre_dif      CHECK (diferencia = valor_reporte - valor_contable),
    CONSTRAINT ck_cuadre_estado   CHECK (esta_cuadrado = (ABS(diferencia) <= tolerancia))
);
COMMENT ON CONSTRAINT ck_cuadre_estado ON cuadre_reporte IS
    'El indicador de cuadre NO se digita: se deriva de la diferencia y la tolerancia. '
    'Asi nadie puede marcar como cuadrado algo que no lo esta.';

-- =====================================================================================
-- 7. ÍNDICES
-- =====================================================================================

CREATE INDEX ix_reporte_envio_periodo ON reporte_envio (reporte_cod, periodo);
CREATE INDEX ix_reporte_envio_estado  ON reporte_envio (estado);
CREATE INDEX ix_reporte_detalle_doc   ON reporte_detalle (tipo_doc_cod, num_doc);
CREATE INDEX ix_reporte_detalle_clas  ON reporte_detalle (clasificacion_cod);
CREATE INDEX ix_reporte_error_envio   ON reporte_error (envio_id, severidad);

-- =====================================================================================
-- 8. VISTAS
-- =====================================================================================

CREATE VIEW vw_estado_envios AS
SELECT  e.envio_id,
        e.reporte_cod,
        d.reporte_nombre,
        e.periodo,
        e.fecha_corte,
        e.fecha_limite,
        e.num_envio,
        e.tipo_envio,
        e.estado,
        e.cant_registros,
        e.monto_total,
        e.fecha_envio,
        CASE WHEN e.fecha_envio IS NULL THEN NULL
             ELSE (e.fecha_limite - e.fecha_envio::DATE) END       AS dias_de_holgura,
        COUNT(er.error_id) FILTER (WHERE er.severidad = 'BLOQUEA')  AS errores_bloqueantes,
        COUNT(er.error_id) FILTER (WHERE er.severidad = 'ADVIERTE') AS advertencias,
        BOOL_AND(COALESCE(c.esta_cuadrado, TRUE))                   AS cuadra_contabilidad
FROM        reporte_envio      e
JOIN        reporte_definicion d  ON d.reporte_cod = e.reporte_cod AND d.version = e.version
LEFT JOIN   reporte_error      er ON er.envio_id = e.envio_id
LEFT JOIN   cuadre_reporte     c  ON c.envio_id = e.envio_id
GROUP BY e.envio_id, e.reporte_cod, d.reporte_nombre, e.periodo, e.fecha_corte,
         e.fecha_limite, e.num_envio, e.tipo_envio, e.estado, e.cant_registros,
         e.monto_total, e.fecha_envio;

COMMENT ON VIEW vw_estado_envios IS
    'Tablero de control regulatorio: que se envio, cuando, con cuantos errores y si cuadra.';

CREATE VIEW vw_linaje_reporte AS
SELECT  c.posicion,
        c.campo_cod,
        c.campo_nombre,
        c.tipo_dato,
        c.longitud,
        c.decimales,
        c.es_obligatorio,
        c.dominio,
        l.esquema_origen || '.' || l.tabla_origen ||
            COALESCE('.' || l.columna_origen, '')  AS origen,
        l.transformacion,
        l.responsable,
        c.base_legal
FROM        reporte_campo  c
LEFT JOIN   reporte_linaje l ON l.reporte_cod = c.reporte_cod
                            AND l.version     = c.version
                            AND l.campo_cod   = c.campo_cod
WHERE       c.reporte_cod = 'RCD'
ORDER BY    c.posicion;

COMMENT ON VIEW vw_linaje_reporte IS
    'El documento que se entrega al supervisor: campo por campo, de donde sale y como se calcula.';
