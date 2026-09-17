# Caso 07 — Modelo lógico y diccionario

```mermaid
erDiagram
    cat_actividad_economica ||--o{ cliente : clasifica
    cat_pais        ||--o{ cliente : "reside en"
    cat_pais        ||--o{ operacion : "contraparte"
    cat_tipo_operacion ||--o{ operacion : tipifica
    cat_tipo_operacion ||--o{ par_umbral : "define umbral de"
    cat_moneda      ||--o{ operacion : denomina
    cat_moneda      ||--o{ par_umbral : denomina
    cat_estado_alerta ||--o{ alerta : clasifica
    cat_disposicion ||--o{ caso_investigacion : resuelve
    cliente         ||--|{ cliente_perfil : declara
    cliente         ||--o{ operacion : realiza
    cliente         ||--o{ alerta : genera
    cliente         ||--o{ caso_investigacion : "es investigado en"
    operacion       ||--o| registro_operacion : registra
    caso_investigacion ||--o{ alerta : agrupa
    caso_investigacion ||--o| ros : origina
    ros             ||--o{ bitacora_acceso_ros : audita

    cliente {
        BIGINT  cliente_id PK
        CHAR    tipo_doc_cod UK
        VARCHAR num_doc UK "DATO PERSONAL"
        VARCHAR nombre_completo "DATO PERSONAL"
        BOOLEAN es_persona_juridica
        CHAR    ciiu_cod FK
        CHAR    pais_residencia FK
    }
    cliente_perfil {
        BIGINT  cliente_id PK,FK
        DATE    fecha_desde PK
        DATE    fecha_hasta
        NUMERIC ingreso_declarado "DATO SENSIBLE"
        NUMERIC monto_esperado_mes
        INTEGER num_op_esperadas_mes
        BOOLEAN es_pep
        VARCHAR nivel_riesgo
        DATE    fecha_ultima_dd
    }
    par_umbral {
        VARCHAR umbral_cod PK
        VARCHAR tipo_op_cod PK,FK
        CHAR    moneda_cod PK,FK
        DATE    fecha_desde PK
        NUMERIC monto_umbral
        SMALLINT ventana_dias "1=individual, >1=fraccionamiento"
        DATE    fecha_hasta
        VARCHAR base_legal
    }
    regla_monitoreo {
        VARCHAR regla_cod PK
        DATE    fecha_desde PK
        VARCHAR regla_nombre
        VARCHAR tipo_regla
        SMALLINT severidad
        JSONB   parametros
        DATE    fecha_hasta
        BOOLEAN esta_activa
        VARCHAR base_legal
    }
    operacion {
        BIGINT    operacion_id PK
        BIGINT    cliente_id FK
        TIMESTAMP fecha_operacion
        DATE      fecha_contable
        VARCHAR   tipo_op_cod FK
        CHAR      moneda_cod FK
        NUMERIC   monto
        NUMERIC   monto_mn
        CHAR      pais_contraparte FK
        VARCHAR   num_operacion UK
    }
    registro_operacion {
        BIGINT  operacion_id PK,FK
        DATE    fecha_registro
        VARCHAR umbral_cod
        NUMERIC monto_umbral
        NUMERIC monto_operacion
        VARCHAR base_legal
    }
    alerta {
        BIGINT  alerta_id PK
        VARCHAR regla_cod
        BIGINT  cliente_id FK
        DATE    fecha_deteccion
        DATE    fecha_desde_eval
        DATE    fecha_hasta_eval
        INTEGER cant_operaciones
        NUMERIC monto_involucrado
        SMALLINT severidad
        VARCHAR estado_alerta_cod FK
        BIGINT  caso_id FK
        JSONB   detalle "EVIDENCIA"
    }
    caso_investigacion {
        BIGINT  caso_id PK
        VARCHAR num_caso UK
        BIGINT  cliente_id FK
        DATE    fecha_apertura
        DATE    fecha_cierre
        VARCHAR analista
        VARCHAR disposicion_cod FK
        NUMERIC monto_total
        INTEGER cant_alertas
    }
    ros {
        BIGINT  ros_id PK
        VARCHAR num_ros UK
        BIGINT  caso_id FK,UK
        DATE    fecha_reporte
        NUMERIC monto_reportado
        VARCHAR oficial_cumplimiento
        DATE    fecha_envio_uif
    }
    bitacora_acceso_ros {
        BIGINT    acceso_id PK
        BIGINT    ros_id
        VARCHAR   usuario_bd
        TIMESTAMP fecha_hora
        VARCHAR   tipo_acceso
        VARCHAR   motivo
    }
```

---

## Los dos usos de `ventana_dias`

Una sola columna soporta dos reglas distintas:

| `ventana_dias` | Significado | Regla que lo usa |
|---|---|---|
| `1` | Evalúa la **operación individual** contra el umbral | R01-UMBRAL |
| `5` | Evalúa el **acumulado de 5 días** contra el mismo umbral | R02-FRACC |

Modelar la ventana como parámetro —y no como dos tablas— permite que cambiar "el fraccionamiento se
evalúa en 7 días" sea un `UPDATE`.

---

## Las restricciones que hacen el trabajo

| Constraint | Qué impide | Consecuencia normativa de no tenerla |
|---|---|---|
| `ck_registro_supera` | Registrar en el RO una operación bajo el umbral | Registro inflado que distorsiona el reporte |
| `ck_caso_disposicion` | Cerrar un caso sin disposición | Casos cerrados sin sustento documentado |
| `uq_cliente_perfil_vigente` | Dos perfiles vigentes simultáneos | Ambigüedad sobre contra qué se evaluó |
| `uq_ros_caso` | Dos ROS para el mismo caso | Duplicación del reporte ante la UIF |
| `ck_alerta_sev` | Severidad fuera de 1-5 | Priorización sin escala válida |
| **Política RLS sobre `ros`** | Que un rol no autorizado lea el ROS | **Violación del deber de reserva** |

---

## Uso de `JSONB`: dos usos legítimos

| Campo | Contenido | Por qué JSONB y no columnas |
|---|---|---|
| `regla_monitoreo.parametros` | Parámetros específicos de cada tipo de regla | Cada tipo necesita claves distintas; una columna por parámetro daría una tabla mayormente nula |
| `alerta.detalle` | Evidencia de la detección | La evidencia depende de la regla: la de fraccionamiento no se parece a la geográfica |

**Cuándo `JSONB` es correcto:** la estructura varía legítimamente por fila y el conjunto de claves
no es estable.
**Cuándo no:** cuando se usa para evitar modelar. Si siempre guarda las mismas cinco claves, esas
cinco claves son columnas.

Para consultarlo con rendimiento se indexa:

```sql
CREATE INDEX ix_alerta_detalle ON alerta USING GIN (detalle);
```

Y se consulta con los operadores de JSONB:

```sql
WHERE (detalle ->> 'operacion_mayor')::NUMERIC < (detalle ->> 'umbral_individual')::NUMERIC
```

---

## Diccionario de datos (extracto)

### `alerta`

| Columna | Tipo | Nulo | Dominio / regla | Descripción | Sensibilidad |
|---|---|---|---|---|---|
| `alerta_id` | BIGINT | No | Identidad | Identificador | Interno |
| `regla_cod` | VARCHAR(20) | No | Regla vigente a la fecha (CAL-02) | Regla que la produjo | Interno |
| `cliente_id` | BIGINT | No | FK | Cliente alertado | **Confidencial** |
| `fecha_desde_eval` / `fecha_hasta_eval` | DATE | No | `hasta >= desde` | Ventana evaluada | Interno |
| `cant_operaciones` | INTEGER | No | > 0 | Operaciones involucradas | **Confidencial** |
| `monto_involucrado` | NUMERIC(18,2) | No | > 0 | Monto de la alerta | **Confidencial** |
| `severidad` | SMALLINT | No | 1 a 5 | Prioridad | Interno |
| `estado_alerta_cod` | VARCHAR(15) | No | FK | Estado de atención | Interno |
| `caso_id` | BIGINT | Sí | Obligatorio si ESCALADA (CAL-05) | Caso al que se escaló | **Confidencial** |
| `detalle` | JSONB | No | No vacío (CAL-15) | **Evidencia** de la detección | **Confidencial** |

### `cliente_perfil` — el dato más sensible del caso

| Columna | Sensibilidad | Tratamiento |
|---|---|---|
| `ingreso_declarado` | **DATO SENSIBLE** (Ley 29733) | Acceso mínimo; prohibido en ambientes no productivos |
| `es_pep` | **Confidencial** | Condición personal con implicancias reputacionales |
| `nivel_riesgo` | **Confidencial** | No debe ser visible para áreas comerciales |

### `ros` — régimen especial

| Aspecto | Tratamiento |
|---|---|
| Acceso | **Solo** `rol_oficial_cumplimiento`, vía política RLS |
| Auditoría | Todo acceso se registra en `bitacora_acceso_ros` |
| Comunicación | **Prohibido** informar al cliente o a terceros |
| Ambientes no productivos | **No se replica**, ni siquiera enmascarado |

---

## Matriz source-to-target

| Destino | Campo | Origen | Transformación | Calidad |
|---|---|---|---|---|
| `operacion` | `monto_mn` | Core transaccional | Conversión a soles con el TC de la fecha (ver caso 06) | > 0 |
| `registro_operacion` | todo | **Derivado** | Operación ⋈ `par_umbral` vigente, filtrando `monto_mn >= umbral` | CAL-01, CAL-10 |
| `alerta` (R01) | `detalle` | **Derivado** | `JSONB_BUILD_OBJECT` con operación, umbral y exceso | CAL-15 |
| `alerta` (R02) | `monto_involucrado` | **Derivado** | `SUM() OVER (RANGE BETWEEN INTERVAL '4 days' PRECEDING…)` | CAL-07 |
| `alerta` (R03) | `detalle` | `vw_comportamiento_mes` ⋈ `cliente_perfil` | Factor real/esperado | CAL-15 |
| `caso_investigacion` | `monto_total` | **Derivado** | `SUM(monto_involucrado)` de sus alertas | CAL-12 |
| `ros` | todo | `caso_investigacion` | Solo disposiciones con `genera_ros` | CAL-04 |

### La transformación crítica

```sql
WINDOW w AS (PARTITION BY o.cliente_id ORDER BY o.fecha_contable
             RANGE BETWEEN INTERVAL '4 days' PRECEDING AND CURRENT ROW)
```

`RANGE` con `INTERVAL` define la ventana por **tiempo transcurrido**, no por número de filas.
`ROWS BETWEEN 3 PRECEDING` sería incorrecto: cuatro operaciones pueden estar separadas por meses.
