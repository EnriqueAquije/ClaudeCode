# Caso 09 — Fuentes de datos

## 1. Naturaleza de los datos

> **100 % SINTÉTICOS.** Ninguna persona, hogar ni respuesta corresponde a un encuestado real.
> La **estructura** de las llaves de negocio sí reproduce la de los microdatos reales de la ENAHO.

| Elemento | Origen | Nota |
|---|---|---|
| Llave de negocio del hogar | **Estructura real de la ENAHO** | `conglomerado + vivienda + hogar + año` |
| Variables demográficas | Sintéticas, con **categorías reales** | Nivel educativo y situación laboral siguen las categorías de la encuesta |
| Ingresos | Sintéticos | Rangos plausibles para el Perú |
| Tenencia de productos | Sintética | Tasas de inclusión aproximadas |
| Ubigeos | **Reales** (muestra INEI de 12 distritos) | Ver caso 01 |
| Motivos de no uso de canales digitales | Categorías plausibles | Inspiradas en las que releva la encuesta |

---

## 2. Fuente real: microdatos del INEI

```
Fuente:         Instituto Nacional de Estadística e Informática (INEI)
Recurso:        Microdatos - Encuesta Nacional de Hogares (ENAHO)
URL:            https://proyectos.inei.gob.pe/microdatos/
Portal INEI:    https://www.inei.gob.pe/
Datos abiertos: https://www.datosabiertos.gob.pe/
Fecha acceso:   2026-09-16
Licencia/uso:   Microdatos públicos. La descarga requiere completar un formulario GRATUITO.
                Revisar las condiciones de uso publicadas por el INEI.
Formato:        SPSS (.sav), STATA (.dta) y CSV, organizados por módulo
Uso aquí:       ESTRUCTURA de la llave de negocio del hogar y categorías de las variables.
                Los valores son sintéticos.
```

### Estructura de la ENAHO que el caso reproduce

Los microdatos se organizan en **módulos**, y la llave que los une es la del hogar:

| Campo | Descripción | En el modelo |
|---|---|---|
| `CONGLOME` | Conglomerado de muestreo | `hub_hogar.conglomerado_bk` |
| `VIVIENDA` | Vivienda dentro del conglomerado | `hub_hogar.vivienda_bk` |
| `HOGAR` | Hogar dentro de la vivienda | `hub_hogar.hogar_bk` |
| `CODPERSO` | Persona dentro del hogar | *(el caso usa documento como llave de persona)* |
| `AÑO` | Año de la encuesta | `hub_hogar.anio_bk` |
| `UBIGEO` | Distrito | `hub_distrito.ubigeo_bk` |

> **Por eso la llave del hub de hogar es compuesta.** No es un capricho del ejercicio: es la llave
> real de la encuesta. Un modelo que la reemplazara por un autoincremental perdería la capacidad de
> cruzar módulos y de comparar olas.

### Módulos útiles para inclusión financiera

| Módulo | Contenido | Uso en el caso |
|---|---|---|
| Características de la vivienda y del hogar | Agua, luz, internet, área urbana/rural | `sat_hogar_caracteristicas` |
| Características de los miembros del hogar | Edad, sexo, educación | `sat_persona_demografia` |
| Empleo e ingresos | Ingresos, formalidad, ocupación | `sat_persona_ingreso` |
| Sumaria | Agregados por hogar | Validación cruzada |

---

## 3. Cómo trabajar con la ENAHO real

```bash
# 1. Descargar desde https://proyectos.inei.gob.pe/microdatos/
#    Seleccionar: Encuesta Nacional de Hogares -> año -> módulo -> formato CSV
```

```sql
-- 2. Staging: todo en texto, como siempre con archivos externos
CREATE TABLE stg_enaho_hogar (
    anio TEXT, conglome TEXT, vivienda TEXT, hogar TEXT, ubigeo TEXT,
    estrato TEXT, p110 TEXT, p1121 TEXT, mieperho TEXT
);

-- \copy stg_enaho_hogar FROM 'enaho_modulo01.csv' WITH (FORMAT csv, HEADER true)

-- 3. Cargar el hub (idempotente: si la llave ya existe, no se duplica)
INSERT INTO hub_hogar (hogar_hk, conglomerado_bk, vivienda_bk, hogar_bk, anio_bk,
                       fecha_carga, sistema_origen)
SELECT DISTINCT
       fn_hash_key(conglome, vivienda, hogar, anio),
       conglome, vivienda, hogar, anio, CURRENT_TIMESTAMP, 'ENAHO_REAL'
FROM   stg_enaho_hogar
ON CONFLICT (hogar_hk) DO NOTHING;

-- 4. Cargar el satélite SOLO si cambió
--    (mismo patrón con hash_diff de la sección 2.2 de carga_datos.sql)
```

> **El modelo no cambia.** Cambian los valores y el `sistema_origen`. Esa es la prueba de que el
> Data Vault está bien construido: absorbe una fuente real sin alterar su estructura.

---

## 4. ⚠️ Protección de datos en microdatos de encuestas

Los microdatos del INEI se publican **anonimizados**: no contienen nombres ni documentos. Este caso,
en cambio, usa un documento sintético como llave de persona para poder demostrar el cruce con los
sistemas del banco.

**Si trabajas con ENAHO real:**

| Regla | Por qué |
|---|---|
| **No intentes reidentificar** a los encuestados | Viola las condiciones de uso y la Ley 29733 |
| **No cruces** los microdatos con bases nominales del banco | Un cruce por ubigeo + edad + sexo + ingreso puede reidentificar a una persona en un distrito pequeño |
| Usa los microdatos para **análisis agregado** | Es su finalidad declarada |
| Respeta los **factores de expansión** | Sin ellos, los porcentajes no representan a la población |

> **Nota metodológica importante:** una encuesta por muestreo **no** se analiza contando filas. Cada
> registro tiene un **factor de expansión** que indica a cuántas personas representa. Este caso los
> omite deliberadamente para centrarse en el modelado, pero un análisis real que los ignore **da
> cifras incorrectas**.

---

## 5. Fuentes complementarias de inclusión financiera

| Fuente | Qué aporta | URL |
|---|---|---|
| **SBS — indicadores de inclusión financiera** | Cobertura de canales y puntos de atención por distrito | <https://www.sbs.gob.pe/> |
| **Global Findex (Banco Mundial)** | Indicadores comparables entre países | <https://data.worldbank.org/> |
| **FMI — Financial Access Survey** | Acceso a servicios financieros por país | <https://data.imf.org/> |
| **INEI — ENAPRES** | Acceso a servicios del Estado, incluidos financieros | <https://proyectos.inei.gob.pe/microdatos/> |
| **BCRP** | Estadísticas de sistemas de pago | <https://estadisticas.bcrp.gob.pe/estadisticas/series/> |

Todas son de acceso público y gratuito, y todas se integrarían al Data Vault **como satélites o
hubs adicionales**, sin modificar lo existente.
