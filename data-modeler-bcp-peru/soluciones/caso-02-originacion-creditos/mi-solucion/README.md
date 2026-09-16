# Mi solución — Caso 02

Guarda aquí tu desarrollo antes de mirar la solución de referencia.

| Archivo | Paso | Contenido |
|---|---|---|
| `00-supuestos.md` | 1-2 | Lectura de la norma y clasificación estructura/dominio/parámetro |
| `01-modelo-conceptual.md` | 3 | Diagrama conceptual + glosario |
| `02-modelo-logico.md` | 4 | E-R lógico, patrón de parámetro vigente, diccionario |
| `03-modelo-fisico.sql` | 5-6 | DDL + `fn_clasificar()` + manejo del redondeo |
| `04-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `05-calidad-datos.sql` | 9 | CAL-01 a CAL-11 |
| `06-simulacion-normativa.sql` | 7 | El cambio de tramo con `ROLLBACK` |
| `07-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] **No existe ningún `CASE WHEN` con días de atraso** en mi solución.
- [ ] Puedo reclasificar marzo con la norma de marzo y octubre con la de octubre.
- [ ] `SUM(monto_capital) = monto_desembolsado` para los 700 créditos, sin excepción.
- [ ] La clasificación cuelga del deudor, no del crédito.
- [ ] Mi regla de integridad de tramos detecta huecos y solapamientos.
- [ ] El ingreso está marcado como **dato sensible** en el diccionario.
- [ ] Puedo medir el tiempo de ciclo de una solicitud por canal.
