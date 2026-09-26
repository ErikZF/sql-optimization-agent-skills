#!/usr/bin/env bash
# Borra lo generado por una corrida del orquestador y los índices que hayan quedado. Deja datos y contenedor.
set -uo pipefail
cd "$(dirname "$0")"
source ./env.sh
rm -rf resultados historial version*_*.sql mejor_*.sql mejor.json ideas.json
# Índices creados por setups que no llegaron a su teardown (deja solo PK y clustered originales)
$SQL_EXEC -Q "DECLARE @s NVARCHAR(MAX) = N'';
SELECT @s += N'DROP INDEX ' + QUOTENAME(i.name) + N' ON dbo.' + QUOTENAME(t.name) + N';'
FROM sys.indexes i JOIN sys.tables t ON t.object_id = i.object_id
WHERE i.name NOT IN ('PK_Orders', 'CIX_Orders_orderdate') AND i.is_primary_key = 0 AND i.type > 0;
EXEC (@s);" >/dev/null 2>&1 || echo "Aviso: no se pudo limpiar índices (¿contenedor apagado?)"
echo "Corrida limpia."
