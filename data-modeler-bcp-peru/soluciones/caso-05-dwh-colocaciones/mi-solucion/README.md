# Mi solución — Caso 05

| Archivo | Paso | Contenido |
|---|---|---|
| `00-matriz-bus.md` | 1 | Procesos × dimensiones, y el **grano declarado en una frase** por proceso |
| `01-modelo-conceptual.md` | 1-2 | Matriz de bus + diagrama + glosario |
| `02-modelo-logico.md` | 3-5 | Estrella, SCD2, diccionario **con aditividad por medida** |
| `03-modelo-fisico.sql` | 3-5 | DDL de dimensiones y hechos |
| `04-etl.sql` | 6 | Carga completa con verificación de prerrequisitos |
| `05-consultas-negocio.sql` | 8 | PN-01 a PN-10 |
| `06-calidad-datos.sql` | 8 | CAL-01 a CAL-15 |
| `07-capa-semantica.sql` | 9 | Vistas de consumo |
| `08-adr.md` | 10 | Decisiones de diseño |

## Autoevaluación

- [ ] Declaré el grano de cada hecho **en una frase**, sin usar "o".
- [ ] Toda dimensión tiene clave sustituta **y** conserva su clave natural.
- [ ] Toda dimensión tiene su miembro DESCONOCIDO (`sk = -1`).
- [ ] Mi ETL usa `LEFT JOIN` + `COALESCE(sk, -1)`, nunca `JOIN` interno.
- [ ] Los hechos se enlazan al SCD2 **por vigencia a la fecha del hecho**.
- [ ] Ejecuté PN-04 en sus dos variantes y **sé cuantificar la diferencia**.
- [ ] Marqué cada medida como aditiva, semiaditiva o no aditiva en el diccionario.
- [ ] El cuadre contra el origen da **exactamente 0** en cantidad y en monto.
- [ ] Mi `dim_cliente` no tiene vigencias solapadas ni huecos.
- [ ] Un usuario de negocio puede responder PN-01 usando solo las vistas.
