#!/usr/bin/env bash
# Prueba medir.sh + elegir.py sin SQL Server: pruebas.sh y sqlcmd falsos, 2 iteraciones, verifica resultados.
# Uso: bash tests/simular.sh     (sale con código 1 si algo falla)
set -uo pipefail
S="$(cd "$(dirname "$0")/../skills/sql-tuning-orquestador/scripts" && pwd)"
# primer python que realmente ejecute (en Windows python3 puede ser el stub de la Store)
for PY in python3 python ""; do [ -n "$PY" ] && "$PY" -c "" >/dev/null 2>&1 && break; done
[ -n "$PY" ] || { echo "Falta Python"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T"; mkdir bin
command -v flock >/dev/null || { printf '#!/bin/sh\nexit 0\n' > bin/flock; chmod +x bin/flock; }
export PATH="$T/bin:$PATH" LOCK="$T/lock" SQL_EXEC=fakesql PRUEBAS=./pruebas.sh

# pruebas.sh falso: tiempo y lecturas salen de "MS=n"; marcas en el .sql simulan fallos
cat > pruebas.sh <<'EOF'
q=$(cat "$1")
echo "id nombre"; echo "1 ana"; echo "2 errorcode_es_un_dato"
case "$q" in *RESULTADO_DISTINTO*) echo "3 extra";; esac
case "$q" in *FALLA*) echo "Msg 208, Level 16, State 1, Line 1";; esac
ms=$(echo "$q" | grep -oE 'MS=[0-9]+' | cut -d= -f2)
echo "Table 'Orders'. Scan count 1, logical reads ${ms}0, physical reads 0"
echo " SQL Server Execution Times: CPU time = 1 ms,  elapsed time = $ms ms."
echo "(2 rows affected)"
EOF
# sqlcmd falso para setup/teardown: error si el archivo contiene FALLA
cat > bin/fakesql <<'EOF'
#!/bin/sh
c=$(cat); case "$c" in *FALLA*) echo "Msg 1913, Level 16";; *) echo ok;; esac
EOF
chmod +x bin/fakesql

fallos=0
check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fallos=$((fallos+1)); fi; }
campo() { "$PY" -c "import json,sys;print(json.load(open(sys.argv[1],encoding='utf-8'))[sys.argv[2]])" "$@"; }
medir() { bash "$S/medir.sh" "$1" 3 >/dev/null; }

echo "== Iteración 1"
echo "MS=100" > query.sql
echo "MS=40" > version1_query.sql; echo "CREATE IDX" > version1_setup.sql; echo "DROP IDX" > version1_teardown.sql
echo "MS=10 RESULTADO_DISTINTO" > version2_query.sql
echo "MS=5" > version3_query.sql; echo "FALLA" > version3_setup.sql
echo "MS=60 FALLA" > version4_query.sql
echo "MS=70" > version5_query.sql
echo '{"1":"indice","2":"distinto","3":"setup roto","4":"error sql","5":"reescritura"}' > ideas.json
for f in query.sql version{1..5}_query.sql; do medir "$f"; done

check "base: métricas SQL Server leídas"      '[ "$(campo resultados/query.json sql_ms_mediana)" = 100 ] && [ "$(campo resultados/query.json logical_reads)" = 1000 ]'
check "setup roto -> ok=false"                '[ "$(campo resultados/version3_query.json ok)" = False ]'
check "error SQL real -> ok=false"            '[ "$(campo resultados/version4_query.json ok)" = False ]'
check "palabra 'error' en datos no es fallo"  '[ "$(campo resultados/version5_query.json ok)" = True ]'
"$PY" "$S/elegir.py" --base resultados/query.json --iter 1 --ideas ideas.json > elegir1.txt
check "ganadora = version1 (índice)"          'grep -q "Nueva mejor: version1" elegir1.txt'
check "resultado distinto descartado"         'grep -q "resultado distinto a base" elegir1.txt'
check "copia setup y teardown de ganadora"    '[ -f mejor_setup.sql ] && [ -f mejor_teardown.sql ]'
check "versiones movidas a historial/iter1"   '[ ! -e version1_setup.sql ] && [ -f historial/iter1/version1_setup.sql ] && [ -f historial/iter1/ideas.json ]'

echo "== Iteración 2"
medir mejor_query.sql
check "base mejor aplica su setup"            '[ -f resultados/mejor_query.setup.log ]'
echo "MS=30" > version1_query.sql
medir version1_query.sql
check "versión sin setup no hereda uno viejo" '[ ! -f resultados/version1_query.setup.log ]'
"$PY" "$S/elegir.py" --base resultados/mejor_query.json --iter 2 > elegir2.txt
check "nueva mejor en iteración 2"            'grep -q "Nueva mejor: version1" elegir2.txt'
check "borra mejor_setup obsoleto"            '[ ! -f mejor_setup.sql ] && [ ! -f mejor_teardown.sql ]'
check "mejor.json guarda historia"            '[ "$("$PY" -c "import json;print(len(json.load(open(\"mejor.json\",encoding=\"utf-8\"))[\"historia\"]))")" = 2 ]'

echo
[ "$fallos" -eq 0 ] && echo "Todo OK" || { echo "$fallos fallo(s)"; exit 1; }
