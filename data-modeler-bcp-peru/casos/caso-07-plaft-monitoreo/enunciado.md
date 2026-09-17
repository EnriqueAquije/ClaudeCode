# Caso 07 — PLAFT: monitoreo de operaciones inusuales y sospechosas

**Dificultad:** ★★★★☆ · **Tiempo estimado:** 10 a 12 horas · **Esquema:** `caso07`
**Técnicas:** motor de reglas como datos · ventanas deslizantes · JSONB para evidencia · seguridad a nivel de fila

---

## 1. Situación de negocio

El área de Cumplimiento tiene tres problemas:

1. **Las reglas de monitoreo están programadas.** Cambiar un umbral, activar una regla nueva o
   desactivar una que satura al equipo requiere un despliegue de software de seis semanas.
2. **No se detecta el fraccionamiento.** El sistema evalúa operación por operación, así que alguien
   que deposita cuatro veces S/ 35 000 en una semana **nunca dispara una alerta**, mientras que
   quien deposita S/ 45 000 de una vez sí.
3. **El acceso a los reportes sospechosos no está controlado.** Un analista comercial puede
   consultar la base y ver qué clientes fueron reportados a la UIF — lo que viola el **deber de
   reserva** y puede constituir una infracción grave.

Te encargan modelar el sistema de monitoreo PLAFT.

## 2. Reglas de negocio

| # | Regla |
|---|---|
| RN-01 | Las operaciones que superan un **umbral** deben incorporarse al **Registro de Operaciones (RO)**. |
| RN-02 | Los umbrales los fija la norma y **cambian**: deben poder modificarse sin desplegar código. |
| RN-03 | Las **reglas de monitoreo** también son configurables: se activan, desactivan y versionan. |
| RN-04 | Cada regla tiene una **severidad** que determina cómo se prioriza la alerta. |
| RN-05 | El **fraccionamiento** debe detectarse: varias operaciones que individualmente no superan el umbral pero **acumuladas en una ventana de días sí lo hacen**. |
| RN-06 | Debe registrarse el **perfil transaccional esperado** de cada cliente (debida diligencia) y compararse contra su comportamiento real. |
| RN-07 | Los clientes **PEP** requieren debida diligencia reforzada. |
| RN-08 | Las operaciones con **jurisdicciones de alto riesgo** generan alerta. |
| RN-09 | Toda alerta debe conservar la **evidencia** que la generó: qué se evaluó, contra qué umbral y con qué valores. |
| RN-10 | Las alertas se agrupan en **casos de investigación** asignados a un analista. |
| RN-11 | Un caso cerrado **siempre** tiene disposición; uno abierto, **nunca**. |
| RN-12 | Solo una disposición genera **ROS** (Reporte de Operaciones Sospechosas). |
| RN-13 | El ROS está sujeto a **reserva estricta**: está prohibido informar al cliente o a terceros. |
| RN-14 | Todo acceso a información del ROS debe quedar **registrado en bitácora**. |

## 3. Normativa aplicable

| Norma | Exigencia | Consecuencia en el modelo |
|---|---|---|
| **Ley N.º 27693** (UIF-Perú) y reglamentos SBS de gestión de riesgos de LA/FT | Registro de Operaciones, detección de inusuales, reporte de sospechosas | `par_umbral`, `regla_monitoreo`, `registro_operacion`, `ros` |
| Deber de reserva del ROS | Prohibido informar al cliente o a terceros | **RLS** sobre `ros` + `bitacora_acceso_ros` |
| Conocimiento del cliente (KYC) | Debida diligencia y perfil transaccional | `cliente_perfil` con vigencia |
| Debida diligencia reforzada | PEP y jurisdicciones de alto riesgo | `es_pep`, `cat_pais.es_alto_riesgo` |
| Ley 29733 | Documento y nombre son datos personales | Clasificación y enmascaramiento |

> ⚠️ Los umbrales, plazos y criterios del caso son **referenciales con fines educativos**.
> Verifica la norma vigente en <https://www.sbs.gob.pe/normativa> y consulta al área de
> Cumplimiento. **Este material no es asesoría legal ni de cumplimiento.**

## 4. Preguntas de negocio

| # | Pregunta |
|---|---|
| PN-01 | ¿Cuántas alertas genera cada regla, con qué severidad y cuántas se escalan? |
| PN-02 | ¿Cuál es la **tasa de falsos positivos** de cada regla? |
| PN-03 | ¿Qué clientes muestran patrón de **fraccionamiento** y cuál es el detalle operación por operación? |
| PN-04 | ¿Qué clientes disparan **varias reglas distintas**? |
| PN-05 | ¿Cómo se reparte la carga entre analistas y cuánto demora cerrar un caso? |
| PN-06 | ¿Qué operaciones entraron al Registro de Operaciones y por qué umbral? |
| PN-07 | ¿Qué operativa tienen los clientes PEP y cuándo fue su última debida diligencia? |
| PN-08 | ¿Qué clientes se desvían más de su perfil declarado? |
| PN-09 | ¿Cuánto se transa con jurisdicciones de alto riesgo? |
| PN-10 | ¿Quién puede ver el ROS y cómo se demuestra ante una revisión? |

## 5. Criterios de aceptación

- [ ] Los umbrales viven en una tabla **con vigencia**, nunca en el código.
- [ ] Las reglas de monitoreo son **filas**, no funciones programadas.
- [ ] La regla de fraccionamiento detecta operaciones acumuladas en **ventana deslizante**.
- [ ] La alerta de fraccionamiento **excluye** los casos donde una operación ya supera el umbral sola.
- [ ] Cada alerta conserva su **evidencia** en un campo estructurado.
- [ ] Un `CHECK` impide un caso cerrado sin disposición.
- [ ] Solo se genera ROS desde disposiciones que lo ameritan.
- [ ] La tabla `ros` tiene **seguridad a nivel de fila** y el rol de negocio **no** tiene acceso.
- [ ] Existe bitácora de acceso al ROS.

## 6. Trampas del caso

1. **Evaluar operación por operación.** Es la trampa central. Una regla que solo mira la operación
   actual **jamás** detecta fraccionamiento. Necesitas una ventana deslizante.
2. **La alerta de fraccionamiento que en realidad es de umbral.** Si no excluyes los casos donde
   una operación ya supera el umbral por sí sola, duplicas alertas y ensucias las estadísticas.
3. **La regla programada.** Si tu regla es una función SQL con los valores incrustados, no
   resolviste el problema del enunciado.
4. **La alerta sin evidencia.** Una alerta que solo dice "cliente 1234, severidad 5" es inútil: el
   analista no puede reconstruir por qué se generó y termina descartándola.
5. **La seguridad en la aplicación.** Si el control de acceso al ROS vive solo en el software, una
   consulta directa a la base lo evade. Debe estar **en la base de datos**.
6. **La tasa de falsos positivos.** Una regla que genera miles de alertas descartadas no es una
   regla estricta: es una regla que **nadie va a revisar**. Hay que medirla.
