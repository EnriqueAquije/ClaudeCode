# Caso 04 — Fuentes de datos

## 1. Naturaleza de los datos

> **100 % SINTÉTICOS y determinísticos.** Ningún usuario, celular, dispositivo o transferencia es
> real. Los números de celular se generan por secuencia dentro de un rango sintético y **no
> corresponden a líneas asignadas**.

| Elemento | Origen | Nota |
|---|---|---|
| Usuarios y celulares | Generados por fórmula | Formato peruano válido (9 dígitos iniciando en 9), pero sintéticos |
| Documentos | Rango sintético reservado | No validados contra ningún registro |
| Identificadores de dispositivo | `MD5` de un contador | No corresponden a dispositivos reales |
| Montos y frecuencias | Fórmula determinística | Calibrados para reflejar micro-pagos (S/ 5 a S/ 50), típicos de billeteras peruanas |
| Límites operativos | **Referenciales** | ⚠️ Ilustrativos; verificar política y norma vigente |
| Ubigeos | **Reales**, INEI (muestra) | Ver caso 01 |

---

## 2. Fuentes públicas de referencia

### 2.1 Escala del mercado de billeteras digitales en el Perú

```
Fuente:         Credicorp - sala de prensa y relación con inversionistas
URL:            https://grupocredicorp.com/
Recurso:        Reportes trimestrales y notas de prensa sobre Yape
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública corporativa
Uso aquí:       Justificar el ORDEN DE MAGNITUD del caso (millones de usuarios activos
                mensuales, decenas de operaciones por usuario al mes) y por tanto la
                necesidad de particionamiento desde el diseño.
Advertencia:    Las cifras cambian cada trimestre. El caso NO reproduce datos de Yape:
                usa un volumen reducido (3 000 usuarios, ~150 000 operaciones) que
                mantiene las mismas propiedades estructurales.
```

### 2.2 Infraestructura tecnológica declarada públicamente

```
Fuente:         Microsoft Customer Stories - BCP
URL:            https://www.microsoft.com/es-mx/customers/story/1801893174290238225-viabcp-azure-banking-and-capital-markets-en-peru
Fecha acceso:   2026-09-16
Uso aquí:       Contexto: los canales digitales del BCP (banca móvil, billetera, portal de
                negocios) operan sobre infraestructura de nube pública.
Relevancia:     Explica por qué el modelo debe ser portable y pensado para escalar
                horizontalmente. NO se usó ninguna información técnica interna.
```

### 2.3 Marco de límites y monitoreo

```
Fuente:         SBS / UIF-Perú - normativa de prevención de LA/FT
Portal:         https://www.sbs.gob.pe/normativa
Uso aquí:       Justificación de la tabla par_limite (límites por operación, por monto
                diario y por cantidad diaria) como PARÁMETRO VIGENTE POR FECHA.
Advertencia:    Los valores cargados (S/ 500 por operación, S/ 2 000 diarios para persona
                natural) son ILUSTRATIVOS y no reproducen ninguna norma ni política real.
                Ver el caso 07 para el tratamiento completo de PLAFT.
```

### 2.4 Estadísticas de pagos digitales

```
Fuente:         Banco Central de Reserva del Perú (BCRP) - estadísticas de sistemas de pagos
URL:            https://estadisticas.bcrp.gob.pe/estadisticas/series/
Fecha acceso:   2026-09-16
Licencia/uso:   Datos públicos, uso libre citando al BCRP
Uso aquí:       Referencia de la evolución del volumen de pagos digitales en el Perú,
                para calibrar la distribución horaria y el ticket promedio.
Transformación: Solo calibración cualitativa. Ninguna cifra del BCRP fue copiada.
```

---

## 3. Cómo escalar este caso

Si quieres probar el modelo a volumen mayor, edita `carga_datos.sql`:

| Cambio | Efecto | Tiempo de carga aproximado |
|---|---|---|
| `generate_series(1, 500)` | ~25 000 transferencias | 3 a 5 s |
| `generate_series(1, 3000)` (por defecto) | ~150 000 transferencias | 20 a 60 s |
| `generate_series(1, 20000)` | ~1 000 000 transferencias | 3 a 8 min |

Con un millón de filas la diferencia entre consultar con y sin filtro de fecha se vuelve **evidente
a simple vista**, lo que hace la demostración del paso 7 mucho más convincente.

> **Recuerda añadir particiones** si extiendes el rango de fechas más allá de setiembre de 2026,
> o todas las filas nuevas caerán en `transferencia_default` y CAL-08 fallará — que es exactamente
> el comportamiento que la regla debe detectar.
