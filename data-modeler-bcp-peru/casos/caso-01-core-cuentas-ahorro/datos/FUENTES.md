# Caso 01 — Fuentes de datos

## 1. Naturaleza de los datos de este caso

> **Los datos de `carga_datos.sql` son 100 % SINTÉTICOS y determinísticos.**
> No provienen de ninguna entidad financiera ni representan a ninguna persona real. Se generan por
> aritmética modular (sin `random()`), de modo que dos ejecuciones producen exactamente el mismo
> resultado — requisito para poder validar el caso automáticamente.

| Elemento | Origen | Nota |
|---|---|---|
| Nombres y apellidos | Listas de apellidos y nombres frecuentes en el Perú | Combinados por fórmula; cualquier coincidencia con una persona real es casual y no intencionada |
| Números de documento | Rango sintético reservado (DNI que inician en `70`, generados por secuencia) | **No corresponden a documentos emitidos**; no fueron validados ni pueden validarse contra RENIEC |
| Números de cuenta y CCI | Generados por secuencia | Formato estructuralmente válido, entidades ficticias |
| Montos y saldos | Fórmula determinística | Órdenes de magnitud plausibles para cuentas de ahorro minoristas |
| Ubigeos | **Reales**, catálogo oficial INEI (muestra de 12 distritos capitales) | Ver fuente 2.1 |
| Cuentas contables | Ilustrativas, con formato del Manual de Contabilidad SBS | No son el plan de cuentas oficial |
| Catálogo de monedas | **Real**, ISO 4217 | PEN, USD |

---

## 2. Fuentes públicas utilizadas como referencia

### 2.1 Ubigeo — INEI

```
Fuente:         Instituto Nacional de Estadística e Informática (INEI)
Recurso:        Codificación geográfica oficial (ubigeo)
URL:            https://www.inei.gob.pe/
Portal abierto: https://www.datosabiertos.gob.pe/
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de libre acceso
Uso aquí:       Catálogo cat_ubigeo (muestra de 12 distritos capitales de provincia)
Transformación: Selección de una muestra; sin modificación de los códigos
```

> El catálogo completo tiene aproximadamente 1 890 distritos. Para ampliar el caso, descarga el
> listado oficial del INEI o de la Plataforma Nacional de Datos Abiertos y reemplaza los 12
> registros de muestra. **La estructura del modelo no cambia.**

### 2.2 Estructura de productos de captación — información comercial pública

```
Fuente:         Información comercial pública de bancos peruanos (tarifarios y hojas de producto)
Ejemplo:        https://www.viabcp.com/
Fecha acceso:   2026-09-16
Uso aquí:       Definir familias de producto realistas (Ahorro, Sueldo, CTS, Corriente) y
                el hecho de que la TREA y la moneda son atributos del producto
Transformación: Los productos del modelo son GENÉRICOS e inventados; no reproducen el tarifario
                ni las condiciones de ningún banco. Las TREA usadas son ilustrativas.
```

### 2.3 Estructura de saldos y captaciones del sistema — SBS

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:        Información Estadística de Banca Múltiple
URL:            https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1
Boletines:      https://www.sbs.gob.pe/publicaciones/boletines-estadisticos
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de libre acceso
Uso aquí:       Referencia conceptual de cómo se reportan depósitos por tipo de producto y moneda
Transformación: Solo estructura conceptual. NO se usaron cifras de la SBS en los datos generados.
```

### 2.4 Marco normativo

```
Fuente:         Ley N.º 29733, Ley de Protección de Datos Personales
URL:            https://www.gob.pe/institucion/congreso-de-la-republica/normas-legales/243470-29733
Uso aquí:       Clasificación de sensibilidad del diccionario de datos; decisión ADR-01
                (documento de identidad no puede ser llave primaria); vistas enmascaradas
```

```
Fuente:         SBS - Manual de Contabilidad para las empresas del sistema financiero
Portal:         https://www.sbs.gob.pe/normativa
Uso aquí:       Justificación del campo cat_tipo_movimiento.cuenta_contable y de la necesidad
                de cuadre contable (regla CAL-04). Los códigos usados son ILUSTRATIVOS.
```

---

## 3. Cómo trabajar este caso con datos reales

Si quieres reemplazar los datos sintéticos por datos públicos reales:

| Qué reemplazar | Fuente real | Cómo |
|---|---|---|
| `cat_ubigeo` | INEI / Datos Abiertos | Descargar el catálogo completo de distritos e insertarlo |
| Volumen de captaciones | SBS, Banca Múltiple | Calibrar los saldos para que el total por producto se aproxime a las cifras públicas del sistema |
| Distribución geográfica | INEI, población por distrito | Distribuir las cuentas proporcionalmente a la población |

**Lo que NO se puede reemplazar con datos reales:** los clientes, cuentas y movimientos
individuales. Esa información está protegida por el **secreto bancario** (Ley 26702) y por la
**Ley 29733**. No existe — ni debe existir — una fuente pública de movimientos bancarios
individuales en el Perú.

---

## 4. Verificación de enlaces

Los enlaces fueron verificados en **setiembre de 2026**. Los portales del Estado peruano
reorganizan sus URLs con frecuencia. Si un enlace falla:

1. Entra al dominio raíz (`sbs.gob.pe`, `inei.gob.pe`) y busca la sección por su nombre.
2. El caso **no depende de ninguna descarga externa**: `carga_datos.sql` genera todo localmente.
