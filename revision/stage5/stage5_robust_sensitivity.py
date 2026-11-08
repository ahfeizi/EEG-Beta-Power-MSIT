"""Stage 5: trial-level robustness SENSITIVITY ANALYSIS for Track A (decision log §10o-1).

    python stage5_robust_sensitivity.py --trials <outRoot>/stage5/erd/stage5_erd_per_trial.csv \
        --cells <outRoot>/stage5/erd/stage5_erd_per_subject_condition.csv \
        --out-dir <outRoot>/stage5/robust

NOT PRE-REGISTERED. §10o-1 records the disclosure in full: this analysis was added on 2026-11-08 AFTER
§10n found that a single trial supplies 89.4 % of sub-06's FS cell mean and that dropping it would reverse
the parametric TOST verdict. Everything it produces is a labelled sensitivity analysis reported BESIDE the
pre-specified mean-based results of §10l and §10n, never in place of them.

What it does. It rebuilds every Track A cell - 39 subjects x 4 conditions x 3 mini-block classes, both
windows - three ways:
    mean     the pre-specified trial average (§10g), recomputed here only to prove the pipeline agrees
    median   the §10o-1 sensitivity estimator: no tuning constant, 50 % breakdown point
    trim20   20 % trimmed mean, reported alongside because it is far more efficient
and then reruns the full §10l statistics and the full §10n equivalence machinery on each, applied
UNIFORMLY to every cell and not only to the cells whose verdict changes.

Every statistical definition is IMPORTED, never restated: holm() and rank_biserial() from
stage5_erd_stats.py, tost() and jzs_bf10_g() and the bound from stage5_equivalence.py. So the sensitivity
analysis cannot differ from the primary analysis by anything except the trial aggregation.

Hard check before anything is reported: the mean-based cells rebuilt here must reproduce the committed
stage5_erd_per_subject_condition.csv to a relative 1e-9, or the script stops. ERD% is recomputed from the
aggregated powers by the same classic formula, (baseline - active) / baseline * 100.

Caveat that §10o-1 requires to travel with the result: the median and the trimmed mean of trial power are
not estimates of the MEAN of trial power. They change the estimand, not just the estimator, and the
classic ERD definition averages power. Agreement therefore supports the robustness of the CONCLUSION, not
of the number.

Never overwrites. Reads only committed CSV tables; no EEG file is touched.
"""
import argparse
import csv
import itertools
import json
import os
import sys

import numpy as np
from scipy.stats import friedmanchisquare, page_trend_test, wilcoxon

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stage5_erd_stats as st                      # noqa: E402  (holm, rank_biserial, COND_ORDER, ...)
import stage5_equivalence as eq                    # noqa: E402  (tost, jzs_bf10_g, the §10m bound)

COND_ORDER = st.COND_ORDER
CLASSES = st.CLASSES
TREND_LEVELS = st.TREND_LEVELS
ESTIMATORS = ('mean', 'median', 'trim20')
PRESPECIFIED = 'mean'
TRIM_FRAC = 0.20


def aggregate(x, how):
    """Aggregate a cell's trial powers. 'mean' is the pre-specified §10g estimator."""
    a = np.sort(np.asarray(x, dtype=float))
    if how == 'mean':
        return float(a.mean())
    if how == 'median':
        return float(np.median(a))
    if how == 'trim20':
        k = int(np.floor(TRIM_FRAC * a.size))
        return float(a[k:a.size - k].mean()) if a.size - 2 * k > 0 else float(np.median(a))
    raise ValueError(how)


def read_trials(path):
    """{(subject, condition, class): (baseline powers, active powers)} over USABLE trials only."""
    out = {}
    with open(path, newline='') as fh:
        for r in csv.DictReader(fh):
            if r['usable'] != '1' or r['condition'] not in COND_ORDER:
                continue
            classes = ['all', 'first' if r['first_in_miniblock'] == '1' else 'later']
            for c in classes:
                k = (r['subject'], r['condition'], c)
                b, a = out.setdefault(k, ([], []))
                b.append(float(r['baseline_power']))
                a.append(float(r['active_power']))
    return out


def build_cells(trials, how):
    """{(metric, class): (subjects, n x 4 array)} for the three metrics, aggregated by `how`."""
    cell = {}
    for (sub, cond, cls), (b, a) in trials.items():
        bb, aa = aggregate(b, how), aggregate(a, how)
        cell[(sub, cond, cls)] = dict(baseline_power_mean=bb, active_power_mean=aa,
                                      erd_pct=(bb - aa) / bb * 100.0 if bb > 0 else float('nan'))
    out = {}
    for metric in ('erd_pct', 'baseline_power_mean', 'active_power_mean'):
        for cls in CLASSES:
            subs = sorted({s for (s, c, cl) in cell if cl == cls})
            subs = [s for s in subs
                    if all((s, c, cls) in cell and np.isfinite(cell[(s, c, cls)][metric])
                           for c in COND_ORDER)]
            m = np.array([[cell[(s, c, cls)][metric] for c in COND_ORDER] for s in subs], dtype=float)
            out[(metric, cls)] = (subs, m)
    return out


def verify_mean(cells, path):
    """The rebuilt mean cells must reproduce the committed table."""
    with open(path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    ref = {(r['subject'], r['condition'], r['miniblock_class']): r for r in rows}
    worst, n = 0.0, 0
    for metric in ('erd_pct', 'baseline_power_mean', 'active_power_mean'):
        for cls in CLASSES:
            subs, m = cells[(metric, cls)]
            for i, s in enumerate(subs):
                for j, c in enumerate(COND_ORDER):
                    v = ref[(s, c, cls)][metric]
                    if v in ('', 'NaN'):
                        continue
                    worst = max(worst, abs(m[i, j] - float(v)) / max(abs(float(v)), 1e-12))
                    n += 1
    assert worst < 1e-9, f'rebuilt mean cells differ from the committed table by {worst:.3e}'
    return dict(n_values_compared=n, max_rel_diff=worst)


def stats_for(cells, how):
    """The §10l statistics on one estimator's cells."""
    omni, pair_rows, trend = [], [], []
    for metric in ('erd_pct', 'baseline_power_mean', 'active_power_mean'):
        for cls in CLASSES:
            subs, m = cells[(metric, cls)]
            n, k = m.shape
            if n < 3:
                continue
            chi2, p = friedmanchisquare(*[m[:, j] for j in range(k)])
            omni.append(dict(estimator=how, metric=metric, miniblock_class=cls, n_subjects=n,
                             friedman_chi2=float(chi2), friedman_p=float(p),
                             kendall_w=float(chi2 / (n * (k - 1))),
                             **{f'median_{c}': float(np.median(m[:, j])) for j, c in enumerate(COND_ORDER)}))
            ps, cache = [], []
            for i, j in itertools.combinations(range(k), 2):
                x, y = m[:, i], m[:, j]
                try:
                    pv = float(wilcoxon(x, y, zero_method='wilcox', method='exact').pvalue)
                except Exception:
                    pv = float(wilcoxon(x, y, zero_method='wilcox', method='approx').pvalue)
                r_rb, _, _, nnz = st.rank_biserial(x, y)
                ps.append(pv)
                cache.append(dict(estimator=how, metric=metric, miniblock_class=cls,
                                  pair=f'{COND_ORDER[i]}_vs_{COND_ORDER[j]}', n_subjects=n,
                                  r_rankbiserial=r_rb, p_wilcoxon=pv))
            for r, padj in zip(cache, st.holm(ps)):
                r['p_holm'] = float(padj)
                pair_rows.append(r)
            idx = {c: j for j, c in enumerate(COND_ORDER)}
            lev = np.column_stack([m[:, [idx[c] for c in g]].mean(axis=1) for g in TREND_LEVELS])
            res = page_trend_test(lev, ranked=False)
            trend.append(dict(estimator=how, metric=metric, miniblock_class=cls, n_subjects=n,
                              page_L=float(res.statistic), page_p=float(res.pvalue),
                              page_method=str(res.method)))
    return omni, pair_rows, trend


def equivalence_for(cells, how):
    """The §10n machinery on one estimator's cells, for the two power metrics."""
    rows = []
    for metric in ('baseline_power_mean', 'active_power_mean'):
        for cls in CLASSES:
            subs, m = cells[(metric, cls)]
            if m.shape[0] < 3 or not (m > 0).all():
                continue
            idx = {c: j for j, c in enumerate(COND_ORDER)}
            for a, b in itertools.combinations(COND_ORDER, 2):
                d = np.log10(m[:, idx[a]]) - np.log10(m[:, idx[b]])
                row = dict(estimator=how, metric=metric, miniblock_class=cls, pair=f'{a}_vs_{b}',
                           primary=int(metric == eq.PRIMARY_METRIC and cls == eq.PRIMARY_CLASS
                                       and (a, b) == eq.PRIMARY_PAIR))
                row.update(eq.tost(d))
                bf10 = eq.jzs_bf10_g(row['t'], row['n'], eq.R_PRIMARY)
                row.update(bf10=bf10, bf01=1.0 / bf10)
                rows.append(row)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--trials', required=True)
    ap.add_argument('--cells', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_robust_omnibus.csv', 'stage5_robust_pairwise.csv', 'stage5_robust_trend.csv',
              'stage5_robust_equivalence.csv', 'stage5_robust_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')

    trials = read_trials(args.trials)
    ncells = len({(s, c) for (s, c, cl) in trials if cl == 'all'})
    built = {how: build_cells(trials, how) for how in ESTIMATORS}
    ver = verify_mean(built[PRESPECIFIED], args.cells)
    print(f'rebuilt mean cells reproduce the committed table: {ver["n_values_compared"]} values, '
          f'max relative difference {ver["max_rel_diff"]:.2e}')
    os.makedirs(args.out_dir, exist_ok=True)

    omni, pair_rows, trend, eqrows = [], [], [], []
    for how in ESTIMATORS:
        o, p_, t = stats_for(built[how], how)
        omni += o
        pair_rows += p_
        trend += t
        eqrows += equivalence_for(built[how], how)
    for key, rows in (('stage5_robust_omnibus.csv', omni), ('stage5_robust_pairwise.csv', pair_rows),
                      ('stage5_robust_trend.csv', trend), ('stage5_robust_equivalence.csv', eqrows)):
        with open(names[key], 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), restval='')
            w.writeheader()
            w.writerows(rows)
    with open(names['stage5_robust_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_robust_sensitivity.py', plan='docs/decision_log.md sec 10o-1',
                       prespecified=False,
                       disclosure='added 2026-11-08 AFTER sec 10n found the sub-06 outlier; a labelled '
                                  'sensitivity analysis reported beside the mean-based primary, never '
                                  'in place of it',
                       estimators=list(ESTIMATORS), prespecified_estimator=PRESPECIFIED,
                       trim_fraction=TRIM_FRAC, n_subject_condition_cells=ncells,
                       mean_reproduction_check=ver,
                       estimand_caveat='the median and trimmed mean of trial power are not estimates of '
                                       'the mean of trial power; they change the estimand',
                       imported_from=['stage5_erd_stats.holm', 'stage5_erd_stats.rank_biserial',
                                      'stage5_equivalence.tost', 'stage5_equivalence.jzs_bf10_g'],
                       bound_ratio=eq.RATIO_BOUND), fh, indent=2)

    print('\nERD%% omnibus per estimator (Friedman p, Kendall W, Page L p):')
    print(f"{'class':6s} " + ' '.join(f'{h:>26s}' for h in ESTIMATORS))
    for cls in CLASSES:
        cells = []
        for how in ESTIMATORS:
            o = next(r for r in omni if r['estimator'] == how and r['metric'] == 'erd_pct'
                     and r['miniblock_class'] == cls)
            t = next(r for r in trend if r['estimator'] == how and r['metric'] == 'erd_pct'
                     and r['miniblock_class'] == cls)
            cells.append(f"p {o['friedman_p']:8.3g} W {o['kendall_w']:.3f} L {t['page_p']:7.2g}")
        print(f'{cls:6s} ' + ' '.join(f'{c:>26s}' for c in cells))

    print('\nbaseline (pre-stimulus) power omnibus per estimator:')
    print(f"{'class':6s} " + ' '.join(f'{h:>26s}' for h in ESTIMATORS))
    for cls in CLASSES:
        cells = []
        for how in ESTIMATORS:
            o = next(r for r in omni if r['estimator'] == how and r['metric'] == 'baseline_power_mean'
                     and r['miniblock_class'] == cls)
            t = next(r for r in trend if r['estimator'] == how
                     and r['metric'] == 'baseline_power_mean' and r['miniblock_class'] == cls)
            cells.append(f"p {o['friedman_p']:8.3g} W {o['kendall_w']:.3f} L {t['page_p']:7.2g}")
        print(f'{cls:6s} ' + ' '.join(f'{c:>26s}' for c in cells))

    print('\nthe §10n PRIMARY comparison (baseline, first class, FS vs 00) per estimator:')
    print(f"{'estimator':10s} {'ratio':>8s} {'90% CI':>19s} {'attained':>9s} {'BF01':>8s} "
          f"{'p_TOST':>8s} {'eq':>3s}")
    for how in ESTIMATORS:
        r = next(x for x in eqrows if x['estimator'] == how and x['primary'] == 1)
        print(f"{how:10s} {r['ratio']:8.4f} "
              f"[{r['ratio_ci90_low']:.4f},{r['ratio_ci90_high']:.4f}] "
              f"{100 * (r['attained_bound_ratio'] - 1):8.1f}% {r['bf01']:8.3f} "
              f"{r['p_tost']:8.4f} {r['equivalent']:3d}")
    print(f"\nwrote: {', '.join(os.path.basename(p) for p in names.values())}")


if __name__ == '__main__':
    main()
