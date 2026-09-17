# Caso 08 — Solución de referencia

## Ejecución

```bash
# Requisito: casos 01, 02, 04 y 07 cargados
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-08-cliente-360-mdm/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:**

| Concepto | Valor |
|---|---|
| Registros en los 6 sistemas | 5 407 |
| **Clientes reales (maestros)** | **4 592** |
| Duplicados resueltos | 953 |
| Candidatos en revisión manual (homónimos) | 12 |
| **Clientes presentes en 3 o más sistemas** | **212** (179 en tres, 33 en cuatro) |
| Referencias cruzadas | 5 407 |
| Trazas de linaje | 14 082 |
| Reglas de calidad en `OK` | **16 / 16** |

> **Por qué 5 407 registros dan 4 592 clientes y no 5 212.** La misma persona aparece en varios
> sistemas: tiene cuenta de ahorros, crédito, billetera y está bajo monitoreo. Los generadores de
> los casos 01, 02, 04 y 07 **comparten deliberadamente parte del espacio de documentos** para que
> eso ocurra. Sin ese solape cada sistema vive en su propio universo, ningún cliente aparece en más
> de dos fuentes, y el MDM no tiene nada que consolidar: es el error más común al construir un juego
> de datos sintético para probar un MDM, y produce una demo que funciona y no demuestra nada.

---

## Registro de decisiones (ADR)

### ADR-01 — Precedencia única entre fuentes

**Contexto.** Cuando dos sistemas discrepan, hay que saber cuál gana.

**Decisión.** `cat_fuente.precedencia` con `UNIQUE`.

**Sustento.** Un empate deja la decisión al plan de ejecución: el mismo proceso puede dar
resultados distintos en dos corridas, y nadie puede explicar por qué. **El `UNIQUE` obliga a que el
empate se resuelva en una reunión de gobierno, no en la base de datos.**

**Consecuencias.** Agregar una fuente exige decidir explícitamente dónde ubicarla en el orden de
autoridad — que es exactamente la conversación que se busca forzar.

---

### ADR-02 — Los datos crudos son inmutables

**Contexto.** Los registros llegan con errores, duplicados y campos vacíos.

**Decisión.** `cliente_fuente` conserva el dato tal cual. La normalización se hace en una **columna
generada**, sin tocar el original.

**Alternativas evaluadas.**
- *Limpiar en la carga*: pierde la evidencia de por qué se fusionaron dos registros, impide
  reprocesar con reglas mejores y hace imposible explicarle a un área dónde quedó su dato.

**Consecuencias.** Más espacio y la necesidad de derivar claves de comparación. A cambio, el
proceso completo es **reproducible y auditable**.

---

### ADR-03 — Tres decisiones de match, no dos

**Contexto.** El matching probabilístico nunca es binario.

**Decisión.** `AUTO_MATCH`, **`REVISION`** y `NO_MATCH`.

**Sustento.** Un modelo binario obliga a equivocarse en algún sentido:

| Error | Costo |
|---|---|
| **Falso positivo** (fusionar dos personas) | Historiales mezclados, reclamos, incidente regulatorio, reproceso manual costoso |
| Falso negativo (no detectar un duplicado) | Una campaña repetida, una métrica inflada |

**En MDM el falso positivo es mucho más grave.** Por eso el umbral es alto (80) y los casos dudosos
van a una persona.

**Consecuencias.** Se necesita un equipo de *data stewards* que atienda la cola. Es un costo
operativo real y debe presupuestarse: un MDM sin stewards acumula candidatos sin resolver.

---

### ADR-04 — Supervivencia por atributo, no por registro

**Contexto.** Hay que construir el golden record a partir de varios registros.

**Decisión.** `regla_supervivencia` define el criterio de **cada atributo** por separado:
PRECEDENCIA, MAS_RECIENTE o FUENTE_FIJA.

**Sustento.** "Gana el registro de la fuente más confiable" produce un maestro con la dirección de
hace cuatro años. **El golden record es un collage**, no una copia del mejor registro.

**Consecuencias.** El proceso de construcción es más complejo (una evaluación por atributo), y por
eso mismo **necesita el linaje**: sin él, nadie entiende de dónde salió cada valor.

---

### ADR-05 — La PK del xref está sobre el registro de origen

**Contexto.** Hay que vincular cada registro de origen con su maestro.

**Decisión.** `PRIMARY KEY (fuente_cod, id_origen)`, **no** `(cliente_maestro_id, fuente_cod, id_origen)`.

**Sustento.** La PK elegida hace **estructuralmente imposible** que un registro de origen cuelgue
de dos maestros — el estado corrupto que un MDM debe impedir. La alternativa lo permitiría y
requeriría una regla de calidad para detectarlo *después*.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| **Fusionar homónimos** | Historiales de dos personas mezclados | **CAL-09** |
| Corregir el maestro a mano | La corrección se pierde en el siguiente proceso | Revisión de diseño |
| Un solo criterio de supervivencia | Direcciones viejas o actividades económicas inventadas | PN-05 |
| Limpiar los datos crudos | Imposible auditar o reprocesar | Revisión de diseño |
| Matching sin blocking ni índice | Producto cartesiano: el proceso no termina | Medir el tiempo de ejecución |
| Umbral de auto-match bajo | Falsos positivos: el error grave | Bajar el umbral y observar |
| Precedencias empatadas | Resultados no deterministas | **CAL-10** |
| Olvidar `(valor IS NULL)` en el orden | Maestro lleno de nulos | Inspección del resultado |
| No guardar la evidencia del match | Fusiones inexplicables e irreversibles | Auditoría |

---

## El experimento que hay que hacer

Baja el umbral de M02 de 80 a 50 y vuelve a ejecutar:

```sql
UPDATE regla_match SET umbral_auto = 50 WHERE regla_cod = 'M02-DOC-TIPEO';
```

Observa cuántos pares pasan de `REVISION` a `AUTO_MATCH` y cuántos de ellos son homónimos. Ese
experimento enseña, en cinco minutos, por qué el umbral no se elige "a ojo" y por qué en MDM se
prefiere pecar de conservador.

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 01-07 | Modelado transaccional, analítico, series, reglas |
| **08** | **Integración de múltiples fuentes: matching, supervivencia, linaje por atributo y la disciplina de no fusionar ante la duda** |
