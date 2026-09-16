# Caso 02 — Originación de créditos de consumo y clasificación del deudor

**Dificultad:** ★★☆☆☆ · **Tiempo estimado:** 6 a 8 horas · **Esquema:** `caso02`
**Técnicas:** dominios regulatorios · parámetros vigentes por fecha · máquina de estados · snapshot mensual

---

## 1. Situación de negocio

El banco quiere lanzar un **crédito de consumo 100 % digital**. La Gerencia de Riesgos advierte un
problema serio: el sistema actual guarda la clasificación del deudor como **texto libre** y los
tramos de días de atraso están **escritos dentro del código** del proceso batch. Cada vez que la SBS
modifica un tramo, el área de TI necesita seis semanas de desarrollo, y en el último cambio
normativo el reporte regulatorio salió con errores.

Te encargan modelar la originación de créditos de consumo **de forma que un cambio normativo sea un
cambio de datos y no de código**.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Un deudor se identifica por tipo y número de documento. |
| RN-02 | Una solicitud de crédito pertenece a un deudor y recorre estos estados: Ingresada → En evaluación → Aprobada / Rechazada / Desistida → Desembolsada. |
| RN-03 | Debe conservarse **toda la historia de estados**, con fecha, hora y usuario. No basta el estado actual. |
| RN-04 | Toda solicitud **rechazada** debe tener un motivo de rechazo. Ninguna solicitud no rechazada puede tenerlo. |
| RN-05 | Cada solicitud evaluada genera **una** evaluación crediticia: score, ingreso verificado, deuda en el sistema, cuota estimada y ratio cuota/ingreso. |
| RN-06 | La evaluación registra la **peor clasificación del deudor en el sistema financiero** (regla de alineamiento). |
| RN-07 | Un crédito desembolsado proviene de **exactamente una** solicitud, y una solicitud genera como máximo un crédito. |
| RN-08 | Todo crédito tiene un **cronograma de cuotas**; cada cuota se descompone en capital, interés y seguro de desgravamen. |
| RN-09 | La suma de los capitales del cronograma debe ser **exactamente** el monto desembolsado (sin centavos perdidos). |
| RN-10 | El tipo de crédito debe pertenecer a los **ocho tipos** de la Res. SBS N.º 11356-2008. |
| RN-11 | La clasificación del deudor debe pertenecer a las **cinco categorías** SBS: Normal, CPP, Deficiente, Dudoso, Pérdida. |
| RN-12 | La clasificación se determina por **días de atraso**, según tramos que **dependen del tipo de crédito** y **cambian por norma**. |
| RN-13 | Debe existir una **foto mensual** de cada deudor: días de atraso, clasificación, saldo y provisión, para reconstruir cualquier mes pasado. |
| RN-14 | La provisión se calcula como saldo × tasa, donde la tasa depende de la clasificación y de si hay garantía preferida. |
| RN-15 | Debe poder responderse: "si la SBS cambia este tramo, ¿cuánta provisión adicional necesito?" **sin modificar el modelo**. |

## 3. Normativa aplicable

| Norma | Exigencia |
|---|---|
| **Res. SBS N.º 11356-2008** | Ocho tipos de crédito, cinco categorías de clasificación, criterio de días de atraso diferenciado entre minorista y no minorista, alineamiento |
| Ley 29733 | El **ingreso económico** es dato sensible; el documento es dato personal |
| Reportes SBS | La foto mensual del deudor alimenta el reporte regulatorio (ver caso 10) |

> ⚠️ Los tramos y tasas usados en el caso son **referenciales con fines educativos**. Verifica el
> texto vigente en <https://www.sbs.gob.pe/normativa>.

## 4. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál es la tasa de aprobación por canal de venta? ¿Los canales digitales aprueban más? |
| PN-02 | ¿Cuáles son los principales motivos de rechazo y qué score promedio tienen? |
| PN-03 | ¿Cuánto se desembolsó por mes y tipo de crédito? ¿Cuál es el ticket promedio? |
| PN-04 | ¿Cómo se distribuye la cartera por clasificación SBS en el último periodo? |
| PN-05 | ¿Cómo evolucionan mensualmente la cartera no normal y las provisiones? |
| PN-06 | ¿Cuántos deudores **migraron** de categoría entre dos meses? (matriz de transición) |
| PN-07 | ¿Qué créditos tienen cuotas vencidas y cuál es su mayor atraso? |
| PN-08 | ¿Se deterioran más las colocaciones de unos meses que de otros? (análisis de cosecha) |
| PN-09 | ¿Cuánto demora una solicitud desde el ingreso hasta el desembolso, por canal? |
| PN-10 | Si la SBS endurece el tramo de CPP, ¿cuánta provisión adicional se necesitaría? |

## 5. Criterios de aceptación

- [ ] Los tramos de días de atraso viven en **una tabla con vigencia**, no en el código ni en un `CASE`.
- [ ] Existe una **función** que devuelve la clasificación a partir de (tipo de crédito, días, fecha).
- [ ] Una regla de calidad verifica que **toda** clasificación registrada coincide con la que
      devuelve la función. Cero excepciones.
- [ ] La suma de capitales del cronograma es exactamente el monto desembolsado (sin descuadres de centavos).
- [ ] Es imposible registrar un rechazo sin motivo.
- [ ] Es imposible registrar dos créditos para la misma solicitud.
- [ ] La matriz de transición (PN-06) se obtiene con una sola consulta sobre el snapshot mensual.
- [ ] PN-10 se responde **sin modificar el modelo**.

## 6. Trampas del caso

1. **El `CASE WHEN dias BETWEEN 9 AND 30 THEN 'CPP'`** dentro de una vista o de un procedimiento es
   exactamente el error que te pidieron corregir. Si lo escribes, fallaste el caso.
2. **¿Snapshot mensual o SCD2?** Ambos guardan historia. ¿Cuál conviene para un reporte con corte
   mensual obligatorio? Sustenta tu elección.
3. **El redondeo del cronograma.** Si repartes el capital con `ROUND(monto/n, 2)` en todas las
   cuotas, perderás centavos. ¿Dónde absorbes la diferencia?
4. **La clasificación es del DEUDOR, no de la operación.** Un deudor con tres créditos tiene una
   sola clasificación (por alineamiento). ¿Tu granularidad lo refleja?
5. **`tiene_garantia` afecta la tasa de provisión.** ¿Está en la llave del parámetro?
