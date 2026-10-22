#!/usr/bin/env python3
"""Riepilogo di un run (jsonl dell'harness) e confronto opzionale con un run di riferimento.

Uso: python3 summarize.py runs/c1.jsonl [runs/c0.jsonl] [--by brand|type] [--diff]
Per ogni id vale l'ultimo record senza errore (i retry si accodano allo stesso file).
"""
import json, sys, collections

METRICS = ['unit_hit', 'part_hit', 'top3_unit_hit', 'bag_hit']


def load(path):
    recs = {}
    for line in open(path):
        r = json.loads(line)
        if 'error' in r and r['id'] in recs:
            continue
        recs[r['id']] = r
    return recs


def stats(recs, ids=None):
    rs = [r for i, r in recs.items() if (ids is None or i in ids) and 'error' not in r]
    n = len(rs)
    out = {'n': n, 'errors': sum(1 for i, r in recs.items() if (ids is None or i in ids) and 'error' in r)}
    for m in METRICS:
        out[m] = sum(1 for r in rs if r.get(m))
    out['avg_s'] = round(sum(r['ms'] for r in rs) / n / 1000, 1) if n else 0
    return out


def fmt(s):
    pct = lambda k: f"{s[k]:>3} ({100 * s[k] / s['n']:4.1f}%)" if s['n'] else '-'
    return f"n={s['n']:>3} err={s['errors']} unit={pct('unit_hit')} part={pct('part_hit')} top3={pct('top3_unit_hit')} bag={pct('bag_hit')} avg={s['avg_s']}s"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    by = 'brand' if '--by' not in sys.argv else sys.argv[sys.argv.index('--by') + 1]
    args = [a for a in args if a not in ('brand', 'type')]
    cur = load(args[0])
    ref = load(args[1]) if len(args) > 1 else None
    common = set(cur) & set(ref) if ref else None
    print(f"{args[0]}: {fmt(stats(cur, common))}")
    if ref:
        print(f"{args[1]}: {fmt(stats(ref, common))}")
    groups = collections.defaultdict(set)
    for i, r in cur.items():
        groups[r.get(by, '?')].add(i)
    print(f"\nper {by} (unit_hit corrente{' / riferimento' if ref else ''}):")
    for g, ids in sorted(groups.items(), key=lambda e: -len(e[1])):
        ids = ids & common if common is not None else ids
        sc = stats(cur, ids)
        line = f"  {g:<16} {sc['unit_hit']:>2}/{sc['n']:<2}"
        if ref:
            sr = stats(ref, ids)
            line += f"   ref {sr['unit_hit']:>2}/{sr['n']:<2}"
        print(line)
    if ref and '--diff' in sys.argv:
        print("\nvariazioni unit_hit:")
        for i in sorted(common):
            a, b = ref[i], cur[i]
            if 'error' in a or 'error' in b or bool(a.get('unit_hit')) == bool(b.get('unit_hit')):
                continue
            sign = '+' if b.get('unit_hit') else '-'
            print(f"  {sign} {i} [{b.get('brand')}/{b.get('type')}] {b['part']}")
            print(f"      ref: {a.get('result_path')}")
            print(f"      cur: {b.get('result_path')}")


if __name__ == '__main__':
    main()
