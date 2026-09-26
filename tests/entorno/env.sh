# Variables del entorno de prueba. Uso: source env.sh
# Contenedor desechable y local: la contraseña no protege nada real. Se puede cambiar con SA_PASSWORD.
export CONTENEDOR="${CONTENEDOR:-sqltest-tuning}"
export PUERTO="${PUERTO:-14333}"
export SA_PASSWORD="${SA_PASSWORD:-Tuning_Local_2026}"
# Usado por pruebas.sh y por medir.sh (setup/teardown). Apunta a TuningDB.
export SQL_EXEC="docker exec -i $CONTENEDOR /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $SA_PASSWORD -C -d TuningDB"
export PRUEBAS="${PRUEBAS:-./pruebas.sh}"
export LOCK="${LOCK:-/tmp/sql_tuning.lock}"
