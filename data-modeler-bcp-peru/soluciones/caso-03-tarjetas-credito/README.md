# Caso 03 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-03-tarjetas-credito/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 350 titulares, 400 cuentas, 500 plásticos, 2 400 ciclos, ~23 900
transacciones, ~13 000 cuotas, 2 400 estados de cuenta y **12 reglas de calidad en `OK`**.

---

## Registro de decisiones (ADR)

### ADR-01 — El cuadre del estado de cuenta es un `CHECK`, no un proceso

**Contexto.** El problema que originó el caso son estados de cuenta que no cuadran.

**Decisión.** `CHECK (saldo_actual = saldo_anterior + total_consumos + total_cargos - total_pagos)`.

**Alternativas evaluadas.**
- *Proceso de reconciliación nocturno*: detecta el error **después** de haberlo enviado al cliente.
- *Validación en la capa de aplicación*: solo protege a quien pase por esa capa; una carga masiva o
  una corrección manual la evade.

**Consecuencias.** Es imposible persistir un estado de cuenta descuadrado. Si la carga falla contra
el `CHECK`, el proceso de carga está mal — y eso es información valiosa, no un obstáculo.

---

### ADR-02 — `periodo_cargo` explícito en la transacción

**Contexto.** El ciclo depende del día de facturación de cada cuenta; no es el mes calendario.

**Decisión.** Almacenar el periodo al que se imputa la transacción.

**Alternativas evaluadas.**
- *Deducirlo en cada consulta*: requiere repetir la lógica de corte en cada reporte, es lento sobre
  millones de filas, y falla con la primera excepción operativa (cierre postergado, transacción
  retroactiva).

**Consecuencias.** Toda consulta agrupa por `periodo_cargo` directamente. El costo es que la regla
de asignación debe aplicarse correctamente una sola vez, en la carga, y verificarse (CAL-08).

---

### ADR-03 — Las compras en cuotas generan un plan, no un cargo único

**Contexto.** Una compra en 12 cuotas no se factura completa en el mes de la compra.

**Decisión.** `transaccion` guarda la compra; `transaccion_cuota` guarda una fila por cuota con su
`periodo_cargo`.

**Consecuencias.** Habilita PN-05 (backlog de cuotas futuras), que es la pregunta que hace Finanzas
para proyectar ingresos. Sin el plan de cuotas, esa pregunta no tiene respuesta. El costo es una
tabla adicional de alto volumen (~13 000 filas para 400 cuentas en 6 meses).

---

### ADR-04 — El PAN completo no tiene columna

**Contexto.** RN-14 prohíbe almacenar el número completo de tarjeta.

**Decisión.** El modelo **no define** ninguna columna para el PAN. Solo `num_plastico_enmasc`.

**Sustento.** Una regla de seguridad implementada como política se incumple; implementada como
estructura, no se puede incumplir. El enmascaramiento ocurre **en origen**, antes de que el dato
llegue al almacén.

**Control compensatorio.** CAL-11 verifica que todo número almacenado contenga `*`.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| Tratar el ciclo como mes calendario | Consumos en el ciclo equivocado; el cliente reclama | CAL-08 |
| Permitir `dia_facturacion = 31` | El proceso de cierre falla en febrero | `CHECK` de dominio |
| Recalcular `saldo_anterior` desde el histórico | Los estados de cuenta ya emitidos cambian solos | CAL-02 |
| Cargar la compra en cuotas completa | El cliente ve un saldo que no reconoce; PN-05 imposible | CAL-03 |
| Redondear todas las cuotas por igual | Descuadre de centavos | CAL-04 |
| Calcular la mora sobre el mismo ciclo | Indicador desplazado un mes | Revisión de RN-13 |
| Guardar el PAN "por si acaso" | Riesgo de seguridad y sancionable | CAL-11 |

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 01 | Normalización, catálogos, cuadre básico |
| 02 | Parámetros regulatorios con vigencia, snapshot mensual |
| **03** | **Períodos que no son meses, encadenamiento de saldos, documento emitido inmutable, seguridad por estructura** |
