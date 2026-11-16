"""Review round 1: split-half reliability of resting CF and BW (IBF, IBB) — decision log §11v (post-hoc).

    python r1_splithalf_icc_cfbw.py --mode extract --stage4 <outRoot>/stage4 --roi-dir <eegOutRoot>/stage4/roi
        --out-dir <outRoot>/review1/splithalf_icc

    python r1_splithalf_icc_cfbw.py --mode synthetic --out-dir <outRoot>/review1/splithalf_icc

Mode `synthetic` (§11v D3 verification; touches no real data): reference checks of the interval code, then
  bivariate-normal pairs, n = 20, true ICC 0.5 / 0.75 / 0.9, 1,000 datasets each, B = 1,999; coverage of the BCa
  95 % interval and of the analytic McGraw & Wong (1996) interval, computed by the same functions that the real
  data will use; the D3 rule (BCa coverage 0.92-0.98, fallback to the analytic interval) applied mechanically.

Mode `extract`:
  1. GATE (§11v D0), entirely in memory. For every one of the 39 rest ROI files the frozen Stage-4 split-half is
     repeated exactly as stage4_peak_detection.py does it (split_half_runs -> welch_runs -> run_pipeline ->
     classify at the subject's own half-length p95), and class_h1/h2 and max_beta_pw_h1/h2 are compared with the
     §9 split_half.csv: class exactly, PW within 1e-9 absolute. The participants classified `peak` in both halves
     must number 20, and ICC(2,1) of their recomputed PW must reproduce `icc_pw` of split_half_summary.json within
     1e-9. Every check is evaluated and reported; if any fails, the script exits with code 1 and writes nothing
     (the out-dir is not even created).
  2. Only if every check passes: for the 20 participants, the tallest beta-range Gaussian of each half
     (core.beta_peaks(peaks)[0], §11v D2b; no cross-half matching) is written, with the D2b descriptives.
No ICC of CF or BW and no bootstrap is computed here (§11v D3 is a later step).

stage4_core, and icc_2_1 from stage4_peak_detection, are imported unchanged (frozen at S4-prereg-frozen).
"""
import argparse
import glob
import json
import os
import sys

import numpy as np

import r1_common as rc                       # puts revision/stage4 on sys.path; imports stage4_core unchanged
from r1_common import core                   # noqa: E402
from stage4_peak_detection import icc_2_1, N_SUBJECTS, PRIMARY   # noqa: E402  (frozen, verified §9)

PW_TOL = 1e-9                                # §11v D0
ICC_TOL = 1e-9                               # §11v D0
N_PEAK_BOTH_EXPECTED = 20                    # §9, §11v D2
BW_BOUND_TOL = 1e-6                          # Hz; "at the 1 or 8 Hz bound" (§11v D2b), see report
CLASS_KEYS = ('class_h1', 'class_h2')
PW_KEYS = ('max_beta_pw_h1', 'max_beta_pw_h2')


def half_fits(rec, thr_half):
    """Repeat stage4_peak_detection.py lines 144-153 for one subject; also keep the fitted peaks."""
    h1, h2 = core.split_half_runs(rec['runs'], rec['fs'])
    th = [thr_half.get(rec['subject'], {}).get(len(h)) for h in (h1, h2)]
    if None in th:
        raise SystemExit(f"{rec['subject']}: no half threshold for {len(h1)} / {len(h2)} epochs")
    hr = [core.run_pipeline(*core.welch_runs(h, rec['fs'])) for h in (h1, h2)]   # = analyse(h, fs)
    out = dict(subject=rec['subject'], n_epochs_h1=len(h1), n_epochs_h2=len(h2))
    for i, (r, t) in enumerate(zip(hr, th), 1):
        out.update({f'thr_p95_h{i}': t, f'r2_h{i}': r['r2'], f'class_h{i}': core.classify(r, t),
                    f'max_beta_pw_h{i}': core.max_beta_pw(r['peaks']), f'peaks_h{i}': r['peaks']})
    return out


def gate(recomputed, stored, icc_stored, n_both_stored):
    """All §11v D0 checks. Returns (passed, report dict, both-peak subjects)."""
    checks, fails = {}, []
    subs_r, subs_s = sorted(recomputed), sorted(stored)
    checks['subjects'] = dict(n_recomputed=len(subs_r), n_stored=len(subs_s), expected=N_SUBJECTS,
                              same_set=subs_r == subs_s)
    if not (len(subs_r) == len(subs_s) == N_SUBJECTS and subs_r == subs_s):
        fails.append('subjects')
    common = [s for s in subs_r if s in stored]

    # input consistency (not a §11v criterion, but a mismatch would make every later check meaningless)
    thr_mis = [(s, k, recomputed[s][k], float(stored[s][k])) for s in common for k in ('thr_p95_h1', 'thr_p95_h2')
               if recomputed[s][k] != float(stored[s][k])]
    ep_mis = [(s, k, recomputed[s][k], int(stored[s][k])) for s in common for k in ('n_epochs_h1', 'n_epochs_h2')
              if recomputed[s][k] != int(stored[s][k])]
    checks['inputs_half_thresholds_and_epoch_counts'] = dict(n_mismatch=len(thr_mis) + len(ep_mis),
                                                             mismatches=thr_mis + ep_mis)
    if thr_mis or ep_mis:
        fails.append('inputs_half_thresholds_and_epoch_counts')

    cls_mis = [(s, k, recomputed[s][k], stored[s][k]) for s in common for k in CLASS_KEYS
               if recomputed[s][k] != stored[s][k]]
    checks['class_exact'] = dict(n_compared=2 * len(common), n_mismatch=len(cls_mis), mismatches=cls_mis)
    if cls_mis:
        fails.append('class_exact')

    dpw = {(s, k): abs(recomputed[s][k] - float(stored[s][k])) for s in common for k in PW_KEYS}
    pw_mis = [(s, k, d) for (s, k), d in dpw.items() if not d <= PW_TOL]        # NaN counts as a failure
    worst = max(dpw.items(), key=lambda kv: kv[1]) if dpw else (None, float('nan'))
    checks['pw_within_tol'] = dict(tol=PW_TOL, n_compared=len(dpw), n_mismatch=len(pw_mis),
                                   max_abs_diff=worst[1], max_at=worst[0], mismatches=pw_mis)
    if pw_mis:
        fails.append('pw_within_tol')

    both = [s for s in subs_r if recomputed[s]['class_h1'] == recomputed[s]['class_h2'] == 'peak']
    checks['n_peak_both'] = dict(recomputed=len(both), expected=N_PEAK_BOTH_EXPECTED, stored_summary=n_both_stored)
    if not len(both) == N_PEAK_BOTH_EXPECTED == n_both_stored:
        fails.append('n_peak_both')

    pw = np.array([[recomputed[s]['max_beta_pw_h1'], recomputed[s]['max_beta_pw_h2']] for s in both],
                  dtype=float).reshape(-1, 2)
    icc = icc_2_1(pw) if len(both) else float('nan')
    checks['icc_pw'] = dict(recomputed=icc, stored=icc_stored, abs_diff=abs(icc - icc_stored), tol=ICC_TOL)
    if not abs(icc - icc_stored) <= ICC_TOL:
        fails.append('icc_pw')

    # informational only (not a criterion): agreement of the fit R^2 with the stored value
    dr2 = [abs(recomputed[s][f'r2_h{i}'] - float(stored[s][f'r2_h{i}'])) for s in common for i in (1, 2)]
    checks['info_max_abs_diff_r2'] = max(dr2) if dr2 else float('nan')
    return not fails, dict(passed=not fails, failed_checks=fails, checks=checks), both


# ---------------------------------------------------------------------------------------------------------
# §11v D3 interval machinery: the same functions are used for the synthetic calibration and the real data.
# ---------------------------------------------------------------------------------------------------------
ALPHA_CI = 0.05                              # two-sided 95 % (§11v D3)
NAN_RESAMPLE_MAX = 0.01                      # > 1 % NaN resamples: stop (real) / flag (synthetic)
B_REAL = 10_000                              # §11v D3 (real data)
SEED_REAL = 20261120                         # §11v D3 (real data); the synthetic run uses its own seed
B_SYNTH = 1_999                              # §11v D3 verification
N_SYNTH = 1_000                              # datasets per true ICC (§11v D3)
TRUE_ICCS = (0.5, 0.75, 0.9)                 # §11v D3
N_SYNTH_SUBJ = 20                            # §11v D3
SEED_SYNTH = 20261121                        # synthetic calibration only (not fixed by §11v; chosen here)
COVERAGE_TARGET = (0.92, 0.98)               # §11v D3


def icc_parts(x):
    """Mean squares of the two-way ANOVA, same formulas as icc_2_1 (stage4_peak_detection.py)."""
    n, k = x.shape
    grand = x.mean()
    msr = k * np.sum((x.mean(axis=1) - grand) ** 2) / (n - 1)
    msc = n * np.sum((x.mean(axis=0) - grand) ** 2) / (k - 1)
    sse = np.sum((x - x.mean(axis=1, keepdims=True) - x.mean(axis=0, keepdims=True) + grand) ** 2)
    mse = sse / ((n - 1) * (k - 1))
    return n, k, msr, msc, mse


def mw_ci(x, alpha=ALPHA_CI):
    """Analytic CI for ICC(A,1), McGraw & Wong (1996), case 2A (Satterthwaite df for the denominator)."""
    from scipy.stats import f as fdist
    n, k, msr, msc, mse = icc_parts(x)
    r = icc_2_1(x)
    a = k * r / (n * (1 - r))
    b = 1 + k * r * (n - 1) / (n * (1 - r))
    v = (a * msc + b * mse) ** 2 / ((a * msc) ** 2 / (k - 1) + (b * mse) ** 2 / ((n - 1) * (k - 1)))
    fl = fdist.ppf(1 - alpha / 2, n - 1, v)
    fu = fdist.ppf(1 - alpha / 2, v, n - 1)
    lo = n * (msr - fl * mse) / (fl * (k * msc + (k * n - k - n) * mse) + n * msr)
    hi = n * (fu * msr - mse) / (k * msc + (k * n - k - n) * mse + n * fu * msr)
    return float(lo), float(hi)


def bca_ci(x, n_boot, rng, alpha=ALPHA_CI):
    """BCa bootstrap CI of icc_2_1, resampling participants (rows; the h1, h2 pair moves together).
    Efron & Tibshirani (1993), §14.3: z0 = Phi^-1(#{theta* < theta_hat} / B'), acceleration from the
    leave-one-out jackknife, adjusted percentiles of the bootstrap distribution (np.quantile, linear).
    B' = non-NaN resamples (NaN ones are counted and dropped, §11v D3)."""
    from scipy.stats import norm
    n = x.shape[0]
    theta = icc_2_1(x)
    idx = rng.integers(0, n, size=(n_boot, n))
    boot = np.array([icc_2_1(x[i]) for i in idx])
    ok = ~np.isnan(boot)
    n_nan = int((~ok).sum())
    boot = boot[ok]
    jack = np.array([icc_2_1(np.delete(x, i, axis=0)) for i in range(n)])
    d = jack.mean() - jack
    a = float(np.sum(d ** 3) / (6 * np.sum(d ** 2) ** 1.5)) if np.sum(d ** 2) > 0 else 0.0
    prop = np.mean(boot < theta) if len(boot) else float('nan')
    out = dict(theta=theta, n_boot=n_boot, n_nan=n_nan, nan_frac=n_nan / n_boot, z0=float('nan'), a=a,
               jack_min=float(jack.min()), jack_max=float(jack.max()), lo=float('nan'), hi=float('nan'))
    if not 0 < prop < 1:                    # z0 infinite: BCa undefined for this sample
        return out
    z0 = norm.ppf(prop)
    zs = norm.ppf([alpha / 2, 1 - alpha / 2])
    adj = norm.cdf(z0 + (z0 + zs) / (1 - a * (z0 + zs)))
    lo, hi = np.quantile(boot, adj)
    out.update(z0=float(z0), lo=float(lo), hi=float(hi), adj_lo=float(adj[0]), adj_hi=float(adj[1]))
    return out


def reference_checks():
    """Implementation checks with known answers, run before the synthetic calibration."""
    from scipy.stats import bootstrap
    # Shrout & Fleiss (1979) Table 2: 6 targets x 4 judges; ICC(2,1) = 0.29 (verified for icc_2_1 in §9)
    sf = np.array([[9, 2, 5, 8], [6, 1, 3, 2], [8, 4, 6, 8], [7, 1, 2, 6], [10, 5, 6, 9], [6, 2, 4, 7]], float)
    sf_lo, sf_hi = mw_ci(sf)
    # BCa vs scipy.stats.bootstrap(method='BCa') on one synthetic dataset, large B: equal up to Monte Carlo
    rng = np.random.default_rng(SEED_SYNTH - 1)
    x = synth_dataset(rng, 0.75, N_SYNTH_SUBJ)
    own = bca_ci(x, 20_000, np.random.default_rng(1))
    sp = bootstrap((x[:, 0], x[:, 1]), lambda a, b: icc_2_1(np.column_stack([a, b])), paired=True,
                   vectorized=False, n_resamples=20_000, confidence_level=1 - ALPHA_CI, method='BCa',
                   random_state=np.random.default_rng(2)).confidence_interval
    return dict(shrout_fleiss=dict(icc=icc_2_1(sf), mw_lo=sf_lo, mw_hi=sf_hi,
                                   note='no external reference value for the interval available locally '
                                        '(no R / pingouin); compare with R irr::icc(type="agreement", '
                                        'model="twoway", unit="single") on the same table'),
                bca_vs_scipy=dict(B=20_000, own_lo=own['lo'], own_hi=own['hi'],
                                  scipy_lo=float(sp.low), scipy_hi=float(sp.high)))


def synth_dataset(rng, icc, n):
    """Bivariate normal: subject effect ~ N(0, icc), error ~ N(0, 1 - icc), no offset between halves."""
    s = rng.normal(0.0, np.sqrt(icc), size=(n, 1))
    return s + rng.normal(0.0, np.sqrt(1 - icc), size=(n, 2))


def synthetic(args):
    n_sets, n_boot = args.n_datasets, args.boot
    official = (n_sets, n_boot) == (N_SYNTH, B_SYNTH)
    tag = '' if official else '_test'
    outs = {k: os.path.join(args.out_dir, k.format(tag=tag)) for k in
            ('r1_splithalf_icc_synthetic{tag}.json', 'r1_splithalf_icc_synthetic_datasets{tag}.csv')}
    outs = {k.format(tag=tag): v for k, v in outs.items()}
    rc.refuse_existing(outs.values())
    refs = reference_checks()
    print(json.dumps(refs, indent=2), flush=True)
    rows, cells = [], []
    for icc_true, ss in zip(TRUE_ICCS, np.random.SeedSequence(SEED_SYNTH).spawn(len(TRUE_ICCS))):
        rng = np.random.default_rng(ss)
        for j in range(n_sets):
            x = synth_dataset(rng, icc_true, N_SYNTH_SUBJ)
            bc = bca_ci(x, n_boot, rng)
            mlo, mhi = mw_ci(x)
            rows.append(dict(true_icc=icc_true, dataset=j, icc=bc['theta'], bca_lo=bc['lo'], bca_hi=bc['hi'],
                             bca_z0=bc['z0'], bca_a=bc['a'], n_nan_resamples=bc['n_nan'], mw_lo=mlo, mw_hi=mhi))
            if (j + 1) % 100 == 0:
                print(f'ICC {icc_true}: {j + 1}/{n_sets}', flush=True)
        cell = [r for r in rows if r['true_icc'] == icc_true]
        summary = dict(true_icc=icc_true, n_datasets=len(cell))
        for m in ('bca', 'mw'):
            lo = np.array([r[f'{m}_lo'] for r in cell]); hi = np.array([r[f'{m}_hi'] for r in cell])
            nan = np.isnan(lo) | np.isnan(hi)
            cov = (~nan) & (lo <= icc_true) & (icc_true <= hi)              # a NaN interval counts as a miss
            k = int(cov.sum())
            summary[m] = dict(coverage=k / len(cell), n_covered=k, coverage_cp95=rc.cp_ci(k, len(cell)),
                              n_nan_interval=int(nan.sum()),
                              n_miss_true_below_lo=int(((~nan) & (lo > icc_true)).sum()),
                              n_miss_true_above_hi=int(((~nan) & (hi < icc_true)).sum()),
                              median_width=float(np.nanmedian(hi - lo)))
        summary['bca']['n_datasets_nan_resamples_over_1pct'] = sum(r['n_nan_resamples'] / n_boot > NAN_RESAMPLE_MAX
                                                                   for r in cell)
        summary['median_icc_hat'] = float(np.median([r['icc'] for r in cell]))
        cells.append(summary)
    # §11v D3, applied mechanically
    bca_low = [c['true_icc'] for c in cells if c['bca']['coverage'] < COVERAGE_TARGET[0]]
    mw_low = [c['true_icc'] for c in cells if c['mw']['coverage'] < COVERAGE_TARGET[0]]
    if not bca_low:
        outcome = 'BCa used for the D4 verdict'
    elif not mw_low:
        outcome = 'fallback: analytic McGraw-Wong interval used for the D4 verdict'
    else:
        outcome = 'STOP: BCa and analytic coverage both below 0.92 in some cell; report'
    res = dict(test_run=not official, n_subjects=N_SYNTH_SUBJ, n_datasets=n_sets, B=n_boot, seed=SEED_SYNTH,
               alpha=ALPHA_CI, coverage_target=COVERAGE_TARGET, reference_checks=refs, cells=cells,
               bca_cells_below_target=bca_low, mw_cells_below_target=mw_low,
               bca_cells_above_target=[c['true_icc'] for c in cells if c['bca']['coverage'] > COVERAGE_TARGET[1]],
               d3_outcome_mechanical=outcome,
               provenance=rc.provenance(__file__, {}))
    os.makedirs(args.out_dir, exist_ok=True)
    rc.write_csv(outs[f'r1_splithalf_icc_synthetic_datasets{tag}.csv'], rows)
    with open(outs[f'r1_splithalf_icc_synthetic{tag}.json'], 'w') as fh:
        json.dump(res, fh, indent=2)
    print(json.dumps({k: res[k] for k in ('cells', 'bca_cells_below_target', 'mw_cells_below_target',
                                          'bca_cells_above_target', 'd3_outcome_mechanical')}, indent=2))


def at_bound(bw):
    return int(abs(bw - core.BW_RANGE[0]) <= BW_BOUND_TOL or abs(bw - core.BW_RANGE[1]) <= BW_BOUND_TOL)


def extract(args):
    sh_csv = os.path.join(args.stage4, 'peak_detection', 'split_half.csv')
    sh_json = os.path.join(args.stage4, 'peak_detection', 'split_half_summary.json')
    half_thr = os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject_half.json')
    outs = {k: os.path.join(args.out_dir, k) for k in
            ('r1_splithalf_gate.json', 'r1_splithalf_cfbw.csv', 'r1_splithalf_descriptives.json')}
    rc.refuse_existing(outs.values())

    # half-length thresholds, read exactly as stage4_peak_detection.py reads them
    with open(half_thr) as fh:
        hj = json.load(fh)
    if hj.get('test_run', True):
        raise SystemExit('half-thresholds file is a TEST run (or lacks test_run)')
    thr_half = {s: {int(n): float(v[PRIMARY]) for n, v in d.items()} for s, d in hj['thresholds'].items()}
    stored = {r['subject']: r for r in rc.read_csv(sh_csv)}
    with open(sh_json) as fh:
        summ = json.load(fh)

    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    recomputed = {}
    for f in files:
        rec = core.load_roi(f)
        if rec['excluded_D12']:                  # as in the frozen script; none in practice (§5)
            continue
        recomputed[rec['subject']] = half_fits(rec, thr_half)
        r = recomputed[rec['subject']]
        print(f"{r['subject']}  halves {r['class_h1']}/{r['class_h2']}", flush=True)

    passed, report, both = gate(recomputed, stored, float(summ['icc_pw']), int(summ['n_peak_both']))
    report['provenance'] = rc.provenance(__file__, dict(split_half_csv=sh_csv, split_half_summary=sh_json,
                                                        half_thresholds=half_thr))
    report['roi_dir'] = args.roi_dir
    report['n_roi_files'] = len(files)
    print(json.dumps({k: report[k] for k in ('passed', 'failed_checks', 'checks')}, indent=2, default=str))
    if not passed:
        print('GATE FAILED: nothing written, CF/BW not extracted.', file=sys.stderr)
        sys.exit(1)

    # ---- gate passed: §11v D2b extraction for the 20 participants ----
    rows = []
    for s in both:
        r = recomputed[s]
        bp = [core.beta_peaks(r[f'peaks_h{i}']) for i in (1, 2)]
        cf1, pw1, bw1 = bp[0][0]
        cf2, pw2, bw2 = bp[1][0]
        rows.append(dict(subject=s, cf_h1=cf1, pw_h1=pw1, bw_h1=bw1, cf_h2=cf2, pw_h2=pw2, bw_h2=bw2,
                         n_beta_h1=len(bp[0]), n_beta_h2=len(bp[1]), abs_dcf=abs(cf1 - cf2),
                         bw_h1_at_bound=at_bound(bw1), bw_h2_at_bound=at_bound(bw2),
                         beta_gaussians_h1=rc.peaks_to_str(r['peaks_h1']),
                         beta_gaussians_h2=rc.peaks_to_str(r['peaks_h2'])))
        # the extracted PW must be the gated PW (same Gaussian)
        assert pw1 == r['max_beta_pw_h1'] and pw2 == r['max_beta_pw_h2'], s
    desc = dict(n=len(rows),
                n_multi_beta_h1=sum(x['n_beta_h1'] > 1 for x in rows),
                n_multi_beta_h2=sum(x['n_beta_h2'] > 1 for x in rows),
                n_multi_beta_either=sum(x['n_beta_h1'] > 1 or x['n_beta_h2'] > 1 for x in rows),
                n_bw_at_bound_h1=sum(x['bw_h1_at_bound'] for x in rows),
                n_bw_at_bound_h2=sum(x['bw_h2_at_bound'] for x in rows),
                n_participants_bw_at_bound_either=sum(x['bw_h1_at_bound'] or x['bw_h2_at_bound'] for x in rows),
                bw_bound_tol_hz=BW_BOUND_TOL,
                note='abs_dcf per participant is in r1_splithalf_cfbw.csv; jackknife ICC range is computed '
                     'with the ICC step (§11v D3), not here')
    os.makedirs(args.out_dir, exist_ok=True)
    with open(outs['r1_splithalf_gate.json'], 'w') as fh:
        json.dump(report, fh, indent=2, default=str)
    rc.write_csv(outs['r1_splithalf_cfbw.csv'], rows)
    with open(outs['r1_splithalf_descriptives.json'], 'w') as fh:
        json.dump(desc, fh, indent=2)
    print(f"GATE PASSED. Written: {', '.join(os.path.basename(p) for p in outs.values())}")
    print(json.dumps({k: v for k, v in desc.items() if k != 'note'}, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--mode', required=True, choices=('extract', 'synthetic'))
    ap.add_argument('--stage4')
    ap.add_argument('--roi-dir')
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--n-datasets', type=int, default=N_SYNTH, help='synthetic only; non-default = _test files')
    ap.add_argument('--boot', type=int, default=B_SYNTH, help='synthetic only; non-default = _test files')
    args = ap.parse_args()
    if args.mode == 'extract':
        if not (args.stage4 and args.roi_dir):
            ap.error('--mode extract needs --stage4 and --roi-dir')
        extract(args)
    else:
        synthetic(args)


if __name__ == '__main__':
    main()
