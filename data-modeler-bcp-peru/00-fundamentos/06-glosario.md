# Glosario — modelado de datos y banca peruana

> Un Data Modeler es, en buena medida, **el custodio del glosario**. Cuando dos áreas discuten,
> casi siempre es porque usan la misma palabra con dos significados.

---

## A. Términos de modelado de datos

| Término | Definición |
|---|---|
| **Entidad** | Cosa del mundo real con identidad propia sobre la que se guarda información (CLIENTE, CUENTA) |
| **Atributo** | Propiedad de una entidad (saldo, fecha de apertura) |
| **Relación** | Vínculo entre entidades, con cardinalidad y verbo ("un CLIENTE mantiene CUENTAS") |
| **Cardinalidad** | Cuántas ocurrencias de una entidad participan: 1:1, 1:N, N:M |
| **Opcionalidad** | Si la participación es obligatoria o no (cero o uno, uno o muchos) |
| **Modelo conceptual** | Qué existe y cómo se relaciona, en lenguaje de negocio |
| **Modelo lógico** | Atributos, llaves y reglas, independiente del motor |
| **Modelo físico** | Implementación concreta en un motor: tipos, índices, particiones |
| **Notación Crow's Foot** | Notación de "pata de gallo" para cardinalidades; la más usada en la industria |
| **Notación Chen** | Notación académica con rombos para relaciones |
| **IDEF1X** | Notación formal usada en entornos corporativos y gobierno |
| **PK (llave primaria)** | Identificador único de cada fila |
| **FK (llave foránea)** | Referencia a la PK de otra tabla; garantiza integridad referencial |
| **Llave natural** | Identificador con significado de negocio (RUC, ubigeo) |
| **Llave sustituta (surrogate)** | Identificador técnico sin significado (autoincremental) |
| **Llave candidata** | Atributo o conjunto que podría ser PK |
| **Normalización** | Proceso de eliminar redundancia y anomalías (1FN, 2FN, 3FN, BCNF) |
| **Desnormalización** | Redundancia introducida a propósito por rendimiento; se documenta |
| **Granularidad** | Qué representa exactamente una fila de una tabla |
| **Cardinalidad de datos** | Número de valores distintos de una columna (afecta indexación) |
| **Integridad referencial** | Garantía de que toda FK apunta a una fila existente |
| **Constraint** | Regla declarada en la BD: PK, FK, UNIQUE, CHECK, NOT NULL |
| **Índice** | Estructura que acelera búsquedas; cuesta en escritura y espacio |
| **Particionamiento** | División física de una tabla (por rango de fecha, por lista) |
| **Diccionario de datos** | Documento que describe cada campo: tipo, dominio, significado, origen |
| **Linaje (lineage)** | Trazabilidad de un dato desde su origen hasta su consumo |
| **Catálogo de datos** | Inventario gobernado de activos de datos |
| **MDM (Master Data Management)** | Gestión de datos maestros para lograr una versión única |
| **Golden record** | Registro consolidado y confiable de una entidad maestra |
| **Data Steward** | Responsable del significado y calidad de un dominio de datos |
| **Esquema estrella** | Dimensional: una tabla de hechos rodeada de dimensiones |
| **Copo de nieve (snowflake)** | Estrella con dimensiones normalizadas |
| **Tabla de hechos** | Contiene métricas y las FK a dimensiones |
| **Dimensión** | Contexto descriptivo por el que se analiza (cliente, tiempo, producto) |
| **Hecho transaccional** | Una fila por evento ocurrido |
| **Hecho snapshot periódico** | Una fila por entidad y periodo (ej. saldo por cuenta y mes) |
| **Hecho acumulado (accumulating)** | Una fila por proceso, con hitos que se van completando |
| **Hecho sin hechos (factless)** | Registra la ocurrencia de una relación sin métricas |
| **SCD (Slowly Changing Dimension)** | Técnica de manejo de cambios históricos en dimensiones |
| **Data Vault 2.0** | Metodología con Hubs (llaves), Links (relaciones) y Satélites (atributos con historia) |
| **Hub / Link / Satélite** | Componentes del Data Vault |
| **Staging** | Zona de aterrizaje temporal de datos antes de transformarlos |
| **ETL / ELT** | Extraer-Transformar-Cargar / Extraer-Cargar-Transformar |
| **Idempotencia** | Ejecutar un proceso varias veces produce el mismo resultado |
| **Source-to-target** | Matriz que documenta el mapeo campo a campo entre origen y destino |
| **ADR** | Architecture Decision Record: registro de una decisión de diseño y su motivo |

---

## B. Términos de banca peruana

| Término | Definición |
|---|---|
| **SBS** | Superintendencia de Banca, Seguros y AFP: regulador y supervisor del sistema financiero |
| **BCRP** | Banco Central de Reserva del Perú: política monetaria, publica el tipo de cambio y estadísticas |
| **UIF-Perú** | Unidad de Inteligencia Financiera, incorporada a la SBS: PLAFT |
| **ANPDP** | Autoridad Nacional de Protección de Datos Personales (MINJUSDH) |
| **Colocaciones** | Créditos otorgados por la entidad (activo) |
| **Captaciones** | Depósitos recibidos del público (pasivo) |
| **Cartera atrasada** | Créditos vencidos y en cobranza judicial |
| **Morosidad** | Cartera atrasada / colocaciones brutas |
| **Provisión** | Reserva contable por riesgo de incobrabilidad |
| **Clasificación del deudor** | Categoría de riesgo: Normal, CPP, Deficiente, Dudoso, Pérdida |
| **CPP** | Con Problemas Potenciales (categoría 1) |
| **Tipo de crédito** | Corporativo, gran/mediana/pequeña empresa, MES, consumo revolvente y no revolvente, hipotecario |
| **MES** | Micro y pequeña empresa |
| **Días de atraso** | Días transcurridos desde el incumplimiento de una cuota |
| **Alineamiento** | Ajuste de la clasificación de un deudor según su peor calificación en el sistema |
| **Central de riesgos** | Registro consolidado de deudores del sistema financiero |
| **RCD / RCC** | Reporte Crediticio de Deudores / Reporte Crediticio Consolidado |
| **Anexos SBS** | Reportes regulatorios periódicos que las entidades remiten a la SBS |
| **Encaje** | Porcentaje de depósitos que debe mantenerse como reserva |
| **TCEA** | Tasa de Costo Efectivo Anual: costo total del crédito para el cliente |
| **TREA** | Tasa de Rendimiento Efectivo Anual: rendimiento real de un depósito |
| **TEA** | Tasa Efectiva Anual |
| **ITF** | Impuesto a las Transacciones Financieras |
| **CCI** | Código de Cuenta Interbancario (20 dígitos) |
| **CTS** | Compensación por Tiempo de Servicios: depósito laboral obligatorio |
| **PLAFT** | Prevención del Lavado de Activos y Financiamiento del Terrorismo |
| **ROS** | Reporte de Operaciones Sospechosas (sujeto a reserva estricta) |
| **RO** | Registro de Operaciones que superan umbrales definidos |
| **KYC** | *Know Your Customer*: conocimiento del cliente |
| **PEP** | Persona Expuesta Políticamente |
| **Debida diligencia** | Nivel de verificación aplicado a un cliente según su riesgo |
| **Fraccionamiento** | Dividir una operación para evadir umbrales de registro |
| **Secreto bancario** | Deber de reserva sobre las operaciones pasivas de los clientes |
| **Ubigeo** | Código de 6 dígitos: departamento (2) + provincia (2) + distrito (2) |
| **RUC** | Registro Único de Contribuyentes (11 dígitos), SUNAT |
| **DNI** | Documento Nacional de Identidad (8 dígitos), RENIEC |
| **CE** | Carné de Extranjería |
| **UIT** | Unidad Impositiva Tributaria: valor de referencia para multas y tramos |
| **ENAHO** | Encuesta Nacional de Hogares (INEI) |
| **Billetera digital** | Aplicación de pagos móviles (Yape, Plin) |
| **Agente / cajero corresponsal** | Comercio que opera transacciones básicas por cuenta del banco |
| **Canal** | Medio por el que se realiza la operación: oficina, ATM, agente, app, web |
| **Core bancario** | Sistema central que gestiona cuentas, saldos y operaciones |

---

## C. Falsos amigos que causan errores de modelado

| Palabra | Significado A | Significado B | Cómo se resuelve |
|---|---|---|---|
| **Cliente** | Quien tiene al menos un producto vigente | Quien alguna vez tuvo un producto | Definir `cliente` y un atributo `estado_cliente` con regla explícita |
| **Cliente activo** | Con producto vigente | Con transacción en los últimos 30 días | Dos indicadores distintos, nombrados distinto |
| **Saldo** | Saldo contable | Saldo disponible (descuenta retenciones) | Modelar ambos como columnas separadas |
| **Fecha de operación** | Cuándo ocurrió | Cuándo se contabilizó | `fecha_operacion` y `fecha_contable` |
| **Monto** | Bruto | Neto de comisiones e impuestos | Nombres explícitos: `monto_bruto`, `monto_neto` |
| **Mora** | Días de atraso | Cartera atrasada | Prefijar: `dias_atraso` vs. `saldo_cartera_atrasada` |
| **Producto** | Familia comercial (Ahorros) | Producto específico (Cuenta Sueldo) | Jerarquía explícita: familia → producto |
| **Deudor** | Titular del crédito | Cualquier obligado (incluye avales) | Modelar rol en la relación persona-operación |
