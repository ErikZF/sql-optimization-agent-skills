#!/usr/bin/env python3
"""Uso: elegir.py --base resultados/<base>.json --iter N [--ideas ideas.json]
Rankea resultados/version*_query.json válidos (ok + checksum == base). Desempate logical_reads.
Métrica: sql_ms_mediana (tiempo reportado por SQL Server) si base y todas las válidas lo tienen; si no, ms_mediana (reloj).
Si ganadora mejora >umbral a la base -> copia a mejor_query.sql (+ setup/teardown) y actualiza mejor.json.
MUEVE versiones + resultados a historial/iterN/ para que la siguiente iteración empiece limpia. Imprime tabla markdown."""
import argparse, glob, json, os, shutil, sys

sys.stdout.reconfigure(encoding='utf-8')

def load(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)

def dump(o, p):
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(o, f, indent=2, ensure_ascii=False)

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True)
ap.add_argument('--iter', type=int, required=True)
ap.add_argument('--ideas', help='json {"1":"idea",...} opcional')
ap.add_argument('--umbral', type=float, default=0.05)
a = ap.parse_args()

base = load(a.base)
ideas = load(a.ideas) if a.ideas and os.path.exists(a.ideas) else {}
rows = []
for f in sorted(glob.glob('resultados/version*_query.json')):
    r = load(f)
    v = os.path.basename(f).split('_')[0].replace('version', '')
    r['version'] = v
    r['idea'] = ideas.get(v, '')
    r['valida'] = bool(r.get('ok')) and r.get('checksum') == base.get('checksum')
    if r.get('ok') and not r['valida']:
        r['error'] = (r.get('error') or '') + ' resultado distinto a base'
    rows.append(r)

val = [r for r in rows if r['valida']]
metrica = 'sql_ms_mediana' if all((r.get('sql_ms_mediana') or 0) > 0 for r in [base] + val) else 'ms_mediana'
ms = lambda r: r.get(metrica) or 0
val.sort(key=lambda r: (ms(r), r.get('logical_reads') or 0))
bm = ms(base) or 1

print(f"Métrica: {metrica}\n")
print(f"| v | idea | ms | logical reads | Δ% vs base | ok |\n|---|---|---|---|---|---|")
print(f"| base | {base['archivo']} | {ms(base)} | {base.get('logical_reads')} | 0 | ✓ |")
for r in sorted(rows, key=lambda r: (not r['valida'], ms(r))):
    d = round((ms(r) - bm) / bm * 100, 1)
    print(f"| {r['version']} | {r['idea'][:60]} | {ms(r)} | {r.get('logical_reads')} | {d} | {'✓' if r['valida'] else '✗ ' + (r.get('error') or '')} |")

# Referencia: la base medida ahora (mismas condiciones). Si la base no es la mejor vigente, exigir superar también mejor.json.
prev = load('mejor.json') if os.path.exists('mejor.json') else None
ref = bm
if prev and os.path.basename(base['archivo']) != 'mejor_query.sql' and prev.get(metrica):
    ref = min(ref, prev[metrica])

w = val[0] if val else None
if not w:
    msg = '\nSin versión válida. mejor_query.sql sin cambios.'
elif ms(w) < ref * (1 - a.umbral):
    shutil.copy(w['archivo'], 'mejor_query.sql')
    # setup/teardown de la ganadora; si no tiene, borrar los de la mejor anterior (la ganadora se midió sin ellos)
    for suf in ('setup', 'teardown'):
        src, dst = w['archivo'].replace('_query.sql', f'_{suf}.sql'), f'mejor_{suf}.sql'
        if os.path.exists(src):
            shutil.copy(src, dst)
        elif os.path.exists(dst):
            os.remove(dst)
    hist = (prev or {}).get('historia', []) + [{'iter': a.iter, 'version': w['version'], metrica: ms(w), 'idea': w['idea']}]
    dump({**w, 'metrica': metrica, 'iter': a.iter, 'original_ms': (prev or {}).get('original_ms', bm), 'historia': hist}, 'mejor.json')
    msg = f"\nNueva mejor: version{w['version']} ({ms(w)} ms vs {ref} ms) -> mejor_query.sql"
else:
    msg = f"\nGanadora version{w['version']} ({ms(w)} ms) no supera mejor actual ({ref} ms) por >{int(a.umbral*100)}%. Sin cambios."

# Archivar moviendo: evita que setup/teardown o resultados de esta iteración se reusen en la siguiente
dest = f'historial/iter{a.iter}'
os.makedirs(dest, exist_ok=True)
for f in (glob.glob('version*_query.sql') + glob.glob('version*_setup.sql') + glob.glob('version*_teardown.sql')
          + glob.glob('resultados/version*_query.*')):
    os.replace(f, os.path.join(dest, os.path.basename(f)))
if a.ideas and os.path.exists(a.ideas):
    shutil.copy(a.ideas, dest)
dump({'metrica': metrica, 'base': base, 'versiones': rows}, f'{dest}/resultados.json')
print(msg)
print(f"Versiones movidas a {dest}/")
