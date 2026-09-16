# Caso 03 — Tarjetas de crédito: ciclo de facturación, cuotas y mora

**Dificultad:** ★★☆☆☆ · **Tiempo estimado:** 6 a 8 horas · **Esquema:** `caso03`
**Técnicas:** ciclos que no son meses · encadenamiento de saldos · cuadre obligatorio · SCD2 · enmascaramiento

---

## 1. Situación de negocio

El área de Tarjetas recibe **reclamos recurrentes**: clientes que afirman que el saldo del estado de
cuenta no corresponde a sus consumos. La investigación revela que el estado de cuenta se genera con
un proceso que **recalcula el saldo desde cero** cada mes, y que las compras en cuotas se cargan de
formas distintas según el sistema que las procese.

Te encargan modelar el producto de tarjeta de crédito de modo que **el estado de cuenta cuadre
siempre, por construcción** y no por reconciliación posterior.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Una cuenta de tarjeta pertenece a un titular, tiene una moneda, una línea aprobada y un **día de facturación**. |
| RN-02 | Una cuenta puede tener varios **plásticos**: uno del titular y varios adicionales. Solo hay **un plástico titular activo**. |
| RN-03 | **El ciclo de facturación no es el mes calendario**: cierra el día de facturación de cada cuenta. Dos clientes tienen ciclos distintos. |
| RN-04 | El estado de cuenta se emite al cierre del ciclo, con una fecha de vencimiento posterior. |
| RN-05 | El **saldo anterior** de un ciclo es exactamente el **saldo actual** del ciclo previo. Sin excepciones. |
| RN-06 | `saldo_actual = saldo_anterior + consumos + cargos − pagos`. Esta igualdad **no puede violarse nunca**. |
| RN-07 | Un consumo **al contado** se factura íntegro en el ciclo en que se procesa. |
| RN-08 | Un consumo **en cuotas** NO se factura íntegro: genera un plan de cuotas, y cada ciclo se factura solo la cuota que vence. |
| RN-09 | La suma de los capitales del plan de cuotas debe ser **exactamente** el monto de la compra. |
| RN-10 | Si el cliente no paga el total facturado, se generan **intereses revolventes** sobre el saldo. Si paga el total, no hay intereses. |
| RN-11 | El **pago mínimo** nunca puede ser mayor que el saldo facturado. |
| RN-12 | La **línea de crédito cambia en el tiempo** (aumentos, reducciones) y debe conservarse la historia con vigencias. |
| RN-13 | Un pago se aplica al estado de cuenta del ciclo **anterior**: para saber si el cliente cumplió, hay que mirar el ciclo siguiente. |
| RN-14 | **Nunca** se almacena el número completo de la tarjeta (PAN). Solo su versión enmascarada. |
| RN-15 | El día de facturación no puede ser mayor a 28. |

## 3. Normativa y estándares aplicables

| Norma / estándar | Exigencia | Consecuencia |
|---|---|---|
| Ley 29733 | Nombre, documento y consumos son datos personales | Enmascaramiento, acceso restringido |
| Ley 26702 (secreto bancario) | Las operaciones del cliente son confidenciales | Clasificación de sensibilidad |
| Buenas prácticas de seguridad de medios de pago | El PAN completo no debe almacenarse salvo con cifrado y controles estrictos | RN-14: el modelo **solo** guarda el PAN enmascarado |
| Transparencia de información (SBS) | El cliente debe poder entender su estado de cuenta | El cuadre debe ser reproducible y explicable |

## 4. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cómo se segmentan los clientes por perfil de pago (total, revolvente, incumplido) y cómo evoluciona? |
| PN-02 | ¿Cuánto genera el producto en intereses y comisiones por periodo? |
| PN-03 | ¿En qué rubros se concentra el consumo? |
| PN-04 | ¿Qué penetración tienen las compras en cuotas y cómo es su ticket frente al contado? |
| PN-05 | ¿Cuánta deuda futura ya está comprometida en cuotas aún no facturadas? |
| PN-06 | ¿Qué cuentas exceden su línea aprobada y por cuánto? |
| PN-07 | ¿Qué porcentaje de la cartera está en mora y con qué antigüedad? |
| PN-08 | ¿El estado de cuenta cuadra contra las transacciones? |
| PN-09 | ¿Cómo evolucionó la línea de crédito de cada cuenta? |
| PN-10 | ¿Puedo reconstruir la cartilla completa de una tarjeta, ciclo por ciclo? |

## 5. Criterios de aceptación

- [ ] El cuadre del estado de cuenta está garantizado por un **`CHECK` en la base**, no por un proceso.
- [ ] El encadenamiento entre ciclos se verifica y no tiene una sola excepción.
- [ ] Una compra en 12 cuotas genera 12 filas cuyos capitales suman **exactamente** el monto.
- [ ] El ciclo de cada cuenta respeta su propio día de facturación.
- [ ] Ningún registro contiene un número de tarjeta sin enmascarar.
- [ ] La historia de líneas de crédito no tiene vigencias solapadas.
- [ ] PN-05 (backlog de cuotas futuras) se responde con una sola consulta.

## 6. Trampas del caso

1. **El ciclo ≠ el mes.** Si modelas `periodo` como mes calendario y filtras transacciones por
   `EXTRACT(MONTH FROM fecha)`, los consumos de los últimos días caerán en el ciclo equivocado.
   Por eso existe `transaccion.periodo_cargo` **explícito**.
2. **El día 31.** Si permites `dia_facturacion = 31`, febrero rompe el proceso. Por eso RN-15.
3. **La compra en cuotas.** ¿La cargas completa y luego "descuentas"? ¿O generas un plan? Si eliges
   mal, PN-05 es imposible y el cliente ve un saldo que no reconoce.
4. **El pago mira hacia adelante.** El pago de octubre corresponde al estado de setiembre. Si no lo
   modelas así, tu indicador de mora estará desplazado un mes.
5. **El saldo a favor.** ¿Qué pasa si el cliente paga de más? El modelo de este caso lo prohíbe
   (CAL-06) — pero en la realidad ocurre. ¿Cómo lo extenderías?
6. **`saldo_anterior` recalculado.** Si cada mes lo recalculas desde el histórico completo, un solo
   movimiento retroactivo cambia todos los estados de cuenta ya emitidos al cliente.
