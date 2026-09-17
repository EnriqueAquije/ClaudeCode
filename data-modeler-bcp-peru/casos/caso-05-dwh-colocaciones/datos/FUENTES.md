# Caso 05 — Fuentes de datos

## 1. Naturaleza de los datos

> **Este caso no genera datos propios.** Su fuente son los esquemas `caso01` (captaciones) y
> `caso02` (colocaciones), ambos 100 % sintéticos. Eso es deliberado: en la realidad **un data
> warehouse nunca nace de la nada**, nace de sistemas transaccionales que ya existen.

| Elemento del DWH | Sistema fuente | Transformación aplicada |
|---|---|---|
| `dim_tiempo` | **Ninguno** — se genera | El calendario no vive en ningún sistema operativo |
| `dim_ubigeo` | `caso01.cat_ubigeo` | **Enriquecido** con `macro_region` (regla de negocio nueva) |
| `dim_oficina` | `caso01.oficina` | Sustitución de clave natural por SK |
| `dim_producto` | `caso01.producto` + `caso02.cat_tipo_credito` | **Conformación**: dos vocabularios → una jerarquía |
| `dim_canal` | `caso01.cat_canal` | Se deriva `es_digital` |
| `dim_cliente` | `caso01.cliente` + `caso02.deudor` | **Integración por documento** + **SCD2** |
| `fact_movimiento` | `caso01.movimiento` | JOIN a dimensiones por vigencia |
| `fact_saldo_captacion_mes` | `caso01.movimiento` | **Agregación** a grano cuenta-mes |
| `fact_colocacion_mes` | `caso02.deudor_clasificacion_mes` | Sustitución de claves |

---

## 2. Fuentes públicas de referencia para el diseño

### 2.1 Estructura de reportes de captaciones y colocaciones

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:        Boletines estadísticos e Información Estadística de Banca Múltiple
URL:            https://www.sbs.gob.pe/publicaciones/boletines-estadisticos
                https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de libre acceso
Uso aquí:       Las DIMENSIONES del modelo (producto, moneda, región, tipo de crédito,
                clasificación) reproducen los ejes por los que la SBS y el propio sistema
                financiero peruano reportan la información. Esto no es casual: el modelo
                analítico debe alinearse con los ejes regulatorios, o el reporte a la SBS
                exigirá transformaciones ad hoc cada mes.
Transformación: Solo estructura. Ninguna cifra de la SBS fue usada en los datos.
```

### 2.2 Jerarquía geográfica oficial

```
Fuente:         Instituto Nacional de Estadística e Informática (INEI)
Recurso:        Codificación geográfica oficial (ubigeo) y división política
URL:            https://www.inei.gob.pe/
Portal abierto: https://www.datosabiertos.gob.pe/
Fecha acceso:   2026-09-16
Uso aquí:       Jerarquía distrito -> provincia -> departamento de dim_ubigeo.
Advertencia:    La MACRO REGIÓN (NORTE/CENTRO/SUR/ORIENTE) del caso es una agrupación
                COMERCIAL ILUSTRATIVA definida para el ejercicio. No corresponde a ninguna
                división administrativa oficial del Perú. Es, justamente, el ejemplo de un
                atributo que el negocio define y que el ETL debe construir.
```

### 2.3 Series macroeconómicas para contraste

```
Fuente:         BCRPData - Banco Central de Reserva del Perú
URL:            https://estadisticas.bcrp.gob.pe/estadisticas/series/
API:            https://estadisticas.bcrp.gob.pe/estadisticas/series/api/
Fecha acceso:   2026-09-16
Licencia/uso:   Datos públicos, sin API key, uso libre citando al BCRP
Uso sugerido:   Ejercicio de ampliación: descargar depósitos y créditos del sistema
                financiero y agregar una tabla de hechos de MERCADO, para comparar la
                evolución del banco contra el sistema. Es un caso clásico de hecho
                con distinto grano (sistema vs. entidad) en el mismo almacén.
```

---

## 3. Metodología de referencia

El modelo sigue la metodología dimensional de **Ralph Kimball**:

| Concepto aplicado | Dónde se ve en este caso |
|---|---|
| Los 4 pasos del diseño dimensional | Paso 1 del README |
| Clave sustituta en toda dimensión | Todas las `dim_*` |
| Miembro desconocido | Filas con `sk = -1` |
| SCD tipo 2 | `dim_cliente` |
| Dimensión conformada | `dim_producto` |
| Dimensión degenerada | `num_operacion` y `cuenta_id_origen` dentro de los hechos |
| Hecho transaccional vs snapshot periódico | `fact_movimiento` vs `fact_saldo_captacion_mes` |
| Medidas aditivas / semiaditivas | Documentadas en el diccionario |

> Estos conceptos son de dominio público y están descritos en la literatura estándar de modelado
> dimensional. Este repositorio los **implementa y valida**, no los reproduce textualmente.

---

## 4. Cómo ampliar el caso con datos reales

| Qué agregar | Fuente real | Ejercicio |
|---|---|---|
| Ubigeo completo (~1 890 distritos) | INEI / Datos Abiertos | Reemplaza la muestra de 12 y verifica que el ETL no se rompe |
| Hechos de mercado | BCRPData / SBS | Agrega `fact_mercado_mensual` con el saldo del **sistema**, y calcula la participación de mercado del banco |
| Población por distrito | INEI | Agrega `poblacion` a `dim_ubigeo` y calcula penetración por habitante |
| Tipo de cambio | BCRPData (caso 06) | Agrega `saldo_mn` para consolidar PEN y USD correctamente |
