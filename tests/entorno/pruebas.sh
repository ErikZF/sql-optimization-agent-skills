#!/usr/bin/env bash
# Prueba oficial. Uso: pruebas.sh <archivo.sql>
# Ejecuta la consulta en TuningDB con STATISTICS IO/TIME. Salida: filas del resultado + métricas de SQL Server.
set -euo pipefail
source "$(dirname "$0")/env.sh"
[ -f "$1" ] || { echo "no existe $1" >&2; exit 1; }
{ echo "SET NOCOUNT OFF; SET STATISTICS IO, TIME ON;"; cat "$1"; } | $SQL_EXEC -W
