# Mi solución — Caso 06

| Archivo | Paso | Contenido |
|---|---|---|
| `00-supuestos.md` | 1 | Los tipos de cambio que existen y quién usa cuál |
| `01-modelo-conceptual.md` | 2 | Diagrama + por qué son **dos** entidades de cotización |
| `02-modelo-logico.md` | 2-4 | E-R lógico, constraints de trazabilidad, diccionario |
| `03-modelo-fisico.sql` | 3-5 | DDL + `fn_convertir_a_mn()` |
| `04-arrastre.sql` | 4 | El LOCF con gaps-and-islands |
| `05-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `06-calidad-datos.sql` | 9 | CAL-01 a CAL-14 |
| `07-pruebas-negativas.sql` | 6 | Las 4 inserciones que deben fallar |
| `08-bcrp-real.md` | 7 | Evidencia de la carga con la serie real (opcional) |
| `09-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] Puedo responder "¿qué publicó el BCRP el sábado 19?" con **"nada, y así está registrado"**.
- [ ] Todo valor arrastrado dice de qué día viene y cuántos días lleva.
- [ ] Mi `CHECK` rechaza un `PUBLICADO` con días de arrastre.
- [ ] Puedo distinguir un feriado de una falla de carga sin mirar un calendario externo.
- [ ] Mi función de conversión devuelve `NULL` —no cero— cuando falta el tipo de cambio.
- [ ] Ejecuté PN-06 y **sé cuantificar** la diferencia entre usar compra o venta.
- [ ] Mi regla de razonabilidad detectaría un `37.25` cargado por error.
- [ ] El resultado por diferencia de cambio usa la posición del día **anterior**.
- [ ] *(Opcional pero recomendable)* Cargué la serie real del BCRP y las 14 reglas siguen en `OK`.
