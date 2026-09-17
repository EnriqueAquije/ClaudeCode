# Caso 10 — Solución de referencia

## Ejecución

⚠️ **Requiere el `caso02` cargado.** El reporte se extrae del sistema de créditos.

```bash
# Prerrequisito (si aún no está)
psql -d bcp_lab -f ../caso-02-originacion-creditos/03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-02-originacion-creditos/datos/carga_datos.sql

# Este caso
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-10-reporte-regulatorio-sbs/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:**

| Objeto | Filas | Lectura |
|---|---|---|
| `reporte_definicion` | 2 | Versión 1 (ene–jun) y versión 2 (jul en adelante) |
| `reporte_campo` | 21 | 11 de la versión 2 + 10 de la versión 1 (sin garantía) |
| `reporte_validacion` | 6 | 4 `BLOQUEA` + 2 `ADVIERTE` |
| `reporte_linaje` | 11 | Uno por campo de la versión vigente |
| `reporte_envio` | 8 | 7 originales (202603–202609) + 1 rectificatorio |
| `reporte_detalle` | 3 001 | Extraídas del `caso02`, no inventadas |
| `reporte_error` | 12 | 11 reclasificaciones indebidas + 1 saldo en cero, todas en junio |
| `cuadre_reporte` | 15 | 2 conceptos por envío original + 1 en el rectificatorio |

Y **17 reglas de calidad en `OK`**.

### La narrativa que debe aparecer en PN-01 y PN-05

```
 periodo | num_envio |   tipo_envio   |  estado   | cant_registros |   concepto    | diferencia | esta_cuadrado
---------+-----------+----------------+-----------+----------------+---------------+------------+---------------
 202606  |         1 | ORIGINAL       | OBSERVADO |            389 | PROVISIONES   |    -256.56 | f
 202606  |         1 | ORIGINAL       | OBSERVADO |            389 | SALDO_CAPITAL |  -25655.67 | f
 202606  |         2 | RECTIFICATORIO | ACEPTADO  |            389 | SALDO_CAPITAL |       0.00 | t
```

> **Léelo con calma: es todo el caso en tres filas.** El envío de junio salió con 389 registros y una
> diferencia de −25 655,67 contra contabilidad. La SBS lo observó. El rectificatorio tiene **la misma
> cantidad de registros** y diferencia **0,00**. Y el original **sigue ahí**, observado, con sus 12
> hallazgos. Nadie borró nada.

---

## Registro de decisiones (ADR)

### ADR-01 — La estructura del reporte vive en tablas, no en el generador

**Contexto.** La SBS define posiciones, tipos, longitudes y dominios de cada campo.

**Decisión.** `reporte_definicion` + `reporte_campo` + `reporte_validacion`. El generador **lee** esas
tablas.

**Alternativas evaluadas.**

| Alternativa | Por qué se descartó |
|---|---|
| Posiciones incrustadas en el código del generador | Un cambio normativo se vuelve un proyecto de TI. En el enunciado, dos meses |
| Estructura en un archivo de configuración (YAML/XML) | Mejor que el código, pero no es consultable, ni versionable con vigencia, ni auditable con SQL |
| Estructura en un Excel del área regulatoria | Existe siempre, y siempre está desactualizado respecto al generador |

**Consecuencias.** Agregar el campo de garantía fue un `INSERT`. El costo: el generador es más
abstracto y menos legible línea a línea que uno con las posiciones a la vista.

---

### ADR-02 — La definición se versiona y la versión anterior no se toca

**Contexto.** En julio de 2026 la SBS agrega el campo de garantía.

**Decisión.** `version` es parte de la clave, con vigencia `[fecha_desde, fecha_hasta]`, y cada envío
guarda la versión con la que se generó.

**Sustento.** Sin esto, regenerar un envío de marzo produciría un archivo de 11 campos cuando lo que
se remitió tenía 10. Ante una revisión, el banco no podría demostrar qué envió.

**Consecuencias.** Claves compuestas de hasta tres columnas propagadas a cuatro tablas. **CAL-13**
verifica que ningún envío declare una versión que no estaba vigente a su fecha de corte.

---

### ADR-03 — Las validaciones del supervisor son datos, con severidad y base legal

**Contexto.** El instructivo del supervisor define qué revisa al recibir el archivo.

**Decisión.** `reporte_validacion`, con `expresion_sql`, `severidad` y `base_legal`.

**Sustento.** Un analista regulatorio puede agregar una validación nueva sin un despliegue. Y cuando
un hallazgo aparece, la fila dice **qué norma lo sustenta** — que es exactamente lo que pregunta el
supervisor.

**Consecuencias.** Ejecutar `expresion_sql` requiere SQL dinámico, y eso exige control: la expresión
debe ser editable solo por un rol acotado y revisada antes de activarse. **En el script del caso las
reglas se implementan explícitamente**, precisamente para no dejar un ejemplo de `EXECUTE` sobre
texto editable.

> **Esta es la tensión real del patrón "la regla como dato":** gana flexibilidad y pierde el control
> que da el código revisado. La respuesta no es abandonarlo, sino gobernarlo: versión, aprobación y
> un entorno donde la regla se prueba antes de aplicarse a un envío real.

---

### ADR-04 — `CHECK` y validación conviven; no se sustituyen

**Contexto.** ¿Por qué `clasificacion_cod IN ('0'..'4')` está como `CHECK` *y* como validación V02?

**Decisión.** Ambos, y son cosas distintas:

| | Rol |
|---|---|
| `CHECK` | Impide que un dato imposible **entre** a la base |
| Validación V02 | Documenta que el supervisor **también** lo revisa, con su severidad y base legal |

**Y el caso al revés, que es el importante:** V05 ("un deudor Normal no debería tener más de 8 días de
atraso") **no puede ser un `CHECK`**. Es una regla de negocio con excepciones legítimas, y expresarla
como restricción impediría cargar datos verdaderos. Por eso es `ADVIERTE`, no `BLOQUEA`.

**Consecuencias.** El error de junio —12 deudores con atraso alto marcados como Normal— es
estructuralmente válido. Ningún `CHECK` lo habría detenido. **Solo la validación lo encontró.**

---

### ADR-05 — El rectificatorio se regenera desde el origen

**Contexto.** La SBS observa el envío de junio con 12 hallazgos.

**Decisión.** El rectificatorio **vuelve a extraer del `caso02`**, con la lógica corregida. No copia
el detalle observado.

**Sustento cuantificado.** La observación de la SBS apuntaba a las reclasificaciones. Regenerando
desde el origen se corrigieron **11 filas de clasificación y, además, el saldo del registro que había
quedado en cero** por un error de corte — que la observación no mencionaba. **Copiar el detalle
observado y parchar lo señalado habría dejado ese segundo error adentro, para que reapareciera en la
siguiente revisión.**

**Consecuencias.** El rectificatorio cuesta lo mismo que el envío original: hay que poder regenerar
cualquier periodo en cualquier momento. Esa capacidad es el verdadero entregable del caso.

---

### ADR-06 — Los totales se guardan, pero derivados y verificados

**Contexto.** `cant_registros` y `monto_total` son calculables desde el detalle.

**Decisión.** Se guardan en `reporte_envio`, se calculan con un `UPDATE` desde el detalle y **CAL-12**
verifica que coincidan.

**Sustento.** Son un **hecho histórico**: lo que se remitió. No una agregación que deba reflejar el
estado actual de los datos.

**El orden importa, y es donde este caso se equivocó primero.** Los totales se calculan **después** de
que el detalle queda en su forma final. Calcularlos antes produce un archivo que se autocontradice:
el encabezado dice una cosa y las líneas dicen otra. Es lo primero que revisa el validador del
supervisor.

---

### ADR-07 — `esta_cuadrado` está atado por restricción

**Decisión.**

```sql
CONSTRAINT ck_cuadre_estado CHECK (esta_cuadrado = (ABS(diferencia) <= tolerancia))
```

**Sustento.** Un indicador de cuadre que un proceso escribe libremente termina en `true` sobre un
reporte que no cuadra. No por mala fe: por un `UPDATE` apresurado a las 11 de la noche del día del
plazo.

**Consecuencias.** `UPDATE cuadre_reporte SET esta_cuadrado = TRUE` sobre una fila descuadrada
**falla**. La única forma de que cuadre es que cuadre.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| Posiciones y longitudes en el código | Cada cambio normativo es un proyecto | Revisión de diseño |
| Sobrescribir la definición en vez de versionarla | No se puede reproducir un envío pasado | **CAL-13** |
| Borrar o modificar el envío observado | Se destruye la evidencia ante el supervisor | Revisión de diseño |
| **Copiar el detalle observado y parchar las filas malas** | Arrastra los errores que la observación no mencionó | Comparar original vs. rectificatorio |
| **Calcular los totales antes de corregir el detalle** | El archivo se autocontradice | **CAL-12** |
| Creer que un `CHECK` reemplaza a una validación | El error de junio pasa inadvertido | **CAL-04** |
| `esta_cuadrado` como columna libre | Envíos "cuadrados" que no cuadran | `ck_cuadre_estado` |
| Reimplementar la clasificación dentro del generador | El reporte y el core clasifican distinto al mismo deudor | Linaje (PN-02) |
| Enviar con errores `BLOQUEA` sin resolver | Rechazo del supervisor | **CAL-04** |
| Un deudor duplicado en el archivo | Causal de observación | **CAL-05**, `uq_reporte_detalle_d` |
| No guardar el hash del archivo | No se puede probar qué se remitió | **CAL-16** |
| Confundir "observado" con "rechazado" | Tableros de cumplimiento que mienten | Revisión del diccionario |

---

## La demostración del caso

Ejecuta `04-consultas-negocio.sql` y detente en tres consultas:

1. **PN-02 (linaje).** Esa tabla es, literalmente, el documento que se entrega cuando el supervisor
   pregunta *"¿de dónde sale este campo?"*. Sin ella, la respuesta exige leer el código del proceso.

2. **PN-04 (qué cambió).** Original y rectificatorio, lado a lado, fila por fila. **Ambos existen.**
   Ese `JOIN` es imposible en cualquier diseño que corrija el envío observado con un `UPDATE`.

3. **PN-10 (generación del archivo).** El archivo de ancho fijo se arma leyendo `reporte_campo`.
   Cambia una longitud en esa tabla y cambia el archivo. **Ese es el pago de haber modelado la
   estructura como dato.**

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 02 | Modelar el crédito y la norma vigente por fecha |
| 05 | Modelo dimensional: optimizado para consultar |
| 09 | Data Vault: optimizado para integrar y auditar |
| **10** | **Modelar el proceso de reporte: la definición, sus versiones, sus reglas, su linaje y su historia de envíos. El caso donde el metadato es el dato** |

> **El cierre del recorrido.** Los nueve casos anteriores modelan **el negocio**. Este modela **la
> obligación de rendir cuentas sobre el negocio** — y es el que más se parece a lo que un data modeler
> hace realmente en un banco peruano, donde una parte grande del trabajo consiste en poder explicarle
> a un supervisor, dos años después, de dónde salió un número.
