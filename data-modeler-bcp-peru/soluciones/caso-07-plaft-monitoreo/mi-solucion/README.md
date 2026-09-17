# Mi solución — Caso 07

| Archivo | Paso | Contenido |
|---|---|---|
| `00-supuestos.md` | 1 | Clasificación fijo / variable de cada elemento normativo |
| `01-modelo-conceptual.md` | 2 | Diagrama + por qué la regla es entidad |
| `02-modelo-logico.md` | 2-5 | E-R lógico, uso justificado de JSONB, diccionario |
| `03-modelo-fisico.sql` | 2-6 | DDL + RLS + bitácora |
| `04-motor-reglas.sql` | 3-5 | Las 5 reglas implementadas |
| `05-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `06-calidad-datos.sql` | 9 | CAL-01 a CAL-15 |
| `07-pruebas-negativas.sql` | 7 | Las 4 inserciones que deben fallar |
| `08-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] **No hay ningún umbral escrito en el código** de mis reglas.
- [ ] Mi regla de fraccionamiento usa `RANGE BETWEEN INTERVAL`, no `ROWS`.
- [ ] Mi regla de fraccionamiento **excluye** las ventanas donde una operación ya supera el umbral.
- [ ] Toda alerta lleva evidencia suficiente para que un analista la entienda sin consultar la base.
- [ ] Puedo responder "¿qué reglas estaban vigentes el 15 de agosto?" con una consulta.
- [ ] Puedo responder "¿contra qué perfil se evaluó esta alerta?" aunque el perfil haya cambiado.
- [ ] El rol de negocio **no puede** leer la tabla `ros`, y puedo demostrarlo con una consulta a
      `pg_policy` e `information_schema.table_privileges`.
- [ ] Medí la tasa de falsos positivos de cada regla.
- [ ] Entiendo que los umbrales del caso son inventados y **no los usaría en un sistema real**.
