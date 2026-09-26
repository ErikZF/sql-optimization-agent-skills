#!/usr/bin/env bash
# Uso: medir.sh <archivo.sql> [corridas=3]
# Corre pruebas.sh N veces bajo lock (medición en serie aunque subagentes vayan en paralelo).
# Si existen <base>_setup.sql / <base>_teardown.sql (ej. version3_setup.sql, mejor_setup.sql) los ejecuta
# vía SQL_EXEC antes y después de las corridas. Si setup o teardown falla -> ok=false.
# Salida: JSON en stdout + resultados/<archivo>.json
# Env opcional:
#   PRUEBAS=./pruebas.sh        ruta script oficial
#   SQL_EXEC="docker exec -i <contenedor> /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD -C"  obligatorio si hay setup/teardown
#   LOCK=/tmp/sql_tuning.lock
set -uo pipefail
F="${1:?falta archivo .sql}"; N="${2:-3}"
PRUEBAS="${PRUEBAS:-./pruebas.sh}"; LOCK="${LOCK:-/tmp/sql_tuning.lock}"
[ -f "$F" ] || { echo "{\"archivo\":\"$F\",\"ok\":false,\"error\":\"no existe\"}"; exit 1; }
[ -f "$PRUEBAS" ] || { echo "{\"archivo\":\"$F\",\"ok\":false,\"error\":\"no existe $PRUEBAS\"}"; exit 1; }
BASE="${F%_query.sql}"; SETUP="${BASE}_setup.sql"; TEAR="${BASE}_teardown.sql"
NOMBRE="$(basename "$F" .sql)"
mkdir -p resultados; TMP=$(mktemp -d); : > "$TMP/ms.txt"; : > "$TMP/sqlms.txt"; : > "$TMP/out1.txt"

# Errores reales de SQL Server / sqlcmd (severidad >= 11), en inglés o español. No usar "error" suelto: puede ser un dato.
SQL_ERR='Msg [0-9]+, Level (1[1-9]|2[0-5])|Mens\. [0-9]+, Nivel (1[1-9]|2[0-5])|Sqlcmd: Error'
ok=true; err=""
fail() { ok=false; err="${err:+$err; }$1"; }

# 0 si el archivo no existe o corrió sin errores. sqlcmd sin -b devuelve 0 aunque falle: revisar salida.
run_sql() {
  [ -f "$1" ] || return 0
  local log="$TMP/$(basename "$1").log"
  [ -n "${SQL_EXEC:-}" ] || { echo "$1 existe pero SQL_EXEC vacío" > "$log"; return 1; }
  $SQL_EXEC < "$1" > "$log" 2>&1 || return 1
  ! grep -qE "$SQL_ERR" "$log"
}
# suma de elapsed time reportado por SET STATISTICS TIME en una corrida
sql_ms() { grep -oiE '(elapsed time|tiempo transcurrido) = [0-9]+' "$1" | grep -oE '[0-9]+$' | awk '{s+=$1} END{print s+0}'; }
mediana() { sort -n "$1" | awk '{a[NR]=$1} END{if(!NR){print 0; exit} print (NR%2)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2)}'; }

exec 9>"$LOCK"; flock 9
t0=$(date +%s%N); run_sql "$SETUP" || fail "setup falló ($(basename "$SETUP"))"; setup_ms=$(( ($(date +%s%N)-t0)/1000000 ))
if $ok; then
  for i in $(seq 1 "$N"); do
    s=$(date +%s%N)
    bash "$PRUEBAS" "$F" > "$TMP/out$i.txt" 2>&1 || fail "pruebas.sh falló corrida $i"
    echo $(( ($(date +%s%N)-s)/1000000 )) >> "$TMP/ms.txt"
    sql_ms "$TMP/out$i.txt" >> "$TMP/sqlms.txt"
  done
fi
run_sql "$TEAR" || fail "teardown falló ($(basename "$TEAR")): esquema puede quedar modificado"
flock -u 9

med=$(mediana "$TMP/ms.txt")
sqlmed=$(mediana "$TMP/sqlms.txt")
# logical reads reportados por SQL Server (STATISTICS IO), si aparecen
lr=$(grep -oiE '(logical reads|lecturas lógicas) [0-9]+' "$TMP/out1.txt" | grep -oE '[0-9]+$' | awk '{s+=$1} END{print s+0}')
filas=$(grep -oiE '\(([0-9]+) rows? affected\)|\(([0-9]+) filas? afectadas?\)' "$TMP/out1.txt" | grep -oE '[0-9]+' | tail -1)
# checksum resultado: salida sin líneas de métricas
ck=$(grep -viE 'time|tiempo|reads|lecturas|scan count| ms|rows affected|filas afectadas|^\s*$' "$TMP/out1.txt" | md5sum | cut -c1-12)
grep -qE "$SQL_ERR" "$TMP/out1.txt" && fail "error SQL en salida"

J=$(printf '{"archivo":"%s","corridas":%s,"ms_mediana":%s,"sql_ms_mediana":%s,"logical_reads":%s,"filas":%s,"checksum":"%s","setup_ms":%s,"ok":%s,"error":"%s"}' \
  "$F" "$N" "$med" "$sqlmed" "$lr" "${filas:-null}" "$ck" "$setup_ms" "$ok" "$err")
echo "$J" | tee "resultados/$NOMBRE.json"
cp "$TMP/out1.txt" "resultados/$NOMBRE.salida.txt"
ls "$TMP"/*.log >/dev/null 2>&1 && cat "$TMP"/*.log > "resultados/$NOMBRE.setup.log"
rm -rf "$TMP"
