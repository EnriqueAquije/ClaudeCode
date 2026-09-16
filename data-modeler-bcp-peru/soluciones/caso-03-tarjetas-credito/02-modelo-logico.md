# Caso 03 — Modelo lógico y diccionario de datos

```mermaid
erDiagram
    cat_marca            ||--o{ cuenta_tarjeta : identifica
    cat_moneda           ||--o{ cuenta_tarjeta : denomina
    cat_estado_tarjeta   ||--o{ cuenta_tarjeta : clasifica
    cat_tipo_transaccion ||--o{ transaccion : tipifica
    cat_rubro            ||--o{ transaccion : clasifica
    titular              ||--o{ cuenta_tarjeta : posee
    cuenta_tarjeta       ||--|{ plastico : emite
    cuenta_tarjeta       ||--|{ ciclo_facturacion : factura
    cuenta_tarjeta       ||--o{ transaccion : registra
    cuenta_tarjeta       ||--|{ linea_credito_hist : historia
    plastico             ||--o{ transaccion : origina
    transaccion          ||--o{ transaccion_cuota : fracciona
    ciclo_facturacion    ||--|| estado_cuenta : produce

    cuenta_tarjeta {
        BIGINT   cuenta_tj_id PK
        VARCHAR  num_cuenta_tj UK
        BIGINT   titular_id FK
        VARCHAR  marca_cod FK
        CHAR     moneda_cod FK
        VARCHAR  estado_tj_cod FK
        SMALLINT dia_facturacion "1..28"
        NUMERIC  linea_aprobada
        NUMERIC  tea_revolvente
        NUMERIC  tea_cuotas
    }
    plastico {
        BIGINT  plastico_id PK
        BIGINT  cuenta_tj_id FK
        CHAR    num_plastico_enmasc UK "SOLO enmascarado"
        VARCHAR tipo_plastico "TITULAR/ADICIONAL"
        DATE    fecha_expiracion
        BOOLEAN esta_activo
    }
    ciclo_facturacion {
        BIGINT cuenta_tj_id PK,FK
        CHAR   periodo PK
        DATE   fecha_inicio
        DATE   fecha_cierre
        DATE   fecha_vencimiento
    }
    transaccion {
        BIGINT   transaccion_id PK
        BIGINT   cuenta_tj_id FK
        BIGINT   plastico_id FK
        VARCHAR  num_operacion UK
        TIMESTAMP fecha_operacion
        DATE     fecha_proceso
        CHAR     periodo_cargo "explicito"
        VARCHAR  tipo_trx_cod FK
        VARCHAR  rubro_cod FK
        NUMERIC  monto
        NUMERIC  monto_con_signo
        SMALLINT num_cuotas
    }
    transaccion_cuota {
        BIGINT   transaccion_id PK,FK
        SMALLINT num_cuota PK
        CHAR     periodo_cargo
        NUMERIC  monto_capital
        NUMERIC  monto_interes
        NUMERIC  monto_cuota
    }
    estado_cuenta {
        BIGINT  cuenta_tj_id PK,FK
        CHAR    periodo PK
        DATE    fecha_cierre
        DATE    fecha_vencimiento
        NUMERIC saldo_anterior
        NUMERIC total_consumos
        NUMERIC total_cargos
        NUMERIC total_pagos
        NUMERIC saldo_actual
        NUMERIC pago_minimo
        NUMERIC linea_aprobada
        NUMERIC linea_disponible
        NUMERIC monto_pagado
        INTEGER dias_atraso
    }
    linea_credito_hist {
        BIGINT  cuenta_tj_id PK,FK
        DATE    fecha_desde PK
        DATE    fecha_hasta
        NUMERIC linea_anterior
        NUMERIC linea_nueva
        VARCHAR motivo
    }
```

---

## Las tres reglas que viven en la base

| Regla | Implementación | Por qué declarativa y no por proceso |
|---|---|---|
| **RN-06 cuadre** | `CHECK (saldo_actual = saldo_anterior + total_consumos + total_cargos - total_pagos)` | Un estado de cuenta descuadrado no debe **poder existir**; detectarlo al día siguiente es tarde: el cliente ya lo recibió |
| **RN-02 un titular activo** | Índice único parcial `WHERE tipo_plastico='TITULAR' AND esta_activo` | Permite históricamente varios titulares (reposiciones), pero solo uno vigente |
| **RN-11 pago mínimo** | `CHECK (pago_minimo <= GREATEST(saldo_actual, 0))` | Evita cobrar más de lo facturado por un error de cálculo |

### RN-14 implementada por **ausencia**

No existe columna para el PAN completo. La forma más fuerte de garantizar que un dato no se filtre
es **que no haya dónde guardarlo**. Complementa con CAL-11, que verifica que todo número almacenado
contenga caracteres de enmascaramiento.

---

## Verificación de formas normales

| Forma | Verificación | Resultado |
|---|---|---|
| 1FN | Las cuotas están en tabla propia, no como columnas `cuota_1..cuota_12` | ✅ |
| 2FN | En `transaccion_cuota (transaccion_id, num_cuota)`, los montos dependen de la PK completa | ✅ |
| 3FN | `rubro_desc` vive en `cat_rubro`; `marca_desc` en `cat_marca`; ningún atributo derivable duplicado en `transaccion` | ✅ |

### Desnormalizaciones deliberadas

| Campo | Motivo | Control |
|---|---|---|
| `estado_cuenta.total_*` y `saldo_*` | El estado de cuenta es un **documento emitido**: sus cifras se congelan | `CHECK` de cuadre + CAL-03 contra transacciones |
| `transaccion.periodo_cargo` | Derivable de la fecha y el ciclo, pero se almacena para fijar el corte y evitar recalcularlo | CAL-08: el periodo debe existir como ciclo de esa cuenta |
| `transaccion.monto_con_signo` | Evita JOIN al catálogo en agregaciones | `CHECK (ABS(monto_con_signo) = monto)` |
| `estado_cuenta.linea_aprobada` | Congela la línea vigente al cierre | `linea_credito_hist` conserva la historia completa |

> **`periodo_cargo` explícito es la decisión más importante del modelo físico.** La alternativa
> —deducir el ciclo en cada consulta a partir de la fecha y el día de facturación— es lenta, se
> repite en cada reporte y se rompe con la primera excepción operativa.

---

## Diccionario de datos (extracto)

### `estado_cuenta`

| Columna | Tipo | Nulo | Dominio / regla | Descripción | Sensibilidad |
|---|---|---|---|---|---|
| `cuenta_tj_id` | BIGINT | No | FK | Cuenta de tarjeta | Interno |
| `periodo` | CHAR(6) | No | FK a ciclo | Periodo AAAAMM | Interno |
| `saldo_anterior` | NUMERIC(18,2) | No | = saldo actual del ciclo previo | Saldo con que abre el ciclo | **Confidencial** |
| `total_consumos` | NUMERIC(18,2) | No | = Σ transacciones del ciclo | Contado + disposiciones + cuotas vencidas | **Confidencial** |
| `total_cargos` | NUMERIC(18,2) | No | ≥ 0 | Intereses + comisiones | **Confidencial** |
| `total_pagos` | NUMERIC(18,2) | No | ≥ 0 | Pagos aplicados en el ciclo | **Confidencial** |
| `saldo_actual` | NUMERIC(18,2) | No | **`CHECK` de cuadre** | Saldo facturado | **Confidencial** |
| `pago_minimo` | NUMERIC(18,2) | No | ≤ `saldo_actual` | Mínimo exigido | **Confidencial** |
| `dias_atraso` | INTEGER | No | ≥ 0 | Atraso al vencimiento | **Confidencial** |

### `plastico`

| Columna | Sensibilidad | Tratamiento |
|---|---|---|
| `num_plastico_enmasc` | **Confidencial** | Solo enmascarado; el PAN completo **no se almacena** |
| `nombre_impreso` | **Dato personal** | Enmascarar fuera de producción |

---

## Matriz source-to-target

| Destino | Campo | Origen | Campo origen | Transformación | Calidad |
|---|---|---|---|---|---|
| `transaccion` | `periodo_cargo` | Autorizador | `FEC_PROCESO` | Ubicar el ciclo de la cuenta que contiene la fecha | CAL-08 |
| `transaccion` | `monto_con_signo` | Autorizador | `IMPORTE`, `COD_TRX` | `IMPORTE × signo` del catálogo | `ABS = monto` |
| `plastico` | `num_plastico_enmasc` | Emisor | `PAN` | **Enmascarar en origen**; el PAN nunca llega al almacén | CAL-11 |
| `estado_cuenta` | `saldo_anterior` | Proceso de cierre | ciclo previo | `LAG(saldo_actual)` | CAL-02 |
| `transaccion_cuota` | `periodo_cargo` | Motor de cuotas | — | periodo de compra + (nro. cuota − 1) meses | CAL-05 |
