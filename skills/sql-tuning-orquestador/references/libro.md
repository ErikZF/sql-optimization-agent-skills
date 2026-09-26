# Catálogo ideas (Ben-Gan et al. 2015, cap. 2 y 5)

Formato: **síntoma en plan → idea → dato libro**. Datos: PerformanceV3 `dbo.Orders` 1M filas, clustered `orderdate`, `PK_Orders` NC `orderid`, 3 niveles.

## Base rápida
- Página 8 KB. Seek = niveles (3). RID lookup = 1 lectura; key lookup = L (3).
- Heap scan 24,396 · CI scan 25,073 · NC covering scan 2,611 · seek+RID 28 · seek+key 78 (25 filas) · NC scan+lookups 4,006 · CI seek 22 (703 filas) · NC covering seek 222 (49,782 filas).
- Tipping point seek+lookups → scan: 6,505 filas (<1%). NC no covering sirve solo muy selectivo.
- Prefetch >25 filas (`WithUnorderedPrefetch`). TF 8744 lo apaga.

## A. Índices
| Síntoma | Idea | Dato |
|---|---|---|
| NC scan + key lookups, filtro columna no líder | Índice clave = columna filtro + INCLUDE resto | custid: 4,006 → 5 lecturas |
| Muchos lookups, rango grande | Hacer covering (INCLUDE) | 49,782 filas en 222 lecturas |
| Igualdad + rango | Clave (igualdades, rango) | `(shipperid, orderdate) INCLUDE(custid, orderid)` |
| Varios rangos | Rango más selectivo primero, resto residual | col1 50% / col2 2% → `(col2, col1)` |
| Sort por ORDER BY / OVER | Clave sigue orden (dirección incluida) | `(col1, col2 DESC)`; backward scan = serial 2014 |
| ORDER BY DESC fuerza plan serial | Índice DESC → scan paralelo adelante | backward siempre serial (2014) |
| Filtro fijo en subconjunto | Índice filtrado + INCLUDE columna filtrada | estadísticas filtradas más precisas |
| Agregados masivos (DW, star join) | Columnstore (batch mode) | 29,300 → 13,235 lecturas, CPU 890 → 172 ms |
| Clustering key en NC | No incluirla: ya viaja en hoja | PK_Orders cubre (orderid, orderdate) |
Costo: cada índice encarece INSERT/UPDATE/DELETE. Reportar.

## B. Reescritura (optimizador corta búsqueda; equivalentes ≠ mismo plan)
| Síntoma | Idea | Dato |
|---|---|---|
| Subquery escalar MAX/MIN desanidada → full scan | `TOP (1) ... ORDER BY ... DESC` (TOP impide unnesting; TOP (100) PERCENT no) | 2,487 → 36 lecturas, 12 seeks |
| GROUP BY sobre columna muy densa | Recorrer tabla de grupos + seek por grupo (APPLY/TOP 1) | escala con #grupos, no #filas |
| NOT IN / anti-semi lento | `NOT EXISTS` + `EXISTS` | 72 lecturas, 19 accesos |
| Cursor / WHILE fila a fila | Set-based (GROUP BY, ventana) | 17 s → 602 ms |
| UDF escalar T-SQL | Expresión inline | UDF escalar mata paralelismo todo el plan |

## C. Objetos temporales
| Síntoma | Idea | Dato |
|---|---|---|
| CTE/derivada referenciada ≥2 veces | Materializar en @tabla (pocas filas) o #temp | 15,696 (6 scans) → 2,622 lecturas |
| Consulta gigante, estimaciones rotas | Partir: resultado intermedio a #temp (stats reales) | #temp histograma; @tabla solo cardinalidad |
| @tabla grande + filtro rango → spill | #temp o RECOMPILE / TF 2453 | @tabla: 30% fijo sin histograma |

## D. TOP / OFFSET-FETCH (cap. 5)
| Síntoma | Idea | Dato |
|---|---|---|
| OFFSET grande + lookups en filas saltadas | Claves primero: CTE con OFFSET solo clave → JOIN | pág 1000: 76,644 → 223; pág 3: 241 → 153 |
| Paginar siguiente página | Ancla: `WHERE key > @last ORDER BY key` + TOP | 87 lecturas fijas; covering 3–4 |
| Ancla 2 claves, líder densa | `(k1 = @a AND k2 > @b) OR k1 > @a` | 2 seek predicates, sin residual |
| ROW_NUMBER paginación con sort | `ORDER BY rn` no por clave | evita Sort extra |
| Top N por grupo, pocos grupos grandes | `CROSS APPLY (SELECT TOP (N) ... ORDER BY)` + índice POC | ~30 lecturas vs 30,000 |
| Top N por grupo, muchos grupos chicos | `ROW_NUMBER() OVER(PARTITION BY)` + POC | ~30,000 secuencial vs 3M aleatorio |
| Top 1 por grupo sin índice POC | Carry-along: MAX(concat orden-preservante) | `CONVERT(CHAR(8),d,112)` + ceros izq + `COLLATE Latin1_General_BIN2` |
| Mediana PERCENTILE_CONT | `ov=(cnt-1)/2, fv=2-cnt%2` + APPLY OFFSET ov FETCH fv + AVG | 79 s → 8 s (ROW_NUMBER) → 1 s |
| DELETE/UPDATE masivo, lock escalation | Bucle `DELETE TOP (n)` + `IF @@ROWCOUNT < n BREAK` | escala 5,000 locks (+1,250); n ≈ ½ punto observado (~3,000) |
POC = Partition + Order en clave, Covering en INCLUDE.

## E. Cardinalidad
| Síntoma | Idea | Dato |
|---|---|---|
| Est ≪ real: seek+lookups, Stream Agg, spill, serial | Arreglar estimación: stats, RECOMPILE, quitar OPTIMIZE FOR malo | OPTIMIZE FOR: est 100, real 500,000 |
| Est ≫ real: scan, hash, grant enorme | RECOMPILE (ve variable) o valor representativo | variable `>`: 30% = 300,000 vs 100 |
| Filas nuevas > último paso histograma | UPDATE STATISTICS / CE 2014 / TF 2389 | legacy estima 1 vs 100,000 |
| Predicados correlacionados | Columna calculada combinada o índice filtrado | AND legacy producto; 2014 backoff S1·S2^½ |
| Expresión sobre columna (`col % 2`) | Reescribir sargable | legacy 31,622 (C^¾) vs 2014 500,000 |
Unknowns: `> < >= <=` 30% · BETWEEN/LIKE 9% (BETWEEN vars 2014: 16.4317%) · `=` única 1 · no única C^½ (2014) / C^¾ (legacy). Auto update stats: 500 + 20%.
Compat 120 = CE nuevo; `QUERYTRACEON 9481` legacy, `2312` nuevo.

## F. Paralelismo
| Síntoma | Idea | Dato |
|---|---|---|
| Repartition de millones de filas + Sort gigante | Parallel APPLY: driver table + CROSS APPLY correlacionado | 31 s → 15 s (57M filas) |
| Plan serial inesperado | Ver `NonParallelPlanReason`: UDF escalar, modificar @tabla, backward scan | quitar inhibidor |
| Paralelo innecesario en OLTP | `MAXDOP` bajo | cost threshold default 5 (rec. 30–50) |
Gather: DOP→1 · Distribute: 1→DOP · Repartition: DOP→DOP. Costo CPU / DOP for costing (min(schedulers/2, MAXDOP)); I/O no se divide.

## Prohibido como "optimización"
- NOLOCK/READ UNCOMMITTED: allocation order scan inseguro (duplica/omite filas por splits).
- Cambiar semántica (quitar DISTINCT, ORDER BY, filas) para ganar tiempo.
