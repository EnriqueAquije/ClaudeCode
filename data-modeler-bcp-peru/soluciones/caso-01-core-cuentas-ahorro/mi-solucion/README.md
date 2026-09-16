# Mi solución — Caso 01

Guarda aquí **tu** desarrollo del caso, antes de mirar la solución de referencia.

## Archivos que debes producir

| Archivo | Paso de la guía | Contenido |
|---|---|---|
| `00-supuestos.md` | Paso 1 | Supuestos normativos y de negocio |
| `01-modelo-conceptual.md` | Paso 3 | Diagrama conceptual + glosario |
| `02-modelo-logico.md` | Paso 4 | Diagrama E-R lógico + diccionario de datos |
| `03-modelo-fisico.sql` | Paso 5 | DDL ejecutable |
| `04-consultas-negocio.sql` | Paso 7 | PN-01 a PN-08 |
| `05-calidad-datos.sql` | Paso 8 | CAL-01 a CAL-06 |
| `06-pruebas-negativas.sql` | Paso 6 | Las 4 inserciones que **deben** fallar |
| `07-diccionario-y-adr.md` | Paso 9 | Diccionario, source-to-target y 3 ADR |

## Cómo probar tu modelo

```bash
# Usa un esquema propio para no pisar la solución de referencia
sed 's/caso01/mi_caso01/g' 03-modelo-fisico.sql > /tmp/mi_ddl.sql
psql -d bcp_lab -f /tmp/mi_ddl.sql
```

## Autoevaluación

- [ ] El DDL corre dos veces seguidas sin errores.
- [ ] Las 4 pruebas negativas fallan (es decir: el modelo se defiende).
- [ ] Las 8 preguntas de negocio se responden con SQL, sin pasos manuales.
- [ ] Las reglas de calidad devuelven 0 filas.
- [ ] Ningún importe es `FLOAT`; ningún ubigeo o documento es numérico.
- [ ] Cada campo del diccionario tiene clasificación de sensibilidad.
- [ ] Puedo explicar en voz alta por qué elegí cada llave primaria.
