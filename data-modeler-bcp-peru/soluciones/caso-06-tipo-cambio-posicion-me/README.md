# Caso 06 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-06-tipo-cambio-posicion-me/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 366 días de calendario (249 hábiles, 15 feriados) — incluye la semilla del 31-dic, 1 245 cotizaciones
publicadas, 1 830 valores vigentes (**585 por arrastre**), 2 196 saldos ME, 732 posiciones diarias
y **15 reglas de calidad en `OK`**.

---

## Registro de decisiones (ADR)

### ADR-01 — Serie publicada y serie vigente en tablas separadas

**Contexto.** El tipo de cambio solo se publica en días hábiles, pero el negocio necesita valorizar
todos los días.

**Decisión.** `tipo_cambio_publicado` (inmutable, solo días hábiles) y `tipo_cambio_vigente`
(derivada, todos los días, con trazabilidad del arrastre).

**Alternativas evaluadas.**
- *Una sola tabla rellenada*: descartada. Se pierde para siempre la respuesta a "¿qué publicó
  realmente la fuente ese día?", que es la pregunta del auditor.
- *Calcular el arrastre en cada consulta*: funcionalmente correcto, pero repite la lógica en cada
  reporte, es costoso sobre series largas y no deja registro de la decisión aplicada.

**Consecuencias.** Duplicación controlada de datos. La serie vigente debe **recalcularse** cuando
llegan cotizaciones nuevas o correcciones; el bloque que la genera es reejecutable.

---

### ADR-02 — Arrastre (LOCF), nunca interpolación

**Contexto.** Hay que asignar un valor a los días sin cotización.

**Decisión.** Arrastrar el último valor publicado, registrando cuántos días se arrastró.

**Sustento.** El tipo de cambio es un **precio de mercado observado**. Promediar viernes y lunes
para "obtener" el sábado inventa un precio que nunca existió y que nadie puede defender ante una
auditoría. El último precio conocido, en cambio, es el precio vigente en ausencia de mercado.

**Consecuencias.** Los valores arrastrados quedan **identificables** (`origen_valor = 'ARRASTRE'`),
de modo que un reporte puede excluirlos si necesita solo observaciones de mercado — como hace PN-03
al calcular el spread promedio.

---

### ADR-03 — El calendario de días hábiles es una tabla propia

**Contexto.** Hay que distinguir un feriado de una falla de carga.

**Decisión.** `cat_calendario` con `es_feriado`, `nombre_feriado` y `es_dia_habil`.

**Alternativas evaluadas.**
- *Calcular el día hábil con `EXTRACT(ISODOW)`*: detecta fines de semana pero **no feriados**, que
  son precisamente los que generan los arrastres largos.
- *Lista de feriados en el código*: cambia por norma cada año y quedaría duplicada en cada proceso.

**Consecuencias.** El calendario debe mantenerse cada año. A cambio, el monitoreo puede alertar
**solo** por ausencias reales, sin falsos positivos todos los sábados.

---

### ADR-04 — Una única función de conversión

**Contexto.** RN-11: debe existir una sola implementación de la regla de conversión.

**Decisión.** `fn_convertir_a_mn(monto, moneda, fecha, tipo_tc DEFAULT 'CONTABLE_SBS')`.

**Detalles deliberados.**
- El **valor por defecto es el contable**: quien no especifique obtiene el que cuadra con el balance.
- `PEN` se devuelve sin convertir, no multiplicado por 1.
- Devuelve `NULL` si no hay tipo de cambio: **un nulo visible es preferible a un cero silencioso**.

**Consecuencias.** Cambiar la regla de conversión es cambiar una función, no auditar cien reportes.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| Una sola columna "tipo de cambio" | Cada área usa uno distinto sin saberlo | PN-06 |
| Rellenar la tabla publicada | Se pierde el dato original; el auditor no puede verificar | Revisión de diseño |
| Interpolar en vez de arrastrar | Precios que nunca existieron | CAL-08 |
| No tener calendario de feriados | Alertas falsas todos los fines de semana | PN-02 |
| Usar la posición del **mismo** día para el resultado | El resultado por diferencia de cambio sale invertido | Revisión de RN-10 |
| `FLOAT` para el tipo de cambio | Descuadres de centavos al valorizar millones | Revisión de tipos |
| No validar la razonabilidad | `37.25` en vez de `3.725` pasa desapercibido | **CAL-07** |
| Redondear en pasos intermedios | Error acumulado | Revisión del cálculo |

---

## La demostración del caso

**PN-06** valoriza USD 1 000 000 con los cuatro tipos de cambio del mismo día. Las diferencias son
de **miles de soles para un solo saldo**.

Ese resultado es el argumento —concreto y cuantificado— para defender `cat_tipo_cambio` cuando
alguien proponga "simplificar el modelo" dejando una sola columna.

---

## La prueba de fuego

Reemplaza la serie simulada por la **serie real del BCRP** siguiendo
[`carga_bcrp_real.sql`](../../casos/caso-06-tipo-cambio-posicion-me/datos/carga_bcrp_real.sql).

**El modelo no debe cambiar ni una línea, y las 15 reglas deben seguir en `OK`.**

Si el modelo solo funciona con los datos para los que fue escrito, no es un modelo: es un molde.

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 01-05 | Transaccional y analítico: normalización, historia, volumen, dimensional |
| **06** | **Series temporales con huecos, trazabilidad del dato derivado, multimoneda correcta, reglas de razonabilidad** |
