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

mkdir -p "${SALIDA}"

# --- Colores (se desactivan si la salida no es una terminal) --------------------------
if [ -t 1 ]; then
    ROJO=$'\033[0;31m'; VERDE=$'\033[0;32m'; AMAR=$'\033[0;33m'
    AZUL=$'\033[0;34m'; NEGRITA=$'\033[1m';  FIN=$'\033[0m'
else
    ROJO=''; VERDE=''; AMAR=''; AZUL=''; NEGRITA=''; FIN=''
fi

# --- Catálogo de casos ---------------------------------------------------------------
#     Orden = orden de dependencia. No se puede alterar.
CASOS=(
    "caso01|caso-01-core-cuentas-ahorro|Core bancario: cuentas de ahorro|-"
    "caso02|caso-02-originacion-creditos|Originación y seguimiento de créditos|-"
    "caso03|caso-03-tarjetas-credito|Tarjetas de crédito y estados de cuenta|-"
    "caso04|caso-04-billetera-digital-p2p|Billetera digital y transferencias P2P|-"
    "caso05|caso-05-dwh-colocaciones|DWH dimensional de colocaciones|caso01,caso02"
    "caso06|caso-06-tipo-cambio-posicion-me|Tipo de cambio y posición en ME|-"
    "caso07|caso-07-plaft-monitoreo|PLAFT: monitoreo de operaciones|-"
    "caso08|caso-08-cliente-360-mdm|Cliente 360 / MDM|caso01,caso02,caso04,caso07"
    "caso09|caso-09-data-vault-inclusion|Data Vault de inclusión financiera|-"
    "caso10|caso-10-reporte-regulatorio-sbs|Reporte regulatorio a la SBS|caso02"
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
        IFS='|' read -r id _ _ deps <<< "${fila}"
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
    printf '%s\n' "${resultado[@]}"
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
if [ $# -ge 1 ]; then
    SOLICITADO="$1"
    if ! printf '%s\n' "${CASOS[@]}" | grep -q "^${SOLICITADO}|"; then
        echo "${ROJO}Caso desconocido: ${SOLICITADO}${FIN}"
        echo "Válidos: caso01 … caso10"
        exit 2
    fi
    while IFS= read -r c; do
        # sin duplicados, conservando el orden
        if ! printf '%s\n' "${A_EJECUTAR[@]:-}" | grep -qx "${c}"; then
            A_EJECUTAR+=("${c}")
        fi
    done < <(expandir_dependencias "${SOLICITADO}")
    echo "${AMAR}Caso solicitado: ${SOLICITADO}${FIN}"
    echo "${AMAR}Se ejecutarán (incluye prerrequisitos): ${A_EJECUTAR[*]}${FIN}"
else
    for fila in "${CASOS[@]}"; do
        A_EJECUTAR+=("${fila%%|*}")
    done
fi

# =====================================================================================
#  Comprobaciones previas
# =====================================================================================

titulo "VALIDACIÓN DEL LABORATORIO — data-modeler-bcp-peru"
echo "Base de datos : ${BD}"
echo "Fecha         : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Casos         : ${#A_EJECUTAR[@]}"

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

FALLIDOS=()
TOTAL_OK=0
TOTAL_FALLA=0
INICIO_GLOBAL=$SECONDS

for ID in "${A_EJECUTAR[@]}"; do

    # datos del caso
    for fila in "${CASOS[@]}"; do
        IFS='|' read -r cid cdir cnom cdep <<< "${fila}"
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
            if [ "${N_FALLA}" -gt 0 ]; then
                echo "${ROJO}${N_FALLA} REGLA(S) EN FALLA${FIN}"
                grep -E '\| FALLA *$' "${LOG_CAL}" | sed 's/^/      /'
                ERROR_CASO=1
                TOTAL_FALLA=$((TOTAL_FALLA + N_FALLA))
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
    fi
done

# =====================================================================================
#  Resumen
# =====================================================================================

DURACION_GLOBAL=$((SECONDS - INICIO_GLOBAL))
titulo "RESUMEN"
echo "  Casos ejecutados     : ${#A_EJECUTAR[@]}"
echo "  Casos válidos        : $(( ${#A_EJECUTAR[@]} - ${#FALLIDOS[@]} ))"
echo "  Reglas de calidad OK : ${TOTAL_OK}"
echo "  Reglas en FALLA      : ${TOTAL_FALLA}"
echo "  Tiempo total         : ${DURACION_GLOBAL}s"
echo "  Logs                 : ${SALIDA#${RAIZ}/}/"

if [ ${#FALLIDOS[@]} -gt 0 ]; then
    echo ""
    echo "${ROJO}${NEGRITA}  VALIDACIÓN FALLIDA — casos con problemas: ${FALLIDOS[*]}${FIN}"
    exit 1
fi

echo ""
echo "${VERDE}${NEGRITA}  ✓ VALIDACIÓN COMPLETA: todos los escenarios son 100 % desarrollables.${FIN}"
exit 0
