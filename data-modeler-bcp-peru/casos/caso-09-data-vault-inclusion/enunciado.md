# Caso 09 — Data Vault 2.0: inclusión financiera con microdatos tipo ENAHO

**Dificultad:** ★★★★★ · **Tiempo estimado:** 12 a 16 horas · **Esquema:** `caso09`
**Técnicas:** Hub / Link / Satélite · claves hash · insert-only · `hash_diff` · absorción de cambios de origen

---

## 1. Situación de negocio

El banco quiere medir **inclusión financiera**: qué segmentos de la población tienen productos
financieros y cuáles no. Los datos vienen de una encuesta de hogares que se levanta **cada año**,
y el área de Estudios Económicos reporta tres problemas:

1. **La encuesta cambia de un año a otro.** Cada ola agrega preguntas nuevas. El modelo dimensional
   actual exige un `ALTER TABLE` sobre una dimensión de millones de filas en cada cambio.
2. **Se perdió la historia.** El modelo sobrescribe: ya no se puede saber qué respondió una persona
   en la ola anterior, ni reproducir el informe publicado el año pasado.
3. **No se sabe de dónde viene cada dato.** Hay tres fuentes (encuesta, catálogo de productos,
   geografía oficial) y los datos ya están mezclados.

Te encargan modelar la capa integrada con **Data Vault 2.0**.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Las **llaves de negocio** (persona, hogar, distrito, producto) son estables y se cargan una sola vez. |
| RN-02 | La llave de negocio del hogar es **compuesta**: conglomerado + vivienda + hogar + año, igual que en los microdatos de la ENAHO. |
| RN-03 | Toda fila debe registrar su **fecha de carga** y su **sistema origen**. |
| RN-04 | **Nunca se hace `UPDATE` ni `DELETE`** sobre los datos: la historia es inmutable. |
| RN-05 | Un atributo que **no cambió** entre dos cargas **no genera una fila nueva**. |
| RN-06 | Debe poder reconstruirse la foto de cualquier persona **a cualquier fecha pasada**. |
| RN-07 | Si la fuente agrega atributos nuevos, el modelo debe absorberlos **sin modificar ninguna tabla existente**. |
| RN-08 | Los atributos **sensibles** (ingreso) deben poder separarse de los demás, con control de acceso propio. |
| RN-09 | Las claves deben permitir **carga en paralelo**, sin depender de secuencias ni de búsquedas previas. |
| RN-10 | El usuario de negocio **no consulta el Data Vault directamente**: consume vistas. |

## 3. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuál es la tasa de inclusión financiera por departamento? |
| PN-02 | ¿Cómo se relaciona la inclusión con el nivel educativo y el ingreso? |
| PN-03 | ¿Cuál es la brecha urbano-rural? |
| PN-04 | ¿Cómo evolucionó el ingreso entre las dos olas? |
| PN-05 | ¿Cuántas filas agregó cada ola a cada tabla? *(la propiedad del Data Vault)* |
| PN-06 | ¿Por qué las personas no usan canales digitales? *(pregunta nueva de la ola 2026)* |
| PN-07 | ¿Cómo se veía una persona el 31 de diciembre de 2025? |
| PN-08 | ¿Qué productos tiene la gente y con qué antigüedad y frecuencia de uso? |
| PN-09 | ¿Cuántos JOINs cuesta una pregunta simple? *(el costo del Data Vault)* |
| PN-10 | ¿Qué sistema origen aportó cada dato? |

## 4. Criterios de aceptación

- [ ] Solo existen tres tipos de tabla: **hub, link y satélite**. Sin excepciones.
- [ ] Ningún hub ni link contiene **atributos descriptivos**.
- [ ] Todas las claves son **hash de la llave de negocio**, calculadas con una función única.
- [ ] Toda fila tiene **fecha de carga** y **sistema origen**.
- [ ] La segunda ola **no duplica** hubs ni links existentes.
- [ ] El satélite solo inserta fila si el **`hash_diff` cambió**.
- [ ] Los atributos nuevos de la ola 2026 se absorben con un **satélite adicional**, sin tocar nada.
- [ ] Se puede reconstruir la foto de cualquier fecha pasada.
- [ ] Existe una capa de vistas que reconstruye la foto plana para el negocio.

## 5. Trampas del caso

1. **Poner atributos en el hub.** Es el error que arruina el modelo: el hub deja de ser una llave
   estable y pasa a necesitar historia. Un hub tiene **la llave y nada más**.
2. **Hacer `UPDATE`.** Rompe la propiedad fundamental. La única excepción tolerada es cerrar
   `fecha_fin_carga`, y hay equipos que ni siquiera eso permiten (usan una vista con `LEAD()`).
3. **Insertar en el satélite en cada carga.** Sin `hash_diff`, un satélite de 10 millones de
   personas crece 10 millones de filas al mes aunque nada haya cambiado.
4. **Calcular el hash de dos formas distintas.** Si un proceso hace `MD5(doc)` y otro
   `MD5(TRIM(UPPER(doc)))`, la misma persona genera dos hubs. Por eso hay **una sola función**.
5. **Dar el Data Vault al usuario final.** Responder una pregunta simple cuesta ocho JOINs. El
   Data Vault optimiza carga y auditoría, **no consulta**.
6. **Creer que el Data Vault reemplaza al modelo dimensional.** Son complementarios: DV como capa
   integrada, estrella como capa de consumo.
