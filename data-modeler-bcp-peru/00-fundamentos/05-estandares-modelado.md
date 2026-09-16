# Estándares de modelado del repositorio

> Todo modelo profesional se rige por un estándar escrito. Este es el que siguen los 10 casos.
> Cópialo y adáptalo a tu organización: lo importante no es *cuál* estándar uses, sino que **exista,
> esté escrito y se cumpla sin excepciones**.

---

## 1. Nomenclatura

### 1.1 Reglas generales

| Regla | Valor |
|---|---|
| Idioma | **Español** (el negocio bancario peruano opera en español) |
| Formato | `snake_case`, todo en minúsculas |
| Caracteres | Solo `a-z`, `0-9`, `_`. **Sin tildes ni ñ** en nombres de objetos |
| Longitud máxima | 30 caracteres (compatibilidad con Oracle) |
| Plural/singular | **Singular** para entidades: `cliente`, no `clientes` |
| Abreviaturas | Solo las del catálogo aprobado (sección 1.4) |

### 1.2 Prefijos por tipo de objeto

| Prefijo | Tipo de objeto | Ejemplo |
|---|---|---|
| *(ninguno)* | Entidad transaccional (OLTP) | `cuenta`, `movimiento` |
| `cat_` | Catálogo / tabla de dominio | `cat_moneda`, `cat_tipo_credito` |
| `dim_` | Dimensión (modelo estrella) | `dim_cliente`, `dim_tiempo` |
| `fact_` | Tabla de hechos | `fact_saldo_mensual` |
| `stg_` | Área de preparación (staging) | `stg_movimiento_core` |
| `hub_` / `lnk_` / `sat_` | Data Vault: Hub / Link / Satélite | `hub_persona`, `lnk_persona_hogar`, `sat_persona_demografia` |
| `vw_` | Vista | `vw_saldo_cliente` |
| `mv_` | Vista materializada | `mv_colocacion_mensual` |
| `par_` | Parámetro vigente por fecha | `par_umbral_plaft` |

### 1.3 Sufijos por tipo de columna

| Sufijo / prefijo | Significado | Tipo |
|---|---|---|
| `_id` | Identificador (PK o FK) | `BIGINT` / `INTEGER` |
| `_cod` | Código de negocio con significado | `VARCHAR` |
| `_desc` | Descripción | `VARCHAR` |
| `fecha_` | Fecha sin hora | `DATE` |
| `fecha_hora_` | Marca de tiempo | `TIMESTAMP` |
| `monto_` / `saldo_` | Importe monetario | `NUMERIC(18,2)` |
| `tasa_` / `pct_` | Porcentaje o tasa | `NUMERIC(9,6)` |
| `cant_` / `num_` | Conteo | `INTEGER` |
| `es_` / `tiene_` | Booleano | `BOOLEAN` |
| `_desde` / `_hasta` | Vigencia (SCD2) | `DATE` |

### 1.4 Abreviaturas aprobadas

| Abreviatura | Significado |
|---|---|
| `mn` | Moneda nacional (soles) |
| `me` | Moneda extranjera |
| `tc` | Tipo de cambio |
| `doc` | Documento de identidad |
| `cta` | Cuenta |
| `mov` | Movimiento |
| `clas` | Clasificación |
| `prov` | Provisión |
| `ubi` | Ubigeo |

### 1.5 Nombres de constraints

```
pk_<tabla>                      pk_cuenta
fk_<tabla>_<tabla_referida>     fk_movimiento_cuenta
uq_<tabla>_<columnas>           uq_cliente_num_doc
ck_<tabla>_<regla>              ck_movimiento_monto_positivo
ix_<tabla>_<columnas>           ix_movimiento_cuenta_fecha
```

---

## 2. Tipos de dato — reglas duras

| Concepto | Tipo obligatorio | Prohibido | Motivo |
|---|---|---|---|
| Dinero | `NUMERIC(18,2)` | `FLOAT`, `REAL`, `DOUBLE` | Los errores de redondeo no cuadran con contabilidad |
| Tasa de interés | `NUMERIC(9,6)` | `FLOAT` | Precisión exacta en cálculos |
| Tipo de cambio | `NUMERIC(12,6)` | `FLOAT` | El BCRP publica 3 a 4 decimales; se reserva margen |
| Fecha contable | `DATE` | `VARCHAR` | Comparaciones y rangos correctos |
| Evento con hora | `TIMESTAMP` | `VARCHAR`, epoch en `INT` | Zona horaria y orden |
| Identificador interno | `BIGINT GENERATED ALWAYS AS IDENTITY` | `UUID` como PK en tablas masivas | Tamaño de índice y localidad |
| Código regulado | `CHAR(n)` o `VARCHAR(n)` + FK a catálogo | texto libre | Dominio cerrado |
| Booleano | `BOOLEAN` | `CHAR(1)` con `'S'/'N'` | Claridad y no ambigüedad |
| Documento de identidad | `VARCHAR(20)` | `INTEGER` | Puede tener ceros a la izquierda y letras (CE, pasaporte) |
| Ubigeo | `CHAR(6)` | `INTEGER` | Los ceros a la izquierda son significativos |

> **El error clásico:** guardar el DNI como número. `07654321` se convierte en `7654321` y deja de
> cruzar con el padrón. Es el bug más repetido en banca peruana.

---

## 3. Reglas de llaves

1. **Toda tabla tiene PK declarada.** Sin excepción.
2. **Llave sustituta** (`BIGINT` identidad) en tablas de alto volumen y en dimensiones.
3. **Llave natural** solo si es estable, regulada y no cambia: `ubigeo`, `codigo_moneda_iso`.
4. Cuando se usa llave sustituta, **la llave natural se protege con `UNIQUE`**.
5. **Toda FK se declara** en el modelo físico, aun cuando por rendimiento se decida no validarla en
   cargas masivas (en ese caso se documenta y se valida por SQL).
6. **Prohibido** usar datos personales como PK (DNI, correo): cambian, se corrigen y bloquean el
   derecho de cancelación de la Ley 29733.

---

## 4. Columnas de auditoría

Toda tabla persistente lleva, como mínimo:

```sql
fecha_hora_creacion    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
usuario_creacion       VARCHAR(50)   NOT NULL DEFAULT CURRENT_USER,
fecha_hora_modificacion TIMESTAMP,
usuario_modificacion   VARCHAR(50)
```

En capas analíticas se añade:

```sql
fecha_carga            DATE          NOT NULL,   -- cuándo entró al almacén
sistema_origen         VARCHAR(30)   NOT NULL    -- de qué fuente vino (linaje)
```

---

## 5. Patrones obligatorios

### 5.1 Catálogo (tabla de dominio)

```sql
CREATE TABLE cat_moneda (
    moneda_cod      CHAR(3)     NOT NULL,
    moneda_desc     VARCHAR(50) NOT NULL,
    es_vigente      BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_cat_moneda PRIMARY KEY (moneda_cod)
);
```

Un dominio regulado **nunca** va como texto libre ni como `CHECK` con lista incrustada si puede
cambiar por norma: va en catálogo, para que un cambio normativo sea un `INSERT`.

### 5.2 SCD tipo 2 (historia de atributos)

```sql
CREATE TABLE dim_cliente (
    cliente_sk      BIGINT GENERATED ALWAYS AS IDENTITY,  -- clave sustituta
    cliente_id      BIGINT      NOT NULL,                 -- clave natural del negocio
    segmento_cod    VARCHAR(10) NOT NULL,
    fecha_desde     DATE        NOT NULL,
    fecha_hasta     DATE        NOT NULL DEFAULT DATE '9999-12-31',
    es_vigente      BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_dim_cliente PRIMARY KEY (cliente_sk),
    CONSTRAINT ck_dim_cliente_vigencia CHECK (fecha_hasta >= fecha_desde)
);
```

Regla: **nunca** dos filas vigentes para la misma clave natural. Se valida por SQL en cada carga.

### 5.3 Parámetro vigente por fecha

```sql
CREATE TABLE par_umbral (
    umbral_cod      VARCHAR(30)     NOT NULL,
    moneda_cod      CHAR(3)         NOT NULL,
    monto_umbral    NUMERIC(18,2)   NOT NULL,
    fecha_desde     DATE            NOT NULL,
    fecha_hasta     DATE            NOT NULL DEFAULT DATE '9999-12-31',
    base_legal      VARCHAR(200),
    CONSTRAINT pk_par_umbral PRIMARY KEY (umbral_cod, moneda_cod, fecha_desde)
);
```

Todo valor que pueda cambiar por norma **vive en una tabla con vigencia**, nunca en el código.

### 5.4 Multimoneda

Toda tabla con importes lleva:

```sql
moneda_cod   CHAR(3)        NOT NULL REFERENCES cat_moneda(moneda_cod),
monto        NUMERIC(18,2)  NOT NULL,
monto_mn     NUMERIC(18,2)                  -- equivalente en soles, con TC de la fecha
```

`monto_mn` es una **desnormalización deliberada y documentada**: evita recalcular el tipo de cambio
en cada consulta analítica. Se documenta en el registro de decisiones.

---

## 6. Antipatrones prohibidos en este repositorio

| Antipatrón | Alternativa correcta |
|---|---|
| `campo_libre_1`, `campo_libre_2`… | Modelar el atributo real, o usar `JSONB` acotado y documentado |
| Tabla "maestra" con 200 columnas de todo | Separar por entidad y ciclo de vida |
| Guardar `total` sin poder reconstruirlo | Guardar el detalle; el total es derivado o snapshot documentado |
| Estado sin historia | SCD2 o tabla de eventos de cambio de estado |
| Fechas como `VARCHAR(8)` `'20260916'` | `DATE` |
| Borrado físico de operaciones | Borrado lógico + bitácora |
| `SELECT *` en vistas de consumo | Columnas explícitas (protege ante cambios de esquema) |
| Lógica de negocio solo en el reporte | Lógica en el modelo (constraints, catálogos, capas) |

---

## 7. Convención de esquemas de este repositorio

Cada caso vive en su propio esquema de PostgreSQL, para poder ejecutarlos todos en la misma base
sin colisiones:

| Caso | Esquema |
|---|---|
| 01 | `caso01` |
| 02 | `caso02` |
| … | … |
| 10 | `caso10` |

Cada script `03-modelo-fisico.sql` empieza con:

```sql
DROP SCHEMA IF EXISTS casoNN CASCADE;
CREATE SCHEMA casoNN;
SET search_path TO casoNN;
```

Esto hace que **los scripts sean reejecutables (idempotentes)**, requisito para poder validarlos
automáticamente.

---

## 8. Plantilla de diccionario de datos

Cada solución incluye su diccionario con este formato:

| Columna | Tipo | Nulo | Dominio / regla | Descripción de negocio | Origen | Sensibilidad |
|---|---|---|---|---|---|---|
| `cliente_id` | BIGINT | No | Identidad | Identificador interno del cliente | Core | Interno |
| `num_doc` | VARCHAR(20) | No | Único por tipo de documento | Número de documento de identidad | Core | **Dato personal** |
| `saldo_disponible` | NUMERIC(18,2) | No | ≥ 0 | Saldo que el cliente puede retirar | Core | Confidencial |

---

## 9. Plantilla de decisión de diseño (ADR)

```markdown
## ADR-001: Llave sustituta en dim_cliente

**Contexto:** el DNI cambia de formato y se corrige; además es dato personal.
**Decisión:** usar clave sustituta `cliente_sk` y `UNIQUE (tipo_doc, num_doc)`.
**Alternativas evaluadas:** DNI como PK (descartada: bloquea el derecho de cancelación).
**Consecuencias:** toda FK apunta a `cliente_sk`; el cruce con fuentes externas usa la clave natural.
**Fecha / autor:** 2026-09-16 / Equipo de Arquitectura de Datos
```
