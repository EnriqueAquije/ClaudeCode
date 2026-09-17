# Caso 07 — Solución de referencia

## Ejecución

```bash
psql -d bcp_lab -f 03-modelo-fisico.sql
psql -d bcp_lab -f ../../casos/caso-07-plaft-monitoreo/datos/carga_datos.sql
psql -d bcp_lab -f 04-consultas-negocio.sql
psql -d bcp_lab -f 05-calidad-datos.sql
```

**Resultado esperado:** 800 clientes, 27 666 operaciones, 59 registros en el RO, **235 alertas**,
21 casos, 2 ROS y **16 reglas de calidad en `OK`**.

| Regla | Alertas | Severidad |
|---|---|---|
| R01-UMBRAL | 59 | 3 |
| R02-FRACC | 21 | 5 |
| R03-PERFIL | 126 | 4 |
| R04-GEO | 15 | 4 |
| R05-PEP | 14 | 5 |

---

## Registro de decisiones (ADR)

### ADR-01 — Las reglas de monitoreo son datos, no código

**Contexto.** Cambiar un umbral requería seis semanas de desarrollo.

**Decisión.** `regla_monitoreo` con vigencia, severidad, `esta_activa` y parámetros en `JSONB`.

**Alternativas evaluadas.**
- *Reglas en funciones SQL o en el motor de la aplicación*: es el problema que el caso pide resolver.
- *Un motor de reglas externo*: válido en organizaciones grandes, pero **no elimina** la necesidad
  de conservar en la base qué regla estaba vigente en cada fecha, que es lo que se exhibe en una
  revisión.

**Consecuencias.** Activar, desactivar o recalibrar una regla es un `UPDATE`. A cambio, el motor de
evaluación debe ser genérico y leer los parámetros, lo que exige disciplina: cada `tipo_regla` debe
documentar las claves que espera en `parametros`.

---

### ADR-02 — `JSONB` para parámetros y para evidencia

**Contexto.** Cada tipo de regla necesita parámetros distintos, y cada alerta una evidencia distinta.

**Decisión.** `regla_monitoreo.parametros` y `alerta.detalle` en `JSONB`, con índice GIN sobre el
segundo.

**Sustento.** Una columna por parámetro daría una tabla de veinte columnas casi siempre nulas, que
habría que alterar cada vez que nace un tipo de regla nuevo.

**Límite explícito de la decisión.** `JSONB` **no** se usa para datos con estructura estable. Los
campos que toda alerta tiene —cliente, fechas, monto, severidad— son **columnas**, porque se filtran,
se agregan y se validan.

---

### ADR-03 — La ventana de fraccionamiento se define por tiempo, no por filas

**Contexto.** Hay que detectar operaciones acumuladas en 5 días.

**Decisión.** `RANGE BETWEEN INTERVAL '4 days' PRECEDING AND CURRENT ROW`.

**Alternativas evaluadas.**
- *`ROWS BETWEEN 3 PRECEDING`*: cuenta **filas**, no días. Cuatro operaciones separadas por meses
  dispararían la alerta.
- *Auto-join por rango de fechas*: funcionalmente equivalente pero mucho más costoso sobre
  volúmenes reales.

**Consecuencias.** La ventana es correcta por definición. Requiere PostgreSQL 11+ y que la columna
de orden sea de tipo fecha.

---

### ADR-04 — La condición que distingue fraccionamiento de una operación grande

**Contexto.** Una operación de S/ 150 000 hace que la suma de la ventana supere el umbral.

**Decisión.** La regla exige, además, que **ninguna operación de la ventana supere el umbral por sí
sola** (`mayor_ventana < umbral`).

**Sustento.** Sin esa condición, R02 duplicaría todas las alertas de R01, saturando al equipo y
distorsionando la tasa de falsos positivos de ambas reglas.

**Control.** **CAL-07** verifica esta propiedad en todas las alertas de fraccionamiento.

---

### ADR-05 — El deber de reserva se implementa con RLS, no en la aplicación

**Contexto.** RN-13: está prohibido que el cliente o terceros conozcan un ROS.

**Decisión.** `ENABLE` **y `FORCE`** `ROW LEVEL SECURITY` sobre `ros`, política que solo admite
`rol_oficial_cumplimiento`, y ausencia deliberada de `GRANT` para `rol_analista_negocio`.

**`FORCE` no es opcional, y omitirlo es el error más común al implementar RLS.** Con `ENABLE` a
secas, el **dueño** de la tabla se salta todas las políticas. En un banco el dueño del esquema suele
ser el usuario con el que corre el proceso batch, así que sin `FORCE` el ROS queda legible
precisamente para la cuenta que más consultas ejecuta. Se comprueba con:

```sql
SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = 'ros';
-- Ambas deben ser true. Con la primera en true y la segunda en false, el control NO existe.
```

**Sustento.**

| Control | ¿Lo evade una consulta SQL directa? |
|---|---|
| Validación en el código | **Sí** |
| Pantalla oculta | **Sí** |
| `GRANT` + RLS **sin `FORCE`** | **Sí, si la hace el dueño de la tabla** |
| `GRANT` + RLS **con `FORCE`** | **No** |

**Consecuencias.** El control es efectivo incluso para quien tenga acceso directo a la base.

**Lo que este caso NO resuelve, y conviene que sepas:** `bitacora_acceso_ros` modela *cómo* se
registraría cada consulta, pero **no se alimenta sola**. Un `SELECT` no dispara un trigger, así que
registrar lecturas exige `pgaudit` o exponer el ROS solo a través de una función `SECURITY DEFINER`
que escriba la bitácora antes de devolver la fila. Las filas que trae el laboratorio están sembradas
a mano. Modelar el control y no implementarlo es legítimo en un ejercicio; **darlo por implementado
sería enseñarte a confiar en algo que no está**.

---

## Errores frecuentes

| Error | Consecuencia | Se detecta con |
|---|---|---|
| Evaluar operación por operación | **El fraccionamiento nunca se detecta** | PN-03 |
| Omitir `mayor_ventana < umbral` | R02 duplica todas las alertas de R01 | **CAL-07** |
| `ROWS` en vez de `RANGE` | Ventana incorrecta: cuenta filas, no días | Revisión de la consulta |
| Umbral incrustado en el código | Cada cambio normativo es un proyecto | Revisión de diseño |
| Alerta sin evidencia | El analista la descarta por defecto | **CAL-15** |
| Sobrescribir el perfil del cliente | No se puede explicar una alerta pasada | `uq_cliente_perfil_vigente` |
| Control de acceso al ROS en la aplicación | Una consulta SQL lo evade | **CAL-14** |
| No medir la tasa de falsos positivos | Reglas que saturan y terminan ignoradas | PN-02 |

---

## La demostración del caso

**PN-03b** muestra las cuatro operaciones de un cliente con patrón de fraccionamiento, con el
acumulado corriendo al lado:

| Fecha | Monto | ¿Sobre umbral? | Acumulado |
|---|---|---|---|
| 10-ago | 35 100 | bajo umbral | 35 100 |
| 11-ago | 34 800 | bajo umbral | 69 900 |
| 12-ago | 36 200 | bajo umbral | 106 100 |
| 13-ago | 35 400 | bajo umbral | 141 500 |

**Ninguna operación es reportable por sí sola. Las cuatro juntas, sí.** Esa tabla es el entregable
que sustenta la alerta ante el Oficial de Cumplimiento.

---

## Advertencia final

Este caso enseña **arquitectura de modelo de datos para monitoreo**, no cumplimiento normativo.
Los umbrales, reglas, listas de países y niveles de riesgo son **inventados**. Un sistema real se
diseña con el Oficial de Cumplimiento de la entidad, sobre la norma vigente de la SBS/UIF-Perú.

Lo transferible es el **cómo**: reglas como datos, parámetros con vigencia, evidencia embebida,
ventanas por tiempo y seguridad en la base de datos.
