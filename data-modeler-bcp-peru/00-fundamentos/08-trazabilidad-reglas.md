# Trazabilidad: de la regla de negocio al control que la hace cumplir

Los 10 enunciados declaran **131 reglas de negocio**. Una regla declarada y no verificada es una
regla que se incumple tarde o temprano, y nadie se entera. Esta página dice, para cada caso, **qué
control hace cumplir cada regla** — y cuáles no tienen ninguno, que es lo que de verdad importa.

## Por qué existe este documento

Lo destapó una auditoría de cobertura: el repositorio no tenía forma de responder *"¿qué regla no
está verificada?"* sin reconstruirlo a mano. Para un laboratorio cuya lección central es **"una
regla que no vive en el modelo se incumple tarde o temprano"**, esa matriz debería haber sido el
entregable número uno de cada caso.

## Los tres tipos de control, y por qué no son intercambiables

| Tipo | Qué hace | Cuándo actúa | Cuándo elegirlo |
|---|---|---|---|
| **Declarativo** | El motor impide el dato imposible | Al escribir | Siempre que se pueda: es el único que no se puede saltar |
| **Regla de calidad** (`CAL-nn`) | Cuenta filas que incumplen | Al validar | Cuando el control necesita agregar, comparar entre filas o consultar otra tabla |
| **Prueba negativa** (`PN-nn`) | Intenta lo prohibido y exige el rechazo | Al validar el modelo | Para comprobar que el control declarativo **existe**, no que los datos estén limpios |

> **Los tres hacen falta, y el orden importa.** Una regla de calidad sobre datos limpios **no
> detecta que falta una restricción**: quita `uq_cliente_doc` del caso 01 y las reglas siguen en
> verde, porque no hay duplicados que contar. Eso solo lo ve una prueba negativa. Y al revés: una
> prueba negativa no ve un cuadre descuadrado. No se sustituyen.

---

## Cobertura actual

| Caso | Reglas declaradas | Reglas de calidad | Pruebas negativas |
|---|---:|---:|---:|
| 01 — Core de ahorros | 15 | 12 | 6 |
| 02 — Originación de créditos | 15 | 14 | 7 |
| 03 — Tarjetas de crédito | 15 | 14 | 6 |
| 04 — Billetera P2P | 12 | 18 | 6 |
| 05 — DWH dimensional | 11 | 17 | 6 |
| 06 — Tipo de cambio | 13 | 15 | 6 |
| 07 — PLAFT | 14 | 17 | 6 |
| 08 — Cliente 360 / MDM | 13 | 16 | 6 |
| 09 — Data Vault | 10 | 17 | 6 |
| 10 — Reporte SBS | 13 | 19 | 7 |
| **Total** | **131** | **159** | **62** |

**Que haya más reglas de calidad que reglas de negocio no significa que estén todas cubiertas.**
Varias reglas de calidad verifican propiedades del modelo que ningún enunciado declara (cuadres
internos, integridad referencial, grano), y algunas reglas de negocio necesitan más de un control.
La cobertura real está caso por caso, abajo.

---

## Reglas cerradas en la última revisión

Estas estaban **declaradas en el enunciado y no las verificaba nada**. Se cerraron:

| Caso | Regla | Qué faltaba | Control nuevo |
|---|---|---|---|
| 01 | **RN-09** — el signo lo define el tipo de movimiento | `ck_movimiento_signo` solo verificaba la *magnitud*. Un depósito guardado con signo de retiro entraba sin resistencia | **CAL-10** |
| 01 | **RN-04** — el producto define la moneda | Nadie contrastaba `cuenta.moneda_cod` contra la del producto | **CAL-11** |
| 02 | **RN-06** — alineamiento: la peor clasificación del deudor manda | Era **imposible de expresar** con el grano anterior: hacía falta que un deudor tuviera varias filas en el mismo periodo | **CAL-17**, tras corregir el grano |
| 03 | **RN-06** — las columnas derivadas se derivan | `linea_disponible` se digitaba y nadie lo comprobaba | **CAL-14** |
| 04 | **RN-10** — límites diarios por monto y por cantidad | Solo se verificaba el límite *por operación*, un tercio de la regla | **CAL-18** |
| 07 | **RN-05** — fraccionamiento | Se auditaba que las alertas emitidas estuvieran bien formadas. **Nadie verificaba el falso negativo**: que el fraccionamiento presente en las operaciones hubiera generado alerta. En PLAFT el riesgo es lo que *no* se detectó | **CAL-17** |
| 09 | **RN-08** — el ingreso, sensible, con control de acceso propio | El ADR prometía el `GRANT` y no había ninguno | **CAL-17** |
| 10 | **RN-04/05** — las validaciones son datos y `BLOQUEA` impide el envío | Las 6 validaciones del catálogo **nunca se ejecutaban**, y 5 de 8 envíos usaban una versión sin validaciones cargadas | **CAL-18**, y versión 1 completada |

---

## Reglas que siguen sin control automático, y por qué

**No todas las reglas de negocio son verificables como dato.** Estas son de proceso, de arquitectura
o de intención, y forzar una regla de calidad sobre ellas produciría una tautología — que es peor
que no tenerla, porque tranquiliza:

| Caso | Regla | Por qué no hay control |
|---|---|---|
| 02 | RN-15 — simular un cambio de tramo sin tocar el modelo | Es una propiedad del **diseño**, no de los datos. Se demuestra haciéndolo: el paso 4 lo pide |
| 04 | RN-11 — purga por antigüedad | Requiere un proceso operativo que el laboratorio no ejecuta |
| 05 | RN-11 — consultar sin escribir `JOIN`s | Se verifica leyendo una consulta, no contándola. El paso 9 lo pide como entregable |
| 09 | RN-09 — carga en paralelo | Exige prueba de concurrencia, que el laboratorio no tiene (ver abajo) |
| 09 | RN-10 — el usuario consume vistas | Igual que 05 RN-11 |
| 10 | RN-10 — el rectificatorio se regenera desde el origen | Es una propiedad del **procedimiento**. Se ve comparando original y rectificatorio (PN-04 del caso) |

> **Decir esto es parte del trabajo.** Un modelador que presenta una matriz de trazabilidad con
> todas las casillas en verde o está mintiendo o no entendió las reglas. Lo honesto es separar *"no
> lo verifico porque ya está declarado"* de *"no lo verifico porque no se puede"* de *"no lo
> verifico y debería"*.

---

## Lo que el laboratorio sigue sin probar

Sin rodeos, porque saber qué no se prueba es tan útil como saber qué sí:

| Tipo de prueba | Estado | Qué pasaría si se añadiera |
|---|---|---|
| **Concurrencia** | **Sí, para la idempotencia** | `validacion/concurrencia.sh` lanza dos sesiones que intentan la misma `clave_idempotencia` a la vez y exige que gane exactamente una. Comprobado que detecta el fallo: sin la restricción entran las dos filas, que es el doble cargo |
| **Frontera** | **Sí, 16 pruebas** | `validacion/fronteras.sql` ataca el punto exacto donde una regla cambia de significado: el día 8 vs el 9 de atraso, el importe igual al umbral, la vigencia de un solo día, el borde de partición, el 28 de febrero. **Encontró un defecto real** (ver abajo) |
| **Carga / volumen** | **No existe** | El caso 04 llega a 600 000 filas, que es suficiente para ver la poda de particiones pero no para medir degradación |
| **Regresión entre versiones** | **Sí** | `validacion/cifras-documentadas.sql` compara 72 cifras contra una línea base |

### Lo que encontró la primera tanda de pruebas de frontera

**El 1 de enero no tenía tipo de cambio.** Es feriado, la serie publicada empezaba el 2 de enero, y
el arrastre no tenía nada de donde tirar hacia atrás. Cualquier valorización de ese día devolvía
`NULL`. **Ninguna de las 15 reglas de calidad del caso 06 lo veía**, porque todas miraban los datos
que había, no el día que faltaba.

La corrección es la que haría un sistema real: el calendario arranca el **31 de diciembre anterior**,
como semilla. Una serie temporal no empieza en el vacío, y la carga inicial de una serie necesita
siempre un valor previo o su primer día es un agujero.

> **Esto es exactamente para lo que sirve una prueba de frontera.** No encontró un error de
> escritura: encontró una regla que nadie había pensado hasta el borde.

**Si quieres llevar el laboratorio más lejos**, lo siguiente sería ampliar las fronteras a los casos
03 (el pago que llega el día del cierre) y 05 (un hecho fechado el último día del mes contra un
`dim_tiempo` que corta ahí), y probar el laboratorio en PostgreSQL 14 y 15, que la sintaxis admite
pero nadie ha ejecutado.

---

## Cómo se comprueba todo esto

```bash
./validacion/validar.sh          # las seis redes, sobre los 10 casos
./validacion/concurrencia.sh     # la septima: dos sesiones a la vez (aparte, necesita 2 conexiones)
./validacion/version-minima.sh   # que version de PostgreSQL exige de verdad
```

Ejecuta, por cada caso: modelo físico → datos → consultas → **reglas de calidad** → **pruebas
negativas**; y después, sobre el conjunto, las **pruebas de frontera**, el **cumplimiento del
estándar de modelado** y las **cifras documentadas**. Seis redes distintas, que atrapan cosas
distintas — y cada una de ellas ha encontrado al menos un defecto que las otras no veían.
