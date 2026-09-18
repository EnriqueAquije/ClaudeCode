#!/usr/bin/env bash
# =====================================================================================
#  concurrencia.sh — la prueba que el resto de la validación no puede hacer
# =====================================================================================
#  La idempotencia del caso 04 solo significa algo BAJO CONCURRENCIA. Una prueba
#  secuencial -- inserta, vuelve a insertar, comprueba que falla -- no demuestra nada:
#  el caso real es el reintento del móvil llegando mientras la primera petición todavía
#  se está procesando. Dos sesiones, la misma clave, a la vez.
#
#  Si el modelo está bien, exactamente UNA gana y la otra recibe un error de unicidad.
#  Si "ganan" las dos, el usuario recibe un doble cargo.
#
#  Se ejecuta aparte de validar.sh porque necesita dos conexiones simultáneas.
#
#  Uso:  ./validacion/concurrencia.sh [base]     (por defecto bcp_lab)
# =====================================================================================

set -uo pipefail
BD="${1:-${PGDATABASE:-bcp_lab}}"

if [ -t 1 ]; then ROJO=$'\033[0;31m'; VERDE=$'\033[0;32m'; NEG=$'\033[1m'; FIN=$'\033[0m'
else ROJO=''; VERDE=''; NEG=''; FIN=''; fi

echo ""
echo "=============================================================="
echo "   PRUEBA DE CONCURRENCIA — idempotencia del caso 04"
echo "=============================================================="
echo "Base: ${BD}"

CLAVE="PN-CONC-$(date +%s)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# Las dos sesiones intentan registrar la MISMA clave de idempotencia a la vez.
# El `pg_sleep` antes del INSERT las solapa a propósito.
cat > "${TMP}/sesion.sql" <<SQL
\set ON_ERROR_STOP 0
BEGIN;
SELECT pg_sleep(0.3);
INSERT INTO caso04.idempotencia (clave_idempotencia, usuario_id, transferencia_id, fecha_operacion)
SELECT '${CLAVE}', usuario_origen_id, transferencia_id, fecha_operacion
FROM   caso04.transferencia LIMIT 1;
COMMIT;
SQL

psql -d "${BD}" -q -f "${TMP}/sesion.sql" > "${TMP}/a.log" 2>&1 &
PID_A=$!
psql -d "${BD}" -q -f "${TMP}/sesion.sql" > "${TMP}/b.log" 2>&1 &
PID_B=$!
wait ${PID_A} ${PID_B}

GANADORAS=$(psql -d "${BD}" -At -c \
  "SELECT COUNT(*) FROM caso04.idempotencia WHERE clave_idempotencia = '${CLAVE}'")
ERRORES=$(grep -lc "ERROR" "${TMP}/a.log" "${TMP}/b.log" 2>/dev/null | wc -l | tr -d ' ')

psql -d "${BD}" -q -c "DELETE FROM caso04.idempotencia WHERE clave_idempotencia = '${CLAVE}'"

echo ""
echo "  Sesiones que intentaron la misma clave : 2"
echo "  Filas que quedaron en la tabla         : ${GANADORAS}"
echo "  Sesiones que recibieron error          : ${ERRORES}"
echo ""

if [ "${GANADORAS}" = "1" ] && [ "${ERRORES}" = "1" ]; then
    echo "${VERDE}${NEG}  ✓ Exactamente una ganó. La idempotencia aguanta concurrencia.${FIN}"
    exit 0
fi
echo "${ROJO}${NEG}  ✗ FALLA: se esperaba 1 fila y 1 error.${FIN}"
echo "    Con 2 filas, el usuario recibiría un doble cargo."
exit 1
