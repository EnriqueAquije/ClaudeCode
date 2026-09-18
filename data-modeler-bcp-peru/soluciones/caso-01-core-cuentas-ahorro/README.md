# Caso 01 — Solución de referencia

> Léela **después** de intentar el caso. El valor está en comparar decisiones, no en copiarlas.

## Contenido

| Archivo | Qué contiene |
|---|---|
| [`01-modelo-conceptual.md`](01-modelo-conceptual.md) | Entidades, relaciones y glosario acordado con negocio |
| [`02-modelo-logico.md`](02-modelo-logico.md) | Diagrama E-R, verificación de formas normales, diccionario de datos, matriz source-to-target |
| [`03-modelo-fisico.sql`](03-modelo-fisico.sql) | DDL PostgreSQL ejecutable e idempotente |
| [`04-consultas-negocio.sql`](04-consultas-negocio.sql) | PN-01 a PN-08 resueltas |
| [`05-calidad-datos.sql`](05-calidad-datos.sql) | CAL-00 a CAL-09 con resumen OK/FALLA |
| [`mi-solucion/`](mi-solucion/) | Espacio para tu propio desarrollo |

## Ejecución completa

```bash
createdb bcp_lab   # si aún no existe
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-01-core-cuentas-ahorro/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 500 clientes, 800 cuentas, **27 807** movimientos y las 12 reglas de calidad
en estado `OK`.

> Las cifras son **exactas**: los datos se generan sin `random()`, así que tu ejecución debe dar
> estos mismos números.

---

## Registro de decisiones de diseño (ADR)

### ADR-01 — Llave sustituta en `cliente`, no el documento de identidad

**Contexto.** El identificador natural del cliente es (tipo de documento, número). Es tentador
usarlo como PK: es único y llega en todos los archivos de origen.

**Decisión.** Usar `cliente_id BIGINT` como PK y proteger la llave natural con
`UNIQUE (tipo_doc_cod, num_doc)`.

**Alternativas evaluadas.**
- *Documento como PK*: descartada. (a) El número de documento se corrige (errores de digitación en
  la apertura son frecuentes) y corregirlo implicaría propagar el cambio a todas las FK.
  (b) Un cliente puede cambiar de tipo de documento (CE → DNI al obtener la nacionalidad).
  (c) La Ley 29733 concede el derecho de cancelación: si el documento es PK, anonimizar al cliente
  destruye la integridad referencial.

**Consecuencias.** Todo cruce con fuentes externas (padrón RUC, centrales de riesgo) se hace por la
llave natural, no por la PK. Eso obliga a un proceso de *matching* — que es exactamente el
**caso 08**.

---

### ADR-02 — `saldo_disponible` como columna generada

**Contexto.** El saldo disponible es saldo contable menos retenciones. Aparece en toda pantalla de
consulta.

**Decisión.** Columna `GENERATED ALWAYS AS (saldo_contable - saldo_retenido) STORED`.

**Alternativas evaluadas.**
- *Columna normal actualizada por la aplicación*: descartada. Crea dos fuentes de verdad; basta un
  proceso que olvide actualizarla para que el banco muestre un saldo incorrecto al cliente.
- *Vista calculada*: válida, pero obliga a un JOIN o a exponer la vista en todos los accesos, y no
  permite indexar el valor.

**Consecuencias.** Es **imposible** desincronizar el saldo disponible. A cambio, no se puede
actualizar directamente: cualquier intento falla, lo que es el comportamiento deseado.

---

### ADR-03 — El signo del movimiento vive en el catálogo, no en el monto

**Contexto.** Un retiro resta y un depósito suma. Hay dos formas de representarlo: guardar montos
negativos, o guardar montos positivos y derivar el signo del tipo de movimiento.

**Decisión.** `monto` siempre positivo; `cat_tipo_movimiento.signo` define el sentido;
`monto_con_signo` materializa el producto, con `CHECK (ABS(monto_con_signo) = monto)`.

**Alternativas evaluadas.**
- *Monto con signo directo*: descartada. Obliga a recordar el signo en cada consulta
  (`SUM(ABS(monto))` vs `SUM(monto)`), y es fuente clásica de reportes de "monto transado" mal
  calculados. Además, un monto negativo pasa desapercibido en validaciones.

**Consecuencias.** `SUM(monto)` da el volumen transado y `SUM(monto_con_signo)` da el efecto neto.
Ambas preguntas se responden sin ambigüedad. El precio es una columna redundante, controlada por
`CHECK`.

---

### ADR-04 — Extorno como movimiento inverso con relación reflexiva

**Contexto.** RN-12 prohíbe borrar movimientos.

**Decisión.** El extorno es un movimiento propio, con su número de operación, su fecha y
`movimiento_extornado_id` apuntando al original. `CHECK` garantiza que `es_extorno` y la FK sean
coherentes.

**Consecuencias.** La contabilidad conserva la partida doble. El impacto neto de un par
original + extorno es exactamente cero (verificado en PN-08). El estado de cuenta del cliente
muestra ambos asientos, como exige la práctica bancaria.

---

## Errores frecuentes al resolver este caso

| Error | Consecuencia | Cómo se detecta |
|---|---|---|
| `cuenta.cliente_id` en vez de tabla puente | Imposible representar cuentas mancomunadas | RN-03 no se puede cumplir |
| Guardar `saldo_disponible` como columna normal | Saldos inconsistentes | Se desincroniza en la primera carga fallida |
| Un solo campo `fecha` | Contabilidad no cuadra por día | PN-03 da cifras distintas a las contables |
| `ubigeo` como `INTEGER` | Se pierden los ceros iniciales: `070101` → `70101` | No cruza con el catálogo INEI |
| `num_doc` numérico | `07654321` → `7654321` | No cruza con RENIEC/SUNAT |
| No filtrar movimientos del banco en PN-04 | **Ninguna** cuenta aparece inactiva | La consulta devuelve 0 filas siempre |
| Usar `FLOAT` para montos | Descuadres de centavos | CAL-04 empieza a fallar de a pocos |

---

## Cómo continúa este modelo

| Pregunta | Caso donde se resuelve |
|---|---|
| ¿Y si el cliente pide un crédito? | Caso 02 |
| ¿Y si hay 20 millones de movimientos al mes? | Caso 04 |
| ¿Cómo consolido PEN + USD? | Caso 06 |
| ¿Cómo lo llevo a un almacén analítico? | Caso 05 |
| ¿Cómo sé que dos clientes son la misma persona? | Caso 08 |
