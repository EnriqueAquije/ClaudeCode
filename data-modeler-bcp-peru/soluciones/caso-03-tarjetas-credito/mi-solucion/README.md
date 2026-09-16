# Mi solución — Caso 03

| Archivo | Paso | Contenido |
|---|---|---|
| `00-supuestos.md` | 1 | Línea de tiempo del ciclo y respuestas |
| `01-modelo-conceptual.md` | 2 | Diagrama conceptual + glosario |
| `02-modelo-logico.md` | 3-4 | E-R lógico, constraints, diccionario |
| `03-modelo-fisico.sql` | 4 | DDL con `CHECK` de cuadre e índice único parcial |
| `04-generacion-estados.sql` | 5 | CTE recursiva del encadenamiento |
| `05-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `06-calidad-datos.sql` | 8 | CAL-01 a CAL-12 |
| `07-pruebas-negativas.sql` | 7 | Las 4 inserciones que deben fallar |
| `08-adr.md` | 9 | Decisiones de diseño |

## Autoevaluación

- [ ] Mi `CHECK` de cuadre rechaza un estado de cuenta inventado.
- [ ] `LAG(saldo_actual)` = `saldo_anterior` en los 2 400 estados, sin una sola excepción.
- [ ] Una compra en 12 cuotas suma **exactamente** el monto original.
- [ ] Puedo responder cuánto está comprometido en cuotas para diciembre de 2026.
- [ ] Ningún número de tarjeta se almacena completo.
- [ ] Mi indicador de mora usa el pago del ciclo **siguiente**, no del mismo.
- [ ] Entiendo por qué `dia_facturacion` está limitado a 28.
