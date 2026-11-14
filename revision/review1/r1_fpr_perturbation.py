"""Review round 1, Item 2: FPR robustness of the per-subject p95 threshold (decision log §11b).

    python r1_fpr_perturbation.py --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/fpr [--test-reps N]

For each of the 39 rest subjects, at its own point estimate theta = (offset, exponent, sigma) and run lengths:
  A  1000 nulls -> welch_runs -> aperiodic_only -> noise_floor: the sampling spread of (offset^, exponent^,
     noise_31_40^). sigma^ = the subject's own sigma -> median noise_31_40Hz curve (§7a points file), inverted.
     Bootstrap draw b: theta_b = theta + (theta^_b - mean theta^), sigma truncated at 0.
  B  one null at each theta_b (1000): FPR_joint against the subject's ORIGINAL p95.   (primary, R1/R2)
  C  each parameter alone at its bootstrap 2.5th / 97.5th percentile, 500 nulls each.  (driver)
  D  1000 nulls at theta with a new seed: the independent at-point FPR; all beta peaks stored (Item 3).
Decision rule (Bradley 1978, liberal): R1 pooled FPR_joint in [0.025, 0.075]; R2 per-subject CP 95 % CI wholly
above 0.075 = liberal failure, wholly below 0.025 = conservative failure. Simulated data only. Never overwrites;
resumable through parts/.
"""
import argparse
import json
import os
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

import r1_common as rc
from r1_common import core, sim

SEED = 20261115
N_A, N_B, N_C, N_D = 1000, 1000, 500, 1000
BRADLEY = (0.025, 0.075)
PARAMS = ('offset', 'exponent', 'rough_sigma')
C_SETTINGS = [(p, q) for p in PARAMS for q in ('lo', 'hi')]      # setting 1..6
STEP = dict(A=0, B=1, C=2, D=3)
ROW_FIELDS = ['subject', 'step', 'setting', 'rep', 'offset', 'exponent', 'rough_sigma', 'fit_failed', 'r2',
              'n_beta_peaks', 'max_beta_pw', 'beta_peaks']
A_FIELDS = ['subject', 'rep', 'ap_ok', 'offset_hat', 'exponent_hat', 'noise_31_40_hat']


def rng_for(i, step, setting):
    return np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i, STEP[step], setting)))


def one_null(rng, pair, offset, exponent, sigma):
    runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], offset, exponent, rough_sigma=sigma)
    freqs, psd = core.welch_runs(runs, pair['fs'])
    return core.run_pipeline(freqs, psd, simulated=True)


def cell_A(i, pair, n):
    rng, rows = rng_for(i, 'A', 0), []
    for rep in range(n):
        runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], pair['offset'], pair['exponent'],
                                  rough_sigma=pair['rough_sigma'])
        freqs, psd = core.welch_runs(runs, pair['fs'])
        ap = core.aperiodic_only(freqs, psd)
        nz = core.noise_floor(ap)['noise_31_40Hz'] if ap['ok'] else np.nan
        rows.append(dict(subject=pair['subject'], rep=rep, ap_ok=int(ap['ok']), offset_hat=ap['params'][0],
                         exponent_hat=ap['params'][1], noise_31_40_hat=nz))
    return rows


def cell_sim(i, step, setting, pair, thetas):
    """thetas: list of (offset, exponent, sigma), one null each, drawn from one random stream."""
    rng, rows = rng_for(i, step, setting), []
    for rep, (o, e, s) in enumerate(thetas):
        res = one_null(rng, pair, o, e, s)
        rows.append(dict(subject=pair['subject'], step=step, setting=setting, rep=rep, offset=o, exponent=e,
                         rough_sigma=s, fit_failed=int(res['fit_failed']), r2=res['r2'],
                         n_beta_peaks=len(core.beta_peaks(res['peaks'])),
                         max_beta_pw=core.max_beta_pw(res['peaks']), beta_peaks=rc.peaks_to_str(res['peaks'])))
    return rows


def sigma_inverse(points, subject):
    """sigma as a function of the simulated median noise_31_40Hz, from the §7a calibration points of this
    subject: sorted by sigma, made monotone (running max), linearly interpolated; below the sigma = 0 point
    -> 0 (§7a floor convention); above the last point -> linear extrapolation from the last two points."""
    pts = sorted((float(r['sigma']), float(r['sim_median'])) for r in points if r['subject'] == subject)
    sg = np.array([p[0] for p in pts])
    md = np.maximum.accumulate(np.array([p[1] for p in pts]))
    n_nonmono = int(np.sum(np.diff([p[1] for p in pts]) < 0))
    # keep the first sigma of each run of equal (flattened) medians, so np.interp gets increasing x
    keep = np.concatenate([[True], np.diff(md) > 0])
    sg, md = sg[keep], md[keep]

    def inv(y):
        y = np.asarray(y, dtype=float)
        out = np.interp(y, md, sg)
        hi = y > md[-1]
        if hi.any():
            slope = (sg[-1] - sg[-2]) / (md[-1] - md[-2])
            out[hi] = sg[-1] + slope * (y[hi] - md[-1])
        out[y <= md[0]] = 0.0 if sg[0] == 0 else sg[0]
        return out, hi
    return inv, n_nonmono


def bootstrap(pair, a_rows, inv):
    ok = [r for r in a_rows if r['ap_ok'] in (1, '1')]
    o = np.array([float(r['offset_hat']) for r in ok])
    e = np.array([float(r['exponent_hat']) for r in ok])
    nz = np.array([float(r['noise_31_40_hat']) for r in ok])
    s, extrap = inv(nz)
    draws = np.column_stack([pair['offset'] + (o - o.mean()), pair['exponent'] + (e - e.mean()),
                             np.maximum(0.0, pair['rough_sigma'] + (s - s.mean()))])
    q = {name: (float(np.percentile(draws[:, j], 2.5)), float(np.percentile(draws[:, j], 97.5)))
         for j, name in enumerate(PARAMS)}
    info = dict(subject=pair['subject'], n_A=len(a_rows), n_A_failed=len(a_rows) - len(ok),
                n_sigma_extrapolated=int(extrap.sum()),
                offset_point=pair['offset'], exponent_point=pair['exponent'], sigma_point=pair['rough_sigma'],
                **{f'{p}_sd': float(draws[:, j].std(ddof=1)) for j, p in enumerate(PARAMS)},
                **{f'{p}_q025': q[p][0] for p in PARAMS}, **{f'{p}_q975': q[p][1] for p in PARAMS},
                offset_hat_mean=float(o.mean()), exponent_hat_mean=float(e.mean()),
                sigma_hat_mean=float(s.mean()), noise_hat_median=float(np.median(nz)))
    return draws, q, info


def fpr(rows, thr):
    k = sum(float(r['max_beta_pw']) >= thr for r in rows)
    lo, hi = rc.cp_ci(k, len(rows))
    return k, len(rows), k / len(rows), lo, hi


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--stage4', required=True, help='<outRoot>/stage4')
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    ap.add_argument('--test-reps', type=int, default=None, help='TEST only: reps per step, prefix TEST_')
    ap.add_argument('--test-subjects', type=int, default=None, help='TEST only: first N subjects')
    args = ap.parse_args()
    test = args.test_reps is not None or args.test_subjects is not None
    nA, nB, nC, nD = (N_A, N_B, N_C, N_D) if args.test_reps is None else (args.test_reps,) * 4
    pre = 'TEST_' if test else ''
    inputs = dict(extraction=os.path.join(args.stage4, 'stage4_extraction_fixedonly.csv'),
                  rough_sigma=os.path.join(args.stage4, 'rough_sigma_per_subject.csv'),
                  rough_points=os.path.join(args.stage4, 'rough_sigma_per_subject_points.csv'),
                  thresholds=os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject.json'),
                  peaks_primary=os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv'))
    outs = {k: os.path.join(args.out_dir, pre + k) for k in
            ('r1_fpr_bootstrap_params.csv', 'r1_fpr_sims.csv', 'r1_fpr_per_subject.csv', 'r1_fpr_driver.csv',
             'r1_fpr_summary.json')}
    rc.refuse_existing(outs.values())
    parts = os.path.join(args.out_dir, f'{pre}parts')
    os.makedirs(parts, exist_ok=True)

    pairs = sim.read_pairs(inputs['extraction'], inputs['rough_sigma'])
    thr = rc.read_thresholds(inputs['thresholds'])
    cls = rc.read_classes(inputs['peaks_primary'])
    assert set(thr) == {p['subject'] for p in pairs} == set(cls), 'subject sets differ'
    if args.test_subjects:
        pairs = pairs[:args.test_subjects]
    points = rc.read_csv(inputs['rough_points'])
    print(f'{len(pairs)} subjects; reps A/B/C/D = {nA}/{nB}/{nC}/{nD}', flush=True)

    def part(key):
        return os.path.join(parts, '_'.join(str(k) for k in key) + '.csv')

    def run(jobs):
        todo = {k: v for k, v in jobs.items() if not os.path.exists(part(k))}
        print(f'{len(jobs) - len(todo)} of {len(jobs)} cells already done', flush=True)
        with ProcessPoolExecutor(max_workers=args.workers) as ex:
            fut = {ex.submit(*v): k for k, v in todo.items()}
            for n, f in enumerate(as_completed(fut), 1):
                k = fut[f]
                rc.write_csv(part(k), f.result(), A_FIELDS if k[0] == 'A' else ROW_FIELDS)
                print(f'cell {k} done ({n}/{len(todo)})', flush=True)

    # phase 1: A (estimator spread) and D (fresh-seed control), independent of each other
    jobs = {}
    for i, p in enumerate(pairs):
        jobs[('A', i)] = (cell_A, i, p, nA)
        jobs[('D', i, 0)] = (cell_sim, i, 'D', 0, p, [(p['offset'], p['exponent'], p['rough_sigma'])] * nD)
    run(jobs)

    # bootstrap draws from A, then phase 2: B (joint) and C (one at a time)
    boot, info_rows, nonmono = {}, [], {}
    for i, p in enumerate(pairs):
        inv, nonmono[p['subject']] = sigma_inverse(points, p['subject'])
        draws, q, info = bootstrap(p, rc.read_csv(part(('A', i))), inv)
        info['n_nonmonotone_points'] = nonmono[p['subject']]
        boot[i] = (draws, q)
        info_rows.append(info)
    jobs = {}
    for i, p in enumerate(pairs):
        draws, q = boot[i]
        # B: draws are cycled if fewer than nB aperiodic fits succeeded (counted in n_A_failed)
        th = [tuple(draws[r % len(draws)]) for r in range(nB)]
        jobs[('B', i, 0)] = (cell_sim, i, 'B', 0, p, th)
        for s, (name, side) in enumerate(C_SETTINGS, 1):
            t = dict(offset=p['offset'], exponent=p['exponent'], rough_sigma=p['rough_sigma'])
            t[name] = q[name][0 if side == 'lo' else 1]
            jobs[('C', i, s)] = (cell_sim, i, 'C', s, p, [(t['offset'], t['exponent'], t['rough_sigma'])] * nC)
    run(jobs)

    # assemble
    all_rows, per_subj = [], []
    pooled = {k: [0, 0] for k in ('B', 'D')}
    drv = {(name, side): [0, 0] for name, side in C_SETTINGS}
    for i, p in enumerate(pairs):
        s, t = p['subject'], thr[p['subject']]
        rB, rD = rc.read_csv(part(('B', i, 0))), rc.read_csv(part(('D', i, 0)))
        all_rows += rB + rD
        kB, nB_, fB, loB, hiB = fpr(rB, t)
        kD, nD_, fD, loD, hiD = fpr(rD, t)
        pooled['B'][0] += kB; pooled['B'][1] += nB_
        pooled['D'][0] += kD; pooled['D'][1] += nD_
        fail = 'liberal' if loB > BRADLEY[1] else 'conservative' if hiB < BRADLEY[0] else ''
        row = dict(subject=s, class_p95=cls[s], thr_p95=t, rough_sigma=p['rough_sigma'],
                   fpr_D_point=fD, fpr_D_ci_low=loD, fpr_D_ci_high=hiD,
                   fpr_B_joint=fB, fpr_B_ci_low=loB, fpr_B_ci_high=hiB, R2_failure=fail,
                   fit_failed_B=sum(int(r['fit_failed']) for r in rB))
        for st, (name, side) in enumerate(C_SETTINGS, 1):
            rC = rc.read_csv(part(('C', i, st)))
            all_rows += rC
            k, n, f, _, _ = fpr(rC, t)
            drv[(name, side)][0] += k; drv[(name, side)][1] += n
            row[f'fpr_C_{name}_{side}'] = f
            row[f'C_{name}_{side}_value'] = float(rC[0][name])
        per_subj.append(row)
    rc.write_csv(outs['r1_fpr_sims.csv'], all_rows, ROW_FIELDS)
    rc.write_csv(outs['r1_fpr_bootstrap_params.csv'], info_rows)
    rc.write_csv(outs['r1_fpr_per_subject.csv'], per_subj)

    drows = []
    for name in PARAMS:
        lo, hi = drv[(name, 'lo')], drv[(name, 'hi')]
        flo, fhi = lo[0] / lo[1], hi[0] / hi[1]
        drows.append(dict(parameter=name, pooled_fpr_at_q025=flo, pooled_fpr_at_q975=fhi,
                          fpr_range=abs(fhi - flo), n_each=lo[1]))
    rc.write_csv(outs['r1_fpr_driver.csv'], drows)
    driver = max(drows, key=lambda d: d['fpr_range'])['parameter']

    kB, nB_ = pooled['B']
    kD, nD_ = pooled['D']
    fB = kB / nB_
    r1 = BRADLEY[0] <= fB <= BRADLEY[1]
    fails = [r for r in per_subj if r['R2_failure']]
    summary = dict(
        rule='decision log §11b; Bradley (1978) liberal criterion [0.025, 0.075]',
        n_subjects=len(pairs), reps=dict(A=nA, B=nB, C=nC, D=nD), seed=SEED, test_run=test,
        pooled_fpr_joint=fB, pooled_fpr_joint_ci=rc.cp_ci(kB, nB_), n_joint=nB_,
        R1_pass=bool(r1),
        pooled_fpr_fresh_point=kD / nD_, pooled_fpr_fresh_point_ci=rc.cp_ci(kD, nD_), n_fresh=nD_,
        R2_liberal_failures=[(r['subject'], r['class_p95'], r['fpr_B_joint']) for r in fails
                             if r['R2_failure'] == 'liberal'],
        R2_conservative_failures=[(r['subject'], r['class_p95'], r['fpr_B_joint']) for r in fails
                                  if r['R2_failure'] == 'conservative'],
        driver=driver, driver_table=drows,
        sigma_points_nonmonotone=nonmono,
        provenance=rc.provenance(__file__, inputs))
    with open(outs['r1_fpr_summary.json'], 'w') as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps({k: summary[k] for k in ('pooled_fpr_joint', 'R1_pass', 'pooled_fpr_fresh_point',
                                              'R2_liberal_failures', 'R2_conservative_failures', 'driver')},
                     indent=1))


if __name__ == '__main__':
    main()
