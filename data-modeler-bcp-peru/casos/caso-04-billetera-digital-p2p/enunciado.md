# Caso 04 — Billetera digital P2P: alto volumen, particionamiento e idempotencia

**Dificultad:** ★★★☆☆ · **Tiempo estimado:** 8 a 10 horas · **Esquema:** `caso04`
**Técnicas:** particionamiento declarativo · idempotencia · partida doble · diseño para volumen

---

## 1. Situación de negocio

El banco opera una **billetera digital** que permite enviar dinero entre celulares. El crecimiento
fue explosivo y el modelo de datos original —una sola tabla `transacciones` sin particionar— empezó
a mostrar tres problemas graves:

1. **Consultas lentas.** El tablero diario tarda minutos porque recorre toda la historia.
2. **Duplicados.** Cuando la red móvil falla y la app reintenta, se registran **dos** transferencias
   por una sola acción del usuario. Hay reclamos por doble cargo.
3. **Purga imposible.** Borrar datos antiguos bloquea la tabla durante horas.

Te encargan rediseñar el modelo para que soporte **volumen real**.

### Referencia de escala (información pública)

Las billeteras digitales peruanas operan a una escala poco intuitiva. Según los reportes
trimestrales públicos del grupo Credicorp, **Yape** —la billetera del BCP— superó los **16 millones
de usuarios activos mensuales**, con un promedio de **decenas de transacciones por usuario al mes**.
Eso implica **miles de millones de operaciones al año**.

> Las cifras exactas cambian cada trimestre; consúltalas en <https://grupocredicorp.com/>.
> Lo importante para este caso no es la cifra: es que **el modelo debe diseñarse para ese orden de
> magnitud desde el primer día**, porque migrar una tabla de mil millones de filas ya en producción
> es un proyecto de meses.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Un usuario de billetera se identifica por su **número de celular** (único) y tiene documento de identidad. |
| RN-02 | Un usuario puede tener **un solo dispositivo activo** a la vez (control antifraude). |
| RN-03 | Una transferencia P2P tiene un usuario origen y un usuario destino. **Nadie se transfiere a sí mismo.** |
| RN-04 | Toda transferencia lleva una **clave de idempotencia** generada por la app. Si la app reintenta con la misma clave, **no debe generarse una segunda transferencia**. |
| RN-05 | Una transferencia puede ser Confirmada, Rechazada o Reversada. Todo rechazo tiene **motivo**. |
| RN-06 | **Solo las transferencias confirmadas mueven dinero.** Una rechazada no genera ningún movimiento. |
| RN-07 | Una transferencia P2P confirmada genera **exactamente dos** movimientos en el libro mayor: un cargo al origen y un abono al destino. |
| RN-08 | Los dos movimientos de una transferencia **suman exactamente cero**: el dinero no se crea ni se destruye. |
| RN-09 | El saldo de una billetera es la suma de sus movimientos y **nunca puede ser negativo**: no es una línea de crédito. |
| RN-10 | Existen **límites** por operación, por monto diario y por cantidad diaria de operaciones, que dependen del segmento (persona natural / negocio) y **cambian por política y por norma**. |
| RN-11 | Los datos deben poder **purgarse por antigüedad** sin bloquear la operación. |
| RN-12 | Las consultas del tablero diario deben leer **solo el periodo consultado**, no toda la historia. |

## 3. Normativa aplicable

| Norma | Exigencia | Consecuencia |
|---|---|---|
| **PLAFT (UIF-Perú / SBS)** | Límites operativos y monitoreo de operaciones inusuales | `par_limite` parametrizado por fecha; base para el caso 07 |
| Ley 29733 | Celular, documento y nombre son datos personales | Clasificación y enmascaramiento |
| Ley 26702 | Secreto bancario sobre operaciones | Control de acceso |
| Retención regulatoria | Conservación por plazos largos | El particionamiento permite archivar sin borrar |

## 4. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál es el pulso diario: operaciones, usuarios activos, monto y ticket promedio? |
| PN-02 | ¿Cuántos **usuarios activos mensuales** hay y cuántas operaciones hace cada uno? |
| PN-03 | ¿A qué hora del día se concentra el uso? |
| PN-04 | ¿Cuáles son los motivos de rechazo y cuánto monto no se procesa por cada uno? |
| PN-05 | ¿Quiénes reciben más dinero? ¿Son negocios o personas? |
| PN-06 | ¿Qué pares de usuarios transfieren entre sí con frecuencia? |
| PN-07 | ¿Algún usuario excedió los límites diarios vigentes? |
| PN-08 | ¿Cómo se comportan las cohortes según su año de alta? |
| PN-09 | ¿Puedo **demostrar** que una consulta con filtro de fecha lee una sola partición? |
| PN-10 | ¿Cómo se distribuyen los saldos de las billeteras? |

## 5. Criterios de aceptación

- [ ] La tabla de transferencias está **particionada por rango de fecha**.
- [ ] `EXPLAIN` demuestra que una consulta con filtro de fecha lee **una sola partición**.
- [ ] Existe una partición `DEFAULT` y una regla de calidad verifica que esté **vacía**.
- [ ] La clave de idempotencia tiene unicidad **global**, pese al particionamiento.
- [ ] Toda transferencia P2P confirmada genera exactamente 2 movimientos que suman 0.
- [ ] Ninguna billetera queda con saldo negativo (garantizado por `CHECK`).
- [ ] Ninguna transferencia rechazada genera movimientos.
- [ ] Los límites se leen de una tabla parametrizada por fecha, no del código.

## 6. Trampas del caso

1. **La llave primaria de una tabla particionada debe incluir la clave de partición.** Si tu PK es
   solo `transferencia_id`, PostgreSQL rechaza la tabla. Esto tiene una consecuencia mayor: ⬇
2. **No puedes poner `UNIQUE (clave_idempotencia)` en la tabla particionada.** Todo índice único
   debe incluir la columna de partición, lo que haría la clave única *por mes* — inútil. ¿Cómo
   garantizas unicidad global? *(la respuesta está en el modelo de la solución)*
3. **La partición `DEFAULT` es una trampa silenciosa.** Evita que una carga falle, pero si recibe
   filas significa que **faltan particiones** y nadie se entera. Por eso se monitorea.
4. **El saldo no se guarda "y ya".** Debe derivarse del libro mayor y cuadrar siempre.
5. **Una transferencia rechazada no mueve dinero**, pero muchos modelos la registran igual en el
   libro mayor "para tener trazabilidad". Eso descuadra el saldo.
6. **`usuario_destino_id` puede ser nulo** (envío a un celular no afiliado). ¿Tu `CHECK` lo
   contempla sin permitir transferencias sin destino alguno?
