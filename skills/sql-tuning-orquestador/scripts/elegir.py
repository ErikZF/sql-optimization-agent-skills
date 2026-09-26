#!/usr/bin/env python3
"""Uso: elegir.py --base resultados/query.json --iter 1 [--ideas ideas.json]
Rankea resultados/version*_query.json (ok + checksum == base), por ms_mediana y desempate logical_reads.
Si ganadora mejora >5% a mejor.json (o base) -> copia a mejor_query.sql (+ setup) y actualiza mejor.json.
Archiva versiones + resultados en historial/iterN/. Imprime tabla markdown."""
import argparse, glob, json, os, shutil

ap = argparse.ArgumentParser()
ap.add_argument('--base', required=True)
ap.add_argument('--iter', type=int, required=True)
ap.add_argument('--ideas', help='json {"1":"idea",...} opcional')
ap.add_argument('--umbral', type=float, default=0.05)
a = ap.parse_args()

base = json.load(open(a.base))
ideas = json.load(open(a.ideas)) if a.ideas and os.path.exists(a.ideas) else {}
rows = []
for f in sorted(glob.glob('resultados/version*_query.json')):
    r = json.load(open(f))
    v = os.path.basename(f).split('_')[0].replace('version', '')
    r['version'] = v
    r['idea'] = ideas.get(v, '')
    r['valida'] = bool(r.get('ok')) and r.get('checksum') == base.get('checksum')
    if r.get('ok') and not r['valida']:
        r['error'] = (r.get('error') or '') + ' resultado distinto a base'
    rows.append(r)

val = sorted([r for r in rows if r['valida']], key=lambda r: (r['ms_mediana'], r.get('logical_reads') or 0))
bm = base['ms_mediana'] or 1
print(f"| v | idea | ms | logical reads | Δ% vs base | ok |\n|---|---|---|---|---|---|")
print(f"| base | {base['archivo']} | {base['ms_mediana']} | {base.get('logical_reads')} | 0 | ✓ |")
for r in sorted(rows, key=lambda r: (not r['valida'], r['ms_mediana'])):
    d = round((r['ms_mediana'] - bm) / bm * 100, 1)
    print(f"| {r['version']} | {r['idea'][:60]} | {r['ms_mediana']} | {r.get('logical_reads')} | {d} | {'✓' if r['valida'] else '✗ ' + (r.get('error') or '')} |")

dest = f'historial/iter{a.iter}'
os.makedirs(dest, exist_ok=True)
for f in glob.glob('version*_query.sql') + glob.glob('version*_setup.sql') + glob.glob('version*_teardown.sql'):
    shutil.copy(f, dest)
json.dump({'base': base, 'versiones': rows}, open(f'{dest}/resultados.json', 'w'), indent=2, ensure_ascii=False)

prev = json.load(open('mejor.json')) if os.path.exists('mejor.json') else None
ref = prev['ms_mediana'] if prev else bm
if not val:
    print('\nSin versión válida. mejor_query.sql sin cambios.'); raise SystemExit
w = val[0]
if w['ms_mediana'] < ref * (1 - a.umbral):
    shutil.copy(w['archivo'], 'mejor_query.sql')
    s = w['archivo'].replace('_query.sql', '_setup.sql')
    if os.path.exists(s): shutil.copy(s, 'mejor_setup.sql')
    hist = (prev or {}).get('historia', []) + [{'iter': a.iter, 'version': w['version'], 'ms': w['ms_mediana'], 'idea': w['idea']}]
    json.dump({**w, 'iter': a.iter, 'original_ms': (prev or {}).get('original_ms', bm), 'historia': hist}, open('mejor.json', 'w'), indent=2, ensure_ascii=False)
    print(f"\nNueva mejor: version{w['version']} ({w['ms_mediana']} ms vs {ref} ms) -> mejor_query.sql")
else:
    print(f"\nGanadora version{w['version']} ({w['ms_mediana']} ms) no supera mejor actual ({ref} ms) por >{int(a.umbral*100)}%. Sin cambios.")
