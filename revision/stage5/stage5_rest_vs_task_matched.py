"""Stage 5: the matched-estimator rest-vs-task comparison (decision log §10o-2).

    python stage5_rest_vs_task_matched.py --rest-roi <eegOutRoot>/stage4/roi \
        --trial-dir <eegOutRoot>/stage5/trials --control-dir <eegOutRoot>/stage5/control \
        --out-dir <outRoot>/stage5/rest_vs_task

This is `revision_plan.md` Stage 5, audit items #5 and #6, CLAUDE.md step 1, and the control-band half of
audit #10. Its decision rule is in §10o-2, committed before the first run.

ONE ESTIMATOR ON BOTH SIDES, which is the entire point. Every window, rest or task, is 500 ms = 250
samples at 500 Hz, through stage5_erd_by_condition.psd_band - imported, not restated - so both sides get
exactly one Hann-tapered periodogram with 2.0 Hz bins, ROI-averaged on linear power and then
band-averaged. Audit #5's objection was that v1 estimated rest with 2 s windows (0.5 Hz bins) and the task
pre-stimulus window with a single 200 ms window (5 Hz true resolution, displayed on 1.95 Hz zero-padded
bins), so alpha could leak into low beta in the task estimate only. After this there is no asymmetry left.

Rest segments (§10o-2). The Stage-4 rest ROI exports hold exactly the KEPT 2 s pseudo-epochs as contiguous
runs. Each is subdivided into four non-overlapping 500 ms segments, so Stage-4's D12 decisions are
inherited unchanged and no new artifact rule enters on the rest side.

The three comparisons, per band, on the within-subject difference of log10 power:
    A   task pre-stimulus vs rest          - the manuscript's +63-73 % claim, recomputed
    B   within-task control window vs rest - the §10m late-ITI window
    C   task pre-stimulus vs control       - is any elevation specific to the pre-stimulus moment?
Bands: 13-30 Hz (the beta claim) and 55-95 Hz (audit #10's EMG control), both clear of the 50/100 Hz line
noise removal and inside the band the pipeline preserves.

Statistics, all imported so nothing can drift: exact Wilcoxon signed-rank on the log10 ratio with
matched-pairs rank-biserial r, Holm-corrected across the three comparisons WITHIN each band; the
geometric-mean percent change with its 90 % CI; and the §10m machinery - the bound-free 90 % CI, TOST at
[0.900, 1.111] and BF01 with r = 0.707. Each comparison is additionally reported with the §10o-1 robust
aggregators, labelled as the post-hoc sensitivity analysis it is.

Never overwrites.
"""
import argparse
import csv
import glob
import json
import os
import sys

import numpy as np
from scipy.io import loadmat
from scipy.stats import wilcoxon

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stage5_erd_by_condition as erd              # noqa: E402  (psd_band, the one estimator)
import stage5_erd_stats as st                      # noqa: E402  (holm, rank_biserial)
import stage5_equivalence as eq                    # noqa: E402  (tost, jzs_bf10_g, the §10m bound)
import stage5_robust_sensitivity as rb             # noqa: E402  (aggregate, the §10o-1 estimators)

N_SUBJECTS = 39
WIN = 250                                          # samples = 500 ms at 500 Hz
BANDS = dict(beta_13_30=(13.0, 30.0), control_55_95=(55.0, 95.0))
SOURCES = ('rest', 'taskpre', 'control')
COMPARISONS = (('A_taskpre_vs_rest', 'taskpre', 'rest'),
               ('B_control_vs_rest', 'control', 'rest'),
               ('C_taskpre_vs_control', 'taskpre', 'control'))
ESTIMATORS = rb.ESTIMATORS                         # ('mean', 'median', 'trim20')
PRESPECIFIED = rb.PRESPECIFIED                     # 'mean'


def segments_rest(path):
    """The kept 2 s pseudo-epochs of one subject, cut into 500 ms segments: (7, 250, n)."""
    d = loadmat(path)
    g = lambda k: np.ravel(d[k])
    fs = float(g('fs')[0])
    assert fs == 500.0, f'{path}: fs {fs}'
    assert int(g('epochSec')[0]) * int(fs) % WIN == 0, 'the 2 s epoch is not a whole number of windows'
    out = []
    for r in d['runs'].ravel():
        a = np.asarray(r, dtype=np.float64)
        n = a.shape[1] // WIN
        assert a.shape[1] % WIN == 0, f'{path}: run of {a.shape[1]} samples is not a multiple of {WIN}'
        out.append(a[:, :n * WIN].reshape(a.shape[0], n, WIN).transpose(0, 2, 1))
    x = np.concatenate(out, axis=2)
    return x, fs, dict(subject=str(g('subject')[0]), excluded=bool(g('excludedD12')[0]),
                       n_kept_epochs=int(g('nKept')[0]))


def segments_task(path, key):
    """The exported 500 ms task windows of one subject: (7, 250, n)."""
    d = loadmat(path)
    g = lambda k: np.ravel(d[k])
    x = np.asarray(d[key], dtype=np.float64)
    if x.ndim == 2:
        x = x[:, :, None]
    assert x.shape[1] == WIN, f'{path}: {key} has {x.shape[1]} samples, {WIN} expected'
    return x, float(g('fs')[0]), dict(subject=str(g('subject')[0]), excluded=bool(g('excludedD12')[0]))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--rest-roi', required=True)
    ap.add_argument('--trial-dir', required=True)
    ap.add_argument('--control-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_rest_vs_task_per_subject.csv', 'stage5_rest_vs_task_tests.csv',
              'stage5_rest_vs_task_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    os.makedirs(args.out_dir, exist_ok=True)

    subs = sorted(os.path.basename(f).split('_')[0]
                  for f in glob.glob(os.path.join(args.rest_roi, 'sub-*_rest_roi.mat')))
    assert len(subs) == N_SUBJECTS, f'{len(subs)} rest ROI files, {N_SUBJECTS} expected'

    per, nseg = [], {s: {} for s in SOURCES}
    power = {(src, band, how): {} for src in SOURCES for band in BANDS for how in ESTIMATORS}
    for sub in subs:
        row = dict(subject=sub)
        got = {}
        got['rest'] = segments_rest(os.path.join(args.rest_roi, f'{sub}_rest_roi.mat'))
        got['taskpre'] = segments_task(os.path.join(args.trial_dir, f'{sub}_msit_trials.mat'), 'base')
        got['control'] = segments_task(os.path.join(args.control_dir, f'{sub}_msit_control.mat'), 'ctrl')
        for src, (x, fs, meta) in got.items():
            assert meta['subject'] == sub, f'{sub}: file says {meta["subject"]}'
            assert not meta['excluded'], f'{sub}: {src} is excluded by D12'
            nseg[src][sub] = x.shape[2]
            row[f'n_{src}'] = x.shape[2]
            for band, lim in BANDS.items():
                p, _, _ = erd.psd_band(x, fs, lim)
                for how in ESTIMATORS:
                    v = rb.aggregate(p, how)
                    power[(src, band, how)][sub] = v
                    if how == PRESPECIFIED:
                        row[f'{src}_{band}'] = v
                row[f'{src}_{band}_median'] = rb.aggregate(p, 'median')
        per.append(row)
        print(f"{sub}  rest {row['n_rest']:5d}  taskpre {row['n_taskpre']:4d}  "
              f"control {row['n_control']:4d} windows", flush=True)

    with open(names['stage5_rest_vs_task_per_subject.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(per[0].keys()), restval='')
        w.writeheader()
        w.writerows(per)

    tests = []
    for band in BANDS:
        for how in ESTIMATORS:
            cache, ps = [], []
            for name, a, b in COMPARISONS:
                x = np.array([power[(a, band, how)][s] for s in subs])
                y = np.array([power[(b, band, how)][s] for s in subs])
                assert (x > 0).all() and (y > 0).all()
                d = np.log10(x) - np.log10(y)
                try:
                    pw = float(wilcoxon(d, zero_method='wilcox', method='exact').pvalue)
                    meth = 'exact'
                except Exception:
                    pw = float(wilcoxon(d, zero_method='wilcox', method='approx').pvalue)
                    meth = 'approx'
                r_rb, _, _, nnz = st.rank_biserial(d, np.zeros_like(d))
                row = dict(band=band, estimator=how, comparison=name,
                           prespecified=int(how == PRESPECIFIED), n=d.size,
                           p_wilcoxon=pw, wilcoxon_method=meth, r_rankbiserial=r_rb,
                           n_nonzero=nnz)
                row.update(eq.tost(d))
                row['geom_pct_change'] = float(100 * (10 ** row['mean_log10_ratio'] - 1))
                row['geom_pct_change_ci90_low'] = float(100 * (10 ** row['ci90_low'] - 1))
                row['geom_pct_change_ci90_high'] = float(100 * (10 ** row['ci90_high'] - 1))
                row['median_pct_change'] = float(100 * (10 ** float(np.median(d)) - 1))
                bf10 = eq.jzs_bf10_g(row['t'], row['n'], eq.R_PRIMARY)
                row.update(bf10=bf10, bf01=1.0 / bf10)
                ps.append(pw)
                cache.append(row)
            for row, padj in zip(cache, st.holm(ps)):
                row['p_holm'] = float(padj)
                tests.append(row)

    with open(names['stage5_rest_vs_task_tests.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(tests[0].keys()), restval='')
        w.writeheader()
        w.writerows(tests)
    with open(names['stage5_rest_vs_task_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_rest_vs_task_matched.py', plan='docs/decision_log.md sec 10o-2',
                       window_samples=WIN, fs=500, bands={k: list(v) for k, v in BANDS.items()},
                       estimator='stage5_erd_by_condition.psd_band, imported; nperseg=250, noverlap=125, '
                                 'nfft=250, hann, detrend constant, density; one segment per window, '
                                 '2.0 Hz bins',
                       rest_segments='the Stage-4 kept 2 s pseudo-epochs subdivided into four 500 ms '
                                     'segments; no new artifact rule',
                       comparisons=[c[0] for c in COMPARISONS],
                       holm='across the 3 comparisons within each band',
                       estimators=list(ESTIMATORS), prespecified_estimator=PRESPECIFIED,
                       robust_disclosure='the median and trim20 rows are the sec 10o-1 sensitivity '
                                         'analysis, added after the sec 10n outlier was found',
                       bound_ratio=eq.RATIO_BOUND,
                       n_segments={k: dict(min=min(v.values()), median=float(np.median(list(v.values()))),
                                           max=max(v.values())) for k, v in nseg.items()}),
                  fh, indent=2)

    for band in BANDS:
        print(f'\n=== {band} ===')
        print(f"{'estimator':10s} {'comparison':22s} {'ratio':>7s} {'geom %':>8s} "
              f"{'90% CI %':>17s} {'p_Holm':>9s} {'r_rb':>7s} {'BF01':>9s} {'p_TOST':>8s} {'eq':>3s}")
        for r in tests:
            if r['band'] != band:
                continue
            tag = '' if r['prespecified'] else ' (sens)'
            print(f"{r['estimator']:10s} {r['comparison']:22s} {r['ratio']:7.4f} "
                  f"{r['geom_pct_change']:+8.2f} "
                  f"[{r['geom_pct_change_ci90_low']:+6.2f},{r['geom_pct_change_ci90_high']:+6.2f}] "
                  f"{r['p_holm']:9.3g} {r['r_rankbiserial']:+7.3f} {r['bf01']:9.3f} "
                  f"{r['p_tost']:8.4f} {r['equivalent']:3d}{tag}")
    print(f"\nwrote: {', '.join(os.path.basename(p) for p in names.values())}")


if __name__ == '__main__':
    main()
