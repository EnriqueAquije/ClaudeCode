# Caso 08 — Modelo lógico y diccionario

```mermaid
erDiagram
    cat_fuente          ||--o{ cliente_fuente : aporta
    cat_fuente          ||--o{ regla_supervivencia : "fuente preferida"
    cliente_fuente      ||--|| calidad_registro : mide
    cliente_fuente      ||--o{ match_candidato : "compara (a)"
    cliente_fuente      ||--o{ match_candidato : "compara (b)"
    cat_regla_match         ||--o{ match_candidato : evalua
    cliente_fuente      ||--|| cliente_xref : vincula
    cliente_maestro     ||--|{ cliente_xref : agrupa
    cliente_maestro     ||--|{ cliente_maestro_linaje : traza
    cliente_fuente      ||--o{ cliente_maestro_linaje : "aporta valor"

    cat_fuente {
        VARCHAR  fuente_cod PK
        VARCHAR  fuente_nombre
        SMALLINT precedencia UK "UNIQUE: sin empates"
        BOOLEAN  es_externa
        BOOLEAN  es_autoritativa_doc
    }
    cliente_fuente {
        VARCHAR fuente_cod PK,FK
        VARCHAR id_origen PK
        CHAR    tipo_doc_cod
        VARCHAR num_doc "DATO PERSONAL"
        VARCHAR ape_paterno
        VARCHAR nombres
        VARCHAR razon_social
        DATE    fecha_nacimiento
        CHAR    ubigeo
        VARCHAR direccion
        VARCHAR telefono
        VARCHAR correo
        CHAR    ciiu_cod
        DATE    fecha_actualizacion
        VARCHAR nombre_normalizado "GENERADA"
    }
    calidad_registro {
        VARCHAR  fuente_cod PK,FK
        VARCHAR  id_origen PK,FK
        SMALLINT campos_completos
        NUMERIC  pct_completitud
        BOOLEAN  doc_valido
        INTEGER  antiguedad_dias
        NUMERIC  score_calidad
    }
    cat_regla_match {
        VARCHAR regla_cod PK
        VARCHAR tipo_match
        NUMERIC score_asignado
        NUMERIC umbral_auto
        BOOLEAN esta_activa
    }
    match_candidato {
        BIGINT  candidato_id PK
        VARCHAR fuente_a FK
        VARCHAR id_origen_a FK
        VARCHAR fuente_b FK
        VARCHAR id_origen_b FK
        VARCHAR regla_cod FK
        NUMERIC score
        VARCHAR decision
        JSONB   evidencia
    }
    regla_supervivencia {
        VARCHAR atributo PK
        VARCHAR criterio "PRECEDENCIA/MAS_RECIENTE/FUENTE_FIJA"
        VARCHAR fuente_preferida FK
    }
    cliente_maestro {
        BIGINT  cliente_maestro_id PK
        CHAR    tipo_doc_cod UK
        VARCHAR num_doc UK
        VARCHAR nombre_completo
        BOOLEAN es_persona_juridica
        DATE    fecha_nacimiento
        CHAR    ubigeo
        VARCHAR direccion
        VARCHAR telefono
        VARCHAR correo
        CHAR    ciiu_cod
        SMALLINT cant_fuentes
        NUMERIC score_confianza
    }
    cliente_xref {
        VARCHAR fuente_cod PK,FK
        VARCHAR id_origen PK,FK
        BIGINT  cliente_maestro_id FK
        VARCHAR tipo_vinculo
        NUMERIC score_vinculo
    }
    cliente_maestro_linaje {
        BIGINT  cliente_maestro_id PK,FK
        VARCHAR atributo PK
        VARCHAR fuente_cod FK
        VARCHAR id_origen FK
        VARCHAR criterio_aplicado
    }
```

---

## Las claves primarias que codifican las reglas

| Tabla | PK | Regla que impone |
|---|---|---|
| `cliente_fuente` | `(fuente_cod, id_origen)` | Cada sistema mantiene su propio identificador |
| **`cliente_xref`** | **`(fuente_cod, id_origen)`** | **Un registro de origen pertenece a UN solo maestro** (RN-12) |
| `cliente_maestro` | `cliente_maestro_id` + `UNIQUE (tipo_doc_cod, num_doc)` | Un maestro por documento |
| `cliente_maestro_linaje` | `(cliente_maestro_id, atributo)` | Un solo origen por atributo |
| `cat_fuente` | `fuente_cod` + **`UNIQUE (precedencia)`** | **Sin empates de autoridad** |

> **La PK de `cliente_xref` es la decisión de diseño más importante del modelo.** Ponerla sobre
> `(cliente_maestro_id, fuente_cod, id_origen)` permitiría que un registro cuelgue de dos maestros,
> y ese es exactamente el estado corrupto que un MDM debe impedir.

---

## Los tres criterios de supervivencia en SQL

```sql
-- PRECEDENCIA
ORDER BY (f.valor IS NULL), rc.precedencia LIMIT 1

-- MAS_RECIENTE
ORDER BY (f.valor IS NULL), rc.fecha_actualizacion DESC LIMIT 1

-- FUENTE_FIJA (SUNAT)
ORDER BY (f.valor IS NULL), (rc.fuente_cod <> 'PADRON_SUNAT'), rc.precedencia LIMIT 1
```

### El detalle que cambia el resultado

`(f.valor IS NULL)` **primero** en el `ORDER BY`. Sin él, una fuente de precedencia 1 que **no tiene
el dato** ganaría con un `NULL`, dejando el maestro incompleto aunque otra fuente sí tuviera el
valor.

Es una línea. Es la diferencia entre un maestro útil y uno lleno de nulos.

---

## Diccionario de datos (extracto)

### `cliente_maestro` — el golden record

| Columna | Tipo | Nulo | Regla | Descripción | Sensibilidad |
|---|---|---|---|---|---|
| `cliente_maestro_id` | BIGINT | No | PK, identidad | Identificador único del cliente real | Interno |
| `tipo_doc_cod` + `num_doc` | CHAR(2)+VARCHAR(20) | No | **UNIQUE** | Clave natural de negocio | **Dato personal** |
| `nombre_completo` | VARCHAR(200) | No | Supervivencia por PRECEDENCIA | Nombre ganador | **Dato personal** |
| `fecha_nacimiento` | DATE | Sí | Supervivencia por PRECEDENCIA | Fecha ganadora | **Dato personal** |
| `ubigeo`, `direccion` | — | Sí | Supervivencia por MAS_RECIENTE | Ubicación más fresca | **Dato personal** |
| `telefono`, `correo` | — | Sí | Supervivencia por MAS_RECIENTE | Contacto más fresco | **Dato personal** |
| `ciiu_cod` | CHAR(4) | Sí | Supervivencia por FUENTE_FIJA (SUNAT) | Actividad económica | Interno |
| `cant_fuentes` | SMALLINT | No | = fuentes distintas en xref (CAL-03) | En cuántos sistemas existe | Interno |
| `score_confianza` | NUMERIC(5,2) | No | 0 a 100 | Promedio de calidad de sus registros | Interno |

### `match_candidato.evidencia` (JSONB)

Contenido según la regla:

| Regla | Claves |
|---|---|
| M01 | `tipo_doc`, `num_doc`, `criterio` |
| M02 | `doc_crm`, `doc_core`, `distancia_edicion`, `nombre`, `fecha_nac`, `criterio` |
| M03 | `nombre`, `fecha_nac`, `doc_a`, `doc_b`, `distancia_edicion`, `criterio` |

Sin esta evidencia, una fusión no se puede auditar ni revertir con criterio.

---

## Nota de protección de datos

Este modelo concentra **todos los datos personales de todos los sistemas** en un solo lugar. Eso lo
hace enormemente útil y, a la vez, el activo más sensible de la organización.

| Exigencia (Ley 29733) | Cómo lo aborda el modelo |
|---|---|
| Minimización | Solo se integran atributos con finalidad declarada |
| Finalidad | El MDM sirve a identificación y gobierno, no a cualquier uso |
| Derecho de cancelación | Requiere borrar/anonimizar el maestro, su linaje y su xref — el orden importa por las FK |
| Enmascaramiento | Obligatorio en ambientes no productivos: **especialmente aquí** |
| Registro del banco de datos | Un maestro de clientes es un banco de datos personales inscribible |

---

## Matriz source-to-target

| Destino | Campo | Origen | Transformación | Calidad |
|---|---|---|---|---|
| `cliente_fuente` | todo | 6 sistemas | **Ninguna**: se conserva el dato crudo | — |
| `cliente_fuente` | `nombre_normalizado` | Derivado | Columna generada: mayúsculas, sin espacios múltiples | — |
| `calidad_registro` | `score_calidad` | Derivado | 60% completitud + 25% validez del documento + 15% frescura | CAL-11 |
| `match_candidato` | M01 | `cliente_fuente` ⋈ sí mismo | Igualdad de `(tipo_doc, num_doc)` entre fuentes distintas | CAL-08 |
| `match_candidato` | M02 | CRM ⋈ CORE_CAPTACIONES | Igualdad de nombre y fecha + `LEVENSHTEIN(doc) <= 2` | CAL-08 |
| `match_candidato` | M03 | `cliente_fuente` ⋈ sí mismo | Igualdad de nombre y fecha + `LEVENSHTEIN(doc) > 2` → `REVISION` | **CAL-09** |
| `cliente_maestro` | cada atributo | Cluster de registros | Regla de supervivencia del atributo | CAL-07 |
| `cliente_xref` | todo | Cluster | Un registro de origen → un maestro | CAL-13 |
| `cliente_maestro_linaje` | todo | Derivado del ganador | Qué registro aportó el valor | CAL-06 |
