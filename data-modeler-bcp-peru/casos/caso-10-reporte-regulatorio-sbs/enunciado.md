# Caso 10 — Reporte regulatorio a la SBS: definición, generación, validación y linaje

**Dificultad:** ★★★★★ · **Tiempo estimado:** 12 a 14 horas · **Esquema:** `caso10`
**Técnicas:** definición del reporte como dato · versionado de estructura · validaciones configurables · linaje campo a campo · rectificaciones

⚠️ **Requisito previo:** haber cargado el **caso 02**. El reporte se genera a partir del sistema de
créditos, no de datos inventados.

---

## 1. Situación de negocio

El banco remite mensualmente a la SBS el **Reporte Crediticio de Deudores**. El proceso actual tiene
cuatro problemas, y los cuatro son de modelado:

1. **La estructura del archivo está programada.** Cuando la SBS agrega un campo, hay que modificar,
   probar y desplegar el generador. El último cambio tomó dos meses.
2. **No se puede reproducir un envío pasado.** El generador usa la estructura *actual*, así que un
   envío de hace seis meses no se puede regenerar tal como se remitió.
3. **Nadie sabe de dónde sale cada campo.** Cuando la SBS observa un dato, el equipo tiene que leer
   el código del proceso para reconstruir cómo se calculó.
4. **El rectificatorio se hace parchando el archivo observado a mano.** El resultado suele contener
   errores nuevos.

Te encargan modelar el proceso regulatorio completo.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | La **estructura del reporte** (campos, posiciones, tipos, longitudes, dominios) es un **dato**, no un programa. |
| RN-02 | La estructura está **versionada**: cuando la SBS la modifica, se crea una versión nueva y **la anterior se conserva**. |
| RN-03 | Cada versión tiene **vigencia**: un envío usa la versión vigente a su fecha de corte. |
| RN-04 | Las **validaciones** que aplica el supervisor también son datos, con su severidad y su base legal. |
| RN-05 | Una validación `BLOQUEA` impide el envío; una `ADVIERTE` lo permite pero queda registrada. |
| RN-06 | Cada campo del reporte tiene **linaje documentado**: sistema, tabla, columna, transformación y área responsable. |
| RN-07 | El reporte debe **cuadrar con contabilidad** antes de enviarse. |
| RN-08 | Un envío observado se corrige con un **rectificatorio**. El original **no se borra ni se modifica**. |
| RN-09 | El primer envío de un periodo es `ORIGINAL`; los siguientes, `RECTIFICATORIO`. |
| RN-10 | El rectificatorio se **regenera desde el origen**, no se parcha el archivo observado. |
| RN-11 | Un deudor aparece **una sola vez por tipo de crédito y moneda**. Varias líneas por deudor es lo normal: quien tiene tarjeta e hipoteca aporta dos. |
| RN-12 | Los totales del envío se **derivan del detalle**, nunca se digitan. |
| RN-13 | Todo envío remitido conserva el **hash del archivo** enviado. |

## 3. Normativa aplicable

| Norma | Exigencia | Consecuencia en el modelo |
|---|---|---|
| **Reportes y anexos SBS** | Remisión periódica con estructura y plazos definidos | `reporte_definicion`, `reporte_campo`, plazos |
| **Res. SBS N.º 11356-2008** | Dominios de tipo de crédito y clasificación del deudor | `CHECK` sobre el detalle |
| Manual de Contabilidad SBS | El reporte debe cuadrar con los libros | `cuadre_reporte` |
| Conservación de información | Reproducir lo remitido ante una revisión | Versionado + `hash_archivo` |

> ⚠️ La estructura del reporte de este caso es una **simplificación educativa**. La estructura real
> del RCD la define la SBS: <https://www.sbs.gob.pe/normativa>. **Este material no es guía de
> cumplimiento regulatorio.**

## 4. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál es el estado de todos los envíos: qué se envió, cuándo, con cuántos errores y si cuadra? |
| PN-02 | ¿De dónde sale cada campo del reporte y cómo se calcula? |
| PN-03 | ¿Qué hallazgos tuvo el envío observado? |
| PN-04 | ¿Qué cambió exactamente entre el original y el rectificatorio? |
| PN-05 | ¿Cada envío cuadra con contabilidad? |
| PN-06 | ¿Cómo se distribuye la cartera reportada por clasificación? |
| PN-07 | ¿Cómo evoluciona la cartera reportada mes a mes? |
| PN-08 | ¿Qué versiones de la estructura existen y en qué se diferencian? |
| PN-09 | ¿Se están cumpliendo los plazos de remisión? |
| PN-10 | ¿Cómo se genera el archivo de ancho fijo a partir de la definición? |

## 5. Criterios de aceptación

- [ ] Los campos, posiciones, tipos y dominios viven en **tablas**, no en el código.
- [ ] La definición está **versionada** y la versión anterior se conserva.
- [ ] Un envío usa la versión **vigente a su fecha de corte**, verificado por una regla.
- [ ] Las validaciones son datos, con severidad y base legal.
- [ ] Existe **linaje campo a campo** para todos los campos de la versión vigente.
- [ ] Ningún envío remitido contiene errores `BLOQUEA` sin resolver.
- [ ] El indicador de cuadre se **deriva**, no se digita.
- [ ] El original observado **se conserva**; el rectificatorio es un envío nuevo.
- [ ] El rectificatorio **se regenera desde el origen**.
- [ ] El archivo de ancho fijo se arma leyendo la definición.

## 6. Trampas del caso

1. **El grano del detalle.** ¿Una línea por deudor, o una por deudor y tipo de crédito? Decídelo
   **antes** de escribir el `CREATE TABLE`, y comprueba tu respuesta contra el origen: ¿cuántos
   deudores del `caso02` tienen más de un tipo de crédito vigente? Si pones `UNIQUE (envío,
   documento)` porque suena a buena higiene, dejarás fuera del reporte a todos ellos — y un RCD
   incompleto es causal de observación. El control correcto es más largo de escribir y es el único
   que reporta la realidad.
2. **La estructura en el código.** Si tu generador tiene las posiciones incrustadas, no resolviste
   el problema del enunciado.
3. **Borrar el envío observado.** Destruye la evidencia. El supervisor puede pedir explicar
   exactamente qué cambió entre un envío y otro.
4. **Parchar el archivo observado.** El rectificatorio debe **regenerarse desde el origen**. Copiar
   el archivo con error y corregir dos líneas a mano suele introducir errores nuevos.
5. **Calcular los totales antes de las correcciones.** Si corriges el detalle y no recalculas los
   totales, el archivo se autocontradice — y es lo primero que revisa el validador del supervisor.
6. **Un `CHECK` no reemplaza una validación.** Una clasificación "Normal" con 60 días de atraso es
   estructuralmente válida: ninguna restricción de la base lo impide. **Solo una regla de validación
   lo detecta.**
7. **El indicador de cuadre digitado.** Si `esta_cuadrado` es una columna que alguien marca, alguien
   la marcará mal. Debe derivarse de la diferencia y la tolerancia.
