-- =====================================================================================
-- CASO 06 - Tipo de cambio y posición en moneda extranjera
-- Modelo FÍSICO - PostgreSQL 14+
-- =====================================================================================
-- Tema central: SERIES TEMPORALES CON HUECOS.
-- El tipo de cambio NO se publica todos los días (fines de semana y feriados), pero el
-- negocio necesita un valor para TODOS los días. El modelo debe distinguir entre
-- "el dato que publicó la fuente" y "el dato que se usa para valorizar".
-- =====================================================================================

DROP SCHEMA IF EXISTS caso06 CASCADE;
CREATE SCHEMA caso06;
SET search_path TO caso06;

-- =====================================================================================
-- 1. CATÁLOGOS
-- =====================================================================================

CREATE TABLE cat_moneda (
    moneda_cod      CHAR(3)     NOT NULL,
    moneda_desc     VARCHAR(50) NOT NULL,
    es_moneda_local BOOLEAN     NOT NULL DEFAULT FALSE,
    decimales       SMALLINT    NOT NULL DEFAULT 2,
    CONSTRAINT pk_cat_moneda PRIMARY KEY (moneda_cod)
);
COMMENT ON COLUMN cat_moneda.es_moneda_local IS
    'Exactamente una moneda es la local (PEN). Se valida con un indice unico parcial.';

-- Solo puede haber UNA moneda local.
CREATE UNIQUE INDEX uq_cat_moneda_local ON cat_moneda (es_moneda_local) WHERE es_moneda_local;

CREATE TABLE cat_tipo_cambio (
    tipo_tc_cod   VARCHAR(20) NOT NULL,
    tipo_tc_desc  VARCHAR(80) NOT NULL,
    fuente_cod    VARCHAR(15) NOT NULL,
    uso_contable  BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_cat_tipo_cambio PRIMARY KEY (tipo_tc_cod),
    CONSTRAINT ck_cat_tc_fuente   CHECK (fuente_cod IN ('BCRP','SBS','SUNAT','INTERNO'))
);
COMMENT ON TABLE cat_tipo_cambio IS
    'Un mismo dia tiene VARIOS tipos de cambio validos segun el uso: compra, venta, '
    'contable, tributario. Confundirlos es el error clasico del modelado multimoneda.';

CREATE TABLE cat_calendario (
    fecha            DATE        NOT NULL,
    anio             SMALLINT    NOT NULL,
    mes              SMALLINT    NOT NULL,
    periodo          CHAR(6)     NOT NULL,
    dia_semana       SMALLINT    NOT NULL,
    es_fin_semana    BOOLEAN     NOT NULL,
    es_feriado       BOOLEAN     NOT NULL DEFAULT FALSE,
    nombre_feriado   VARCHAR(60),
    es_dia_habil     BOOLEAN     NOT NULL,
    es_fin_mes       BOOLEAN     NOT NULL,
    CONSTRAINT pk_cat_calendario PRIMARY KEY (fecha),
    CONSTRAINT ck_cat_calendario_feriado CHECK (
        (es_feriado = TRUE AND nombre_feriado IS NOT NULL)
     OR (es_feriado = FALSE AND nombre_feriado IS NULL))
);
COMMENT ON TABLE cat_calendario IS
    'Calendario de dias habiles bancarios del Peru. Sin esta tabla no se puede distinguir '
    '"no hubo cotizacion porque era feriado" de "falta el dato".';

-- =====================================================================================
-- 2. SERIE PUBLICADA POR LA FUENTE
--    Grano: una fila por fecha, moneda y tipo de cambio EFECTIVAMENTE PUBLICADO.
--    Los días sin publicación simplemente NO tienen fila. Eso es información, no un error.
-- =====================================================================================

CREATE TABLE tipo_cambio_publicado (
    fecha           DATE           NOT NULL,
    moneda_cod      CHAR(3)        NOT NULL,
    tipo_tc_cod     VARCHAR(20)    NOT NULL,
    valor           NUMERIC(12,6)  NOT NULL,
    codigo_serie    VARCHAR(20),
    fecha_carga     TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_tc_publicado      PRIMARY KEY (fecha, moneda_cod, tipo_tc_cod),
    CONSTRAINT fk_tc_pub_moneda     FOREIGN KEY (moneda_cod)  REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT fk_tc_pub_tipo       FOREIGN KEY (tipo_tc_cod) REFERENCES cat_tipo_cambio (tipo_tc_cod),
    CONSTRAINT fk_tc_pub_calendario FOREIGN KEY (fecha)       REFERENCES cat_calendario (fecha),
    CONSTRAINT ck_tc_pub_valor      CHECK (valor > 0)
);
COMMENT ON TABLE tipo_cambio_publicado IS
    'Serie TAL COMO LA PUBLICA LA FUENTE. No se rellena, no se interpola: es el dato crudo. '
    'Origen: BCRPData (https://estadisticas.bcrp.gob.pe/estadisticas/series/).';
COMMENT ON COLUMN tipo_cambio_publicado.codigo_serie IS
    'Codigo de la serie en BCRPData (ej. PD04640PD). Trazabilidad hacia la fuente.';

-- =====================================================================================
-- 3. SERIE VIGENTE (derivada): un valor para CADA día calendario
--    Aquí se resuelve el hueco, y se deja CONSTANCIA de cómo se resolvió.
-- =====================================================================================

CREATE TABLE tipo_cambio_vigente (
    fecha              DATE          NOT NULL,
    moneda_cod         CHAR(3)       NOT NULL,
    tipo_tc_cod        VARCHAR(20)   NOT NULL,
    valor              NUMERIC(12,6) NOT NULL,
    fecha_cotizacion   DATE          NOT NULL,   -- de qué día viene realmente el valor
    origen_valor       VARCHAR(15)   NOT NULL,   -- PUBLICADO / ARRASTRE
    dias_arrastre      SMALLINT      NOT NULL DEFAULT 0,
    CONSTRAINT pk_tc_vigente        PRIMARY KEY (fecha, moneda_cod, tipo_tc_cod),
    CONSTRAINT fk_tc_vig_moneda     FOREIGN KEY (moneda_cod)  REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT fk_tc_vig_tipo       FOREIGN KEY (tipo_tc_cod) REFERENCES cat_tipo_cambio (tipo_tc_cod),
    CONSTRAINT fk_tc_vig_calendario FOREIGN KEY (fecha)       REFERENCES cat_calendario (fecha),
    CONSTRAINT ck_tc_vig_valor      CHECK (valor > 0),
    CONSTRAINT ck_tc_vig_origen     CHECK (origen_valor IN ('PUBLICADO','ARRASTRE')),
    CONSTRAINT ck_tc_vig_arrastre   CHECK (
        (origen_valor = 'PUBLICADO' AND dias_arrastre = 0 AND fecha_cotizacion = fecha)
     OR (origen_valor = 'ARRASTRE'  AND dias_arrastre > 0 AND fecha_cotizacion < fecha))
);
COMMENT ON TABLE tipo_cambio_vigente IS
    'Serie COMPLETA para valorizar cualquier dia. Conserva la trazabilidad: de que dia '
    'viene el valor y cuantos dias se arrastro. Nunca se pierde el dato original.';
COMMENT ON CONSTRAINT ck_tc_vig_arrastre ON tipo_cambio_vigente IS
    'Impide declarar ARRASTRE con 0 dias o PUBLICADO con fecha de cotizacion distinta.';

-- =====================================================================================
-- 4. POSICIÓN EN MONEDA EXTRANJERA
-- =====================================================================================

CREATE TABLE saldo_me_dia (
    fecha            DATE           NOT NULL,
    moneda_cod       CHAR(3)        NOT NULL,
    cuenta_contable  CHAR(6)        NOT NULL,
    naturaleza       VARCHAR(10)    NOT NULL,   -- ACTIVO / PASIVO
    saldo_me         NUMERIC(18,2)  NOT NULL,
    CONSTRAINT pk_saldo_me          PRIMARY KEY (fecha, moneda_cod, cuenta_contable),
    CONSTRAINT fk_saldo_me_moneda   FOREIGN KEY (moneda_cod) REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT fk_saldo_me_cal      FOREIGN KEY (fecha)      REFERENCES cat_calendario (fecha),
    CONSTRAINT ck_saldo_me_nat      CHECK (naturaleza IN ('ACTIVO','PASIVO'))
);

CREATE TABLE posicion_cambio_dia (
    fecha              DATE           NOT NULL,
    moneda_cod         CHAR(3)        NOT NULL,
    activos_me         NUMERIC(18,2)  NOT NULL,
    pasivos_me         NUMERIC(18,2)  NOT NULL,
    posicion_me        NUMERIC(18,2)  NOT NULL,
    tipo_cambio_cierre NUMERIC(12,6)  NOT NULL,
    posicion_mn        NUMERIC(18,2)  NOT NULL,
    resultado_cambio   NUMERIC(18,2)  NOT NULL DEFAULT 0,
    CONSTRAINT pk_posicion_cambio     PRIMARY KEY (fecha, moneda_cod),
    CONSTRAINT fk_posicion_moneda     FOREIGN KEY (moneda_cod) REFERENCES cat_moneda (moneda_cod),
    CONSTRAINT fk_posicion_calendario FOREIGN KEY (fecha)      REFERENCES cat_calendario (fecha),
    -- El cuadre estructural de la posición de cambio
    CONSTRAINT ck_posicion_cuadre     CHECK (posicion_me = activos_me - pasivos_me),
    CONSTRAINT ck_posicion_mn         CHECK (posicion_mn = ROUND(posicion_me * tipo_cambio_cierre, 2))
);
COMMENT ON TABLE posicion_cambio_dia IS
    'Posicion de cambio diaria: activos menos pasivos en moneda extranjera, valorizada. '
    'Base del control de limites de posicion (sobrecompra / sobreventa).';
COMMENT ON COLUMN posicion_cambio_dia.resultado_cambio IS
    'Efecto en resultados de la variacion del tipo de cambio sobre la posicion del dia anterior.';

-- =====================================================================================
-- 5. FUNCIÓN DE CONVERSIÓN
--    Toda conversión pasa por aquí: una sola implementación de la regla.
-- =====================================================================================

CREATE FUNCTION fn_convertir_a_mn(
    p_monto      NUMERIC,
    p_moneda     CHAR(3),
    p_fecha      DATE,
    p_tipo_tc    VARCHAR(20) DEFAULT 'CONTABLE_SBS'
) RETURNS NUMERIC
LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN p_moneda = 'PEN' THEN ROUND(p_monto, 2)
        ELSE ROUND(p_monto * (SELECT v.valor
                              -- El esquema va CALIFICADO a proposito: sin eso, la funcion solo
                              -- funciona "desde su casa" y falla al invocarla desde otro esquema,
                              -- porque depende del search_path de quien la llama. Es el mismo
                              -- error que documenta el caso 02.
                              FROM   caso06.tipo_cambio_vigente v
                              WHERE  v.fecha       = p_fecha
                                AND  v.moneda_cod  = p_moneda
                                AND  v.tipo_tc_cod = p_tipo_tc), 2)
    END;
$$;
COMMENT ON FUNCTION fn_convertir_a_mn IS
    'Conversion a moneda nacional. Devuelve NULL si no hay tipo de cambio para esa fecha: '
    'es preferible un NULL visible a un numero inventado.';

-- =====================================================================================
-- 6. VISTAS
-- =====================================================================================

CREATE VIEW vw_tipo_cambio_diario AS
SELECT  v.fecha,
        c.periodo,
        c.es_dia_habil,
        v.moneda_cod,
        MAX(v.valor) FILTER (WHERE v.tipo_tc_cod = 'BANCARIO_COMPRA') AS tc_compra,
        MAX(v.valor) FILTER (WHERE v.tipo_tc_cod = 'BANCARIO_VENTA')  AS tc_venta,
        MAX(v.valor) FILTER (WHERE v.tipo_tc_cod = 'CONTABLE_SBS')    AS tc_contable,
        ROUND(MAX(v.valor) FILTER (WHERE v.tipo_tc_cod = 'BANCARIO_VENTA')
            - MAX(v.valor) FILTER (WHERE v.tipo_tc_cod = 'BANCARIO_COMPRA'), 6) AS spread,
        BOOL_OR(v.origen_valor = 'ARRASTRE')                          AS hubo_arrastre,
        MAX(v.dias_arrastre)                                          AS dias_arrastre
FROM    tipo_cambio_vigente v
JOIN    cat_calendario      c ON c.fecha = v.fecha
GROUP BY v.fecha, c.periodo, c.es_dia_habil, v.moneda_cod;

COMMENT ON VIEW vw_tipo_cambio_diario IS
    'Una fila por dia y moneda con los tres tipos de cambio y la marca de arrastre.';

CREATE VIEW vw_variacion_cambiaria AS
SELECT  fecha,
        moneda_cod,
        tc_contable,
        LAG(tc_contable) OVER (PARTITION BY moneda_cod ORDER BY fecha)            AS tc_anterior,
        ROUND(tc_contable - LAG(tc_contable) OVER (PARTITION BY moneda_cod ORDER BY fecha), 6) AS variacion_abs,
        ROUND(100.0 * (tc_contable - LAG(tc_contable) OVER (PARTITION BY moneda_cod ORDER BY fecha))
              / NULLIF(LAG(tc_contable) OVER (PARTITION BY moneda_cod ORDER BY fecha), 0), 4)  AS variacion_pct
FROM    vw_tipo_cambio_diario;

-- =====================================================================================
-- 7. ÍNDICES
-- =====================================================================================

CREATE INDEX ix_tc_pub_moneda_fecha ON tipo_cambio_publicado (moneda_cod, fecha);
CREATE INDEX ix_tc_vig_moneda_fecha ON tipo_cambio_vigente (moneda_cod, fecha);
CREATE INDEX ix_saldo_me_fecha      ON saldo_me_dia (fecha);
CREATE INDEX ix_posicion_fecha      ON posicion_cambio_dia (fecha);
