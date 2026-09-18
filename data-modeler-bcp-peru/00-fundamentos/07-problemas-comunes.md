# Problemas comunes al ejecutar el laboratorio

Esta página existe porque estás solo. Busca tu mensaje de error, no leas de corrido.

---

## 1. No puedo conectarme a PostgreSQL

```
psql: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed
```

**El servidor no está corriendo.** Arráncalo:

```bash
sudo service postgresql start        # Debian / Ubuntu
brew services start postgresql@16    # macOS
```

En Windows, PostgreSQL se instala como servicio: búscalo en *Servicios* y arráncalo desde ahí.

```
psql: error: FATAL: role "tu_usuario" does not exist
```

**Tu usuario del sistema no existe como rol en PostgreSQL.** La salida más rápida:

```bash
sudo -u postgres createuser --superuser $USER
sudo -u postgres createdb $USER
```

```
psql: error: FATAL: database "bcp_lab" does not exist
```

**Falta crearla:** `createdb bcp_lab`.

---

## 2. `CREATE EXTENSION` falla

```
ERROR: could not open extension control file ".../pg_trgm.control": No such file or directory
```

**Falta el paquete `contrib`.** Es el tropiezo número uno, y solo afecta al caso 08:

```bash
sudo apt install postgresql-contrib     # Debian / Ubuntu
brew install postgresql@16              # macOS: ya viene incluido
```

```
ERROR: permission denied to create extension "pg_trgm"
HINT: Must be superuser to create this extension.
```

**Tu rol no es superusuario.** En tu máquina, conviértelo:
`sudo -u postgres psql -c "ALTER ROLE $USER SUPERUSER;"`.
En una base gestionada (RDS, Cloud SQL, Neon) pídeselo al administrador — o **salta el caso 08**,
que es el único que las necesita.

---

## 3. Un caso falla diciendo que le falta otro

```
ERROR: Falta el esquema caso02. Ejecute primero el caso 02 completo.
ERROR: El esquema caso02 existe pero esta VACIO.
```

**No es un fallo: es el modelo protegiéndote.** Cuatro casos leen de otros:

| Caso | Necesita antes |
|---|---|
| 05 — DWH | 01 y 02 |
| 08 — MDM | 01, 02, 04 y 07 |
| 10 — Reporte SBS | 02 |

La forma cómoda de resolverlo:

```bash
./validacion/validar.sh caso08     # carga 01, 02, 04, 07 y después 08
```

El segundo mensaje —*existe pero está VACÍO*— significa que creaste las tablas pero no cargaste los
datos. Te falta el `carga_datos.sql` de ese caso.

---

## 4. "Ya existe" al volver a ejecutar

```
ERROR: relation "cliente" already exists
```

**No debería pasar:** todos los `03-modelo-fisico.sql` empiezan con `DROP SCHEMA IF EXISTS ... CASCADE`
y son idempotentes. Si lo ves, casi seguro estás ejecutando **tu propio** DDL sin esa línea. Añádela
al principio:

```sql
DROP SCHEMA IF EXISTS mi_caso01 CASCADE;
CREATE SCHEMA mi_caso01;
SET search_path TO mi_caso01, public;
```

> Que tu DDL se pueda volver a ejecutar sin errores no es un detalle: es lo que te permite iterar.
> Si cada cambio te obliga a borrar la base a mano, dejarás de iterar.

---

## 5. La carga tarda muchísimo o se queda sin memoria

El **caso 04** genera unas 600 000 filas y tarda entre 15 y 60 segundos. Si tu máquina sufre, baja
el volumen: en `casos/caso-04-billetera-digital-p2p/datos/carga_datos.sql` busca

```sql
CROSS JOIN LATERAL generate_series(1, 30 + (u.usuario_id % 40)) AS g(k)
```

y reduce `usuario_billetera` a 500 usuarios en su `generate_series`. Las proporciones se mantienen y
las lecciones del caso también; solo cambian las cifras del `README`.

---

## 6. Mis cifras no coinciden con las del README

**No deberían diferir.** Los datos son deterministas: ningún generador usa `random()`, así que dos
personas obtienen exactamente las mismas filas. Si no coinciden, en orden de probabilidad:

1. **Cargaste dos veces sin volver a crear el esquema.** Ejecuta el `03-modelo-fisico.sql` otra vez
   (borra y recrea) y después la carga.
2. **Editaste el generador** para probar algo y olvidaste revertirlo. `git diff` te lo dice.
3. **Te saltaste un prerrequisito** y el caso cargó con menos filas de origen.

Compruébalo de golpe:

```bash
psql -d bcp_lab -f validacion/cifras-documentadas.sql
```

Te dice, cifra por cifra, qué documenta el README, qué hay en tu base y la diferencia exacta.

---

## 7. `validar.sh` no se ejecuta

```
bash: ./validacion/validar.sh: Permission denied
```

`chmod +x validacion/validar.sh`, o ejecútalo como `bash validacion/validar.sh`.

```
'.' is not recognized as an internal or external command
```

**Estás en Windows con `cmd` o PowerShell.** El validador es un script de `bash`. Usa **WSL** o
**Git Bash**. Los `.sql` funcionan igual desde `psql` en cualquier sistema; el validador solo
automatiza el orden.

```
No se puede escribir en .../validacion/salida
```

El repositorio está en una ruta de solo lectura. Cópialo a tu carpeta personal.

---

## 8. Una regla de calidad me da `FALLA`

**Léela: te está diciendo exactamente qué pasa.**

```
CAL-04 | Cuadre | saldo_contable = suma de movimientos | 3 | FALLA
```

Eso significa que **3 filas** incumplen. Para verlas, cada `05-calidad-datos.sql` trae consultas de
detalle antes del resumen: ejecútalas y mira las filas concretas.

Si la regla falla sobre la **solución de referencia** recién cargada, es un defecto del laboratorio y
conviene reportarlo. Si falla sobre **tu** modelo, es el laboratorio haciendo su trabajo.

---

## 9. Una prueba negativa me da `FALLA`

```
PN-01 | Dos clientes con el mismo documento | unicidad de (tipo_doc, num_doc) | FALLA
```

**Significa que tu modelo ACEPTÓ una operación que debería haber rechazado.** No es un error de
ejecución: es un hueco en tu DDL. La columna `deberia_impedirlo` te dice qué falta.

Es la señal más útil de todo el laboratorio, porque es la que las reglas de calidad **no** pueden
darte: sobre datos limpios, una restricción que falta no se nota.

---

## 10. Nada de lo anterior

Ejecuta esto y guarda la salida — es lo que necesita cualquiera para ayudarte:

```bash
psql --version
psql -d bcp_lab -c "SELECT version(); SHOW server_encoding; SHOW lc_collate;"
bash --version | head -1
./validacion/validar.sh caso01 2>&1 | tail -30
```

Los registros completos de la última ejecución están en `validacion/salida/`, un fichero por caso y
por etapa.
