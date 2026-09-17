# Caso 05 — Data warehouse dimensional de captaciones y colocaciones

**Dificultad:** ★★★☆☆ · **Tiempo estimado:** 10 a 12 horas · **Esquema:** `caso05`
**Técnicas:** modelo estrella (Kimball) · SCD2 · dimensión conformada · medidas semiaditivas · ETL

⚠️ **Requisito previo obligatorio:** haber completado y cargado los **casos 01 y 02**.
Este caso **no genera datos propios**: los extrae de esos sistemas transaccionales, como ocurre en
la realidad.

---

## 1. Situación de negocio

El banco tiene los sistemas transaccionales funcionando (casos 01 y 02), pero **el negocio no puede
responder preguntas**:

- Comercial pide "saldo por región y segmento" y TI responde que tarda dos días en prepararlo.
- Riesgos y Comercial reportan **cifras distintas de clientes** porque cada uno define "cliente" a
  su manera.
- Nadie puede responder "¿cuánto captamos del segmento Preferente **en mayo**?" porque el segmento
  de los clientes se sobrescribe cada vez que cambia.
- Los reportes de captaciones y de colocaciones **no se pueden cruzar**: usan códigos de producto
  distintos y códigos de cliente distintos.

Te encargan diseñar el **modelo analítico** que resuelva esto.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | El modelo debe permitir analizar **captaciones y colocaciones en el mismo tablero**. |
| RN-02 | El cliente se identifica por **tipo y número de documento**, aunque venga de dos sistemas distintos. |
| RN-03 | El **segmento del cliente cambia en el tiempo**. Un análisis de mayo debe usar el segmento que el cliente tenía **en mayo**, no el actual. |
| RN-04 | Debe existir una **jerarquía geográfica**: distrito → provincia → departamento → macro región. |
| RN-05 | La macro región **no existe en ningún sistema fuente**: la define el negocio y se construye en el ETL. |
| RN-06 | Se necesitan tres niveles de detalle: el **movimiento individual**, el **saldo mensual por cuenta** y la **situación mensual del deudor**. |
| RN-07 | El saldo de fin de mes **no puede sumarse entre meses**: es una medida semiaditiva. |
| RN-08 | Ningún hecho puede perderse por un dato faltante en una dimensión. |
| RN-09 | Todo dato del almacén debe poder **rastrearse hasta su sistema origen**. |
| RN-10 | El almacén debe **cuadrar exactamente** con los sistemas fuente: misma cantidad y mismos montos. |
| RN-11 | El usuario de negocio debe poder consultar sin escribir JOINs. |

## 3. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuánto captamos por mes, familia de producto y moneda? |
| PN-02 | ¿Cómo evoluciona el saldo por macro región? |
| PN-03 | ¿Qué departamentos concentran la captación? |
| PN-04 | ¿Cuánto transó cada segmento **en cada mes**, con el segmento vigente en ese mes? |
| PN-05 | ¿Cómo se distribuye la cartera de créditos por clasificación SBS y región? |
| PN-06 | ¿Cuántos clientes tienen **a la vez** productos de captación y de colocación? |
| PN-07 | ¿Qué proporción de operaciones es digital frente a presencial? |
| PN-08 | ¿Cuál es el saldo total del banco? *(cuidado: la respuesta obvia está mal)* |
| PN-09 | ¿Quiénes son los 10 clientes con mayor saldo y de qué segmento y región son? |
| PN-10 | ¿El almacén cuadra exactamente con los sistemas fuente? |

## 4. Criterios de aceptación

- [ ] El modelo es **estrella**: tablas de hechos rodeadas de dimensiones, sin cadenas de JOINs.
- [ ] Toda dimensión tiene **clave sustituta** y conserva su clave natural.
- [ ] Toda dimensión tiene un **miembro DESCONOCIDO** (`sk = -1`).
- [ ] `dim_cliente` es **SCD tipo 2** y no tiene vigencias solapadas ni huecos.
- [ ] Los hechos se enlazan a la versión de la dimensión **vigente a la fecha del hecho**.
- [ ] `dim_producto` es **conformada**: sirve a captaciones y colocaciones.
- [ ] Existen los tres tipos de hecho: transaccional y **dos** snapshots periódicos.
- [ ] Las medidas semiaditivas están **documentadas como tales**.
- [ ] El cuadre con el origen es **exacto** (diferencia = 0 en cantidad y monto).
- [ ] Existen vistas de consumo para el usuario de negocio.

## 5. Trampas del caso

1. **El JOIN al SCD2.** Si enlazas los hechos a la versión vigente **hoy**, reescribes la historia:
   las ventas de enero aparecerán bajo el segmento que el cliente tiene ahora. Es el error más caro
   del modelado analítico y es **invisible** hasta que alguien compara dos reportes de distinta fecha.
2. **Sumar el saldo entre meses.** `SUM(saldo_fin_mes)` sobre todos los meses da un número enorme y
   sin significado. Es la medida semiaditiva.
3. **`MAX(periodo)` no es el "último periodo".** En estos datos el último mes solo contiene
   movimientos de cierre de cuentas canceladas. Un reporte que use ciegamente el máximo mostrará
   cifras absurdas.
4. **El `JOIN` interno que pierde hechos.** Si un movimiento no encuentra su cliente y usas `JOIN`
   en vez de `LEFT JOIN` + miembro desconocido, **el hecho desaparece** y el almacén deja de cuadrar.
   Nadie lo nota: simplemente faltan filas.
5. **Dos sistemas, un cliente.** El mismo documento puede venir del core de captaciones y del core
   de créditos con **ids internos distintos**. ¿Cuál es la clave natural de la dimensión?
6. **La macro región no existe en el origen.** ¿Dónde vive esa regla? Si la pones en cada reporte,
   habrá tantas definiciones como analistas.
