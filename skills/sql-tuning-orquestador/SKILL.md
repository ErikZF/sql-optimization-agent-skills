---
name: sql-tuning-orquestador
description: Orquestador de tuning T-SQL con 5 subagentes paralelos. Toma query.sql, genera 5 ideas (Ben-Gan, T-SQL Querying cap. 2 y 5), subagentes escriben version1..5_query.sql, mide con contenedor + pruebas.sh, itera 1 vez y guarda mejor versión para próximas corridas. Usar SIEMPRE que usuario pida optimizar/afinar/acelerar consulta SQL Server, comparar alternativas de query, reducir tiempo de ejecución o logical reads, o mencione query.sql, pruebas.sh o versionN_query.sql, aunque no diga "orquestador".
---

# Orquestador tuning T-SQL

Rol: orquestador. Tú generas ideas, eliges, iteras. Subagentes implementan + miden. Contexto: SQL Server 2014+ (libro), vale en versiones nuevas.

## Archivos
- `query.sql`: consulta original. NUNCA modificar.
- `pruebas.sh`: prueba oficial. Leer antes de empezar: args, salida, si valida resultado.
- `version1_query.sql` … `version5_query.sql`: alternativas iteración actual.
- `mejor_query.sql` + `mejor.json`: mejor histórica. Si existen al iniciar → punto de partida (no `query.sql`).
- `historial/iterN/`: copia versiones + `resultados.json` de cada iteración.
- `versionN_setup.sql` / `versionN_teardown.sql`: solo si idea cambia esquema (índices).

## Flujo

### 0. Preparar
1. `docker ps` → contenedor SQL Server. Leer `pruebas.sh`.
2. Base = `mejor_query.sql` si existe, si no `query.sql`.
3. Medir base: `bash <skill>/scripts/medir.sh <base> 3` → `resultados/<base>.json` (mediana ms, logical reads, checksum). `<skill>` = carpeta de este SKILL.md; correr desde carpeta del proyecto.
4. Plan real / `SET STATISTICS IO, TIME ON` de base → ubicar operador caro (scan grande, lookups masivos, Sort con spill, estimado vs real muy distinto, plan serial raro, CTE repetida).

### 1. Generar 5 ideas (iteración 1)
- Leer `references/libro.md`. Elegir 5 ideas DISTINTAS, cada una ataca causa observada en plan. No 5 variantes de lo mismo.
- Mezclar familias: índice, reescritura, objeto temporal, TOP/OFFSET/APPLY, cardinalidad/paralelismo.
- Cada idea: 1 línea qué + 1 línea por qué (dato del plan) + ganancia esperada.

### 2. Lanzar 5 subagentes EN PARALELO
Una llamada con 5 tareas. Prompt por subagente:

```
Tarea: versión {N} de optimización.
Base: {ruta_base}. Idea: {idea}. Por qué: {motivo}.
1. Escribe version{N}_query.sql aplicando SOLO esta idea. Mismo resultado que base (filas, columnas, orden si hay ORDER BY).
2. Si idea crea índice/estadística: version{N}_setup.sql (CREATE) + version{N}_teardown.sql (DROP). No tocar esquema fuera de esos archivos.
3. Mide: bash {skill}/scripts/medir.sh version{N}_query.sql 3
4. Devuelve SOLO JSON:
{"version":N,"idea":"...","ms_mediana":0,"logical_reads":0,"filas":0,"checksum":"...","ok":true,"notas":"plan: operadores clave"}
Si falla o resultado distinto: ok=false + error.
```

Reglas subagentes:
- Medición serializada: `medir.sh` usa `flock`. Paralelo al escribir, serie al medir → tiempos no se contaminan.
- Setup/teardown corren dentro del lock. Tiempo de CREATE INDEX va aparte en `notas` (costo mantenimiento).

### 3. Evaluar
- Descartar `ok=false` o checksum ≠ baseline.
- Guardar ideas en `ideas.json` (`{"1":"idea",...}`).
- `python3 <skill>/scripts/elegir.py --base resultados/<base>.json --iter 1 --ideas ideas.json` → tabla ranking (ms_mediana, desempate logical_reads), valida checksum vs base, archiva `historial/iter1/`, y si ganadora mejora >5% copia a `mejor_query.sql` (+ setup) y actualiza `mejor.json`.

### 4. Iterar 1 vez (iteración 2)
- 5 ideas nuevas desde ganadora: combinar top-2 compatibles, afinar la mejor (índice más angosto, INCLUDE justo, forma predicado), probar idea descartada si fallo fue arreglable.
- Repetir pasos 2–3 sobre nueva base (`mejor_query.sql`; medir base de nuevo), `--iter 2`.
- Parar tras iteración 2. Mejor queda en `mejor_query.sql` para futuras corridas.

### 5. Reporte final (corto)
Tabla: versión | idea | ms | logical reads | Δ% vs original | ok. Luego: ganadora, por qué ganó (operador que cambió), índices a crear en prod + costo escritura, riesgos (NOLOCK, cambio semántica, dependencia de datos).

## Reglas duras
- Resultado idéntico siempre. Más rápido pero distinto = descartado.
- Medir mediana de ≥3 corridas, mismo estado cache (todas calientes, o todas frías con `CHECKPOINT; DBCC DROPCLEANBUFFERS;` solo en contenedor de prueba).
- NOLOCK no es optimización: allocation order scan inseguro, duplica/omite filas.
- Parámetros/variables: probar con valores representativos (unknowns = 30%, 9%, densidad).
- No aceptar ganancia < 5% como ganadora real (ruido); preferir menos logical reads.

## Recursos
- `references/libro.md`: catálogo ideas + cifras cap. 2 y 5. Leer en paso 1.
- `scripts/medir.sh`: wrapper `pruebas.sh` + lock + mediana + checksum. Env: `PRUEBAS`, `SQL_EXEC` (sqlcmd en contenedor para setup/teardown), `LOCK`.
- `scripts/elegir.py`: ranking + historial + actualiza `mejor.json`.
