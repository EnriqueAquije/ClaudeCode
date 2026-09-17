# Caso 05 — Solución de referencia

## Ejecución

```bash
# Requisito: casos 01 y 02 cargados
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-05-dwh-colocaciones/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:**

| Tabla | Filas |
|---|---|
| `dim_tiempo` | 1 096 |
| `dim_ubigeo` | 13 |
| `dim_oficina` | 21 |
| `dim_producto` | 15 |
| `dim_canal` | 7 |
| `dim_cliente` | 1 501 (de las cuales **100 son versión 2** del SCD2) |
| `fact_movimiento` | 27 807 |
| `fact_saldo_captacion_mes` | 3 188 |
| `fact_colocacion_mes` | 2 795 | Grano: mes × deudor × producto × moneda |

Y **17 reglas de calidad en `OK`**, incluyendo el cuadre exacto contra los sistemas fuente.

---

## Registro de decisiones (ADR)

### ADR-01 — Tres tablas de hechos, no una

**Contexto.** Se necesita el detalle del movimiento, el saldo mensual y la situación crediticia.

**Decisión.** `fact_movimiento` (transaccional) + `fact_saldo_captacion_mes` y
`fact_colocacion_mes` (snapshots periódicos).

**Sustento.** Tienen **granos distintos** y granos distintos no conviven en una tabla. Además, los
snapshots responden en milisegundos preguntas que sobre el transaccional exigirían recorrer
millones de filas.

**Consecuencias.** Redundancia controlada: el saldo podría derivarse del transaccional. El costo es
espacio y un paso de ETL; el beneficio es que el tablero responde al instante. **CAL-09 y CAL-10
protegen el grano** de los snapshots contra duplicados.

---

### ADR-02 — `dim_cliente` en SCD tipo 2

**Contexto.** RN-03 exige analizar el pasado con el segmento vigente entonces.

**Decisión.** SCD2 con `fecha_desde` / `fecha_hasta` / `es_vigente`, clave natural = documento.

**Alternativas evaluadas.**
- *SCD1 (sobrescribir)*: descartada. Reescribe la historia; los reportes del mes pasado cambian
  solos y nadie puede explicar por qué.
- *SCD3 (columna "segmento anterior")*: solo guarda **un** cambio. Insuficiente para un atributo
  que puede cambiar varias veces.
- *Guardar el segmento en el hecho*: funcionaría, pero duplica el dato en millones de filas y
  obliga a reprocesar todos los hechos si cambia la definición.

**Consecuencias.** La dimensión crece (1 501 filas para 1 400 personas). Todo JOIN debe hacerse
**por vigencia**, no por `es_vigente`. Tres reglas de calidad (CAL-02, 03, 04) vigilan la
consistencia de las vigencias.

---

### ADR-03 — Miembro DESCONOCIDO (`sk = -1`) en todas las dimensiones

**Contexto.** Un hecho puede llegar con una clave que no existe en la dimensión.

**Decisión.** Cada dimensión tiene una fila `sk = -1`; el ETL usa `LEFT JOIN` + `COALESCE(sk, -1)`.

**Sustento.** Con `JOIN` interno, el hecho **desaparece silenciosamente** y el almacén deja de
cuadrar con el origen sin que salte ningún error.

**Consecuencias.** El almacén siempre cuadra (CAL-05, CAL-06). Los problemas de datos quedan
**visibles y contables** (CAL-12, CAL-13) en lugar de invisibles.

---

### ADR-04 — `dim_producto` conformada entre captaciones y colocaciones

**Contexto.** Captaciones y créditos usan vocabularios de producto distintos.

**Decisión.** Una sola dimensión con `negocio_cod` para distinguir el lado del balance.

**Consecuencias.** PN-06 (clientes con producto dual) se responde con una consulta. El costo es que
el ETL debe mantener el mapeo de ambos orígenes y que agregar un producto nuevo exige decidir su
familia y su negocio — precisamente la conversación de gobierno que se busca forzar.

---

### ADR-05 — `tiempo_sk` como clave inteligente `AAAAMMDD`

**Contexto.** La regla general dice que las claves sustitutas no deben tener significado.

**Decisión.** Excepción deliberada: `tiempo_sk = 20260815`.

**Sustento.** Permite filtrar y ordenar por rango de fechas **directamente en el hecho**, sin JOIN
a `dim_tiempo`, y es legible al depurar. Es práctica estándar en modelado dimensional y el riesgo
(que alguien haga aritmética con la clave) es bajo y controlable.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| JOIN al SCD2 por `es_vigente` | La historia se reescribe; **no hay error visible** | Comparar PN-04 (a) vs (b) |
| `JOIN` interno en el ETL | Hechos que desaparecen sin aviso | **CAL-05 / CAL-06** |
| Sumar `saldo_fin_mes` entre meses | Cifras absurdas en el tablero | PN-08 |
| Usar `MAX(periodo)` como "último mes" | Reporte basado en un mes no representativo | PN-03 |
| Olvidar el miembro desconocido | Se pierden hechos o falla la FK | CAL-01 |
| Grano duplicado en el snapshot | Doble conteo del saldo | CAL-09 / CAL-10 |
| No documentar la aditividad | El usuario suma lo que no debe | Diccionario de medidas |
| Poner el segmento en el hecho | Reproceso masivo ante cada cambio de definición | Revisión de diseño |

---

## La demostración que vale el caso entero

Ejecuta PN-04 y compara las dos tablas. Son la misma pregunta, respondida de dos formas:

- **(a)** atribuye cada movimiento al segmento vigente **ese mes** → correcto.
- **(b)** usa el segmento **actual** → reescribe la historia.

Los 100 clientes que cambiaron de segmento el 1 de junio hacen que ambas respuestas difieran para
mayo. En un banco real con cientos de miles de reclasificaciones al año, esa diferencia es lo que
hace que el reporte de enero cambie cada vez que se vuelve a ejecutar — y que nadie confíe en el
almacén.

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 01-04 | Modelado transaccional: normalización, reglas, historia, volumen |
| **05** | **Modelado analítico: grano, estrella, SCD2, dimensiones conformadas, aditividad, ETL con cuadre exacto** |
