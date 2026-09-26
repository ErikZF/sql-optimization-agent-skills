#!/usr/bin/env bash
# Uso: medir.sh <archivo.sql> [corridas=3]
# Corre pruebas.sh N veces bajo lock (medición en serie aunque subagentes vayan en paralelo).
# Ejecuta versionN_setup.sql / versionN_teardown.sql si existen (vía SETUP_CMD).
# Salida: JSON en stdout + resultados/<archivo>.json
# Env opcional:
#   PRUEBAS=./pruebas.sh        ruta script oficial
#   SQL_EXEC="docker exec -i <contenedor> /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD -C"  para setup/teardown
#   LOCK=/tmp/sql_tuning.lock
set -uo pipefail
F="${1:?falta archivo .sql}"; N="${2:-3}"
PRUEBAS="${PRUEBAS:-./pruebas.sh}"; LOCK="${LOCK:-/tmp/sql_tuning.lock}"
[ -f "$F" ] || { echo "{\"archivo\":\"$F\",\"ok\":false,\"error\":\"no existe\"}"; exit 1; }
[ -f "$PRUEBAS" ] || { echo "{\"archivo\":\"$F\",\"ok\":false,\"error\":\"no existe $PRUEBAS\"}"; exit 1; }
BASE="${F%_query.sql}"; SETUP="${BASE}_setup.sql"; TEAR="${BASE}_teardown.sql"
mkdir -p resultados; TMP=$(mktemp -d)

run_sql() { [ -f "$1" ] || return 0; [ -n "${SQL_EXEC:-}" ] || { echo "WARN: $1 existe pero SQL_EXEC vacío" >&2; return 1; }; $SQL_EXEC < "$1" > "$TMP/$(basename "$1").log" 2>&1; }

exec 9>"$LOCK"; flock 9
t0=$(date +%s%N); run_sql "$SETUP"; setup_ms=$(( ($(date +%s%N)-t0)/1000000 ))
ok=true; err=""
for i in $(seq 1 "$N"); do
  s=$(date +%s%N)
  if ! bash "$PRUEBAS" "$F" > "$TMP/out$i.txt" 2>&1; then ok=false; err="pruebas.sh falló corrida $i"; fi
  echo $(( ($(date +%s%N)-s)/1000000 )) >> "$TMP/ms.txt"
done
run_sql "$TEAR"
flock -u 9

med=$(sort -n "$TMP/ms.txt" | awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2)}')
# logical reads y elapsed reportados por SQL Server (STATISTICS IO/TIME), si aparecen
lr=$(grep -oiE 'logical reads [0-9]+' "$TMP/out1.txt" | awk '{s+=$3} END{print s+0}')
sqlms=$(grep -oiE 'elapsed time = [0-9]+' "$TMP/out1.txt" | awk '{s+=$4} END{print s+0}')
filas=$(grep -oiE '\(([0-9]+) rows? affected\)|\(([0-9]+) filas? afectadas?\)' "$TMP/out1.txt" | grep -oE '[0-9]+' | tail -1)
# checksum resultado: salida sin líneas de métricas
ck=$(grep -viE 'time|tiempo|reads|lecturas|scan count| ms|rows affected|filas afectadas|^\s*$' "$TMP/out1.txt" | md5sum | cut -c1-12)
grep -qiE 'error|msg [0-9]+, level 1[1-9]' "$TMP/out1.txt" && { ok=false; err="${err:-error SQL en salida}"; }

J=$(printf '{"archivo":"%s","corridas":%s,"ms_mediana":%s,"sql_elapsed_ms":%s,"logical_reads":%s,"filas":%s,"checksum":"%s","setup_ms":%s,"ok":%s,"error":"%s"}' \
  "$F" "$N" "$med" "$sqlms" "$lr" "${filas:-null}" "$ck" "$setup_ms" "$ok" "$err")
echo "$J" | tee "resultados/$(basename "$F" .sql).json"
cp "$TMP/out1.txt" "resultados/$(basename "$F" .sql).salida.txt"
rm -rf "$TMP"
