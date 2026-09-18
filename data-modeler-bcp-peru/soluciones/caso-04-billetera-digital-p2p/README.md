# Caso 04 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-04-billetera-digital-p2p/datos/carga_datos.sql   # 20-60 s
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 3 001 usuarios (3 000 personas + **la cuenta puente del banco**),
151 500 transferencias (148 700 confirmadas, 2 800 rechazadas), 297 400 movimientos, partición `DEFAULT` vacía y **17 reglas de calidad en `OK`**.

**Y dos patrones que los datos reproducen a propósito**, porque sin ellos dos preguntas de negocio
no tendrían respuesta:

| Patrón | Cifra | Qué habilita |
|---|---:|---|
| Pares origen-destino con 3 o más transferencias | **14 962** | PN-06, la red de contactos |
| Días en que un usuario excede el límite diario | **182** | PN-07, el control de límites |

> **El segundo es el interesante.** Cada una de esas operaciones está **por debajo** del límite por
> operación: individualmente todas son legales. Lo que se excede es la **suma del día**. Un control
> que mira operación por operación no ve nada; hay que acumular por usuario y por día. Es el mismo
> razonamiento del fraccionamiento del caso 07, en pequeño.

---

## Registro de decisiones (ADR)

### ADR-01 — Particionamiento por rango mensual de `fecha_operacion`

**Contexto.** El volumen proyectado está en el orden de miles de millones de filas al año.

**Decisión.** `PARTITION BY RANGE (fecha_operacion)`, con una partición por mes y una `DEFAULT`.

**Alternativas evaluadas.**
- *Sin particionar*: la purga de datos antiguos requiere `DELETE` masivo con bloqueos prolongados y
  `VACUUM` que no alcanza a recuperar espacio.
- *Partición por hash de usuario*: distribuye bien la escritura, pero **no permite purgar por
  antigüedad** ni podar por fecha, que son los dos requisitos del caso (RN-11, RN-12).
- *Partición diaria*: reduce el tamaño por partición, pero genera ~365 particiones al año;
  PostgreSQL degrada la planificación con miles de particiones y la ganancia sobre mensual no
  compensa en este perfil de consultas.

**Consecuencias.** Purga = `DROP TABLE` (instantáneo). Consultas con filtro de fecha leen una
partición. **Costo:** las consultas sin filtro de fecha son ligeramente más lentas, y hay que
crear las particiones futuras de forma automatizada.

---

### ADR-02 — La idempotencia vive en una tabla no particionada

**Contexto.** RN-04 exige que un reintento de la app no genere una segunda transferencia.

**Decisión.** Tabla `idempotencia` **sin particionar**, con `PRIMARY KEY (clave_idempotencia)`.

**Sustento técnico.** PostgreSQL exige que todo índice único de una tabla particionada incluya las
columnas de partición. Por lo tanto:

```sql
UNIQUE (clave_idempotencia)                    -- ❌ rechazado por el motor
UNIQUE (clave_idempotencia, fecha_operacion)   -- ❌ única por mes: inútil
```

**Alternativas evaluadas.**
- *Validar en la aplicación*: no resiste concurrencia. Dos reintentos simultáneos pasan ambos la
  verificación previa y ambos insertan.
- *Índice único global en la tabla particionada*: no existe en PostgreSQL.

**Consecuencias.** El flujo de inserción debe escribir en ambas tablas **dentro de la misma
transacción**. Es un costo de escritura aceptable frente al costo de un doble cargo al cliente.

---

### ADR-03 — Transferencia y movimiento son tablas separadas

**Contexto.** Una transferencia mueve dinero en dos billeteras.

**Decisión.** `transferencia` (hecho de negocio) + `movimiento_billetera` (libro mayor, dos filas
por transferencia P2P confirmada).

**Consecuencias.** Habilita las reglas CAL-03 (exactamente 2 movimientos) y CAL-04 (suman cero),
que son la garantía de que el dinero no se crea ni se destruye. El estado de cuenta de cada usuario
se obtiene filtrando `movimiento_billetera` por `usuario_id`, que es indexable y podable — a
diferencia de un `WHERE origen = X OR destino = X` sobre la tabla de transferencias.

---

### ADR-04 — Saldo materializado con `CHECK (saldo >= 0)`

**Contexto.** El saldo se consulta en cada apertura de la app.

**Decisión.** Tabla `saldo_billetera` con el valor materializado y `CHECK` de no negatividad.

**Sustento.** Calcular `SUM(movimientos)` sobre miles de millones de filas en cada consulta es
inviable. El `CHECK` expresa una regla de negocio estructural: **la billetera no es una línea de
crédito**.

**Control compensatorio.** CAL-02 verifica el cuadre contra el libro mayor.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| PK sin la clave de partición | PostgreSQL rechaza el `CREATE TABLE` | Al ejecutar el DDL |
| Intentar `UNIQUE` global en la tabla particionada | Error del motor; o peor, una unicidad "por mes" que no protege | CAL-07 |
| Olvidar crear particiones futuras | Todo cae en `DEFAULT`; el rendimiento se degrada sin aviso | **CAL-08** |
| Registrar movimientos de transferencias rechazadas | Saldos descuadrados | CAL-05 |
| Consultar sin filtrar por fecha | Se pierde toda la ventaja del particionamiento | `EXPLAIN` |
| Permitir autotransferencias | Patrón típico de prueba de fraude o error de la app | CAL-06 |
| Guardar el saldo sin `CHECK` | Billeteras en negativo por un proceso mal ordenado | CAL-01 |

---

## Demostración clave del caso

```sql
-- CON filtro de fecha: una sola partición
EXPLAIN (COSTS OFF) SELECT COUNT(*) FROM caso04.transferencia
WHERE fecha_operacion >= TIMESTAMP '2026-08-01' AND fecha_operacion < TIMESTAMP '2026-09-01';
```

```
Aggregate
  ->  Seq Scan on transferencia_2026_08 transferencia
```

**Una sola partición leída.** Ese plan es el entregable que sustenta la decisión de arquitectura
ante el comité — mucho más convincente que cualquier explicación verbal.

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 01-03 | Normalización, catálogos, cuadres, historia, parámetros |
| **04** | **Diseñar para volumen: particionamiento, restricciones del motor que condicionan el modelo conceptual, idempotencia, partida doble a escala** |
