# Mi solución — Caso 08

| Archivo | Paso | Contenido |
|---|---|---|
| `00-precedencia.md` | 1 | Orden de autoridad entre fuentes, **con justificación de cada una** |
| `01-modelo-conceptual.md` | 2 | Diagrama + glosario |
| `02-modelo-logico.md` | 2-6 | E-R lógico, PK del xref, criterios de supervivencia, diccionario |
| `03-modelo-fisico.sql` | 2-6 | DDL completo |
| `04-matching.sql` | 3 | Las 3 reglas de match |
| `05-supervivencia.sql` | 4-6 | Construcción del maestro + linaje + xref |
| `06-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `07-calidad-datos.sql` | 9 | CAL-01 a CAL-15 |
| `08-experimento-umbral.md` | — | Qué pasó al bajar el umbral a 50 |
| `09-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] Mi cuadre da exacto: `registros fuente = maestros + duplicados resueltos`.
- [ ] **Los homónimos NO están fusionados**, y tengo una regla que lo verifica.
- [ ] Cada atributo del maestro tiene su criterio de supervivencia documentado y **son distintos entre sí**.
- [ ] Puedo responder "¿de dónde salió esta dirección?" para cualquier cliente.
- [ ] Ningún registro de origen cuelga de dos maestros, y la **PK lo hace imposible**.
- [ ] Mi matching no es un producto cartesiano (usé blocking y/o índice de trigramas).
- [ ] Mis precedencias son únicas: no hay empates.
- [ ] Hice el experimento de bajar el umbral y **puedo explicar qué se rompió**.
- [ ] Entiendo por qué, en MDM, el falso positivo es peor que el falso negativo.
