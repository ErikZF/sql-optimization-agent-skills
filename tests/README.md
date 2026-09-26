# Pruebas

Todo se corre en **Linux o WSL** (`medir.sh` usa `flock`). En Windows:
1. Abrir Docker Desktop → Settings → Resources → WSL integration → activar **Ubuntu**.
2. Correr los comandos dentro de Ubuntu (WSL), desde `/mnt/d/...` hasta la carpeta del repo.

## 1. Simulación (sin SQL Server, segundos)
Prueba `medir.sh` y `elegir.py` con datos falsos: fallos de setup, errores SQL, resultado distinto, 2 iteraciones.

```bash
bash tests/simular.sh
```

## 2. Entorno real (SQL Server en Docker)

```bash
cd tests/entorno
bash levantar.sh      # contenedor + TuningDB (1M filas) + copia skills a .claude/skills/
source env.sh
bash .claude/skills/sql-tuning-orquestador/scripts/medir.sh query.sql 3
```

Luego abrir Claude Code en `tests/entorno/` y pedir **"optimiza query.sql"**.

| Archivo | Qué es |
|---|---|
| `env.sh` | Contenedor, puerto (14333), contraseña local, `SQL_EXEC` |
| `datos.sql` | `TuningDB`: Orders 1M filas + Customers 20k, datos deterministas |
| `query.sql` | Consulta lenta a propósito (YEAR no sargable, sin índice custid) |
| `pruebas.sh` | Prueba oficial: ejecuta con `STATISTICS IO, TIME` |
| `limpiar.sh` | Borra versiones, resultados e índices sobrantes para repetir |

Borrar todo: `docker rm -f sqltest-tuning`.
