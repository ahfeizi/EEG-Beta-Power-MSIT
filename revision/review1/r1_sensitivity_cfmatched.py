"""Review round 1, Item 3B: CF-matched detection sensitivity for the 14 no_peak subjects (decision log §11c).

    python r1_sensitivity_cfmatched.py --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/sens_cf \
        [--chance <outRoot>/review1/fpr/r1_fpr_sims.csv] [--test-reps N]

Each no_peak subject (p95 class of §9) at its own point (offset, exponent, sigma_i, run lengths); a Gaussian of
CF in {14, 18, 22, 26, 29} Hz x BW in {2, 4, 6, 8} Hz x PW in {0.05, ..., 0.50} is injected with the frozen
generator, 200 repetitions per cell. Every beta-range peak of every fit is stored.
  hit (primary)   a qualifying beta peak (CF in [13, 30], BW in [1, 8]) with PW >= the subject's p95 and
                  |CF_detected - CF_injected| <= 2 Hz; sensitivity tolerances 1 and 3 Hz
  hit (any)       the pipeline's own rule: max beta PW >= p95 (comparable with 3A)
  MDE             per CF x BW, the smallest PW whose pooled primary detection is >= 0.80 ('not reached')
  chance          with --chance: the CF-matched false-hit rate in Item 2 step D's at-point nulls
Simulated data only. Never overwrites; resumable through parts/.
"""
import argparse
import json
import os
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

import r1_common as rc
from r1_common import core, sim

SEED = 20261116
N_REPS = 200
CFS = (14.0, 18.0, 22.0, 26.0, 29.0)
BWS = (2.0, 4.0, 6.0, 8.0)
LEVELS = sim.LEVELS                                   # 0.05 ... 0.50, as §7b
TOLS = (1.0, 2.0, 3.0)
PRIMARY_TOL = 2.0
MDE_TARGET = 0.80
FIELDS = ['subject', 'cf', 'bw', 'pw', 'rep', 'fit_failed', 'r2', 'n_beta_peaks', 'max_beta_pw', 'beta_peaks']


def cell(i, ci, bi, li, pair, n):
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i, ci, bi, li)))
    cf, bw, pw = CFS[ci], BWS[bi], LEVELS[li]
    rows = []
    for rep in range(n):
        runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], pair['offset'], pair['exponent'],
                                  cf=cf, bw=bw, pw=pw, rough_sigma=pair['rough_sigma'])
        freqs, psd = core.welch_runs(runs, pair['fs'])
        res = core.run_pipeline(freqs, psd, simulated=True)
        rows.append(dict(subject=pair['subject'], cf=cf, bw=bw, pw=pw, rep=rep, fit_failed=int(res['fit_failed']),
                         r2=res['r2'], n_beta_peaks=len(core.beta_peaks(res['peaks'])),
                         max_beta_pw=core.max_beta_pw(res['peaks']), beta_peaks=rc.peaks_to_str(res['peaks'])))
    return rows


def matched(peaks_str, cf, thr, tol):
    p = rc.str_to_peaks(peaks_str)
    return bool(len(p)) and bool(np.any((p[:, 1] >= thr) & (np.abs(p[:, 0] - cf) <= tol)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--stage4', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--chance', default=None, help='Item 2 r1_fpr_sims.csv (step D rows give the chance level)')
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    ap.add_argument('--test-reps', type=int, default=None)
    ap.add_argument('--test-subjects', type=int, default=None)
    args = ap.parse_args()
    test = args.test_reps is not None or args.test_subjects is not None
    n = N_REPS if args.test_reps is None else args.test_reps
    pre = 'TEST_' if test else ''
    inputs = dict(extraction=os.path.join(args.stage4, 'stage4_extraction_fixedonly.csv'),
                  rough_sigma=os.path.join(args.stage4, 'rough_sigma_per_subject.csv'),
                  thresholds=os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject.json'),
                  peaks_primary=os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv'))
    if args.chance:
        inputs['chance'] = args.chance
    outs = {k: os.path.join(args.out_dir, pre + k) for k in
            ('r1_sens_cf_sims.csv', 'r1_sens_cf_curve.csv', 'r1_sens_cf_per_subject.csv', 'r1_sens_cf_mde.csv',
             'r1_sens_cf_chance.csv', 'r1_sens_cf_summary.json')}
    rc.refuse_existing(outs.values())
    parts = os.path.join(args.out_dir, f'{pre}parts')
    os.makedirs(parts, exist_ok=True)

    allpairs = sim.read_pairs(inputs['extraction'], inputs['rough_sigma'])
    thr = rc.read_thresholds(inputs['thresholds'])
    cls = rc.read_classes(inputs['peaks_primary'])
    idx = [i for i, p in enumerate(allpairs) if cls[p['subject']] == 'no_peak']
    assert len(idx) == 14, f'{len(idx)} no_peak subjects, 14 expected (§9)'
    if args.test_subjects:
        idx = idx[:args.test_subjects]
    noise = {r['subject']: float(r['noise_31_40Hz']) for r in rc.read_csv(inputs['extraction'])}
    print(f'{len(idx)} no_peak subjects, {n} reps x {len(CFS) * len(BWS) * len(LEVELS)} cells each', flush=True)

    keys = [(i, ci, bi, li) for i in idx for ci in range(len(CFS)) for bi in range(len(BWS))
            for li in range(len(LEVELS))]
    part = {k: os.path.join(parts, 'p{:02d}_cf{}_bw{}_pw{:02d}.csv'.format(*k)) for k in keys}
    todo = [k for k in keys if not os.path.exists(part[k])]
    print(f'{len(keys) - len(todo)} of {len(keys)} cells already done', flush=True)
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        fut = {ex.submit(cell, *k, allpairs[k[0]], n): k for k in todo}
        for m, f in enumerate(as_completed(fut), 1):
            rc.write_csv(part[fut[f]], f.result(), FIELDS)
            if m % 20 == 0 or m == len(todo):
                print(f'{m}/{len(todo)} cells done', flush=True)

    rows = [r for k in keys for r in rc.read_csv(part[k])]
    assert len(rows) == len(keys) * n
    rc.write_csv(outs['r1_sens_cf_sims.csv'], rows, FIELDS)

    # classify every simulation once
    for r in rows:
        t, cf = thr[r['subject']], float(r['cf'])
        r['_any'] = float(r['max_beta_pw']) >= t
        for tol in TOLS:
            r[f'_m{tol:g}'] = matched(r['beta_peaks'], cf, t, tol)

    curve, persub = [], []
    for cf in CFS:
        for bw in BWS:
            for pw in LEVELS:
                sel = [r for r in rows if float(r['cf']) == cf and float(r['bw']) == bw
                       and np.isclose(float(r['pw']), pw)]
                d = dict(cf=cf, bw=bw, pw=pw, pct_above_aperiodic=100 * (10 ** pw - 1), n=len(sel),
                         n_fit_failed=sum(int(r['fit_failed']) for r in sel))
                for tag in ['any'] + [f'm{t:g}' for t in TOLS]:
                    k = sum(r[f'_{tag}'] for r in sel)
                    lo, hi = rc.cp_ci(k, len(sel))
                    d.update({f'p_{tag}': k / len(sel), f'p_{tag}_ci_low': lo, f'p_{tag}_ci_high': hi})
                curve.append(d)
                for s in sorted({r['subject'] for r in sel}):
                    ss = [r for r in sel if r['subject'] == s]
                    persub.append(dict(subject=s, cf=cf, bw=bw, pw=pw, snr=pw / noise[s], n=len(ss),
                                       p_m2=sum(r['_m2'] for r in ss) / len(ss),
                                       p_any=sum(r['_any'] for r in ss) / len(ss)))
    rc.write_csv(outs['r1_sens_cf_curve.csv'], curve)
    rc.write_csv(outs['r1_sens_cf_per_subject.csv'], persub)

    mde = []
    for cf in CFS:
        for bw in BWS:
            c = [d for d in curve if d['cf'] == cf and d['bw'] == bw]
            hit = [d['pw'] for d in c if d['p_m2'] >= MDE_TARGET]
            row = dict(cf=cf, bw=bw, mde_pw=min(hit) if hit else 'not reached')
            row['mde_pct_above_aperiodic'] = 100 * (10 ** row['mde_pw'] - 1) if hit else 'not reached'
            if hit:
                snrs = [pw / noise[s] for s in {r['subject'] for r in rows} for pw in [row['mde_pw']]]
                row['mde_snr_median_over_subjects'] = float(np.median(snrs))
            else:
                row['mde_snr_median_over_subjects'] = 'not reached'
            row['p_m2_at_max_pw'] = c[-1]['p_m2']
            mde.append(row)
    rc.write_csv(outs['r1_sens_cf_mde.csv'], mde)

    chance = []
    if args.chance:
        D = [r for r in rc.read_csv(args.chance) if r['step'] == 'D' and r['subject'] in {allpairs[i]['subject']
                                                                                         for i in idx}]
        for cf in CFS:
            d = dict(cf=cf, n=len(D))
            for tol in TOLS:
                k = sum(matched(r['beta_peaks'], cf, thr[r['subject']], tol) for r in D)
                lo, hi = rc.cp_ci(k, len(D))
                d.update({f'p_m{tol:g}': k / len(D), f'p_m{tol:g}_ci_low': lo, f'p_m{tol:g}_ci_high': hi})
            chance.append(d)
        rc.write_csv(outs['r1_sens_cf_chance.csv'], chance)

    with open(outs['r1_sens_cf_summary.json'], 'w') as fh:
        json.dump(dict(rule='decision log §11c (3B)', subjects=[allpairs[i]['subject'] for i in idx],
                       reps=n, cfs=CFS, bws=BWS, levels=LEVELS, tolerances=TOLS, primary_tolerance=PRIMARY_TOL,
                       mde_target=MDE_TARGET, seed=SEED, test_run=test, n_sims=len(rows),
                       n_fit_failed=sum(int(r['fit_failed']) for r in rows), mde=mde, chance=chance,
                       provenance=rc.provenance(__file__, inputs)), fh, indent=2)
    for r in mde:
        print(r)


if __name__ == '__main__':
    main()
