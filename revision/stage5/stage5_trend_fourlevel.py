"""Stage 5: POST-HOC four-level Page's L on the literature reaction-time order (decision log §10q).

    python stage5_trend_fourlevel.py --cells <outRoot>/stage5/erd/stage5_erd_per_subject_condition.csv \
        --out-dir <outRoot>/stage5/trend_fourlevel

NOT PRE-SPECIFIED, and §10q says why in full. The four-level order 00 < S0 < F0 < FS is externally
justified - Palucha et al. (2025, bioRxiv 10.1101/2025.03.05.641477) report reaction times of 535.86,
592.98, 676.85 and 744.33 ms on this same paradigm and stimulus set, with every adjacent pair separated
at p < .001 - but the decision to run this test was taken AFTER §10l's condition medians were known, and
those medians put S0 above F0 in the first-in-mini-block class, the reverse of the reaction-time order.
So this test is reported beside §10k's pre-specified three-level result and NEVER replaces it.

Note also, from the same paper, that accuracy does NOT separate Simon from flanker (p = .80): the
four-level order is a SPEED order. That is why §10k's collapse of the two single-conflict conditions
remains the defensible pre-specified choice.

What it does: Page's L over the four conditions in the order 00 < S0 < F0 < FS, for every metric and
every mini-block class, next to the three-level result recomputed here by the same call so the two are
directly comparable. scipy.stats.page_trend_test is used, exact where it can be. Nothing else is
computed and no verdict is derived: the output is descriptive by construction.

Reads only the committed cell table. Never overwrites.
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from scipy.stats import page_trend_test

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stage5_erd_stats as st                      # noqa: E402  (COND_ORDER, CLASSES, TREND_LEVELS, ...)

FOUR_LEVEL = ('00', 'S0', 'F0', 'FS')              # §10q: the Palucha et al. 2025 reaction-time order
THREE_LEVEL = st.TREND_LEVELS                      # §10k: 00 < mean(F0, S0) < FS
METRICS = st.METRICS
CLASSES = st.CLASSES
PRIMARY = st.PRIMARY


def page(levels):
    res = page_trend_test(levels, ranked=False)
    return float(res.statistic), float(res.pvalue), str(res.method)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cells', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_trend_fourlevel.csv', 'stage5_trend_fourlevel_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    cells, _ = st.read_cells(args.cells)
    os.makedirs(args.out_dir, exist_ok=True)

    idx = {c: j for j, c in enumerate(st.COND_ORDER)}
    rows = []
    for metric in METRICS:
        for cls in CLASSES:
            subs, m = cells[(metric, cls)]
            if m.shape[0] < 3:
                continue
            four = m[:, [idx[c] for c in FOUR_LEVEL]]
            three = np.column_stack([m[:, [idx[c] for c in g]].mean(axis=1) for g in THREE_LEVEL])
            L4, p4, meth4 = page(four)
            L3, p3, meth3 = page(three)
            rows.append(dict(metric=metric, miniblock_class=cls, primary_metric=int(metric == PRIMARY),
                             n_subjects=m.shape[0],
                             four_level_order='<'.join(FOUR_LEVEL), page_L_4=L4, page_p_4=p4,
                             page_method_4=meth4, prespecified_4=0,
                             three_level_order='<'.join('+'.join(g) for g in THREE_LEVEL),
                             page_L_3=L3, page_p_3=p3, page_method_3=meth3, prespecified_3=1,
                             agree_at_05=int((p4 < 0.05) == (p3 < 0.05)),
                             **{f'median_{c}': float(np.median(m[:, idx[c]])) for c in st.COND_ORDER}))

    with open(names['stage5_trend_fourlevel.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), restval='')
        w.writeheader()
        w.writerows(rows)
    with open(names['stage5_trend_fourlevel_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_trend_fourlevel.py', plan='docs/decision_log.md sec 10q',
                       prespecified=False,
                       disclosure='post-hoc: the four-level order is externally justified by Palucha et '
                                  'al. 2025 reaction times, but the decision to run the test came after '
                                  'sec 10l medians were known; it never replaces the sec 10k three-level '
                                  'result',
                       four_level_order=list(FOUR_LEVEL),
                       four_level_source='Palucha et al. 2025, bioRxiv 10.1101/2025.03.05.641477; RTs '
                                         '535.86 / 592.98 / 676.85 / 744.33 ms, all adjacent pairs '
                                         'p < .001; accuracy does NOT separate S0 from F0 (p = .80)',
                       three_level_order=[list(g) for g in THREE_LEVEL],
                       cells_file=args.cells), fh, indent=2)

    print(f"{'metric':22s} {'class':6s} {'n':>3s} | {'L4':>7s} {'p4':>10s} | {'L3':>7s} {'p3':>10s} | agree")
    for r in rows:
        star = ' <- PRIMARY' if r['primary_metric'] else ''
        print(f"{r['metric']:22s} {r['miniblock_class']:6s} {r['n_subjects']:3d} | "
              f"{r['page_L_4']:7.1f} {r['page_p_4']:10.3g} | "
              f"{r['page_L_3']:7.1f} {r['page_p_3']:10.3g} | "
              f"{'yes' if r['agree_at_05'] else 'NO '}{star}")
    print('\nmedians by condition (primary metric only):')
    for r in rows:
        if r['primary_metric']:
            print(f"  {r['miniblock_class']:6s} " +
                  '  '.join(f"{c} {r[f'median_{c}']:7.3f}" for c in FOUR_LEVEL) +
                  ('   <- S0 above F0, against the RT order'
                   if r['median_S0'] > r['median_F0'] else '   <- follows the RT order'))
    print(f"\nwrote: {', '.join(os.path.basename(p) for p in names.values())}")


if __name__ == '__main__':
    main()
