# Caso 08 — Fuentes de datos

## 1. Naturaleza de los datos

> Este caso **integra los clientes de otros cuatro casos del repositorio** (01, 02, 04 y 07), todos
> sintéticos, y añade dos fuentes propias: un CRM con errores de digitación y un padrón SUNAT
> simulado. **Los duplicados y los homónimos están insertados a propósito.**

| Fuente en el modelo | De dónde sale | Qué aporta al ejercicio |
|---|---|---|
| `CORE_CAPTACIONES` | `caso01.cliente` (500) | Datos completos y validados |
| `CORE_CREDITOS` | `caso02.deudor` (900) | Otro sistema, otros ids |
| `BILLETERA` | `caso04.usuario_billetera` (3 000) | Alta cobertura, pocos atributos |
| `MONITOREO` | `caso07.cliente` (800) | Actividad económica y personas jurídicas |
| `CRM` | **Generado**: duplicados de `caso01` con transposición de dígitos + homónimos | El material del matching probabilístico |
| `PADRON_SUNAT` | **Generado** con el formato del padrón real | Fuente externa autoritativa |

### Patrones insertados deliberadamente

| Patrón | Cómo se insertó | Qué regla lo detecta | Decisión esperada |
|---|---|---|---|
| Mismo documento en varios sistemas | Emerge de la integración | M01-DOC-EXACTO | `AUTO_MATCH` |
| **Error de digitación** | 107 registros CRM con los dos últimos dígitos del DNI transpuestos | M02-DOC-TIPEO | `AUTO_MATCH` |
| **Homónimos** | 12 registros CRM con el mismo nombre y fecha de nacimiento pero documento totalmente distinto | M03-NOMBRE-FECHA | **`REVISION`** |

---

## 2. Fuente externa real: Padrón Reducido del RUC (SUNAT)

```
Fuente:         Superintendencia Nacional de Aduanas y de Administración Tributaria (SUNAT)
Recurso:        Padrón Reducido del RUC
URL descarga:   https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html
Otros padrones: https://www.sunat.gob.pe/padronesnotificaciones/
Consulta RUC:   https://e-consultaruc.sunat.gob.pe/
Portal abierto: https://www.datosabiertos.gob.pe/dataset/padrón-ruc-superintendencia-nacional-de-aduanas-y-de-administración-tributaria-sunat
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de libre acceso, publicada periódicamente por SUNAT
Formato:        ZIP con archivo de texto delimitado (varios millones de filas)
Uso aquí:       ESTRUCTURA de la fuente externa autoritativa: RUC, razón social, estado,
                condición, dirección, ubigeo y actividad económica (CIIU).
Transformación: El padrón del caso es SINTÉTICO y pequeño (88 registros). Los datos reales
                no se incluyen por tamaño y porque el repositorio no debe distribuir datos
                de contribuyentes.
```

### ⚠️ Advertencia de protección de datos

El padrón reducido **contiene datos personales** de personas naturales con RUC (nombre y dirección
del negocio). Aunque es de acceso público:

- La **Ley N.º 29733 aplica al tratamiento posterior**: que un dato sea público no autoriza
  cualquier uso.
- **No debe redistribuirse** en un repositorio ni publicarse en un tablero accesible.
- Debe usarse solo para la **finalidad declarada** (en banca: validación de identidad y debida
  diligencia).
- En ambientes no productivos debe ir **enmascarado**.

Por eso este repositorio **no incluye el padrón real**, solo su estructura.

---

## 3. Cómo usar el padrón real

```bash
# 1. Descargar (archivo grande: varios cientos de MB comprimido)
curl -O https://www.sunat.gob.pe/descargaPRR/padron_reducido_ruc.zip
unzip padron_reducido_ruc.zip

# 2. Tomar una muestra para practicar (el archivo completo es innecesario)
head -50000 padron_reducido_ruc.txt > muestra_ruc.txt
```

```sql
-- 3. Área de staging: TODO en texto, como siempre con archivos externos
CREATE TABLE stg_padron_ruc (
    ruc           TEXT, razon_social TEXT, estado        TEXT,
    condicion     TEXT, ubigeo       TEXT, tipo_via      TEXT,
    nombre_via    TEXT, numero       TEXT, ciiu          TEXT
);

-- \copy stg_padron_ruc FROM 'muestra_ruc.txt' WITH (FORMAT csv, DELIMITER '|', HEADER true)

-- 4. Revisar ANTES de transformar (el formato puede variar entre publicaciones)
-- SELECT * FROM stg_padron_ruc LIMIT 20;

-- 5. Cargar a cliente_fuente
-- INSERT INTO cliente_fuente (fuente_cod, id_origen, tipo_doc_cod, num_doc, razon_social,
--                             ubigeo, direccion, ciiu_cod, fecha_actualizacion)
-- SELECT 'PADRON_SUNAT', ruc, '06', ruc, razon_social, ubigeo,
--        TRIM(tipo_via || ' ' || nombre_via || ' ' || numero),
--        LEFT(ciiu, 4), CURRENT_DATE
-- FROM   stg_padron_ruc
-- WHERE  ruc ~ '^[0-9]{11}$';
```

> **El modelo no cambia.** Solo cambia el origen de una de las seis fuentes. Esa es la prueba de que
> `cliente_fuente` está bien diseñada: absorbe una fuente nueva sin alterar la estructura.

---

## 4. Otras fuentes de validación de identidad en el Perú

| Fuente | Qué valida | Acceso |
|---|---|---|
| **RENIEC** | Identidad de personas naturales (DNI) | **No público**. Las entidades financieras acceden mediante convenio y con base legal |
| **SUNAT — padrón RUC** | Personas jurídicas y naturales con negocio | **Público y gratuito** |
| **SBS — Central de Riesgos** | Situación crediticia | Acceso restringido a entidades supervisadas |
| **SMV** | Empresas listadas y sus vinculadas | Público |

> Un proceso de MDM bancario real cruza con **RENIEC** para validar identidad. Este caso usa solo
> SUNAT porque es la única de acceso público. La estructura del modelo es la misma: una fuente más
> en `cat_fuente`, con su precedencia.

---

## 5. Sobre la metodología

Los conceptos aplicados (golden record, matching determinista y probabilístico, reglas de
supervivencia, referencia cruzada, data stewardship) son estándar de la disciplina de **Master Data
Management** y están descritos en la literatura de gestión de datos, incluido el marco **DAMA-DMBOK**.

Este repositorio los **implementa y valida en SQL**; no reproduce texto de ninguna fuente.
