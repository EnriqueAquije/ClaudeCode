# Caso 01 — Núcleo de captaciones: cuentas de ahorro y movimientos

**Dificultad:** ★☆☆☆☆ · **Tiempo estimado:** 4 a 6 horas · **Esquema:** `caso01`
**Técnicas:** normalización 3FN · integridad transaccional · catálogos regulados · multimoneda

---

## 1. Situación de negocio

Eres Data Modeler en el equipo de Arquitectura de Datos de un banco peruano de escala similar al
BCP. La Gerencia de Productos Pasivos va a lanzar una nueva familia de cuentas de ahorro y descubre
que **no existe un modelo de datos documentado** del núcleo de captaciones: cada área tiene su
propia planilla y los saldos no coinciden entre el reporte comercial y el contable.

Te encargan **modelar desde cero el núcleo de captaciones**: clientes, productos de ahorro, cuentas
y movimientos, de modo que sirva como fuente única de verdad para operaciones, contabilidad y, más
adelante, para el almacén analítico.

## 2. Reglas de negocio levantadas

Estas son las reglas que el equipo de negocio te entregó en las entrevistas (fase 2 del ciclo):

| # | Regla de negocio |
|---|---|
| RN-01 | Un cliente se identifica por **tipo y número de documento**; la combinación es única. Los tipos válidos son DNI, Carné de Extranjería, RUC y Pasaporte. |
| RN-02 | Un cliente puede tener **cero o muchas cuentas**. Una cuenta pertenece al menos a un cliente. |
| RN-03 | Una cuenta puede ser **mancomunada**: varios clientes sobre la misma cuenta, pero **exactamente un titular principal** vigente. |
| RN-04 | Toda cuenta corresponde a un **producto** (Cuenta Ahorro Soles, Cuenta Sueldo, CTS, Ahorro Dólares, etc.). El producto define la moneda y la TREA. |
| RN-05 | Toda cuenta tiene una **moneda** (PEN o USD). **No existen cuentas multimoneda**: los importes de una cuenta están siempre en su moneda. |
| RN-06 | Una cuenta tiene un **estado**: Activa, Inactiva, Bloqueada o Cerrada. Solo las cuentas activas admiten movimientos. |
| RN-07 | Todo movimiento tiene **fecha de operación** (cuándo ocurrió, con hora) y **fecha contable** (a qué día se imputa). Pueden diferir: una operación del sábado se contabiliza el lunes. |
| RN-08 | Todo movimiento ocurre por un **canal**: Oficina, Cajero automático, Agente, App móvil, Banca por internet o Proceso batch. |
| RN-09 | Todo movimiento tiene un **tipo** (depósito, retiro, transferencia recibida/enviada, comisión, abono de intereses, ITF) y cada tipo define si **suma o resta** al saldo. |
| RN-10 | El **saldo contable** de una cuenta debe ser siempre igual a la suma algebraica de sus movimientos. Esta es la regla que hoy se está incumpliendo. |
| RN-11 | El **saldo disponible** es el saldo contable menos las retenciones (embargos, cheques en canje). Nunca se almacena manualmente: es derivado. |
| RN-12 | Un movimiento se puede **extornar** (anular), pero **nunca se borra**: se genera un movimiento inverso que referencia al original. |
| RN-13 | Cada movimiento tiene un **número de operación único** en todo el banco (evita doble contabilización de un mismo evento). |
| RN-14 | Las cuentas de ahorro **no admiten saldo negativo**; las cuentas corrientes con línea aprobada sí. |
| RN-15 | Cada cuenta se abre en una **oficina**, ubicada en un distrito identificado por su **ubigeo** de 6 dígitos. |

## 3. Restricciones normativas aplicables

| Norma | Exigencia | Consecuencia |
|---|---|---|
| Ley 26702 — secreto bancario | Las operaciones pasivas son confidenciales | Clasificación de sensibilidad; enmascaramiento fuera de producción |
| Ley 29733 — datos personales | Nombre, documento y dirección son datos personales | Documento **no** puede ser llave primaria; debe permitirse anonimización |
| Manual de Contabilidad SBS | Los movimientos deben poder cuadrar con contabilidad | Cada tipo de movimiento mapea a una cuenta contable |
| Normativa de ITF | El impuesto se aplica sobre ciertas operaciones | Tipo de movimiento específico para ITF |

## 4. Preguntas de negocio que el modelo debe responder

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál es el saldo total de captaciones por producto y moneda a una fecha? |
| PN-02 | ¿Cuáles son los 10 clientes con mayor saldo consolidado? |
| PN-03 | ¿Cómo se distribuyen los movimientos por canal y por mes (cantidad y monto)? |
| PN-04 | ¿Qué cuentas activas no registran movimientos del cliente en los últimos 90 días? |
| PN-05 | ¿Cuál es el saldo promedio mensual de cada cuenta (base para el cálculo de intereses)? |
| PN-06 | ¿Qué oficinas concentran la mayor captación? |
| PN-07 | ¿El saldo contable de cada cuenta cuadra con la suma de sus movimientos? |
| PN-08 | ¿Qué movimientos fueron extornados y cuál es el impacto neto? |

## 5. Entregables exigidos

1. **Modelo conceptual** con entidades, relaciones y cardinalidades (notación Crow's Foot).
2. **Modelo lógico** con atributos, PK/FK, dominios y diccionario de datos.
3. **Modelo físico** en PostgreSQL: DDL ejecutable con constraints, índices y comentarios.
4. **Consultas** que respondan las 8 preguntas de negocio.
5. **Reglas de calidad** ejecutables que verifiquen RN-01, RN-03, RN-10 y RN-13.
6. **Registro de decisiones (ADR)** de al menos 3 decisiones de diseño.

## 6. Criterios de aceptación

El caso está aprobado si:

- [ ] El DDL se ejecuta sin errores en PostgreSQL 14+ y es reejecutable.
- [ ] Es **imposible** insertar dos clientes con el mismo tipo y número de documento.
- [ ] Es **imposible** registrar dos titulares principales vigentes en una misma cuenta.
- [ ] Es **imposible** insertar un movimiento con monto cero o negativo.
- [ ] Es **imposible** duplicar un número de operación.
- [ ] El saldo contable de **todas** las cuentas cuadra exactamente con la suma de sus movimientos.
- [ ] Las 8 preguntas de negocio se responden con SQL sobre el modelo, sin transformaciones manuales.
- [ ] Ningún importe usa tipo de punto flotante.
- [ ] El diccionario clasifica cada campo por sensibilidad.

## 7. Trampas del caso (lo que evalúa realmente)

> Estas son las decisiones donde la mayoría se equivoca. Piénsalas antes de leer la solución.

1. **¿`saldo_disponible` se almacena o se calcula?** Si lo almacenas, tendrás dos fuentes de verdad
   que se desincronizan.
2. **¿La relación cliente-cuenta es 1:N o N:M?** Las cuentas mancomunadas obligan a N:M — pero
   entonces, ¿dónde vive la regla de "un solo titular principal"?
3. **¿Cómo modelas el extorno?** Si permites `DELETE`, pierdes auditoría. Si solo marcas un flag,
   pierdes el asiento contable inverso.
4. **¿Un único campo `fecha`?** Contabilidad y negocio necesitan fechas distintas.
5. **¿El signo del movimiento va en el monto o en el tipo?** Si guardas montos negativos, cada
   consulta debe recordar el signo; si el signo vive en el catálogo, el dato queda autoexplicado.
