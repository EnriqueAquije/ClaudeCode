# Caso 10 — Fuentes de datos

## 1. Naturaleza de los datos

> **El detalle del reporte NO es sintético en este caso: se extrae del `caso02`.**
> Esa es justamente la lección. Un reporte regulatorio no se "arma": se **deriva** de los sistemas
> transaccionales. Los datos del `caso02` sí son sintéticos, pero para el `caso10` cumplen el papel
> del **sistema origen**, y el modelo los trata como tal.

| Elemento | Origen | Nota |
|---|---|---|
| Deudores, créditos, saldos, días de atraso | **`caso02` (sistema de originación y seguimiento)** | Extraídos con `SELECT`, no digitados |
| Clasificación del deudor | **`caso02.fn_clasificar()`** | La misma función que usa el sistema fuente |
| Códigos de tipo de crédito (1–8) | **Res. SBS N.º 11356-2008** | Dominio real |
| Códigos de clasificación (0–4) | **Res. SBS N.º 11356-2008** | Dominio real |
| Estructura del archivo (campos, posiciones, longitudes) | **Simplificación educativa** | La estructura real la publica la SBS |
| Valores contables del cuadre | Sintéticos | Simulan el saldo de los libros |
| Observaciones de la SBS | Sintéticas | Redactadas al estilo de una observación de supervisor |

> ⚠️ **Este material no es guía de cumplimiento regulatorio.** La estructura, los plazos y los
> dominios reales los define la SBS y cambian con el tiempo. Aquí se reproduce el **mecanismo de
> modelado**, no el formato oficial vigente.

---

## 2. Fuente real: normativa y reportes de la SBS

```
Fuente:         Superintendencia de Banca, Seguros y AFP del Perú (SBS)
Portal:         https://www.sbs.gob.pe/
Normativa:      https://www.sbs.gob.pe/normativa
Estadísticas:   https://www.sbs.gob.pe/estadisticas-y-publicaciones
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de un organismo del Estado peruano.
                Consulta y descarga gratuitas.
Uso aquí:       DOMINIOS reales (tipos de crédito, clasificaciones) y la ESTRUCTURA CONCEPTUAL
                del ciclo de remisión: envío, observación, rectificatorio.
```

### Normas que sustentan el modelo

| Norma | Qué exige | Dónde se ve en el modelo |
|---|---|---|
| **Res. SBS N.º 11356-2008** — Evaluación y clasificación del deudor | 8 tipos de crédito y 5 categorías de clasificación | `ck_reporte_det_tipo`, `ck_reporte_det_clasif` |
| **Ley 26702** — Ley General del Sistema Financiero | Facultad de la SBS de requerir información | `reporte_definicion.base_legal` |
| **Manual de Contabilidad para las Empresas del Sistema Financiero** | El reporte debe ser consistente con los libros | `cuadre_reporte` |
| **Ley 29733** — Protección de Datos Personales | El nombre del deudor es dato personal | Ver sección 5 |

### El dominio de clasificación (real)

| Código | Categoría | Referencia |
|---|---|---|
| `0` | Normal | Res. SBS N.º 11356-2008 |
| `1` | Con Problemas Potenciales (CPP) | Res. SBS N.º 11356-2008 |
| `2` | Deficiente | Res. SBS N.º 11356-2008 |
| `3` | Dudoso | Res. SBS N.º 11356-2008 |
| `4` | Pérdida | Res. SBS N.º 11356-2008 |

> **Por qué el código es `CHAR(1)` y no `SMALLINT`:** es un **código**, no una cantidad. No se suma,
> no se promedia, y el archivo de ancho fijo lo transporta como carácter. Ver
> `00-fundamentos/05-estandares-modelado.md`.

---

## 3. Cómo obtener la estructura real de un reporte

La SBS publica los formatos, los instructivos y los plazos de los reportes y anexos en su portal de
normativa. El procedimiento que sigue un data modeler es siempre el mismo:

```
1. Ubicar la resolución que aprueba el reporte y su instructivo de llenado.
2. Extraer de ese instructivo, campo por campo:
       posición · nombre · tipo · longitud · decimales · obligatoriedad · dominio
3. Cargar eso en `reporte_campo`, con el número de versión y su vigencia.
4. Extraer del mismo instructivo las validaciones que aplica el supervisor.
5. Cargar eso en `reporte_validacion`, con severidad y base legal.
6. Documentar el linaje: qué tabla y qué columna del core alimentan cada campo.
```

**El paso 3 es el que distingue a un data modeler de un programador.** El programador escribe el
instructivo en el código; el data modeler lo escribe en tablas. Cuando la SBS publique la siguiente
versión, el primero abre un proyecto y el segundo hace un `INSERT`.

---

## 4. Requisito previo: el `caso02` cargado

Este caso **no genera deudores**. Los extrae:

```sql
-- Comprobación previa (está al inicio de carga_datos.sql):
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'caso02') THEN
        RAISE EXCEPTION 'Falta el esquema caso02. Cargue primero el caso 02.';
    END IF;
END $$;
```

Si el esquema no está, el script **se detiene**. Es deliberado: un proceso regulatorio que arranca
sin su fuente produce un archivo vacío, y un archivo vacío remitido a tiempo es peor que uno tardío.

Orden de carga:

```bash
psql -d bcp_lab -f soluciones/caso-02-originacion-creditos/03-modelo-fisico.sql
psql -d bcp_lab -f casos/caso-02-originacion-creditos/datos/carga_datos.sql
psql -d bcp_lab -f soluciones/caso-10-reporte-regulatorio-sbs/03-modelo-fisico.sql
psql -d bcp_lab -f casos/caso-10-reporte-regulatorio-sbs/datos/carga_datos.sql
```

---

## 5. ⚠️ Protección de datos: el reporte contiene datos personales

El detalle del reporte contiene **documento de identidad, nombre completo, deuda y clasificación**
de personas naturales. En datos reales eso es, simultáneamente:

| Marco | Consecuencia |
|---|---|
| **Ley 29733** (Protección de Datos Personales) | Tratamiento con finalidad determinada: la remisión al supervisor |
| **Ley 26702, art. 140** (secreto bancario) | La remisión a la SBS está amparada por ley; **cualquier otro destino, no** |
| **Res. SBS N.º 11356-2008** | La clasificación del deudor es información reservada |

**Reglas prácticas si trabajas con el reporte real:**

| Regla | Por qué |
|---|---|
| **No copies el archivo a un entorno de desarrollo** | Es el incidente de fuga más común en un banco |
| Si necesitas probar, **enmascara documento y nombre** | Conserva el formato, destruye la identidad |
| El acceso a `reporte_detalle` va **por rol**, no por persona | Trazabilidad de quién consultó qué |
| Los archivos generados **se cifran y se retienen con plazo definido** | Conservación ≠ acumulación indefinida |
| **Nunca envíes el archivo por correo** | Ni siquiera "para revisar rápido" |

> En este caso los nombres son sintéticos y generados por el `caso02`. **No corresponden a ninguna
> persona real.**

---

## 6. Fuentes complementarias

| Fuente | Qué aporta | URL |
|---|---|---|
| **SBS — Normativa** | Resoluciones, formatos e instructivos de reportes | <https://www.sbs.gob.pe/normativa> |
| **SBS — Estadísticas** | Series de cartera, morosidad y clasificación del sistema | <https://www.sbs.gob.pe/estadisticas-y-publicaciones> |
| **BCRP** | Series monetarias y de crédito para contrastar magnitudes | <https://estadisticas.bcrp.gob.pe/estadisticas/series/> |
| **UIF-Perú (dentro de la SBS)** | Reportes de operaciones sospechosas — otro régimen de remisión | <https://www.sbs.gob.pe/> |
| **Portal de Datos Abiertos del Perú** | Conjuntos de datos públicos del Estado | <https://www.datosabiertos.gob.pe/> |

Para contrastar las cifras del caso con la realidad del sistema financiero peruano, las estadísticas
de la SBS publican la distribución de la cartera por clasificación. **El orden de magnitud del caso
—mayoría en Normal, cola larga en Pérdida— reproduce ese perfil**, aunque los valores sean sintéticos.
