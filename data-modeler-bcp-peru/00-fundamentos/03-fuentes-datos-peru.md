# Fuentes de datos legales, verificadas y gratuitas — Perú y banca

> Catálogo de fuentes públicas usadas por los 10 casos. Todas son de **acceso gratuito**, **legal** y
> **sin necesidad de pagar**. Algunas requieren registro gratuito (se indica).
>
> **Fecha de verificación de enlaces: setiembre de 2026.** Los portales estatales reorganizan sus
> URLs con cierta frecuencia: si un enlace directo falla, entra al dominio raíz y busca la sección
> indicada. Por eso **cada caso de este repositorio incluye además un generador de datos propio**,
> de modo que el ejercicio se puede completar aunque la descarga externa no esté disponible.

---

## 1. Reguladores y estadística oficial

### 1.1 SBS — Superintendencia de Banca, Seguros y AFP

| Recurso | Qué contiene | Formato | URL |
|---|---|---|---|
| Portal institucional | Normativa, reglamentos, resoluciones | HTML/PDF | <https://www.sbs.gob.pe/> |
| Boletines estadísticos | Información mensual por entidad: banca múltiple, financieras, cajas | Excel/PDF | <https://www.sbs.gob.pe/publicaciones/boletines-estadisticos> |
| Estadística de Banca Múltiple | Colocaciones, depósitos, morosidad, patrimonio **por banco** | Excel | <https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1> |
| Series históricas del Sistema Financiero | Series largas para análisis temporal | Excel | <https://www.sbs.gob.pe/app/pp/serieshistoricas2/> |
| Tasas de interés | Tasas activas y pasivas por entidad y producto | Web/Excel | <https://www.sbs.gob.pe/app/pp/EstadisticasSAEEPortal/Paginas/TIActivaTipoCreditoEmpresa.aspx> |
| Normativa (búsqueda) | Resoluciones y circulares | PDF | <https://www.sbs.gob.pe/normativa> |

**Uso en este repositorio:** casos 02, 05, 07 y 10.
**Licencia / condiciones:** información pública de acceso libre. Cita la fuente y la fecha de corte.

### 1.2 BCRP — Banco Central de Reserva del Perú

| Recurso | Qué contiene | Formato | URL |
|---|---|---|---|
| **BCRPData** | Base de series estadísticas macroeconómicas y financieras | Web/Excel | <https://estadisticas.bcrp.gob.pe/estadisticas/series/> |
| **API BCRPData** | Consulta directa de series, **sin API key** | JSON/CSV/XML | <https://estadisticas.bcrp.gob.pe/estadisticas/series/api/> |
| Documentación de la API | Formato de URL y parámetros | PDF | <https://estadisticas.bcrp.gob.pe/estadisticas/series/documentos/bcrpdataapi.pdf> |
| Add-in para Excel | Descarga de series desde Excel | Excel | <https://estadisticas.bcrp.gob.pe/estadisticas/series/ayuda/addin> |

**Formato de la API** (no requiere registro):

```
https://estadisticas.bcrp.gob.pe/estadisticas/series/api/{codigos}/{formato}/{desde}/{hasta}/{idioma}
```

Ejemplo — tipo de cambio bancario promedio, en JSON:

```bash
curl "https://estadisticas.bcrp.gob.pe/estadisticas/series/api/PD04640PD/json/2026-01-01/2026-01-31/esp"
```

Reglas de uso de la API: mínimo 1 y máximo 10 códigos de serie por llamada, separados por guion, y
todas las series deben tener la **misma frecuencia**. Formatos soportados: `json`, `xml`, `csv`,
`txt`, `jsonp`.

> Cómo encontrar el código de una serie: entra a BCRPData, busca la serie (ej. "tipo de cambio
> bancario"), ábrela y copia el código que aparece en su ficha (formato tipo `PD04640PD`,
> `PN01288PM`). Los códigos pueden cambiar entre versiones del portal; **verifícalos siempre en la
> ficha de la serie** antes de codificar una carga automática.

**Uso en este repositorio:** caso 06 (tipo de cambio y posición en moneda extranjera).
**Licencia:** datos públicos, uso libre citando al BCRP.

### 1.3 Plataforma Nacional de Datos Abiertos

| Recurso | URL |
|---|---|
| Portal | <https://www.datosabiertos.gob.pe/> |
| Búsqueda de conjuntos de datos | <https://www.datosabiertos.gob.pe/search/type/dataset> |

Incluye conjuntos publicados por SUNAT, INEI, MINSA, RENIEC y gobiernos regionales. La mayoría se
publica bajo licencias abiertas; **revisa la licencia indicada en la ficha de cada conjunto**.

### 1.4 INEI — Instituto Nacional de Estadística e Informática

| Recurso | Qué contiene | URL |
|---|---|---|
| **Microdatos** | Bases de encuestas: ENAHO, ENAPRES, ENDES, CENSOS | <https://proyectos.inei.gob.pe/microdatos/> |
| ENAHO | Encuesta Nacional de Hogares: ingresos, gastos, acceso a servicios financieros | vía Microdatos |
| Ubigeo | Codificación oficial de departamento / provincia / distrito | <https://www.inei.gob.pe/> |
| Series estadísticas | Población, PBI, empleo | <https://www.inei.gob.pe/estadisticas/indice-tematico/> |

**Registro:** la descarga de microdatos requiere completar un formulario gratuito.
**Uso en este repositorio:** casos 05 y 09.

### 1.5 SUNAT

| Recurso | Qué contiene | Formato | URL |
|---|---|---|---|
| **Padrón Reducido del RUC** | Padrón de contribuyentes: RUC, razón social, estado, condición, dirección, CIIU | ZIP/TXT | <https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html> |
| Padrones y notificaciones | Otros padrones (buenos contribuyentes, agentes de retención) | Varios | <https://www.sunat.gob.pe/padronesnotificaciones/> |
| Consulta RUC | Consulta individual | Web | <https://e-consultaruc.sunat.gob.pe/> |

> El padrón reducido es un archivo grande (varios millones de filas). Para practicar basta con
> tomar una muestra. **No contiene datos de personas naturales sin negocio**, pero sí contiene datos
> de personas naturales con RUC: trátalo como **dato personal** bajo la Ley 29733.

**Uso en este repositorio:** caso 08 (MDM / Cliente 360).

### 1.6 Otras fuentes peruanas útiles

| Fuente | Qué contiene | URL |
|---|---|---|
| **SMV** — Superintendencia del Mercado de Valores | Estados financieros auditados de empresas listadas (incluido el propio BCP) | <https://www.smv.gob.pe/> |
| **Bolsa de Valores de Lima** | Cotizaciones e información de emisores | <https://www.bvl.com.pe/> |
| **Credicorp — sala de prensa e inversionistas** | Reportes trimestrales, memorias, cifras de Yape y BCP | <https://grupocredicorp.com/> |
| **BCP institucional** | Tarifario, memoria anual, contratos de productos | <https://www.viabcp.com/> |
| **Plataforma del Estado Peruano** | Normas legales | <https://www.gob.pe/> |
| **Diario Oficial El Peruano** | Texto oficial de normas | <https://diariooficial.elperuano.pe/> |
| **RENIEC** | Padrón electoral y estadísticas (no datos individuales) | <https://www.reniec.gob.pe/> |

---

## 2. Datasets internacionales con licencia libre (para riesgo de crédito)

Los datos de comportamiento crediticio a nivel cliente **no son públicos en el Perú** (están
protegidos por secreto bancario y por la Ley 29733). Para practicar modelado de riesgo se usan
datasets académicos con licencia abierta, adaptados al contexto peruano.

| Dataset | Contenido | Licencia | URL |
|---|---|---|---|
| **Statlog (German Credit Data)** | 1 000 solicitudes clasificadas como buen/mal riesgo, 20 atributos | CC BY 4.0 | <https://archive.ics.uci.edu/dataset/144/statlog+german+credit+data> |
| **Default of Credit Card Clients** | 30 000 clientes de tarjeta, 24 variables, historial de pago y mora | CC BY 4.0 | <https://archive.ics.uci.edu/dataset/350/default+of+credit+card+clients> |
| **Bank Marketing** | Campañas de telemarketing bancario | CC BY 4.0 | <https://archive.ics.uci.edu/dataset/222/bank+marketing> |
| **Portal UCI** | Catálogo general | Ver cada dataset | <https://archive.ics.uci.edu/> |
| **World Bank Open Data** | Indicadores de inclusión financiera (Global Findex) por país | CC BY 4.0 | <https://data.worldbank.org/> |
| **FMI — Financial Access Survey** | Acceso a servicios financieros por país | Uso público | <https://data.imf.org/> |

**Importante:** estos datasets son de origen alemán/taiwanés. En los casos de este repositorio se
usan como **estructura de referencia**, adaptando dominios y montos al contexto peruano
(soles, DNI, ubigeo, categorías SBS). Eso es exactamente lo que se hace en un proyecto real cuando
no se dispone aún de datos productivos.

---

## 3. Cómo citar una fuente en un entregable profesional

Cada caso incluye un `datos/FUENTES.md` con este formato mínimo:

```
Fuente:        Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:       Información Estadística de Banca Múltiple
URL:           https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1
Fecha acceso:  2026-09-16
Corte:         Julio 2026
Licencia/uso:  Información pública de libre acceso
Uso aquí:      Calibración de órdenes de magnitud de colocaciones y depósitos
Transformación: Agregado, anonimizado; los registros individuales son sintéticos
```

---

## 4. Reglas éticas y legales al usar datos en banca peruana

1. **Nunca uses datos productivos reales de clientes para practicar.** Están cubiertos por el
   secreto bancario (Ley 26702, art. 140 y siguientes) y por la Ley 29733.
2. **No publiques datos personales**, aunque los hayas obtenido de una fuente pública. La Ley 29733
   aplica igual al tratamiento posterior.
3. **Enmascara siempre** en ambientes de desarrollo, QA y capacitación.
4. **Cita la fuente y la fecha de corte**: una cifra bancaria sin fecha de corte no significa nada.
5. **Distingue dato real de dato sintético** en todo entregable. En este repositorio, los datos de
   los casos son **100% sintéticos y generados por script**.
6. **Respeta los términos de uso** de cada portal; no hagas *scraping* agresivo de sitios estatales.
