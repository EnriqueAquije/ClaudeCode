# Mi solución — Caso 10

| Archivo | Paso | Contenido |
|---|---|---|
| `01-definicion-reporte.md` | 1-2 | La estructura como dato: campos, posiciones, dominios y versiones |
| `01-modelo-conceptual.md` | 2 | Diagrama conceptual + glosario (distingue "observado" de "rechazado") |
| `02-modelo-logico.md` | 3-4 | E-R lógico, clave compuesta versionada, diccionario, matriz source-to-target |
| `03-modelo-fisico.sql` | 3-6 | DDL con versionado, `CHECK` de coherencia y cuadre atado por restricción |
| `04-consultas-negocio.sql` | 8 | PN-01 a PN-10, incluida la generación del archivo de ancho fijo |
| `05-calidad-datos.sql` | 9 | CAL-01 a CAL-16 |
| `06-linaje.md` | 4 | El documento de linaje campo a campo que se entrega al supervisor |
| `07-rectificatorio.sql` | 7 | La regeneración desde el origen, no el parche del archivo observado |
| `08-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] Ninguna posición, longitud ni dominio del archivo está escrito en mi código generador.
- [ ] Puedo agregar un campo nuevo al reporte **sin modificar una línea de código**.
- [ ] Conservo la versión anterior de la estructura y puedo **reproducir un envío de marzo** tal como
      se remitió, con 10 campos.
- [ ] Una regla verifica que ningún envío use una versión que no estaba vigente a su fecha de corte.
- [ ] Sé explicar por qué el error de junio (Normal con 60 días de atraso) **no puede** detectarse con
      un `CHECK`.
- [ ] Sé explicar por qué V05 es `ADVIERTE` y no `BLOQUEA`.
- [ ] El envío observado **sigue existiendo** después de la rectificación, con sus hallazgos.
- [ ] Mi rectificatorio se **regeneró desde el origen**; no copié el detalle observado.
- [ ] Mis totales se calculan **después** de que el detalle queda final, y una regla lo verifica.
- [ ] `UPDATE cuadre_reporte SET esta_cuadrado = TRUE` sobre una fila descuadrada **falla** en mi
      modelo. Lo probé.
- [ ] Todo campo de la versión vigente tiene linaje documentado en una **tabla**, no en un Excel.
- [ ] Puedo responder, con un solo `SELECT`, la pregunta *"¿de dónde sale este campo y cómo se
      calculó?"*.
- [ ] Ningún envío remitido tiene errores `BLOQUEA` sin resolver.
- [ ] Mis 16 reglas de calidad están en `OK`.
