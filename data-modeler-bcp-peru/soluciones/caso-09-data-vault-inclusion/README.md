# Caso 09 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-09-data-vault-inclusion/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:**

| Tabla | Filas | Lectura |
|---|---|---|
| `hub_persona` | 1 600 | 1 500 (ola 2025) + 100 nuevas (2026) |
| `hub_hogar` | 600 | Cargados una vez |
| `lnk_persona_producto` | 6 442 | Incluye productos adquiridos en 2026 |
| `sat_persona_demografia` | 3 000 | 1 500 + **1 500**: todos cumplieron un año |
| `sat_persona_ingreso` | 2 000 | 1 500 + **500**: solo cambió 1 de cada 3 |
| `sat_persona_canal_digital` | 1 600 | **Satélite nuevo** de la ola 2026 |

Y **17 reglas de calidad en `OK`**.

> **La fila que resume el caso:** el satélite de ingreso creció 500 y no 1 500. Esa diferencia,
> multiplicada por millones de personas y por cargas mensuales, es la razón económica del `hash_diff`.

---

## Registro de decisiones (ADR)

### ADR-01 — Claves hash en lugar de secuencias

**Contexto.** Hay que asignar claves técnicas a hubs y links.

**Decisión.** `MD5` de la llave de negocio normalizada, mediante una función única `fn_hash_key()`.

**Alternativas evaluadas.**
- *Secuencias*: obligan a buscar el hub antes de cargar un link, lo que serializa la carga.
  Al reprocesar, las claves cambian y todo lo aguas abajo se invalida.
- *Hash calculado en cada proceso*: si un proceso hace `MD5(doc)` y otro `MD5(TRIM(UPPER(doc)))`,
  la misma persona genera dos hubs. Por eso hay **una sola función**, y CAL-01 verifica que se usó.

**Consecuencias.** Carga paralela sin coordinación; claves idénticas entre entornos y entre
reprocesos. Costo: 32 caracteres por clave en lugar de 8 bytes.

> ### ⚠️ El hash NO anonimiza. Compruébalo tú mismo
>
> Es el malentendido más caro de esta decisión, y casi todo el mundo lo comete: *"el DNI está
> hasheado, así que el dato está protegido"*. **No lo está.** El DNI peruano tiene 8 dígitos: son
> 100 millones de combinaciones, y recorrerlas es cuestión de minutos en un portátil.
>
> ```sql
> WITH objetivo AS (SELECT persona_hk, num_doc_bk FROM hub_persona LIMIT 1)
> SELECT o.num_doc_bk AS dni_real, g.n AS dni_recuperado
> FROM   objetivo o
> JOIN   generate_series(70000000, 79999999) AS g(n)
>   ON   fn_hash_key('01', g.n::TEXT) = o.persona_hk;
> ```
>
> Devuelve el DNI. En Data Vault el hash se usa por su **distribución**, no por su seguridad, y eso
> es correcto — lo incorrecto es confundir una cosa con la otra.
>
> **Si necesitas que la clave misma no sea reversible**, el camino es HMAC con una sal guardada
> fuera del esquema. Pero entonces pierdes justo la propiedad que hace útil al hash: que dos
> procesos independientes calculen la misma clave **sin coordinarse**. Es un intercambio real, y
> este caso elige la distribución y protege el dato con el control que corresponde: el acceso.

---

### ADR-02 — `hash_diff` para evitar el crecimiento inútil

**Contexto.** Un satélite que inserta en cada carga crece aunque nada cambie.

**Decisión.** `hash_diff` de todos los atributos; solo se inserta si difiere del vigente.

**Sustento cuantificado.** Con 10 millones de personas y carga mensual: 120 millones de filas al
año insertando siempre, contra las que realmente cambian. **En este caso la diferencia fue 500 vs
1 500 — un tercio.**

**Consecuencias.** Comparar hashes es más barato que comparar columna por columna, y no hay que
modificar la lógica cuando el satélite gana atributos. Requiere disciplina: el `hash_diff` debe
calcularse **sobre los mismos atributos y en el mismo orden**, siempre.

---

### ADR-03 — Satélites separados por sensibilidad y ritmo de cambio

**Contexto.** La persona tiene atributos demográficos, de ingreso y de uso de canales.

**Decisión.** Tres satélites separados.

**Sustento.**

| Criterio | Efecto |
|---|---|
| **Sensibilidad** | El ingreso es dato sensible (Ley 29733): en tabla aparte se le da un `GRANT` distinto — **y está dado**, ver abajo |
| **Ritmo de cambio** | La demografía cambia cada ola; el ingreso, no. Juntos, un cambio de edad reescribiría el ingreso |
| **Fuente** | Cada satélite declara su origen; mezclar fuentes destruye la trazabilidad |

**Consecuencias.** Más tablas y más JOINs para reconstruir la persona. Se compensa con la vista
`vw_persona_vigente`.

> **La separación física no protege nada por sí sola.** Una versión anterior de este caso separaba
> el satélite de ingreso "para poder darle un `GRANT` distinto" y **no daba ninguno**: la tabla
> quedaba tan accesible como el resto. Era una intención presentada como control, que es peor que
> no tener control, porque tranquiliza.
>
> Ahora el esquema crea dos roles y los usa:
>
> ```sql
> GRANT  SELECT ON sat_persona_demografia TO rol_analista_inclusion;
> REVOKE ALL    ON sat_persona_ingreso  FROM rol_analista_inclusion;
> GRANT  SELECT ON sat_persona_ingreso    TO rol_datos_sensibles;
> ```
>
> Y **CAL-17** lo verifica consultando `information_schema.role_table_grants`: si alguien quita el
> `REVOKE`, la regla falla en la siguiente ejecución. Es la diferencia entre documentar un control
> y tenerlo.

---

### ADR-04 — Ningún atributo en hubs ni links, verificado por regla

**Contexto.** Es la regla que más se rompe "por comodidad".

**Decisión.** Hubs y links contienen **solo** llaves y trazabilidad, y **CAL-07/CAL-08 lo verifican
consultando `information_schema`**.

**Sustento.** Un atributo en el hub obliga a hacer `UPDATE` cuando cambia, rompiendo el insert-only
y la inmutabilidad de la historia.

**Consecuencias.** Si alguien agrega una columna descriptiva a un hub, la validación falla en la
siguiente ejecución. **Una regla de calidad que valida el diseño, no los datos.**

---

### ADR-05 — El Data Vault no se expone al usuario final

**Contexto.** Responder una pregunta simple cuesta ocho JOINs (PN-09).

**Decisión.** Capa de vistas (`vw_persona_vigente`, `vw_inclusion_financiera`) como Information Mart.

**Consecuencias.** Sobre esa capa se puede construir, además, un modelo estrella como el del caso 05.
Data Vault y dimensional **no compiten: se complementan**.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| **Atributos en el hub** | Rompe el insert-only y la inmutabilidad | **CAL-07** |
| Atributos en el link | Igual | **CAL-08** |
| Insertar en el satélite en cada carga | Crecimiento sin motivo | **CAL-09** |
| Calcular el hash de dos formas | La misma persona genera dos hubs | **CAL-01** |
| Usar `<>` en lugar de `IS DISTINCT FROM` | La primera carga no inserta nada | Ninguna fila cargada |
| Hacer `UPDATE` sobre un satélite | Se pierde la historia | Revisión de diseño |
| Dar el Data Vault al usuario final | Consultas de ocho JOINs, nadie lo usa | PN-09 |
| Olvidar `sistema_origen` | Sin trazabilidad ante una auditoría | **CAL-06** |
| Confundir `fecha_carga` con la fecha del hecho | Análisis temporal incorrecto | Revisión del diccionario |

---

## La demostración del caso

Ejecuta la ola 2026 y observa:

1. **`hub_persona` casi no creció** (solo las 100 personas nuevas): las llaves de negocio ya existían.
2. **`sat_persona_ingreso` creció 500, no 1 500**: solo cambió un tercio.
3. **`sat_persona_canal_digital` es una tabla nueva**: la fuente agregó preguntas y el modelo las
   absorbió **sin modificar una sola tabla existente**.

El punto 3 es el argumento del Data Vault. En un modelo dimensional habría requerido `ALTER TABLE`
sobre una dimensión de millones de filas, revisar todos los procesos que la leen y decidir qué valor
tienen las filas históricas.

---

## Lo que enseña este caso frente a los anteriores

| Caso | Aporte nuevo |
|---|---|
| 05 | Modelo dimensional: optimizado para consultar |
| **09** | **Data Vault: optimizado para integrar, auditar y absorber cambios de las fuentes. Y por qué ambos conviven** |
