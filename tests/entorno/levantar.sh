#!/usr/bin/env bash
# Levanta SQL Server en Docker, carga TuningDB y copia los skills del repo a .claude/skills/.
# Correr en Linux/WSL (medir.sh necesita flock). Uso: bash levantar.sh
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh
REPO="$(cd ../.. && pwd)"

for c in docker python3 flock; do
  command -v "$c" >/dev/null || { echo "Falta '$c'. (flock: sudo apt install util-linux)"; exit 1; }
done

if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTENEDOR"; then
  echo "Creando contenedor $CONTENEDOR (puerto $PUERTO)..."
  docker run -d --name "$CONTENEDOR" -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD="$SA_PASSWORD" \
    -p "$PUERTO:1433" mcr.microsoft.com/mssql/server:2022-latest >/dev/null
else
  docker start "$CONTENEDOR" >/dev/null
fi

SQLCMD="docker exec -i $CONTENEDOR /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD -C -b"
printf 'Esperando SQL Server'
for _ in $(seq 60); do $SQLCMD -Q "SELECT 1" >/dev/null 2>&1 && break; printf .; sleep 2; done; echo
$SQLCMD -Q "SELECT 1" >/dev/null || { echo "SQL Server no respondió. Ver: docker logs $CONTENEDOR"; exit 1; }

echo "Cargando TuningDB (1M filas, puede tardar ~1 min)..."
$SQLCMD < datos.sql

rm -rf .claude/skills && mkdir -p .claude/skills && cp -r "$REPO"/skills/* .claude/skills/
echo "Skills copiados a $(pwd)/.claude/skills/"

cat <<EOF

Listo. Siguiente:
  source env.sh
  bash .claude/skills/sql-tuning-orquestador/scripts/medir.sh query.sql 3   # medir base
  claude    # y pedir: "optimiza query.sql"
Reiniciar corrida: bash limpiar.sh     Borrar contenedor: docker rm -f $CONTENEDOR
EOF
