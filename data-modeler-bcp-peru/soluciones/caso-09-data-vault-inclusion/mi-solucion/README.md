# Mi solución — Caso 09

| Archivo | Paso | Contenido |
|---|---|---|
| `00-llaves-de-negocio.md` | 1 | Clasificación hub / link / satélite de cada elemento |
| `01-modelo-conceptual.md` | 1 | Los tres pasos: llaves, relaciones, atributos |
| `02-modelo-logico.md` | 2-4 | Estructura de cada tipo de tabla + diccionario |
| `03-modelo-fisico.sql` | 2-5 | DDL + `fn_hash_key()` |
| `04-carga-ola-2025.sql` | 6 | Carga inicial |
| `05-carga-ola-2026.sql` | 5-6 | Carga incremental con `hash_diff` + satélite nuevo |
| `06-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `07-calidad-datos.sql` | 9 | CAL-01 a CAL-15 |
| `08-comparacion-dimensional.md` | 8 | Data Vault vs el caso 05, con números |
| `09-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] **Ningún hub ni link tiene atributos descriptivos**, y tengo una regla que lo verifica contra
      `information_schema`.
- [ ] Todas mis claves salen de **una sola** función de hash.
- [ ] Mi satélite de ingreso creció **menos** que el de demografía en la segunda ola, y sé por qué.
- [ ] Usé `IS DISTINCT FROM`, no `<>`.
- [ ] Absorbí los atributos nuevos de 2026 **sin modificar ninguna tabla existente**.
- [ ] Puedo reconstruir la foto de una persona al 31 de diciembre de 2025.
- [ ] Separé el ingreso en su propio satélite, y sé justificar por qué (sensibilidad **y** ritmo).
- [ ] Conté los JOINs que cuesta una pregunta simple y entiendo por qué hace falta la capa de vistas.
- [ ] Puedo explicar cuándo **no** usaría Data Vault.
