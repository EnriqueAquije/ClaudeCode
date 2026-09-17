# Caso 06 — Fuentes de datos

## 1. Naturaleza de los datos

| Elemento | Origen | Nota |
|---|---|---|
| Serie de tipo de cambio | **SIMULADA** determinísticamente | Oscila alrededor de 3.72 PEN/USD; conserva las **propiedades estructurales** de la serie real: solo días hábiles, spread compra-venta, variación diaria acotada |
| **Calendario de feriados 2026** | **REAL** (referencial) | Feriados nacionales del Perú; ver advertencia abajo |
| Saldos en moneda extranjera | Sintéticos | Órdenes de magnitud plausibles para un banco mediano |
| Códigos de serie (`PD04637PD`, …) | **Reales** de BCRPData | Incluidos para trazabilidad; **verificar vigencia** antes de automatizar |

> **Este es el único caso del repositorio cuya fuente real es descargable en un solo paso y sin
> registro.** Por eso incluye [`carga_bcrp_real.sql`](carga_bcrp_real.sql): puedes reemplazar la
> serie simulada por la real y comprobar que **el modelo no cambia**.

---

## 2. Fuente principal: BCRPData

```
Fuente:         Banco Central de Reserva del Perú (BCRP)
Recurso:        BCRPData - Base de Datos de Estadísticas del BCRP
Portal:         https://estadisticas.bcrp.gob.pe/estadisticas/series/
API:            https://estadisticas.bcrp.gob.pe/estadisticas/series/api/
Documentación:  https://estadisticas.bcrp.gob.pe/estadisticas/series/documentos/bcrpdataapi.pdf
Add-in Excel:   https://estadisticas.bcrp.gob.pe/estadisticas/series/ayuda/addin
Fecha acceso:   2026-09-16
Licencia/uso:   Datos públicos, sin API key, uso libre citando al BCRP
```

### Formato de la API

```
https://estadisticas.bcrp.gob.pe/estadisticas/series/api/{codigos}/{formato}/{desde}/{hasta}/{idioma}
```

| Parámetro | Valores |
|---|---|
| `codigos` | De 1 a 10 códigos de serie, separados por guion. Todas de la **misma frecuencia** |
| `formato` | `json`, `xml`, `csv`, `txt`, `jsonp` |
| `desde` / `hasta` | Según la frecuencia de la serie (diaria: `AAAA-MM-DD`) |
| `idioma` | `esp` o `ing` |

Ejemplo:

```bash
curl "https://estadisticas.bcrp.gob.pe/estadisticas/series/api/PD04637PD/csv/2026-01-01/2026-12-31/esp"
```

> ⚠️ **Los códigos de serie pueden cambiar entre versiones del portal.** Verifícalos siempre
> abriendo la ficha de la serie en BCRPData (busca "tipo de cambio bancario") antes de codificar
> una carga automática. Los códigos citados aquí son referenciales a la fecha de acceso.

---

## 3. Fuentes complementarias

### 3.1 Tipo de cambio contable — SBS

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:        Tipo de cambio contable publicado para el sistema financiero
Portal:         https://www.sbs.gob.pe/
Uso aquí:       Justificar la existencia del tipo CONTABLE_SBS, distinto del bancario del BCRP.
                Es el que se usa para valorizar el balance de las entidades supervisadas.
Advertencia:    Los valores del caso son SIMULADOS.
```

### 3.2 Tipo de cambio tributario — SUNAT

```
Fuente:         Superintendencia Nacional de Aduanas y de Administración Tributaria (SUNAT)
Portal:         https://www.sunat.gob.pe/
Uso aquí:       Justificar el tipo SUNAT_VENTA: el tipo de cambio de uso tributario puede
                diferir del contable y del bancario del mismo día.
```

### 3.3 Feriados nacionales

```
Fuente:         Plataforma del Estado Peruano
URL:            https://www.gob.pe/
Fecha acceso:   2026-09-16
Uso aquí:       Calendario de días no hábiles bancarios de cat_calendario.
Advertencia:    ⚠️ REFERENCIAL. Los feriados se establecen y modifican por norma (feriados
                largos, días no laborables del sector público, feriados regionales). Jueves y
                Viernes Santo son movibles: en 2026 caen el 2 y 3 de abril.
                VERIFICAR la lista oficial de cada año antes de usarla en producción.
```

---

## 4. Por qué la serie del caso es simulada y no descargada

El contenedor donde se validó este repositorio no tiene acceso de red a los portales del Estado
peruano, y **un caso que solo funciona con conexión a internet no es 100 % desarrollable**.

La solución adoptada es la correcta desde el punto de vista del diseño:

| Decisión | Consecuencia |
|---|---|
| La serie simulada conserva las propiedades estructurales de la real | Los huecos, el spread y la variación acotada se comportan igual |
| El modelo no distingue una fuente de otra | Cambiar de origen no requiere cambiar el modelo |
| `carga_bcrp_real.sql` documenta el camino completo | Quien tenga conexión puede usar datos reales en 5 minutos |
| Las 14 reglas de calidad son independientes de la fuente | Sirven igual con datos simulados o reales |

**La prueba de que el modelo está bien hecho es que funcione con ambos.**

---

## 5. Ejercicios con datos reales

| Ejercicio | Serie sugerida | Qué se aprende |
|---|---|---|
| Serie 2020-2026 completa | Tipo de cambio bancario | Volatilidad real, feriados de varios años, arrastres largos |
| Inflación mensual | Índice de precios al consumidor | Series de **frecuencia mensual**: el modelo debe adaptarse al grano |
| Tasa de referencia del BCRP | Tasa de política monetaria | Series que cambian pocas veces al año: muchos arrastres |
| Comparar dos fuentes | Bancario (BCRP) vs contable (SBS) | Cuantificar la diferencia entre fuentes para el mismo día |
