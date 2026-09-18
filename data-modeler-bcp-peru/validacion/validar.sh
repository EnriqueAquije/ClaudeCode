#!/usr/bin/env bash
# =====================================================================================
#  validar.sh — Validación integral del laboratorio de modelado de datos
# =====================================================================================
#  Ejecuta, en orden de dependencia, los 10 casos contra PostgreSQL:
#
#      modelo físico  →  carga de datos  →  consultas de negocio  →  reglas de calidad
#
#  Falla (código de salida 1) si:
#    · algún script devuelve error de PostgreSQL, o
#    · alguna regla de calidad reporta el estado FALLA.
#
#  Uso:
#      ./validacion/validar.sh              # los 10 casos
#      ./validacion/validar.sh caso04       # solo el caso 04 (y sus prerrequisitos)
#      PGDATABASE=otra ./validacion/validar.sh
#
#  Variables de entorno reconocidas: PGHOST, PGPORT, PGUSER, PGDATABASE
# =====================================================================================

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SALIDA="${RAIZ}/validacion/salida"
BD="${PGDATABASE:-bcp_lab}"

# El mkdir SE COMPRUEBA: si el repositorio esta montado en solo lectura, sin esto el
# script sigue adelante y termina culpando al modelo del alumno de un fallo de permisos.
if ! mkdir -p "${SALIDA}" 2>/dev/null; then
    echo "No se puede escribir en ${SALIDA}." >&2
    echo "Revisa los permisos del directorio, o copia el repositorio a una ruta con escritura." >&2
    exit 3
fi

# --- Colores (se desactivan si la salida no es una terminal) --------------------------
if [ -t 1 ]; then
    ROJO=$'\033[0;31m'; VERDE=$'\033[0;32m'; AMAR=$'\033[0;33m'
    AZUL=$'\033[0;34m'; NEGRITA=$'\033[1m';  FIN=$'\033[0m'
else
    ROJO=''; VERDE=''; AMAR=''; AZUL=''; NEGRITA=''; FIN=''
fi

# --- Catálogo de casos ---------------------------------------------------------------
#     id | directorio | nombre | dependencias | reglas de calidad esperadas
#     Orden = orden de dependencia. No se puede alterar.
#
#     La ultima columna existe para que "0 reglas OK" NO cuente como caso valido: sin ella,
#     un fichero de calidad vacio o truncado pasaria la validacion sin evaluar nada.
CASOS=(
    "caso01|caso-01-core-cuentas-ahorro|Core bancario: cuentas de ahorro|-|10"
    "caso02|caso-02-originacion-creditos|Originación y seguimiento de créditos|-|14"
    "caso03|caso-03-tarjetas-credito|Tarjetas de crédito y estados de cuenta|-|13"
    "caso04|caso-04-billetera-digital-p2p|Billetera digital y transferencias P2P|-|15"
    "caso05|caso-05-dwh-colocaciones|DWH dimensional de colocaciones|caso01,caso02|17"
    "caso06|caso-06-tipo-cambio-posicion-me|Tipo de cambio y posición en ME|-|15"
    "caso07|caso-07-plaft-monitoreo|PLAFT: monitoreo de operaciones|-|16"
    "caso08|caso-08-cliente-360-mdm|Cliente 360 / MDM|caso01,caso02,caso04,caso07|16"
    "caso09|caso-09-data-vault-inclusion|Data Vault de inclusión financiera|-|16"
    "caso10|caso-10-reporte-regulatorio-sbs|Reporte regulatorio a la SBS|caso02|19"
)

# =====================================================================================
#  Funciones auxiliares
# =====================================================================================

titulo() {
    echo ""
    echo "${AZUL}${NEGRITA}======================================================================${FIN}"
    echo "${AZUL}${NEGRITA}  $*${FIN}"
    echo "${AZUL}${NEGRITA}======================================================================${FIN}"
}

# Resuelve los prerrequisitos de un caso, en orden y sin repetir.
expandir_dependencias() {
    local objetivo="$1"
    local resultado=()
    local fila id deps dep

    for fila in "${CASOS[@]}"; do
        IFS='|' read -r id _ _ deps _ <<< "${fila}"
        if [ "${id}" = "${objetivo}" ]; then
            if [ "${deps}" != "-" ]; then
                IFS=',' read -ra ADEPS <<< "${deps}"
                for dep in "${ADEPS[@]}"; do
                    resultado+=("${dep}")
                done
            fi
            resultado+=("${id}")
            break
        fi
    done
    printf '%s\n' ${resultado[@]+"${resultado[@]}"}
}

ejecutar_sql() {
    # $1 = ruta del script  ·  $2 = archivo de log
    local archivo="$1" log="$2"
    if [ ! -f "${archivo}" ]; then
        echo "  ${ROJO}✗${FIN} no existe: ${archivo#${RAIZ}/}"
        return 1
    fi
    psql -d "${BD}" -v ON_ERROR_STOP=1 -q -f "${archivo}" > "${log}" 2>&1
}

# =====================================================================================
#  Selección de casos a ejecutar
# =====================================================================================

A_EJECUTAR=()
if [ $# -gt 1 ]; then
    # Un argumento de mas suele ser "validar.sh caso01 caso02": quien lo teclea espera dos
    # casos y obtendria uno en silencio. Mejor fallar y decirlo.
    echo "${ROJO}Solo se admite UN caso por ejecución (recibidos: $#).${FIN}"
    echo "Para varios casos, ejecuta el script una vez por caso, o sin argumentos para los 10."
    exit 2
fi

if [ $# -eq 1 ]; then
    SOLICITADO="$1"

    # Comparación EXACTA, no con grep. Con `grep "^${SOLICITADO}|"` un argumento como
    # 'caso0[12]' o 'caso0.' es una expresión regular que empareja, pasa el filtro, y luego
    # no coincide con ningún id: la lista queda vacía, no se ejecuta nada y el script
    # terminaba declarando "todos los escenarios son 100 % desarrollables". Falso verde.
    CASO_VALIDO=0
    for fila in "${CASOS[@]}"; do
        [ "${fila%%|*}" = "${SOLICITADO}" ] && { CASO_VALIDO=1; break; }
    done
    if [ "${CASO_VALIDO}" -eq 0 ]; then
        echo "${ROJO}Caso desconocido: ${SOLICITADO}${FIN}"
        echo "Válidos: caso01 … caso10"
        exit 2
    fi

    while IFS= read -r c; do
        # sin duplicados, conservando el orden
        YA=0
        for v in ${A_EJECUTAR[@]+"${A_EJECUTAR[@]}"}; do
            [ "${v}" = "${c}" ] && { YA=1; break; }
        done
        [ "${YA}" -eq 0 ] && A_EJECUTAR+=("${c}")
    done < <(expandir_dependencias "${SOLICITADO}")

    echo "${AMAR}Caso solicitado: ${SOLICITADO}${FIN}"
    echo "${AMAR}Se ejecutarán (incluye prerrequisitos): ${A_EJECUTAR[*]}${FIN}"
else
    for fila in "${CASOS[@]}"; do
        A_EJECUTAR+=("${fila%%|*}")
    done
fi

# Red de seguridad: si por lo que sea la lista quedó vacía, esto NO es un éxito.
N_CASOS=0
for _c in ${A_EJECUTAR[@]+"${A_EJECUTAR[@]}"}; do N_CASOS=$((N_CASOS + 1)); done
if [ "${N_CASOS}" -eq 0 ]; then
    echo "${ROJO}No hay ningún caso que ejecutar. Abortando sin validar nada.${FIN}"
    exit 2
fi

# =====================================================================================
#  Comprobaciones previas
# =====================================================================================

titulo "VALIDACIÓN DEL LABORATORIO — data-modeler-bcp-peru"
echo "${AMAR}Qué valida  : la SOLUCIÓN DE REFERENCIA de cada caso (soluciones/caso-NN/).${FIN}"
echo "${AMAR}              NO valida lo que hayas escrito en mi-solucion/. Sirve para comprobar${FIN}"
echo "${AMAR}              que tu entorno funciona y para comparar contra el resultado esperado.${FIN}"
echo ""
echo "Base de datos : ${BD}"
echo "Fecha         : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Casos         : ${N_CASOS}"

if ! command -v psql > /dev/null 2>&1; then
    echo "${ROJO}✗ No se encontró psql en el PATH.${FIN}"
    echo "  Instala el cliente de PostgreSQL o revisa 00-fundamentos/02-herramientas.md"
    exit 3
fi

if ! psql -d "${BD}" -c 'SELECT 1' > /dev/null 2>&1; then
    echo "${ROJO}✗ No se puede conectar a la base '${BD}'.${FIN}"
    echo "  Créala con:  createdb ${BD}"
    exit 3
fi

echo "${VERDE}✓${FIN} Conexión a PostgreSQL: $(psql -d "${BD}" -At -c 'SHOW server_version')"

# =====================================================================================
#  Ejecución
# =====================================================================================

# PORTABILIDAD: en bash 4.3 y anteriores -- y el bash del sistema en macOS es 3.2 --
# expandir un array VACIO bajo `set -u` aborta con "unbound variable". Por eso el conteo
# se lleva en variables escalares y no con ${#array[@]}: el script tiene que sobrevivir
# a la corrida exitosa, que es justo cuando FALLIDOS esta vacio.
FALLIDOS=()
N_FALLIDOS=0
TOTAL_OK=0
TOTAL_FALLA=0
INICIO_GLOBAL=$SECONDS

for ID in ${A_EJECUTAR[@]+"${A_EJECUTAR[@]}"}; do

    # datos del caso
    for fila in "${CASOS[@]}"; do
        IFS='|' read -r cid cdir cnom cdep cmin <<< "${fila}"
        [ "${cid}" = "${ID}" ] && break
    done

    titulo "${ID} — ${cnom}"
    [ "${cdep}" != "-" ] && echo "  ${AMAR}Requiere:${FIN} ${cdep}"

    DIR_SOL="${RAIZ}/soluciones/${cdir}"
    DIR_CASO="${RAIZ}/casos/${cdir}"
    INICIO=$SECONDS
    ERROR_CASO=0

    # --- 1. Modelo físico ------------------------------------------------------------
    printf '  %-28s' "1. modelo físico"
    if ejecutar_sql "${DIR_SOL}/03-modelo-fisico.sql" "${SALIDA}/${ID}-01-ddl.log"; then
        echo "${VERDE}OK${FIN}"
    else
        echo "${ROJO}ERROR${FIN}"; ERROR_CASO=1
        tail -n 12 "${SALIDA}/${ID}-01-ddl.log" | sed 's/^/      /'
    fi

    # --- 2. Carga de datos -----------------------------------------------------------
    if [ ${ERROR_CASO} -eq 0 ]; then
        printf '  %-28s' "2. carga de datos"
        if ejecutar_sql "${DIR_CASO}/datos/carga_datos.sql" "${SALIDA}/${ID}-02-datos.log"; then
            echo "${VERDE}OK${FIN}"
        else
            echo "${ROJO}ERROR${FIN}"; ERROR_CASO=1
            tail -n 12 "${SALIDA}/${ID}-02-datos.log" | sed 's/^/      /'
        fi
    fi

    # --- 3. Consultas de negocio -----------------------------------------------------
    if [ ${ERROR_CASO} -eq 0 ]; then
        printf '  %-28s' "3. consultas de negocio"
        if ejecutar_sql "${DIR_SOL}/04-consultas-negocio.sql" "${SALIDA}/${ID}-03-consultas.log"; then
            echo "${VERDE}OK${FIN}"
        else
            echo "${ROJO}ERROR${FIN}"; ERROR_CASO=1
            tail -n 12 "${SALIDA}/${ID}-03-consultas.log" | sed 's/^/      /'
        fi
    fi

    # --- 4. Reglas de calidad --------------------------------------------------------
    if [ ${ERROR_CASO} -eq 0 ]; then
        printf '  %-28s' "4. reglas de calidad"
        LOG_CAL="${SALIDA}/${ID}-04-calidad.log"
        if ejecutar_sql "${DIR_SOL}/05-calidad-datos.sql" "${LOG_CAL}"; then
            # La ultima consulta de cada 05-calidad-datos.sql imprime una fila por regla,
            # terminada en OK o en FALLA. Eso es lo que se cuenta aqui.
            N_OK=$(grep -cE '\| OK *$'    "${LOG_CAL}" || true)
            N_FALLA=$(grep -cE '\| FALLA *$' "${LOG_CAL}" || true)
            N_TOTAL=$((N_OK + N_FALLA))
            if [ "${N_FALLA}" -gt 0 ]; then
                echo "${ROJO}${N_FALLA} REGLA(S) EN FALLA${FIN}"
                grep -E '\| FALLA *$' "${LOG_CAL}" | sed 's/^/      /'
                ERROR_CASO=1
                TOTAL_FALLA=$((TOTAL_FALLA + N_FALLA))
                TOTAL_OK=$((TOTAL_OK + N_OK))
            elif [ "${N_TOTAL}" -lt "${cmin}" ]; then
                # "0 reglas OK" NO es un exito: significa que no se evaluo nada. Un fichero
                # de calidad vacio, truncado o que fallo a medias daria verde sin este control.
                echo "${ROJO}SOLO ${N_TOTAL} REGLAS EVALUADAS (se esperaban ${cmin})${FIN}"
                echo "      El fichero de calidad no produjo el resumen completo."
                echo "      Revisa ${LOG_CAL#${RAIZ}/}"
                ERROR_CASO=1
            else
                echo "${VERDE}${N_OK} reglas OK${FIN}"
                TOTAL_OK=$((TOTAL_OK + N_OK))
            fi
        else
            echo "${ROJO}ERROR${FIN}"; ERROR_CASO=1
            tail -n 12 "${LOG_CAL}" | sed 's/^/      /'
        fi
    fi

    DURACION=$((SECONDS - INICIO))
    if [ ${ERROR_CASO} -eq 0 ]; then
        echo "  ${VERDE}${NEGRITA}✓ ${ID} validado${FIN} (${DURACION}s)"
    else
        echo "  ${ROJO}${NEGRITA}✗ ${ID} FALLÓ${FIN} (${DURACION}s) — revisa ${SALIDA}/${ID}-*.log"
        FALLIDOS+=("${ID}")
        N_FALLIDOS=$((N_FALLIDOS + 1))
    fi
done

# =====================================================================================
#  Cifras documentadas
#  Solo en la corrida completa: el script consulta los 10 esquemas a la vez.
# =====================================================================================

TOTAL_CIFRAS=0
CIFRAS_FALLA=0

if [ $# -eq 0 ] && [ "${N_FALLIDOS}" -eq 0 ]; then
    titulo "CIFRAS DOCUMENTADAS vs. BASE DE DATOS"
    echo "  Los datos son deterministas, asi que cada cifra citada en un README"
    echo "  debe cumplirse siempre. Si un generador cambia y el README no, esto falla."
    echo ""
    LOG_CIF="${SALIDA}/cifras-documentadas.log"
    printf '  %-28s' "verificando"
    if ejecutar_sql "${RAIZ}/validacion/cifras-documentadas.sql" "${LOG_CIF}"; then
        TOTAL_CIFRAS=$(grep -cE '\| OK *$'    "${LOG_CIF}" || true)
        CIFRAS_FALLA=$(grep -cE '\| FALLA *$' "${LOG_CIF}" || true)
        if [ "${CIFRAS_FALLA}" -gt 0 ]; then
            echo "${ROJO}${CIFRAS_FALLA} CIFRA(S) NO COINCIDEN CON LA DOCUMENTACION${FIN}"
            grep -E '\| FALLA *$' "${LOG_CIF}" | sed 's/^/      /'
            FALLIDOS+=("cifras-documentadas")
            N_FALLIDOS=$((N_FALLIDOS + 1))
        else
            echo "${VERDE}${TOTAL_CIFRAS} cifras coinciden${FIN}"
        fi
    else
        echo "${ROJO}ERROR${FIN}"
        tail -n 12 "${LOG_CIF}" | sed 's/^/      /'
        FALLIDOS+=("cifras-documentadas")
        N_FALLIDOS=$((N_FALLIDOS + 1))
    fi
fi

# =====================================================================================
#  Resumen
# =====================================================================================

DURACION_GLOBAL=$((SECONDS - INICIO_GLOBAL))
titulo "RESUMEN"
echo "  Casos ejecutados     : ${N_CASOS}"
echo "  Casos válidos        : $(( N_CASOS - N_FALLIDOS ))"
echo "  Reglas de calidad OK : ${TOTAL_OK}"
echo "  Reglas en FALLA      : ${TOTAL_FALLA}"
if [ "${TOTAL_CIFRAS}" -gt 0 ] || [ "${CIFRAS_FALLA}" -gt 0 ]; then
    echo "  Cifras documentadas  : ${TOTAL_CIFRAS} verificadas, ${CIFRAS_FALLA} en FALLA"
fi
echo "  Tiempo total         : ${DURACION_GLOBAL}s"
echo "  Logs                 : ${SALIDA#${RAIZ}/}/"

if [ "${N_FALLIDOS}" -gt 0 ]; then
    echo ""
    echo "${ROJO}${NEGRITA}  VALIDACIÓN FALLIDA — casos con problemas: ${FALLIDOS[*]}${FIN}"
    exit 1
fi

echo ""
echo "${VERDE}${NEGRITA}  ✓ VALIDACIÓN COMPLETA: todos los escenarios son 100 % desarrollables.${FIN}"
exit 0
