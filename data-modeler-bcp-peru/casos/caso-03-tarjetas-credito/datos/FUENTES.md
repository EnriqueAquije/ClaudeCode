# Caso 03 — Fuentes de datos

## 1. Naturaleza de los datos

> **100 % SINTÉTICOS y determinísticos.** Ningún titular, tarjeta, consumo o comercio es real.

| Elemento | Origen | Nota |
|---|---|---|
| Titulares y cuentas | Generados por fórmula | Documentos en rango sintético reservado |
| **Números de plástico** | **Ficticios y enmascarados** | Usan prefijos de prueba públicos (`411111`, `535522`, `378282`) que las redes reservan para pruebas y **no corresponden a tarjetas emitidas**. Además están enmascarados |
| Comercios y rubros | Nombres genéricos inventados | No representan comercios reales |
| Montos, líneas y tasas | Fórmula determinística | Órdenes de magnitud plausibles para el mercado peruano |
| Estructura del estado de cuenta | Basada en la cartilla estándar de tarjetas en el Perú | Ver fuente 2.2 |

> **Nota de seguridad:** el modelo **no tiene columna** para el número completo de tarjeta (PAN).
> Esa es una decisión de diseño deliberada: lo que no existe no se puede filtrar.

---

## 2. Fuentes públicas de referencia

### 2.1 Estadística de tarjetas de crédito del sistema financiero

```
Fuente:         Superintendencia de Banca, Seguros y AFP (SBS)
Recurso:        Información Estadística de Banca Múltiple - créditos de consumo y tarjetas
URL:            https://www.sbs.gob.pe/app/stats/EstadisticaBoletinEstadistico.asp?p=1
Fecha acceso:   2026-09-16
Licencia/uso:   Información pública de libre acceso
Uso aquí:       Calibración cualitativa del nivel de utilización de línea y de morosidad
Transformación: Solo calibración. NO se usaron cifras de la SBS en los datos generados.
```

### 2.2 Transparencia de información al usuario financiero

```
Fuente:         SBS - Normativa de transparencia de información y tarifarios de tarjetas
Portal:         https://www.sbs.gob.pe/normativa
Referencia:     https://www.sbs.gob.pe/usuarios
Uso aquí:       Estructura del estado de cuenta (saldo anterior, consumos, cargos, pagos,
                saldo actual, pago mínimo, fecha de vencimiento, línea disponible) y
                conceptos de TCEA, pago mínimo y compras en cuotas
Advertencia:    Las tasas y comisiones del caso son ILUSTRATIVAS, no reproducen ningún tarifario.
```

### 2.3 Tarifarios públicos de tarjetas de crédito en el Perú

```
Fuente:         Información comercial pública de entidades financieras peruanas
Ejemplo:        https://www.viabcp.com/  (sección tarjetas de crédito / tarifario)
Comparador:     https://www.sbs.gob.pe/app/retasas/paginas/retasasInicio.aspx
Uso aquí:       Confirmar que las compras en cuotas y el pago mínimo son características
                estándar del mercado peruano, y los rangos usuales de TEA revolvente
Transformación: Los productos del caso son genéricos e inventados.
```

### 2.4 Dataset abierto de comportamiento de tarjeta (para ampliar el caso)

```
Fuente:         UCI Machine Learning Repository
Dataset:        Default of Credit Card Clients (30 000 clientes, 24 variables)
URL:            https://archive.ics.uci.edu/dataset/350/default+of+credit+card+clients
Licencia:       Creative Commons Attribution 4.0 International (CC BY 4.0)
Fecha acceso:   2026-09-16
Uso aquí:       Referencia de ESTRUCTURA de variables de comportamiento de pago
                (límite de crédito, historial de pago mensual, montos facturados y pagados).
                Ningún registro fue copiado: los datos del caso se generan por fórmula.
Uso sugerido:   Cárgalo en una tabla stg_ y mapea sus columnas PAY_0..PAY_6, BILL_AMT1..6
                y PAY_AMT1..6 al modelo de estado_cuenta. Es un excelente ejercicio de
                mapeo origen-destino con una fuente real.
```

---

## 3. Cómo trabajar este caso con datos reales

| Qué | Fuente | Cómo |
|---|---|---|
| Comportamiento de pago | UCI *Default of Credit Card Clients* | Mapea sus 6 meses de historial al modelo de ciclos |
| Tasas de mercado | SBS, comparador de tasas | Reemplaza `tea_revolvente` y `tea_cuotas` |
| Niveles de morosidad | SBS, Banca Múltiple | Calibra la proporción de perfiles de pago |

**Nunca** uses datos reales de tarjetahabientes. Además del secreto bancario y la Ley 29733, los
datos de medios de pago tienen requisitos de seguridad específicos.
