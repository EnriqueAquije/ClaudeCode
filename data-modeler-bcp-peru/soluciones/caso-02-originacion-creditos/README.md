# Caso 02 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-02-originacion-creditos/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 900 deudores, 1 400 solicitudes, 700 créditos, 20 400 cuotas,
**2 795** filas de snapshot mensual y **14 reglas de calidad en `OK`**.

> **Las 2 795 filas no son 2 612 + ruido.** El snapshot tiene grano
> `(deudor, periodo, tipo de crédito, moneda)`, así que un deudor con tarjeta e hipoteca
> produce **dos** filas por mes. Son 183 filas de deudor-periodo con más de una línea, que el
> modelo anterior perdía. Y **172 de ellas empeoran su clasificación por alineamiento**: ese es
> el efecto de la regla RN-06, ahora visible en los datos.

---

## Registro de decisiones (ADR)

### ADR-01 — Los tramos normativos son datos, no código

**Contexto.** La clasificación por días de atraso está definida por la SBS y cambia por resolución.

**Decisión.** Tabla `par_clasificacion_dias` con `fecha_desde`/`fecha_hasta` y `base_legal`, más la
función `fn_clasificar(tipo, dias, fecha)` que la consulta.

**Alternativas evaluadas.**
- *`CASE WHEN` en una vista o procedimiento*: descartada. Es el problema que el caso pide resolver.
  Un cambio normativo obliga a modificar, probar y desplegar código; y además **reescribe el
  pasado**: los reportes históricos dejan de ser reproducibles.
- *Columna `clasificacion` calculada por la aplicación*: descartada. La regla quedaría duplicada en
  cada sistema que la necesite (originación, cobranzas, reportes), y se desincronizarían.

**Consecuencias.** Un cambio normativo es un `UPDATE` de vigencia más un `INSERT`. La reclasificación
histórica es correcta por construcción. El costo: toda consulta de clasificación pasa por la función
o por un JOIN al parámetro.

---

### ADR-02 — Snapshot mensual en lugar de SCD2

**Contexto.** Hay que conservar la clasificación histórica del deudor.

**Decisión.** Tabla `deudor_clasificacion_mes` con grano **deudor-periodo**.

**Alternativas evaluadas.**
- *SCD2 con vigencias*: técnicamente más compacta (solo escribe al cambiar), pero el grano del
  negocio es mensual porque **el reporte regulatorio es mensual**. Con SCD2, responder "cartera al
  31 de julio" exige lógica de vigencia en cada consulta, y reprocesar un mes obliga a reabrir
  vigencias cerradas.

**Consecuencias.** Mayor volumen (una fila por deudor y mes), a cambio de que el reproceso de un
periodo sea `DELETE WHERE periodo = '202607'` + recarga. En banca, **la capacidad de reprocesar un
mes vale más que el espacio ahorrado.**

---

### ADR-03 — La tasa de provisión se congela en el snapshot

**Contexto.** `monto_provision = saldo × tasa`. La tasa viene del parámetro vigente.

**Decisión.** Copiar `tasa_provision` dentro de `deudor_clasificacion_mes`.

**Sustento.** No es una dependencia transitiva que viole 3FN: es un **hecho histórico**. Si mañana
la SBS cambia la tasa de Dudoso de 60 % a 55 %, la provisión reportada en julio **no debe cambiar**.
Guardar solo el `clasificacion_cod` y recalcular contra el parámetro actual alteraría el pasado.

**Control compensatorio.** CAL-04 verifica `monto_provision = ROUND(saldo × tasa, 2)`.

---

### ADR-04 — La última cuota absorbe la diferencia de redondeo

**Contexto.** `ROUND(monto / plazo, 2)` no suma exactamente el monto desembolsado.

**Decisión.** Capital constante en las cuotas 1..n-1; la cuota n recibe
`monto − capital_constante × (n−1)`.

**Alternativas evaluadas.**
- *Repartir el centavo en las primeras cuotas*: válido, pero produce cuotas de importes distintos
  sin razón visible para el cliente.
- *Dejar el descuadre*: inaceptable. Contabilidad lo reporta como diferencia.

**Consecuencias.** `SUM(monto_capital) = monto_desembolsado` **exactamente**, verificado por CAL-07.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| `CASE WHEN dias BETWEEN 9 AND 30` en el código | Cada cambio normativo es un proyecto de TI | Revisión de diseño |
| Clasificación colgando del crédito y no del deudor | Un deudor con dos categorías simultáneas | El reporte SBS es rechazado |
| No guardar la tasa aplicada en el snapshot | Los reportes históricos cambian solos | Comparar dos ejecuciones del mismo mes |
| Tramos con hueco (9-30 y 32-60) | Deudores sin clasificar | **CAL-08** |
| Guardar solo el estado actual de la solicitud | PN-09 imposible | Intentar medir el tiempo de ciclo |
| Redondear el capital en todas las cuotas | Descuadre de centavos | **CAL-07** |
| Tratar el ingreso como dato ordinario | Incumplimiento de la Ley 29733 | Auditoría de clasificación de datos |

---

## Ejercicio de validación del diseño

Ejecuta esto: demuestra en 5 minutos lo que a un modelo mal hecho le cuesta 6 semanas.

```sql
BEGIN;
SET search_path TO caso02;

UPDATE par_clasificacion_dias SET fecha_hasta = DATE '2026-06-30'
WHERE  tipo_credito_cod = '7' AND clasificacion_cod IN ('0','1');

INSERT INTO par_clasificacion_dias
    (tipo_credito_cod, clasificacion_cod, dias_desde, dias_hasta, fecha_desde, base_legal)
VALUES ('7','0',0,4,DATE '2026-07-01','Hipotetica 2026'),
       ('7','1',5,30,DATE '2026-07-01','Hipotetica 2026');

SELECT periodo,
       COUNT(*) FILTER (WHERE clasificacion_cod = '0') AS normal_antes,
       COUNT(*) FILTER (WHERE fn_clasificar(tipo_credito_cod, dias_atraso, fecha_corte) = '0') AS normal_despues
FROM   deudor_clasificacion_mes
GROUP  BY periodo ORDER BY periodo;

ROLLBACK;
```

El modelo respondió sin una sola línea de código nuevo.
