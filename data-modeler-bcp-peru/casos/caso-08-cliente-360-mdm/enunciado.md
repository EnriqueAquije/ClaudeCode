# Caso 08 — MDM / Cliente 360: un solo cliente a partir de seis sistemas

**Dificultad:** ★★★★☆ · **Tiempo estimado:** 12 a 14 horas · **Esquema:** `caso08`
**Técnicas:** matching determinista y probabilístico · reglas de supervivencia · linaje por atributo · referencia cruzada

⚠️ **Requisito previo:** haber cargado los **casos 01, 02, 04 y 07**. Este caso integra los
clientes de esos cuatro sistemas, más un CRM y el padrón de SUNAT.

---

## 1. Situación de negocio

La Gerencia General pide una cifra simple: **¿cuántos clientes tiene el banco?**

Cada área da un número distinto:

| Área | Su respuesta | De dónde la saca |
|---|---|---|
| Captaciones | 500 | Su core |
| Créditos | 900 | Su core |
| Billetera digital | 3 000 | Su plataforma |
| Cumplimiento | 800 | Su sistema de monitoreo |
| Comercial | "unos 5 000" | Suma todo |

**Todas están mal.** La misma persona puede tener cuenta de ahorro, crédito y billetera: en la suma
se cuenta tres veces. Y en el CRM aparece otra vez, con el documento mal tipeado.

Las consecuencias son concretas: la rentabilidad por cliente está mal calculada, las campañas
duplican envíos, el riesgo agregado por persona no se ve, y Cumplimiento no puede saber que un
cliente alertado en un sistema es el mismo que opera en otro.

Te encargan construir el **registro maestro de clientes**.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Cada sistema fuente tiene su propio identificador de cliente. **No hay una clave común.** |
| RN-02 | La clave natural de negocio es **tipo + número de documento**. |
| RN-03 | Los sistemas tienen una **precedencia** definida: cuando discrepan, se sabe cuál gana. |
| RN-04 | Dos registros con el **mismo documento** son la misma persona: match determinista. |
| RN-05 | Dos registros con el mismo nombre, misma fecha de nacimiento y documento a **distancia de edición ≤ 2** son probablemente la misma persona con un error de digitación. |
| RN-06 | Dos registros con el mismo nombre y fecha de nacimiento pero **documentos totalmente distintos** son probablemente **homónimos**: van a revisión manual, **nunca** a fusión automática. |
| RN-07 | El registro maestro se **deriva**, nunca se digita. |
| RN-08 | Cada atributo del maestro puede tener un **criterio de supervivencia distinto**. |
| RN-09 | La **actividad económica** de una persona jurídica la determina **SUNAT**, sin importar la frescura del dato. |
| RN-10 | La **dirección y el teléfono** se toman del dato **más reciente**, no del más autoritativo. |
| RN-11 | Debe poder responderse, por cada atributo del maestro, **de qué sistema salió**. |
| RN-12 | Un registro de origen pertenece a **un solo** maestro. |
| RN-13 | Debe medirse la **calidad** de cada registro y de cada fuente. |

## 3. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuántos clientes **reales** tiene el banco? ¿Cuál era el porcentaje de duplicación? |
| PN-02 | ¿Cuántos duplicados detectó cada regla y con qué score? |
| PN-03 | ¿Qué casos quedaron en revisión manual y por qué **no** se fusionaron? |
| PN-04 | ¿En cuántos sistemas existe cada cliente? |
| PN-05 | ¿De qué fuente salió cada atributo del maestro? |
| PN-06 | ¿Qué calidad tiene cada sistema fuente? |
| PN-07 | ¿Qué fuente aporta más al registro maestro? |
| PN-08 | ¿Qué clientes están en tres o más sistemas? |
| PN-09 | ¿Cómo se ve un cliente **antes** y **después** de la fusión? |
| PN-10 | ¿Qué combinaciones de productos tienen los clientes? *(imposible sin MDM)* |

## 4. Criterios de aceptación

- [ ] Existe un catálogo de fuentes con **precedencia única** (sin empates).
- [ ] Los registros crudos de cada fuente **se conservan sin modificar**.
- [ ] El matching es determinista **y** probabilístico, con reglas configurables y umbrales.
- [ ] Los **homónimos NO se fusionan**: quedan en revisión manual.
- [ ] Cada atributo del maestro tiene un criterio de supervivencia documentado.
- [ ] Existe **linaje por atributo**: se sabe de qué registro de origen salió cada dato.
- [ ] Un registro de origen pertenece a un solo maestro (garantizado por la PK del xref).
- [ ] Se mide la calidad de cada registro y se puede comparar entre fuentes.
- [ ] El cuadre es exacto: `registros fuente = maestros + duplicados resueltos`.

## 5. Trampas del caso

1. **Fusionar homónimos.** Es el **peor error posible del MDM**: mezcla el historial de dos
   personas distintas. Si un cliente con crédito moroso se fusiona con otro que no lo tiene, ambos
   quedan mal clasificados, y deshacerlo es carísimo. Ante la duda, **no se fusiona**.
2. **Corregir el maestro a mano.** Si alguien edita el golden record, el próximo proceso lo
   sobrescribe. Las correcciones van **a la fuente**.
3. **Un solo criterio de supervivencia para todo.** "Siempre gana el core" da direcciones de hace
   cuatro años. "Siempre gana lo más reciente" da la actividad económica que digitó un vendedor.
4. **Modificar los datos crudos.** Si "limpias" el origen, pierdes la evidencia de por qué se
   fusionó y no puedes reprocesar.
5. **Matching sin índice.** Comparar nombres de todos contra todos es un producto cartesiano. Con
   5 000 registros son 25 millones de comparaciones; con 5 millones, 25 billones.
6. **Umbral demasiado bajo.** Bajar el umbral de auto-match sube la cobertura y sube los falsos
   positivos. En MDM el falso positivo es **más grave** que el falso negativo.
