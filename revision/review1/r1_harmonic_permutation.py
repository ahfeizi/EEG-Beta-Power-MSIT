"""Review round 1: permutation test of the alpha-harmonic coincidence (decision log §11q; post-hoc).

    python r1_harmonic_permutation.py --mode synthetic --out-dir <outRoot>/review1/harmonic_perm
    python r1_harmonic_permutation.py --mode real --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/harmonic_perm

Statistic: the number of peaks with |CF - 2 x IAF| <= tol (frozen tol = 2 Hz, stage4_core.HARMONIC_TOL). Null: the
IAFs are permuted across participants (each participant's peak set moves as a unit), B = 10,000, seed 20261118;
one-sided p = (1 + #{null >= observed}) / (B + 1). Real mode: primary (24 primary peaks, tol 2) with a gate that the
count is 19 and matches primary_alpha_harmonic peak by peak; secondary all-in-range Gaussians (poor-fit participant and
participants without an IAF excluded); window sensitivity tol 1 and 3. Synthetic mode: the two checks of §11q.
Never overwrites.
"""
import argparse
import json
import os

import numpy as np
from scipy.stats import binom

import r1_common as rc
from r1_common import core

SEED = 20261118
B = 10000
TOL = core.HARMONIC_TOL                       # 2.0 Hz, frozen


def perm_test(cf_sets, iaf, tol, b, rng):
    """cf_sets: list (one per participant) of arrays of CFs; iaf: array of IAFs (same order).
    Returns observed count, null counts (b,), one-sided p."""
    n = len(cf_sets)
    owner = np.concatenate([np.full(len(s), i) for i, s in enumerate(cf_sets)])
    cf = np.concatenate(cf_sets)
    obs = int(np.sum(np.abs(cf - 2.0 * iaf[owner]) <= tol))
    perms = np.array([rng.permutation(n) for _ in range(b)])          # (b, n): participant i gets iaf[perm[i]]
    null = np.sum(np.abs(cf[None, :] - 2.0 * iaf[perms][:, owner]) <= tol, axis=1)
    p = (1 + int(np.sum(null >= obs))) / (b + 1)
    return obs, null, p


def summary(obs, null, p):
    return dict(observed=obs, null_mean=float(null.mean()), null_sd=float(null.std(ddof=1)),
                null_q025=float(np.percentile(null, 2.5)), null_q975=float(np.percentile(null, 97.5)),
                ratio_obs_to_expected=float(obs / null.mean()) if null.mean() > 0 else float('nan'), p_one_sided=p)


def synthetic(out_dir):
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(99,)))
    n = 24
    # (i) harmonic: CF = 2 x IAF + small noise
    iaf = rng.uniform(8.5, 12.0, n)
    cf_h = [np.array([2 * a + rng.normal(0, 0.5)]) for a in iaf]
    obs, null, p = perm_test(cf_h, iaf, TOL, B, rng)
    t1 = dict(case='harmonic', **summary(obs, null, p))
    pass1 = obs >= 22 and p < 0.001
    # (ii) independent: 2000 datasets, B = 999; CF and IAF drawn independently
    rej, nsets, a = 0, 2000, 0.05
    for _ in range(nsets):
        iaf_i = rng.uniform(8.5, 12.0, n)
        cf_i = [np.array([v]) for v in rng.uniform(13.0, 30.0, n)]
        _, _, pi = perm_test(cf_i, iaf_i, TOL, 999, rng)
        rej += pi <= a
    upper = binom.ppf(0.975, nsets, a) / nsets
    t2 = dict(case='independent', datasets=nsets, B=999, rejection_rate=rej / nsets, upper_limit=float(upper))
    pass2 = rej / nsets <= upper
    res = dict(rule='decision log §11q, verification', check_i=t1, check_i_pass=bool(pass1),
               check_ii=t2, check_ii_pass=bool(pass2), all_pass=bool(pass1 and pass2))
    path = os.path.join(out_dir, 'r1_harmonic_perm_synthetic.json')
    rc.refuse_existing([path])
    with open(path, 'w') as fh:
        json.dump(res, fh, indent=2)
    print(json.dumps(res, indent=1))
    if not res['all_pass']:
        raise SystemExit('synthetic verification failed')


def real(stage4, out_dir):
    pp = os.path.join(stage4, 'peak_detection', 'peaks_primary.csv')
    pa = os.path.join(stage4, 'peak_detection', 'peaks_all_in_range.csv')
    outs = {k: os.path.join(out_dir, k) for k in ('r1_harmonic_perm_raw.json', 'r1_harmonic_perm_null.csv')}
    rc.refuse_existing(outs.values())
    P = rc.read_csv(pp)
    isnum = lambda v: v not in ('', 'nan', 'NaN')
    pk = [r for r in P if r['class_p95'] == 'peak']
    assert len(pk) == 24 and all(isnum(r['iaf']) for r in pk)
    cf = [np.array([float(r['primary_cf'])]) for r in pk]
    iaf = np.array([float(r['iaf']) for r in pk])
    flags = np.array([int(r['primary_alpha_harmonic']) for r in pk])
    mine = (np.abs(np.concatenate(cf) - 2 * iaf) <= TOL).astype(int)
    assert int(mine.sum()) == 19 and np.array_equal(mine, flags), 'gate: count or flags differ from §9'

    rng = np.random.default_rng(SEED)
    out, nulls = {}, {}
    o, nl, p = perm_test(cf, iaf, TOL, B, rng)
    out['primary_tol2'] = dict(n_peaks=24, n_participants=24, **summary(o, nl, p))
    nulls['primary_tol2'] = nl
    for tol in (1.0, 3.0):
        o, nl, p = perm_test(cf, iaf, tol, B, rng)
        out[f'primary_tol{tol:g}'] = dict(n_peaks=24, n_participants=24, **summary(o, nl, p))
        nulls[f'primary_tol{tol:g}'] = nl

    cls = {r['subject']: r['class_p95'] for r in P}
    iafd = {r['subject']: float(r['iaf']) for r in P if isnum(r['iaf'])}
    A = rc.read_csv(pa)
    keep = [r for r in A if cls[r['subject']] != 'poor_fit' and r['subject'] in iafd]
    subs = sorted({r['subject'] for r in keep})
    sets = [np.array([float(r['cf']) for r in keep if r['subject'] == s]) for s in subs]
    o, nl, p = perm_test(sets, np.array([iafd[s] for s in subs]), TOL, B, rng)
    out['all_in_range_tol2'] = dict(n_peaks=len(keep), n_participants=len(subs),
                                    n_excluded_rows=len(A) - len(keep),
                                    n_below_threshold=sum(r['pw_ge_p95'] == '0' for r in keep), **summary(o, nl, p))
    nulls['all_in_range_tol2'] = nl

    rows = [dict(permutation=i + 1, **{k: int(v[i]) for k, v in nulls.items()}) for i in range(B)]
    rc.write_csv(outs['r1_harmonic_perm_null.csv'], rows)
    res = dict(rule='decision log §11q (post-hoc)', B=B, seed=SEED, results=out,
               provenance=rc.provenance(__file__, dict(peaks_primary=pp, peaks_all_in_range=pa)))
    with open(outs['r1_harmonic_perm_raw.json'], 'w') as fh:
        json.dump(res, fh, indent=2)
    print(json.dumps(out, indent=1))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--mode', required=True, choices=('synthetic', 'real'))
    ap.add_argument('--stage4')
    ap.add_argument('--out-dir', required=True)
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    if a.mode == 'synthetic':
        synthetic(a.out_dir)
    else:
        assert a.stage4, '--stage4 required in real mode'
        real(a.stage4, a.out_dir)


if __name__ == '__main__':
    main()
