-- =====================================================================================
-- CASO 07 - PLAFT: monitoreo de operaciones inusuales y sospechosas
-- Modelo FÍSICO - PostgreSQL 14+
-- =====================================================================================
-- Temas: umbrales parametrizados, motor de reglas, detección de fraccionamiento,
--        y DEBER DE RESERVA implementado con seguridad a nivel de fila (RLS).
-- =====================================================================================

DROP SCHEMA IF EXISTS caso07 CASCADE;
CREATE SCHEMA caso07;
SET search_path TO caso07;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

CREATE TABLE cat_moneda (
    moneda_cod  CHAR(3)     NOT NULL,
    moneda_desc VARCHAR(50) NOT NULL,
    CONSTRAINT pk_cat_moneda PRIMARY KEY (moneda_cod)
);

CREATE TABLE cat_tipo_operacion (
    tipo_op_cod   VARCHAR(15) NOT NULL,
    tipo_op_desc  VARCHAR(60) NOT NULL,
    es_efectivo   BOOLEAN     NOT NULL,
    sujeta_a_ro   BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_cat_tipo_operacion PRIMARY KEY (tipo_op_cod)
);
COMMENT ON COLUMN cat_tipo_operacion.sujeta_a_ro IS
    'Si la operacion debe evaluarse para el Registro de Operaciones (RO).';

CREATE TABLE cat_actividad_economica (
    ciiu_cod        CHAR(4)     NOT NULL,
    actividad_desc  VARCHAR(90) NOT NULL,
    nivel_riesgo    SMALLINT    NOT NULL,
    CONSTRAINT pk_cat_actividad PRIMARY KEY (ciiu_cod),
    CONSTRAINT ck_cat_actividad_riesgo CHECK (nivel_riesgo BETWEEN 1 AND 3)
);
COMMENT ON TABLE cat_actividad_economica IS
    'Actividad economica (CIIU) con su nivel de riesgo PLAFT. REFERENCIAL con fines educativos.';

CREATE TABLE cat_pais (
    pais_cod        CHAR(2)     NOT NULL,
    pais_desc       VARCHAR(60) NOT NULL,
    es_alto_riesgo  BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_cat_pais PRIMARY KEY (pais_cod)
);

CREATE TABLE cat_estado_alerta (
    estado_alerta_cod  VARCHAR(15) NOT NULL,
    estado_alerta_desc VARCHAR(60) NOT NULL,
    es_final           BOOLEAN     NOT NULL,
    CONSTRAINT pk_cat_estado_alerta PRIMARY KEY (estado_alerta_cod)
);

CREATE TABLE cat_disposicion (
    disposicion_cod  VARCHAR(20) NOT NULL,
    disposicion_desc VARCHAR(80) NOT NULL,
    genera_ros       BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_cat_disposicion PRIMARY KEY (disposicion_cod)
);
COMMENT ON TABLE cat_disposicion IS
    'Resultado del analisis de un caso. Solo una disposicion genera Reporte de Operaciones Sospechosas.';

-- =====================================================================================
-- 2. PARÁMETROS NORMATIVOS (vigentes por fecha)
--    Los umbrales de PLAFT cambian por norma. Jamás van en el código.
-- =====================================================================================

CREATE TABLE par_umbral (
    umbral_cod      VARCHAR(30)   NOT NULL,
    tipo_op_cod     VARCHAR(15)   NOT NULL,
    moneda_cod      CHAR(3)       NOT NULL,
    monto_umbral    NUMERIC(18,2) NOT NULL,
    ventana_dias    SMALLINT      NOT NULL DEFAULT 1,
    fecha_desde     DATE          NOT NULL,
    fecha_hasta     DATE          NOT NULL DEFAULT DATE '9999-12-31',
    base_legal      VARCHAR(150),
    CONSTRAINT pk_par_umbral      PRIMARY KEY (umbral_cod, tipo_op_cod, moneda_cod, fecha_desde),
    CONSTRAINT fk_par_umbral_tipo FOREIGN KEY (tipo_op_cod) REFERENCES cat_tipo_operacion (tipo_op_cod),
    CONSTRAINT fk_par_umbral_mon  FOREIGN KEY (moneda_cod)  REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT ck_par_umbral_monto CHECK (monto_umbral > 0),
    CONSTRAINT ck_par_umbral_vent  CHECK (ventana_dias >= 1),
    CONSTRAINT ck_par_umbral_vig   CHECK (fecha_hasta >= fecha_desde)
);
COMMENT ON TABLE par_umbral IS
    'Umbrales de registro y de alerta. REFERENCIALES con fines educativos: verificar la '
    'norma vigente de la SBS/UIF-Peru antes de cualquier uso profesional.';
COMMENT ON COLUMN par_umbral.ventana_dias IS
    'Ventana de acumulacion. ventana_dias=1 evalua la operacion individual; >1 detecta '
    'FRACCIONAMIENTO: varias operaciones pequenas que juntas superan el umbral.';

-- =====================================================================================
-- 3. MOTOR DE REGLAS
--    Las reglas son DATOS, no código: se activan, desactivan y versionan sin desplegar.
-- =====================================================================================

CREATE TABLE regla_monitoreo (
    regla_cod       VARCHAR(20)   NOT NULL,
    regla_nombre    VARCHAR(100)  NOT NULL,
    descripcion     VARCHAR(300)  NOT NULL,
    tipo_regla      VARCHAR(20)   NOT NULL,
    severidad       SMALLINT      NOT NULL,
    parametros      JSONB         NOT NULL DEFAULT '{}'::JSONB,
    fecha_desde     DATE          NOT NULL,
    fecha_hasta     DATE          NOT NULL DEFAULT DATE '9999-12-31',
    esta_activa     BOOLEAN       NOT NULL DEFAULT TRUE,
    base_legal      VARCHAR(150),
    CONSTRAINT pk_regla_monitoreo  PRIMARY KEY (regla_cod, fecha_desde),
    CONSTRAINT ck_regla_severidad  CHECK (severidad BETWEEN 1 AND 5),
    CONSTRAINT ck_regla_tipo       CHECK (tipo_regla IN ('UMBRAL','FRACCIONAMIENTO','PERFIL',
                                                          'GEOGRAFICA','COMPORTAMIENTO')),
    CONSTRAINT ck_regla_vig        CHECK (fecha_hasta >= fecha_desde)
);
COMMENT ON COLUMN regla_monitoreo.parametros IS
    'Parametros especificos de la regla en JSONB. Permite reglas heterogeneas sin una columna '
    'por parametro. Cada tipo_regla documenta sus claves esperadas.';

-- =====================================================================================
-- 4. CLIENTE Y SU PERFIL DE RIESGO
-- =====================================================================================

CREATE TABLE cliente (
    cliente_id        BIGINT        GENERATED BY DEFAULT AS IDENTITY,
    tipo_doc_cod      CHAR(2)       NOT NULL,
    num_doc           VARCHAR(20)   NOT NULL,
    nombre_completo   VARCHAR(160)  NOT NULL,
    es_persona_juridica BOOLEAN     NOT NULL DEFAULT FALSE,
    ciiu_cod          CHAR(4),
    pais_residencia   CHAR(2)       NOT NULL,
    fecha_vinculacion DATE          NOT NULL,
    CONSTRAINT pk_cliente        PRIMARY KEY (cliente_id),
    CONSTRAINT uq_cliente_doc    UNIQUE (tipo_doc_cod, num_doc),
    CONSTRAINT fk_cliente_ciiu   FOREIGN KEY (ciiu_cod)        REFERENCES cat_actividad_economica (ciiu_cod),
    CONSTRAINT fk_cliente_pais   FOREIGN KEY (pais_residencia) REFERENCES cat_pais (pais_cod)
);

-- Perfil transaccional ESPERADO, declarado en la debida diligencia (KYC).
-- Es contra este perfil que se compara el comportamiento REAL.
CREATE TABLE cliente_perfil (
    cliente_id          BIGINT        NOT NULL,
    fecha_desde         DATE          NOT NULL,
    fecha_hasta         DATE          NOT NULL DEFAULT DATE '9999-12-31',
    ingreso_declarado   NUMERIC(18,2) NOT NULL,
    monto_esperado_mes  NUMERIC(18,2) NOT NULL,
    num_op_esperadas_mes INTEGER      NOT NULL,
    es_pep              BOOLEAN       NOT NULL DEFAULT FALSE,
    nivel_riesgo        VARCHAR(10)   NOT NULL,
    fecha_ultima_dd     DATE          NOT NULL,
    CONSTRAINT pk_cliente_perfil     PRIMARY KEY (cliente_id, fecha_desde),
    CONSTRAINT fk_cliente_perfil_cli FOREIGN KEY (cliente_id) REFERENCES cliente (cliente_id),
    CONSTRAINT ck_cliente_perfil_niv CHECK (nivel_riesgo IN ('BAJO','MEDIO','ALTO')),
    CONSTRAINT ck_cliente_perfil_vig CHECK (fecha_hasta >= fecha_desde),
    CONSTRAINT ck_cliente_perfil_mon CHECK (monto_esperado_mes >= 0 AND num_op_esperadas_mes >= 0)
);
COMMENT ON TABLE cliente_perfil IS
    'Perfil transaccional ESPERADO (KYC). El monitoreo compara el comportamiento REAL contra este.';
COMMENT ON COLUMN cliente_perfil.es_pep IS
    'Persona Expuesta Politicamente: exige debida diligencia reforzada.';

CREATE UNIQUE INDEX uq_cliente_perfil_vigente
    ON cliente_perfil (cliente_id) WHERE fecha_hasta = DATE '9999-12-31';

-- =====================================================================================
-- 5. OPERACIONES
-- =====================================================================================

CREATE TABLE operacion (
    operacion_id    BIGINT        GENERATED BY DEFAULT AS IDENTITY,
    cliente_id      BIGINT        NOT NULL,
    fecha_operacion TIMESTAMP     NOT NULL,
    fecha_contable  DATE          NOT NULL,
    tipo_op_cod     VARCHAR(15)   NOT NULL,
    moneda_cod      CHAR(3)       NOT NULL,
    monto           NUMERIC(18,2) NOT NULL,
    monto_mn        NUMERIC(18,2) NOT NULL,
    pais_contraparte CHAR(2),
    canal_cod       VARCHAR(10)   NOT NULL,
    num_operacion   VARCHAR(30)   NOT NULL,
    CONSTRAINT pk_operacion        PRIMARY KEY (operacion_id),
    CONSTRAINT uq_operacion_num    UNIQUE (num_operacion),
    CONSTRAINT fk_operacion_cli    FOREIGN KEY (cliente_id)       REFERENCES cliente (cliente_id),
    CONSTRAINT fk_operacion_tipo   FOREIGN KEY (tipo_op_cod)      REFERENCES cat_tipo_operacion (tipo_op_cod),
    CONSTRAINT fk_operacion_mon    FOREIGN KEY (moneda_cod)       REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT fk_operacion_pais   FOREIGN KEY (pais_contraparte) REFERENCES cat_pais (pais_cod),
    CONSTRAINT ck_operacion_monto  CHECK (monto > 0 AND monto_mn > 0)
);

-- Registro de Operaciones: obligación normativa para operaciones sobre umbral.
CREATE TABLE registro_operacion (
    operacion_id    BIGINT        NOT NULL,
    fecha_registro  DATE          NOT NULL,
    umbral_cod      VARCHAR(30)   NOT NULL,
    monto_umbral    NUMERIC(18,2) NOT NULL,
    monto_operacion NUMERIC(18,2) NOT NULL,
    base_legal      VARCHAR(150),
    CONSTRAINT pk_registro_operacion PRIMARY KEY (operacion_id),
    CONSTRAINT fk_registro_op        FOREIGN KEY (operacion_id) REFERENCES operacion (operacion_id),
    CONSTRAINT ck_registro_supera    CHECK (monto_operacion >= monto_umbral)
);
COMMENT ON TABLE registro_operacion IS
    'Registro de Operaciones (RO). Solo entran operaciones que EFECTIVAMENTE superan el umbral: '
    'el CHECK lo garantiza.';

-- =====================================================================================
-- 6. ALERTAS Y CASOS
-- =====================================================================================

CREATE TABLE alerta (
    alerta_id         BIGINT        GENERATED BY DEFAULT AS IDENTITY,
    regla_cod         VARCHAR(20)   NOT NULL,
    cliente_id        BIGINT        NOT NULL,
    fecha_deteccion   DATE          NOT NULL,
    fecha_desde_eval  DATE          NOT NULL,
    fecha_hasta_eval  DATE          NOT NULL,
    cant_operaciones  INTEGER       NOT NULL,
    monto_involucrado NUMERIC(18,2) NOT NULL,
    severidad         SMALLINT      NOT NULL,
    estado_alerta_cod VARCHAR(15)   NOT NULL,
    caso_id           BIGINT,
    detalle           JSONB         NOT NULL DEFAULT '{}'::JSONB,
    CONSTRAINT pk_alerta          PRIMARY KEY (alerta_id),
    CONSTRAINT fk_alerta_cli      FOREIGN KEY (cliente_id)        REFERENCES cliente (cliente_id),
    CONSTRAINT fk_alerta_estado   FOREIGN KEY (estado_alerta_cod) REFERENCES cat_estado_alerta (estado_alerta_cod),
    CONSTRAINT ck_alerta_periodo  CHECK (fecha_hasta_eval >= fecha_desde_eval),
    CONSTRAINT ck_alerta_montos   CHECK (monto_involucrado > 0 AND cant_operaciones > 0),
    CONSTRAINT ck_alerta_sev      CHECK (severidad BETWEEN 1 AND 5)
);
COMMENT ON COLUMN alerta.detalle IS
    'Evidencia de la alerta en JSONB: que se evaluo, contra que umbral, con que valores. '
    'Sin esto, un analista no puede reconstruir por que se genero.';

-- Relación N:M: una alerta puede sustentar un caso; un caso agrupa varias alertas.
CREATE TABLE caso_investigacion (
    caso_id           BIGINT        GENERATED BY DEFAULT AS IDENTITY,
    num_caso          VARCHAR(20)   NOT NULL,
    cliente_id        BIGINT        NOT NULL,
    fecha_apertura    DATE          NOT NULL,
    fecha_cierre      DATE,
    analista          VARCHAR(40)   NOT NULL,
    disposicion_cod   VARCHAR(20),
    monto_total       NUMERIC(18,2) NOT NULL,
    cant_alertas      INTEGER       NOT NULL DEFAULT 0,
    CONSTRAINT pk_caso            PRIMARY KEY (caso_id),
    CONSTRAINT uq_caso_num        UNIQUE (num_caso),
    CONSTRAINT fk_caso_cliente    FOREIGN KEY (cliente_id)      REFERENCES cliente (cliente_id),
    CONSTRAINT fk_caso_disp       FOREIGN KEY (disposicion_cod) REFERENCES cat_disposicion (disposicion_cod),
    CONSTRAINT ck_caso_cierre     CHECK (fecha_cierre IS NULL OR fecha_cierre >= fecha_apertura),
    -- Un caso cerrado SIEMPRE tiene disposición; uno abierto, nunca.
    CONSTRAINT ck_caso_disposicion CHECK (
        (fecha_cierre IS NOT NULL AND disposicion_cod IS NOT NULL)
     OR (fecha_cierre IS NULL     AND disposicion_cod IS NULL))
);

ALTER TABLE alerta
    ADD CONSTRAINT fk_alerta_caso FOREIGN KEY (caso_id) REFERENCES caso_investigacion (caso_id);

-- =====================================================================================
-- 7. REPORTE DE OPERACIONES SOSPECHOSAS (ROS)
--    DEBER DE RESERVA: el acceso se restringe a nivel de fila y todo acceso se registra.
-- =====================================================================================

CREATE TABLE ros (
    ros_id           BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    num_ros          VARCHAR(20)  NOT NULL,
    caso_id          BIGINT       NOT NULL,
    fecha_reporte    DATE         NOT NULL,
    monto_reportado  NUMERIC(18,2) NOT NULL,
    oficial_cumplimiento VARCHAR(40) NOT NULL,
    fecha_envio_uif  DATE,
    CONSTRAINT pk_ros       PRIMARY KEY (ros_id),
    CONSTRAINT uq_ros_num   UNIQUE (num_ros),
    CONSTRAINT uq_ros_caso  UNIQUE (caso_id),
    CONSTRAINT fk_ros_caso  FOREIGN KEY (caso_id) REFERENCES caso_investigacion (caso_id),
    CONSTRAINT ck_ros_envio CHECK (fecha_envio_uif IS NULL OR fecha_envio_uif >= fecha_reporte)
);
COMMENT ON TABLE ros IS
    'Reporte de Operaciones Sospechosas. SUJETO A RESERVA ESTRICTA: esta PROHIBIDO informar '
    'al cliente o a terceros. El modelo aplica seguridad a nivel de fila y bitacora de acceso.';

CREATE TABLE bitacora_acceso_ros (
    acceso_id       BIGINT       GENERATED BY DEFAULT AS IDENTITY,
    ros_id          BIGINT,
    usuario_bd      VARCHAR(50)  NOT NULL,
    fecha_hora      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    tipo_acceso     VARCHAR(15)  NOT NULL,
    motivo          VARCHAR(200),
    CONSTRAINT pk_bitacora_ros   PRIMARY KEY (acceso_id),
    CONSTRAINT ck_bitacora_tipo  CHECK (tipo_acceso IN ('CONSULTA','CREACION','MODIFICACION','ENVIO'))
);
COMMENT ON TABLE bitacora_acceso_ros IS
    'Bitacora de acceso a informacion sujeta a reserva. Exigible ante una revision de la SBS.';

-- Seguridad a nivel de fila sobre el ROS
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_oficial_cumplimiento') THEN
        CREATE ROLE rol_oficial_cumplimiento;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_analista_negocio') THEN
        CREATE ROLE rol_analista_negocio;
    END IF;
END $$;

ALTER TABLE ros ENABLE ROW LEVEL SECURITY;

-- Solo el oficial de cumplimiento ve el ROS. El analista de negocio no ve NADA.
CREATE POLICY pol_ros_cumplimiento ON ros
    FOR ALL TO rol_oficial_cumplimiento
    USING (TRUE);

GRANT USAGE ON SCHEMA caso07 TO rol_oficial_cumplimiento, rol_analista_negocio;
GRANT SELECT ON ros TO rol_oficial_cumplimiento;
-- Deliberadamente NO se otorga SELECT sobre ros a rol_analista_negocio.
GRANT SELECT ON operacion, alerta TO rol_analista_negocio;

COMMENT ON POLICY pol_ros_cumplimiento ON ros IS
    'El deber de reserva se implementa en la BASE DE DATOS, no en la aplicacion: '
    'una consulta directa tampoco puede saltarselo.';

-- =====================================================================================
-- 8. ÍNDICES
-- =====================================================================================

CREATE INDEX ix_operacion_cliente_fecha ON operacion (cliente_id, fecha_contable);
CREATE INDEX ix_operacion_fecha         ON operacion (fecha_contable);
CREATE INDEX ix_operacion_tipo          ON operacion (tipo_op_cod);
CREATE INDEX ix_operacion_pais          ON operacion (pais_contraparte) WHERE pais_contraparte IS NOT NULL;
CREATE INDEX ix_alerta_cliente          ON alerta (cliente_id, fecha_deteccion);
CREATE INDEX ix_alerta_estado           ON alerta (estado_alerta_cod);
CREATE INDEX ix_alerta_regla            ON alerta (regla_cod);
CREATE INDEX ix_caso_analista           ON caso_investigacion (analista);
CREATE INDEX ix_alerta_detalle          ON alerta USING GIN (detalle);

-- =====================================================================================
-- 9. VISTAS
-- =====================================================================================

CREATE VIEW vw_comportamiento_mes AS
SELECT  o.cliente_id,
        TO_CHAR(o.fecha_contable, 'YYYYMM')                        AS periodo,
        COUNT(*)                                                   AS cant_operaciones,
        SUM(o.monto_mn)                                            AS monto_total_mn,
        SUM(o.monto_mn) FILTER (WHERE t.es_efectivo)               AS monto_efectivo_mn,
        COUNT(*) FILTER (WHERE o.pais_contraparte IS NOT NULL)     AS op_internacionales,
        MAX(o.monto_mn)                                            AS operacion_mayor
FROM    operacion o
JOIN    cat_tipo_operacion t ON t.tipo_op_cod = o.tipo_op_cod
GROUP BY o.cliente_id, TO_CHAR(o.fecha_contable, 'YYYYMM');

COMMENT ON VIEW vw_comportamiento_mes IS
    'Comportamiento REAL del cliente por mes. Se compara contra cliente_perfil (lo ESPERADO).';

CREATE VIEW vw_alerta_detalle AS
SELECT  a.alerta_id,
        a.regla_cod,
        r.regla_nombre,
        r.tipo_regla,
        a.severidad,
        c.cliente_id,
        c.nombre_completo,
        c.es_persona_juridica,
        p.nivel_riesgo,
        p.es_pep,
        a.fecha_deteccion,
        a.cant_operaciones,
        a.monto_involucrado,
        a.estado_alerta_cod,
        a.caso_id,
        a.detalle
FROM        alerta a
JOIN        cliente c ON c.cliente_id = a.cliente_id
LEFT JOIN   cliente_perfil p ON p.cliente_id = a.cliente_id
                            AND p.fecha_hasta = DATE '9999-12-31'
LEFT JOIN   regla_monitoreo r ON r.regla_cod = a.regla_cod
                             AND a.fecha_deteccion BETWEEN r.fecha_desde AND r.fecha_hasta;
