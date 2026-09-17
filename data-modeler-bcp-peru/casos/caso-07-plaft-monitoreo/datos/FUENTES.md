# Caso 07 — Fuentes de datos

## 1. Naturaleza de los datos

> **100 % SINTÉTICOS.** Ningún cliente, operación, alerta, caso ni reporte corresponde a una persona
> o hecho real. **Los patrones sospechosos fueron insertados a propósito** para que las reglas
> tengan qué detectar.

| Elemento | Origen | Nota |
|---|---|---|
| Clientes y operaciones | Generados por fórmula | Documentos en rango sintético reservado |
| **Patrón de fraccionamiento** | **Insertado deliberadamente** | 4 depósitos de ~35 000 en 5 días para ~21 clientes |
| Umbrales | **Referenciales** | ⚠️ No reproducen la norma vigente |
| Códigos CIIU | **Formato real** | Los códigos de actividad económica son del estándar CIIU; el **nivel de riesgo asignado es ilustrativo** |
| Países de alto riesgo | **Ilustrativos** | ⚠️ No reproducen ninguna lista oficial vigente |
| Nombres de analistas y oficiales | Ficticios | `analista.uno`, `oficial.cumplimiento` |

---

## 2. Advertencia especial de este caso

> ### ⚠️ Este caso NO es asesoría de cumplimiento
>
> El monitoreo PLAFT es una **obligación legal** con consecuencias penales y administrativas. Este
> material es **exclusivamente educativo sobre modelado de datos**.
>
> - Los **umbrales** (S/ 40 000) son inventados para el ejercicio.
> - Las **reglas de monitoreo** son ilustrativas y no constituyen un sistema de detección válido.
> - La **lista de países** no reproduce ninguna lista oficial (GAFI, SBS u otra).
> - Los **niveles de riesgo** por actividad económica son ilustrativos.
>
> Un sistema real se diseña con el **Oficial de Cumplimiento** de la entidad, siguiendo la norma
> vigente de la SBS/UIF-Perú. Lo transferible de este caso es la **arquitectura del modelo de
> datos**, no sus parámetros.

---

## 3. Marco normativo de referencia

```
Fuente:         Ley N.º 27693 - Ley que crea la Unidad de Inteligencia Financiera del Perú
Portal:         https://www.gob.pe/
Uso aquí:       Marco general de las obligaciones de PLAFT: Registro de Operaciones,
                deteccion de operaciones inusuales, Reporte de Operaciones Sospechosas
                y deber de reserva.
```

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS) - UIF-Perú
Recurso:        Reglamentos de gestión de riesgos de lavado de activos y financiamiento
                del terrorismo para el sistema financiero
Buscador:       https://www.sbs.gob.pe/normativa
Portal UIF:     https://www.sbs.gob.pe/prevencion-de-lavado-activos
Fecha acceso:   2026-09-16
Licencia/uso:   Normas públicas de libre acceso
Uso aquí:       Estructura del modelo: Registro de Operaciones con umbrales, debida
                diligencia del cliente (KYC), tratamiento reforzado de PEP y de
                jurisdicciones de alto riesgo, y deber de reserva del ROS.
Advertencia:    ⚠️ TODOS los valores numéricos del caso son inventados. La norma vigente
                debe consultarse directamente.
```

```
Fuente:         Ley N.º 29733 - Ley de Protección de Datos Personales
URL:            https://www.gob.pe/institucion/congreso-de-la-republica/normas-legales/243470-29733
Uso aquí:       Clasificación de sensibilidad. Nota relevante: la información PLAFT tiene
                plazos de conservación largos por obligación legal, lo que interactúa con
                el derecho de cancelación. Esa tensión se documenta en el modelo.
```

---

## 4. Estándar de clasificación de actividad económica

```
Fuente:         Clasificación Industrial Internacional Uniforme (CIIU)
Referencia:     Naciones Unidas / INEI (adopción peruana)
Portal INEI:    https://www.inei.gob.pe/
Uso aquí:       Los códigos de 4 dígitos de cat_actividad_economica siguen el formato CIIU.
Advertencia:    El campo nivel_riesgo (1 a 3) es una ASIGNACIÓN ILUSTRATIVA del ejercicio,
                no una clasificación oficial de riesgo PLAFT.
```

---

## 5. Datos de contexto disponibles públicamente

Si quieres enriquecer el caso con datos públicos reales:

| Qué | Fuente | Uso |
|---|---|---|
| Padrón de contribuyentes (RUC) | SUNAT — <https://www.sunat.gob.pe/descargaPRR/mrc137_padron_reducido.html> | Validar que la actividad económica declarada coincide con la registrada ante SUNAT. **Es un control PLAFT real** |
| Estadísticas del sistema financiero | SBS — <https://www.sbs.gob.pe/> | Calibrar volúmenes de operación por tipo de entidad |
| Tipo de cambio | BCRPData — <https://estadisticas.bcrp.gob.pe/estadisticas/series/> | Convertir operaciones en ME para compararlas contra umbrales en soles (ver caso 06) |

> El cruce con el padrón RUC de SUNAT es un ejercicio especialmente valioso: detectar que un cliente
> declarado como "restaurante" tiene actividad registrada de "casa de cambio" es exactamente el tipo
> de inconsistencia que busca la debida diligencia. Ese cruce es el **caso 08**.

---

## 6. Sobre los patrones insertados

Para que un motor de reglas pueda probarse, los datos deben contener lo que se busca detectar:

| Patrón | Cómo se insertó | Qué regla lo detecta |
|---|---|---|
| Operación sobre umbral | Clientes con `id % 17 = 0`: una operación de 45 000 a 165 000 | R01-UMBRAL |
| **Fraccionamiento** | Clientes con `id % 37 = 0`: 4 depósitos de ~33 000-39 000 entre el 10 y el 13 de agosto | **R02-FRACC** |
| Exceso de perfil | Emerge naturalmente de la relación entre operativa y perfil declarado | R03-PERFIL |
| Jurisdicción de riesgo | Clientes con `id % 53 = 0`: transferencia a PA, KY o VG | R04-GEO |
| PEP con efectivo alto | Clientes con `id % 79 = 0` marcados como PEP | R05-PEP |

**Esta transparencia es parte del método:** un conjunto de datos de prueba debe documentar **qué
contiene**, o no se puede saber si el motor falla por un error o porque no había nada que detectar.
