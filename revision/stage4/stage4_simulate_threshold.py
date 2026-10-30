"""Stage 4 threshold calibration by simulation (docs/zenodo_preregistration_stage4.md, §3.6).

    python stage4_simulate_threshold.py --extraction <outRoot>/stage4/stage4_extraction.csv --out-dir <outRoot>/stage4/sim

Design (full factorial): every subject retained by D12 gives one empirical (offset_fixed, exponent_fixed)
pair and its run lengths (39 - k pairs if D12 excluded k subjects; decided 2026-10-30; the count used is
reported). Per pair: 1000 null signals (no peak) and 1000 signals at each of 10 injected heights
(PW 0.05 ... 0.50, CF ~ U[13, 30] Hz, BW ~ U[1, 8] Hz). Every signal goes through the identical pipeline
(stage4_core: welch_runs -> run_pipeline(simulated=True)). The poor-fit flag is not applied. A failed fit
is labelled fit_failed and counts as a non-detection (max PW = 0).

Outputs (out-dir; never overwritten):
  sim_null.csv        one row per null signal       (fit_failed column)
  sim_injected.csv    one row per injected signal   (fit_failed column)
  thresholds.json     p90 / p95 (primary) / p99 of the pooled null max-PW distribution (NumPy 'linear'),
                      pairs used, fit_failed counts and rates (null and per level)
  power_curve.csv     per level: n, detections at p95, proportion, Clopper-Pearson CI, fit_failed count/rate
  logistic.json       binomial MLE on the individual injected outcomes: logit P(detect) = b0 + b1 * height
Each (pair, condition) cell is seeded by SeedSequence(SEED, spawn_key=(pair, condition)) and saved to
parts/ when done, so an interrupted run resumes with identical results.
"""
import argparse
import csv
import json
import os
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np
from scipy.optimize import minimize
from scipy.stats import binomtest

import stage4_core as core

SEED = 20261030
N_REPS = 1000                                             # §3.6
LEVELS = tuple(round(0.05 * i, 2) for i in range(1, 11))  # §3.6: PW 0.05, 0.10, ..., 0.50
CF_RANGE = (13.0, 30.0)                                   # §3.6: CF ~ U[13, 30]
BW_SIM = (1.0, 8.0)                                       # §3.6: BW ~ U[1, 8]
PERCENTILES = (90, 95, 99)                                # §3.6, §3.5.2; 95 = primary
CI_LEVEL = 0.95                                           # §3.6: Clopper-Pearson at 95 % (decided 2026-10-30)
FIELDS = ['subject', 'pair', 'level_pw', 'rep', 'cf_injected', 'bw_injected', 'fit_failed',
          'r2', 'n_beta_peaks', 'max_beta_pw']


def read_pairs(path):
    with open(path, newline='') as fh:
        rows = [r for r in csv.DictReader(fh) if r['excluded_D12'] == '0']
    pairs = []
    for r in rows:
        fs = float(r['fs'])
        epoch = int(round(core.EPOCH_S * fs))
        pairs.append(dict(subject=r['subject'], fs=fs, offset=float(r['offset_fixed']),
                          exponent=float(r['exponent_fixed']),
                          run_lengths=[int(k) * epoch for k in r['run_lengths_epochs'].split(';')]))
        assert np.isfinite(pairs[-1]['offset']) and np.isfinite(pairs[-1]['exponent'])
    return pairs


def run_cell(pair_idx, cond, pair, n_reps):
    """cond 0 = null; cond i >= 1 = injected height LEVELS[i - 1]. Returns one row per repetition."""
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(pair_idx, cond)))
    rows = []
    for rep in range(n_reps):
        if cond == 0:
            pw = cf = bw = None
        else:
            pw = LEVELS[cond - 1]
            cf = rng.uniform(*CF_RANGE)
            bw = rng.uniform(*BW_SIM)
        runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], pair['offset'], pair['exponent'],
                                  cf=cf, bw=bw, pw=pw)
        freqs, psd = core.welch_runs(runs, pair['fs'])
        res = core.run_pipeline(freqs, psd, simulated=True)
        rows.append(dict(subject=pair['subject'], pair=pair_idx, level_pw=0.0 if pw is None else pw, rep=rep,
                         cf_injected='' if cf is None else cf, bw_injected='' if bw is None else bw,
                         fit_failed=int(res['fit_failed']),
                         r2=res['r2'], n_beta_peaks=len(core.beta_peaks(res['peaks'])),
                         max_beta_pw=core.max_beta_pw(res['peaks'])))
    return rows


def write_csv(path, rows):
    tmp = path + '.tmp'
    with open(tmp, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)                                 # a part file is either complete or absent


def read_csv(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def logistic_mle(h, y):
    """Binomial MLE of logit P(y = 1) = b0 + b1 * h on individual outcomes."""
    X = np.column_stack([np.ones_like(h), h])

    def nll(b):
        eta = X @ b
        return np.sum(np.logaddexp(0.0, eta) - y * eta)

    def grad(b):
        return X.T @ (1.0 / (1.0 + np.exp(-(X @ b))) - y)

    r = minimize(nll, np.zeros(2), jac=grad, method='BFGS')
    return dict(b0=float(r.x[0]), b1=float(r.x[1]), converged=bool(r.success), message=str(r.message),
                neg_log_likelihood=float(r.fun), n=int(y.size))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--extraction', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    ap.add_argument('--test-reps', type=int, default=None,
                    help='TEST only: fewer repetitions; outputs get the prefix TEST_ and are not the calibration')
    args = ap.parse_args()
    n_reps = N_REPS if args.test_reps is None else args.test_reps
    prefix = '' if args.test_reps is None else 'TEST_'
    names = {k: os.path.join(args.out_dir, prefix + k) for k in
             ('sim_null.csv', 'sim_injected.csv', 'thresholds.json', 'power_curve.csv', 'logistic.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    parts = os.path.join(args.out_dir, f'{prefix}parts_r{n_reps}')
    os.makedirs(parts, exist_ok=True)

    pairs = read_pairs(args.extraction)
    print(f'{len(pairs)} pairs (subjects retained by D12), {n_reps} repetitions per cell')
    cells = [(i, c) for i in range(len(pairs)) for c in range(len(LEVELS) + 1)]
    part = {cell: os.path.join(parts, f'p{cell[0]:02d}_c{cell[1]:02d}.csv') for cell in cells}
    todo = [cell for cell in cells if not os.path.exists(part[cell])]
    print(f'{len(cells) - len(todo)} of {len(cells)} cells already done')
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        fut = {ex.submit(run_cell, i, c, pairs[i], n_reps): (i, c) for i, c in todo}
        for k, f in enumerate(as_completed(fut), 1):
            write_csv(part[fut[f]], f.result())
            print(f'cell {fut[f]} done ({k}/{len(todo)})', flush=True)

    null = [r for i in range(len(pairs)) for r in read_csv(part[(i, 0)])]
    inj = [r for i in range(len(pairs)) for c in range(1, len(LEVELS) + 1) for r in read_csv(part[(i, c)])]
    assert len(null) == len(pairs) * n_reps and len(inj) == len(pairs) * n_reps * len(LEVELS)
    write_csv(names['sim_null.csv'], null)
    write_csv(names['sim_injected.csv'], inj)

    # threshold: percentiles of the pooled null max-PW distribution (fit_failed rows have max PW = 0)
    null_pw = np.array([float(r['max_beta_pw']) for r in null])
    thr = {f'p{q}': float(np.percentile(null_pw, q, method='linear')) for q in PERCENTILES}
    primary = thr['p95']

    # detection-power curve at the primary threshold; Clopper-Pearson (exact) CI
    h = np.array([float(r['level_pw']) for r in inj])
    y = np.array([float(r['max_beta_pw']) >= primary for r in inj], dtype=float)
    failed = np.array([int(r['fit_failed']) for r in inj])
    curve = []
    for lv in LEVELS:
        m = np.isclose(h, lv)
        n, k = int(m.sum()), int(y[m].sum())
        ci = binomtest(k, n).proportion_ci(confidence_level=CI_LEVEL, method='exact')
        curve.append(dict(level_pw=lv, n=n, n_detected=k, proportion=k / n, ci_low=ci.low, ci_high=ci.high,
                          n_fit_failed=int(failed[m].sum()), fit_failed_rate=float(failed[m].mean())))
    with open(names['power_curve.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(curve[0]))
        w.writeheader()
        w.writerows(curve)

    null_failed = np.array([int(r['fit_failed']) for r in null])
    with open(names['thresholds.json'], 'w') as fh:
        json.dump(dict(thresholds=thr, primary='p95', percentile_method='linear', n_null=int(null_pw.size),
                       n_pairs=len(pairs), subjects=[p['subject'] for p in pairs], n_reps=n_reps,
                       levels=LEVELS, seed=SEED, ci_level=CI_LEVEL, fooof_version=core.FOOOF_VERSION,
                       null_fit_failed=int(null_failed.sum()), null_fit_failed_rate=float(null_failed.mean()),
                       injected_fit_failed=int(failed.sum()), injected_fit_failed_rate=float(failed.mean()),
                       test_run=args.test_reps is not None), fh, indent=2)
    with open(names['logistic.json'], 'w') as fh:
        json.dump(dict(model='logit P(detect) = b0 + b1 * level_pw', threshold=primary,
                       **logistic_mle(h, y)), fh, indent=2)
    print(json.dumps(thr))


if __name__ == '__main__':
    main()
