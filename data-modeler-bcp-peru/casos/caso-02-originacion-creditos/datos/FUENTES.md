# Caso 02 — Fuentes de datos

## 1. Naturaleza de los datos

> **Datos 100 % SINTÉTICOS y determinísticos.** Ninguna persona, deudor ni operación real está
> representada. No existe ni puede existir una fuente pública peruana de historial crediticio
> individual: está protegida por el secreto bancario (Ley 26702) y la Ley 29733.

| Elemento | Origen | Nota |
|---|---|---|
| Deudores, solicitudes, créditos | Generados por fórmula | Documentos en rango sintético reservado |
| **Tipos de crédito (8)** | **Reales**: Res. SBS N.º 11356-2008 | Dominio regulatorio |
| **Categorías de clasificación (5)** | **Reales**: Res. SBS N.º 11356-2008 | Normal, CPP, Deficiente, Dudoso, Pérdida |
| Tramos de días de atraso | **Referenciales**, basados en la norma | ⚠️ Verificar texto vigente antes de uso profesional |
| Tasas de provisión | **Referenciales** | ⚠️ Simplificadas con fines educativos |
| Scores y ratios | Generados por fórmula | Rangos plausibles, no corresponden a ningún motor real |

---

## 2. Fuentes regulatorias

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:        Resolución S.B.S. N.º 11356-2008 - Reglamento para la Evaluación y
                Clasificación del Deudor y la Exigencia de Provisiones
URL:            https://www.sbs.gob.pe/portals/0/jer/pfrpv_normatividad/20160719_res-11356-2008.pdf
Buscador:       https://www.sbs.gob.pe/normativa
Fecha acceso:   2026-09-16
Licencia/uso:   Norma pública de libre acceso
Uso aquí:       Catálogos cat_tipo_credito y cat_clasificacion; estructura de
                par_clasificacion_dias y par_provision; regla de alineamiento
Advertencia:    La resolución ha sido modificada por normas posteriores. Los tramos y tasas
                cargados en carga_datos.sql son REFERENCIALES con fines educativos y NO deben
                usarse para cálculos regulatorios reales.
```

```
Fuente:         SBS - Información Estadística de Banca Múltiple
URL:            https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1
Uso aquí:       Referencia para calibrar órdenes de magnitud de morosidad y estructura de
                cartera por categoría de riesgo del sistema financiero peruano
Transformación: Solo calibración cualitativa. NO se usaron cifras de la SBS en los datos.
```

```
Fuente:         Ley N.º 29733 - Ley de Protección de Datos Personales
URL:            https://www.gob.pe/institucion/congreso-de-la-republica/normas-legales/243470-29733
Uso aquí:       Clasificación de `deudor.ingreso_declarado` e `ingreso_verificado` como
                DATO SENSIBLE (ingresos económicos), con tratamiento reforzado
```

---

## 3. Dataset abierto de referencia (estructura de evaluación crediticia)

La estructura de la tabla `evaluacion_crediticia` (score, propósito, plazo, situación laboral,
antigüedad, ratio de endeudamiento) sigue el patrón de variables del dataset académico más usado
en riesgo de crédito:

```
Fuente:         UCI Machine Learning Repository
Dataset:        Statlog (German Credit Data)
URL:            https://archive.ics.uci.edu/dataset/144/statlog+german+credit+data
Licencia:       Creative Commons Attribution 4.0 International (CC BY 4.0)
Fecha acceso:   2026-09-16
Uso aquí:       ESTRUCTURA de variables de evaluación crediticia. Los valores fueron
                REGENERADOS y adaptados al contexto peruano (soles, DNI, tipos de crédito SBS).
                No se copiaron registros del dataset original.
```

Dataset complementario, útil si amplías el caso hacia comportamiento de pago:

```
Dataset:        Default of Credit Card Clients
URL:            https://archive.ics.uci.edu/dataset/350/default+of+credit+card+clients
Licencia:       CC BY 4.0
Uso:            Ver caso 03 (tarjetas de crédito)
```

---

## 4. Cómo trabajar este caso con datos reales

| Qué | Fuente real | Cómo |
|---|---|---|
| Tramos y tasas vigentes | SBS, norma vigente | Reemplaza las filas de `par_clasificacion_dias` y `par_provision`, y **cierra la vigencia** de las anteriores (no las borres) |
| Estructura de cartera del sistema | SBS, Banca Múltiple | Calibra la distribución por categoría |
| Variables de scoring | UCI German Credit | Carga el CSV a una tabla `stg_` y mapea sus variables al modelo |

**Nunca** uses datos reales de deudores para practicar.
