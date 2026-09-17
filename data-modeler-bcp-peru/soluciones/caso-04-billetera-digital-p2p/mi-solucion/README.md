# Mi solución — Caso 04

| Archivo | Paso | Contenido |
|---|---|---|
| `00-dimensionamiento.md` | 1 | Estimación de volumen y consecuencias |
| `01-modelo-conceptual.md` | 2 | Diagrama conceptual + glosario (define "usuario activo") |
| `02-modelo-logico.md` | 3-4 | E-R lógico, consecuencias del particionamiento, diccionario |
| `03-modelo-fisico.sql` | 3-5 | DDL con particiones, idempotencia y partida doble |
| `04-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `05-calidad-datos.sql` | 9 | CAL-01 a CAL-14 |
| `06-pruebas-negativas.sql` | 6 | Las 4 inserciones que deben fallar |
| `07-plan-ejecucion.md` | 7 | Salida de `EXPLAIN` con y sin filtro de fecha |
| `08-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] Mi `EXPLAIN` con filtro de fecha muestra **una sola** partición.
- [ ] Sé explicar por qué `UNIQUE (clave_idempotencia)` no funciona en la tabla particionada.
- [ ] Mi partición `DEFAULT` está vacía y tengo una regla que lo verifica.
- [ ] Toda transferencia P2P confirmada genera 2 movimientos que suman 0.
- [ ] Ninguna transferencia rechazada generó movimientos.
- [ ] Ningún saldo es negativo, y lo garantiza un `CHECK`.
- [ ] Definí por escrito qué es un "usuario activo" antes de calcular el MAU.
- [ ] Puedo explicar qué pasa el 1 de octubre si nadie crea la partición de octubre.
