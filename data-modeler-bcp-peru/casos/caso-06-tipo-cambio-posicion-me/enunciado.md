# Caso 06 — Tipo de cambio y posición en moneda extranjera

**Dificultad:** ★★★☆☆ · **Tiempo estimado:** 6 a 8 horas · **Esquema:** `caso06`
**Técnicas:** series temporales con huecos · LOCF / gaps-and-islands · multimoneda · trazabilidad del dato derivado

---

## 1. Situación de negocio

Contabilidad reporta un descuadre recurrente en la valorización de la cartera en dólares. La
investigación revela tres causas:

1. **Cada sistema usa un tipo de cambio distinto.** Tesorería usa el de venta, Contabilidad el
   contable y Reportes el de compra. Nadie está equivocado: **están usando tipos de cambio
   diferentes**, pero nadie lo documentó.
2. **Los fines de semana y feriados no hay cotización**, y cada proceso rellena el hueco a su manera:
   unos arrastran el valor anterior, otros interpolan, otros dejan cero.
3. **No se puede reconstruir** con qué tipo de cambio se valorizó un saldo el mes pasado.

Te encargan modelar el tipo de cambio como **fuente única de verdad**, con trazabilidad completa.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Un mismo día tiene **varios tipos de cambio válidos** según el uso: compra, venta, contable y tributario. |
| RN-02 | Cada tipo de cambio tiene una **fuente** (BCRP, SBS, SUNAT) que debe quedar registrada. |
| RN-03 | El tipo de cambio **solo se publica en días hábiles**. Fines de semana y feriados no tienen cotización. |
| RN-04 | El negocio necesita un valor **para todos los días**, incluidos los no hábiles. |
| RN-05 | Cuando se usa el valor de un día anterior, debe quedar registrado **de qué día viene** y **cuántos días se arrastró**. |
| RN-06 | El dato publicado por la fuente **nunca se modifica ni se rellena**: se conserva tal cual llegó. |
| RN-07 | El tipo de cambio **venta siempre es mayor** que el de compra. |
| RN-08 | La **posición de cambio** es activos en ME menos pasivos en ME, por moneda. |
| RN-09 | La posición valorizada es `posición × tipo de cambio de cierre`. |
| RN-10 | El **resultado por diferencia de cambio** del día es la posición del día anterior multiplicada por la variación del tipo de cambio. |
| RN-11 | Debe existir **una sola implementación** de la regla de conversión a soles. |
| RN-12 | Debe poder distinguirse "no hubo cotización porque era feriado" de "falta el dato". |
| RN-13 | Existe exactamente **una moneda local** (PEN). |

## 3. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál fue el tipo de cambio de cada día, y en qué días se arrastró un valor anterior? |
| PN-02 | ¿Qué días no tuvieron cotización y por qué? |
| PN-03 | ¿Cuál fue el promedio, mínimo, máximo y spread mensual? |
| PN-04 | ¿Qué días tuvieron la mayor variación? |
| PN-05 | ¿Cuál es la posición de cambio diaria y su resultado? ¿Estamos sobrecomprados o sobrevendidos? |
| PN-06 | ¿Cuánto cambia la valorización de USD 1 000 000 según el tipo de cambio que se use? |
| PN-07 | ¿Cómo se convierte un saldo a soles de forma consistente en toda la organización? |
| PN-08 | ¿Cuáles fueron los periodos de mayor arrastre? |
| PN-09 | ¿Cuál es el resultado acumulado por diferencia de cambio del año? |
| PN-10 | ¿Cuál fue la volatilidad mensual del tipo de cambio? |

## 4. Criterios de aceptación

- [ ] Existen **dos tablas separadas**: la serie publicada (cruda) y la serie vigente (derivada).
- [ ] La serie vigente tiene un valor para **todos** los días del calendario.
- [ ] Cada valor arrastrado registra su **fecha de cotización original** y los **días de arrastre**.
- [ ] Un `CHECK` impide declarar "PUBLICADO" con días de arrastre, o "ARRASTRE" con cero días.
- [ ] Existe un **calendario de días hábiles** con feriados peruanos.
- [ ] La conversión a soles está implementada **una sola vez**, en una función.
- [ ] La posición de cambio cuadra por `CHECK`, no por proceso.
- [ ] Una regla de calidad detecta variaciones diarias anómalas.
- [ ] El modelo funciona igual con datos simulados y con la **serie real del BCRP**.

## 5. Trampas del caso

1. **"El tipo de cambio del día" no existe.** Existen varios. Modelarlo como un solo número por
   fecha es el error de origen de todo el problema.
2. **Rellenar la serie publicada.** Si escribes el valor arrastrado sobre la tabla cruda, pierdes
   para siempre la información de qué publicó realmente la fuente. **Dos tablas, no una.**
3. **Interpolar.** Promediar el valor del viernes y el del lunes para "obtener" el del sábado
   inventa un dato que nunca existió. En banca se **arrastra**, no se interpola.
4. **El calendario.** Sin una tabla de feriados no puedes distinguir un feriado de un fallo del
   proceso de carga. Ambos se ven igual: una fila que falta.
5. **La función de conversión que devuelve `NULL`.** Si no hay tipo de cambio para esa fecha, ¿qué
   debe pasar? Un `NULL` visible es preferible a un cero silencioso que descuadra el balance.
6. **El resultado por diferencia de cambio usa la posición del día ANTERIOR**, no la del día. Es un
   error clásico que invierte el signo del resultado.
