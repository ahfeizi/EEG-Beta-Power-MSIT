"""Per-subject thresholds from an existing simulation run (decided 2026-10-31, option (ii)).

    python stage4_per_subject_thresholds.py --sim-dir <outRoot>/stage4/sim_rough

No new simulation. From the sim-dir outputs of stage4_simulate_threshold.py:
  1. per subject: p90 / p95 / p99 (NumPy 'linear') of that subject's own null max-PW values
     -> thresholds_per_subject.json (read by stage4_peak_detection.py)
  2. every injected signal is classified with its own subject's p95 (detected = max_beta_pw >= p95)
     -> detection_per_subject.csv (per subject x level: n, n_detected)
  3. power curve over all injected signals per level, with Clopper-Pearson 95 % CIs, plus the null row
     (h = 0: each null signal against its own subject's p95) -> power_curve_per_subject.csv
  4. logistic fit (binomial MLE on the individual injected outcomes, null excluded): BFGS from (0, 0),
     then BFGS from (-3, 10), then trust-exact from (-3, 10); the first that converges is reported, or
     converged = false -> logistic_per_subject.json
  5. FPR of every subject at its own p95 (sanity check) -> fpr_per_subject.csv
Simulated data only; nothing from real 13-30 Hz data is read. Never overwrites.
"""
import argparse
import csv
import hashlib
import json
import os

import numpy as np
from scipy.optimize import minimize
from scipy.stats import binomtest

import stage4_simulate_threshold as sim

PERCENTILES = sim.PERCENTILES
OUT = ('thresholds_per_subject.json', 'detection_per_subject.csv', 'power_curve_per_subject.csv',
       'logistic_per_subject.json', 'fpr_per_subject.csv')


def sha256(path):
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def logistic_fit(h, y):
    X = np.column_stack([np.ones_like(h), h])

    def nll(b):
        eta = X @ b
        return np.sum(np.logaddexp(0.0, eta) - y * eta)

    def grad(b):
        return X.T @ (1.0 / (1.0 + np.exp(-(X @ b))) - y)

    def hess(b):
        p = 1.0 / (1.0 + np.exp(-(X @ b)))
        return (X * (p * (1 - p))[:, None]).T @ X

    tried = []
    for method, b0 in (('BFGS', (0.0, 0.0)), ('BFGS', (-3.0, 10.0)), ('trust-exact', (-3.0, 10.0))):
        kw = dict(hess=hess) if method == 'trust-exact' else {}
        r = minimize(nll, np.array(b0), jac=grad, method=method, **kw)
        tried.append(dict(method=method, start=b0, converged=bool(r.success), message=str(r.message),
                          b0=float(r.x[0]), b1=float(r.x[1]), neg_log_likelihood=float(r.fun)))
        if r.success:
            break
    best = tried[-1]
    return dict(model='logit P(detect) = b0 + b1 * level_pw', n=int(y.size), **best, attempts=tried)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sim-dir', required=True)
    args = ap.parse_args()
    paths = {k: os.path.join(args.sim_dir, k) for k in OUT}
    for p in paths.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    with open(os.path.join(args.sim_dir, 'thresholds.json')) as fh:
        meta = json.load(fh)
    if meta.get('test_run', True):
        raise SystemExit('the simulation run is a TEST run (or lacks test_run)')
    null_path = os.path.join(args.sim_dir, 'sim_null.csv')
    inj_path = os.path.join(args.sim_dir, 'sim_injected.csv')
    null = sim.read_csv(null_path)
    inj = sim.read_csv(inj_path)
    subjects = sorted({r['subject'] for r in null})

    thr = {}
    for s in subjects:
        v = np.array([float(r['max_beta_pw']) for r in null if r['subject'] == s])
        assert v.size == meta['n_reps'], f'{s}: {v.size} null signals'
        thr[s] = {f'p{q}': float(np.percentile(v, q, method='linear')) for q in PERCENTILES}
    with open(paths['thresholds_per_subject.json'], 'w') as fh:
        json.dump(dict(thresholds=thr, primary='p95', percentile_method='linear', n_null_per_subject=meta['n_reps'],
                       source_sim_dir=args.sim_dir, sim_null_sha256=sha256(null_path),
                       sim_thresholds_json=meta, test_run=False), fh, indent=2)

    # FPR at each subject's own p95 (sanity check) and the h = 0 row
    fpr = []
    for s in subjects:
        v = np.array([float(r['max_beta_pw']) for r in null if r['subject'] == s])
        k = int((v >= thr[s]['p95']).sum())
        fpr.append(dict(subject=s, rough_sigma=null[[r['subject'] for r in null].index(s)]['rough_sigma'],
                        p95=thr[s]['p95'], n=int(v.size), n_above=k, fpr=k / v.size))
    with open(paths['fpr_per_subject.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(fpr[0]))
        w.writeheader()
        w.writerows(fpr)

    h = np.array([float(r['level_pw']) for r in inj])
    y = np.array([float(r['max_beta_pw']) >= thr[r['subject']]['p95'] for r in inj], dtype=float)
    subj = np.array([r['subject'] for r in inj])
    det = []
    for s in subjects:
        for lv in sim.LEVELS:
            m = (subj == s) & np.isclose(h, lv)
            det.append(dict(subject=s, level_pw=lv, n=int(m.sum()), n_detected=int(y[m].sum())))
    with open(paths['detection_per_subject.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(det[0]))
        w.writeheader()
        w.writerows(det)

    curve = []
    n0, k0 = sum(r['n'] for r in fpr), sum(r['n_above'] for r in fpr)
    for lv, n, k in [(0.0, n0, k0)] + [(lv, int(np.isclose(h, lv).sum()), int(y[np.isclose(h, lv)].sum()))
                                       for lv in sim.LEVELS]:
        ci = binomtest(k, n).proportion_ci(confidence_level=sim.CI_LEVEL, method='exact')
        curve.append(dict(level_pw=lv, n=n, n_detected=k, proportion=k / n, ci_low=ci.low, ci_high=ci.high,
                          condition='null' if lv == 0.0 else 'injected'))
    with open(paths['power_curve_per_subject.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(curve[0]))
        w.writeheader()
        w.writerows(curve)

    with open(paths['logistic_per_subject.json'], 'w') as fh:
        json.dump(logistic_fit(h, y), fh, indent=2)
    print('done:', ', '.join(OUT))


if __name__ == '__main__':
    main()
