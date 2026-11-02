"""Stage 5 Track A: the pre-specified cross-condition statistics on ERD% (§10g).

    python stage5_erd_stats.py --cells <outRoot>/stage5/erd/stage5_erd_per_subject_condition.csv \
        --out-dir <outRoot>/stage5/erd

Runs exactly the plan recorded in docs/decision_log.md §10g, with no data-dependent branching:
  omnibus   Friedman test across the four MSIT+ conditions (F0, FS, 00, S0) on the subject x condition
            cell means, with Kendall's W = chi2 / (n * (k - 1)) as the effect size. Distribution-free, so
            there is no assumption to check and therefore no branch to take.
  post hoc  Wilcoxon signed-rank on all six pairs, Holm-corrected across the six p-values, with the
            matched-pairs rank-biserial correlation r_rb = (W+ - W-) / (W+ + W-) (Kerby, 2014) computed
            from tied ranks of the absolute non-zero differences - the same definition as
            legacy_v1/statistics/effect_size_rankbiserial.m, so the effect sizes are comparable with the
            ones already in the manuscript. The normal-approximation Z and r = Z / sqrt(N) are reported
            alongside for cross-checking, as that script also does.
  trend     Page's L on the THREE ordered conflict levels the design licenses (§10k): no conflict (00) <
            single conflict (the within-subject mean of F0 and S0) < double conflict (FS), predicted to
            increase in that order. Dzianok et al. 2022 define 00 as non-conflict, S0 as Simon, F0 as
            Flanker and FS as the two combined, so the four conditions carry only a PARTIAL order: the two
            single-conflict conditions are not ordered against each other, and collapsing them is the only
            monotone hypothesis the design supports. scipy's page_trend_test is used (exact where it can
            be, asymptotic otherwise) and the method it chose is reported per row.

Metrics, each analysed independently (§10g):
  erd_pct               PRIMARY: classic ERD% from the trial-averaged powers
  active_power_mean     secondary: absolute post-onset band power
  baseline_power_mean   secondary: absolute baseline band power (shows which side of the ratio moves)
  erd_pct_trialwise     diagnostic: mean of per-trial ratios (heavier tails; see the §10g amendment)

Each metric is run for all three mini-block classes (all / first / later) separately, because §10g
established that the baseline sits a median of 2940 ms after the previous response for first-in-mini-block
trials but only 864 ms for later ones, so ERD% magnitudes are not comparable between the classes.

A subject contributes to a cell only if all four conditions have a value; the n used is reported per row.
Never overwrites.
"""
import argparse
import csv
import itertools
import json
import os

import numpy as np
from scipy.stats import friedmanchisquare, page_trend_test, rankdata, wilcoxon

COND_ORDER = ('F0', 'FS', '00', 'S0')
CLASSES = ('all', 'first', 'later')
METRICS = ('erd_pct', 'active_power_mean', 'baseline_power_mean', 'erd_pct_trialwise')
PRIMARY = 'erd_pct'
# The ordered levels for Page's L (sec 10k): the two single-conflict conditions are averaged within
# subject, because Dzianok et al. 2022's definitions order 00 < {F0, S0} < FS and leave F0 against S0
# unordered. Written as the hypothesis direction: conflict increases left to right.
TREND_LEVELS = (('00',), ('F0', 'S0'), ('FS',))


def holm(pvals):
    """Holm-Bonferroni adjusted p-values, order preserved, monotonicity enforced."""
    p = np.asarray(pvals, dtype=float)
    m = p.size
    order = np.argsort(p)
    adj = np.empty(m)
    run = 0.0
    for i, k in enumerate(order):
        run = max(run, (m - i) * p[k])
        adj[k] = min(1.0, run)
    return adj


def rank_biserial(x, y):
    """Matched-pairs rank-biserial correlation (Kerby 2014), as in
    legacy_v1/statistics/effect_size_rankbiserial.m: exact-zero differences dropped, tied ranks of |d|.
    Sign convention: positive means x > y."""
    d = np.asarray(x, dtype=float) - np.asarray(y, dtype=float)
    d = d[d != 0]
    if d.size == 0:
        return float('nan'), 0.0, 0.0, 0
    r = rankdata(np.abs(d))
    wp = float(r[d > 0].sum())
    wn = float(r[d < 0].sum())
    return (wp - wn) / (wp + wn), wp, wn, int(d.size)


def read_cells(path):
    """{(metric, class): (subjects, n x 4 array)} plus the raw rows."""
    with open(path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    out = {}
    for metric in METRICS:
        for cls in CLASSES:
            d = {}
            for r in rows:
                if r['miniblock_class'] != cls or r['condition'] not in COND_ORDER:
                    continue
                v = r.get(metric, '')
                d.setdefault(r['subject'], {})[r['condition']] = (float(v) if v not in ('', 'NaN') else
                                                                  float('nan'))
            subs = sorted(s for s, dd in d.items()
                          if len(dd) == len(COND_ORDER) and all(np.isfinite(x) for x in dd.values()))
            m = np.array([[d[s][c] for c in COND_ORDER] for s in subs], dtype=float) if subs \
                else np.zeros((0, len(COND_ORDER)))
            out[(metric, cls)] = (subs, m)
    return out, rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cells', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_erd_stats_omnibus.csv', 'stage5_erd_stats_pairwise.csv',
              'stage5_erd_stats_trend.csv', 'stage5_erd_stats_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    cells, _ = read_cells(args.cells)
    os.makedirs(args.out_dir, exist_ok=True)

    omni, pair_rows, trend_rows = [], [], []
    for metric in METRICS:
        for cls in CLASSES:
            subs, m = cells[(metric, cls)]
            n, k = m.shape
            row = dict(metric=metric, miniblock_class=cls, primary=int(metric == PRIMARY), n_subjects=n,
                       n_conditions=k, **{f'median_{c}': '' for c in COND_ORDER})
            if n < 2:
                row.update(friedman_chi2='', friedman_df='', friedman_p='', kendall_w='',
                           note='fewer than 2 complete subjects')
                omni.append(row)
                continue
            chi2, p = friedmanchisquare(*[m[:, j] for j in range(k)])
            row.update(friedman_chi2=float(chi2), friedman_df=k - 1, friedman_p=float(p),
                       kendall_w=float(chi2 / (n * (k - 1))), note='',
                       **{f'median_{c}': float(np.median(m[:, j])) for j, c in enumerate(COND_ORDER)})
            omni.append(row)

            ps, cache = [], []
            for i, j in itertools.combinations(range(k), 2):
                x, y = m[:, i], m[:, j]
                try:
                    pv = float(wilcoxon(x, y, zero_method='wilcox', method='exact').pvalue)
                    meth = 'exact'
                except Exception:
                    pv = float(wilcoxon(x, y, zero_method='wilcox', method='approx').pvalue)
                    meth = 'approx'
                try:
                    res = wilcoxon(x, y, zero_method='wilcox', method='approx')
                    z = float(getattr(res, 'zstatistic', float('nan')))
                except Exception:
                    z = float('nan')
                r_rb, wp, wn, nnz = rank_biserial(x, y)
                ps.append(pv)
                cache.append(dict(metric=metric, miniblock_class=cls, primary=int(metric == PRIMARY),
                                  pair=f'{COND_ORDER[i]}_vs_{COND_ORDER[j]}', n_subjects=n,
                                  n_nonzero_diffs=nnz, W_plus=wp, W_minus=wn, r_rankbiserial=r_rb,
                                  Z=z, r_Zoversqrtn=z / np.sqrt(nnz) if nnz else float('nan'),
                                  median_diff=float(np.median(x - y)), p_wilcoxon=pv, p_method=meth))
            for r, padj in zip(cache, holm(ps)):
                r['p_holm'] = float(padj)
                pair_rows.append(r)

            # Page's L on the three ordered conflict levels (sec 10k). Columns are built in the
            # hypothesised increasing order; the single-conflict level is the within-subject mean of the
            # two unordered single-conflict conditions.
            idx = {c: j for j, c in enumerate(COND_ORDER)}
            lev = np.column_stack([m[:, [idx[c] for c in grp]].mean(axis=1) for grp in TREND_LEVELS])
            trow = dict(metric=metric, miniblock_class=cls, primary=int(metric == PRIMARY), n_subjects=n,
                        n_levels=lev.shape[1],
                        levels='<'.join('+'.join(g) for g in TREND_LEVELS),
                        **{f'median_level{j + 1}': float(np.median(lev[:, j]))
                           for j in range(lev.shape[1])})
            try:
                res = page_trend_test(lev, ranked=False)
                trow.update(page_L=float(res.statistic), page_p=float(res.pvalue),
                            page_method=str(res.method), note='')
            except Exception as exc:                     # too few subjects, or a degenerate cell
                trow.update(page_L='', page_p='', page_method='', note=f'{type(exc).__name__}: {exc}')
            trend_rows.append(trow)

    for key, rows in (('stage5_erd_stats_omnibus.csv', omni),
                      ('stage5_erd_stats_pairwise.csv', pair_rows),
                      ('stage5_erd_stats_trend.csv', trend_rows)):
        with open(names[key], 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), restval='')
            w.writeheader()
            w.writerows(rows)
    with open(names['stage5_erd_stats_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_erd_stats.py', plan='docs/decision_log.md §10g',
                       conditions=COND_ORDER, classes=CLASSES, metrics=METRICS, primary_metric=PRIMARY,
                       omnibus='Friedman chi2, Kendall W = chi2 / (n (k-1))',
                       post_hoc='Wilcoxon signed-rank, all 6 pairs, Holm-corrected over the 6 p-values',
                       effect_size='matched-pairs rank-biserial (Kerby 2014), as in '
                                   'legacy_v1/statistics/effect_size_rankbiserial.m',
                       ordered_trend_test="Page's L on 00 < mean(F0, S0) < FS "
                                          '(sec 10k; F0 vs S0 unordered by design)',
                       cells_file=args.cells), fh, indent=2)

    print(f"{'metric':22s} {'class':6s} {'n':>3s} {'chi2':>8s} {'p':>10s} {'W':>6s}")
    for r in omni:
        if r['friedman_p'] == '':
            print(f"{r['metric']:22s} {r['miniblock_class']:6s} {r['n_subjects']:>3d}  {r['note']}")
        else:
            star = ' <- PRIMARY' if r['primary'] else ''
            print(f"{r['metric']:22s} {r['miniblock_class']:6s} {r['n_subjects']:>3d} "
                  f"{r['friedman_chi2']:8.3f} {r['friedman_p']:10.3g} {r['kendall_w']:6.3f}{star}")
    print('\nsignificant pairs after Holm (p_holm < .05):')
    sig = [r for r in pair_rows if r['p_holm'] < 0.05]
    if not sig:
        print('  none')
    for r in sig:
        print(f"  {r['metric']:22s} {r['miniblock_class']:6s} {r['pair']:12s} "
              f"p_holm {r['p_holm']:.4g}  r_rb {r['r_rankbiserial']:+.3f}")
    print()
    print("Page's L, 00 < mean(F0, S0) < FS:")
    for r in trend_rows:
        if r['page_p'] == '':
            print(f"  {r['metric']:22s} {r['miniblock_class']:6s} {r['note']}")
        else:
            star = ' <- PRIMARY' if r['primary'] else ''
            print(f"  {r['metric']:22s} {r['miniblock_class']:6s} n {r['n_subjects']:>3d} "
                  f"L {r['page_L']:9.1f}  p {r['page_p']:9.3g} ({r['page_method']}){star}")

    print('\nwrote:', ', '.join(os.path.basename(p) for p in names.values()))


if __name__ == '__main__':
    main()
