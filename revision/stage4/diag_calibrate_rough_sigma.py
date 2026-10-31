"""Calibration of the simulation roughness parameter ROUGH_SIGMA (decided 2026-10-31).

    python diag_calibrate_rough_sigma.py --extraction <outRoot>/stage4/stage4_extraction_fixedonly.csv --out <csv>

Target: the median of the real noise_31_40Hz column (pooled over the retained subjects). For each
sigma, every retained subject's (offset_fixed, exponent_fixed, run lengths) gives 50 null signals from the
frozen generator with rough_sigma = sigma; each is passed through welch_runs -> aperiodic_only ->
noise_floor, exactly as the extraction-only script, and the pooled median of noise_31_40Hz is compared
with the target. Coarse grid 0, 0.05, ..., 0.50, then steps of 0.01 inside the coarse interval where the
simulated median crosses the target. The chosen sigma minimises |simulated median - target|.
Common random numbers: the seed of subject i is the same for every sigma. Aperiodic statistics only: no
full fit, no peak, nothing restricted to 13-30 Hz. Writes one row per sigma tested. Never overwrites.
"""
import argparse
import csv
import os
from concurrent.futures import ProcessPoolExecutor

import numpy as np

import stage4_core as core
import stage4_simulate_threshold as sim

SEED = 20261101
N_REPS = 50
COARSE = tuple(round(0.05 * i, 2) for i in range(11))
BAND = 'noise_31_40Hz'


def run_pair(args):
    i, pair, sigma = args
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i,)))
    out = []
    for _ in range(N_REPS):
        runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], pair['offset'], pair['exponent'],
                                  rough_sigma=sigma)
        a = core.aperiodic_only(*core.welch_runs(runs, pair['fs']))
        assert a['ok'], f"{pair['subject']}: aperiodic-only fit failed"
        out.append(core.noise_floor(a)[BAND])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--extraction', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')
    pairs = sim.read_pairs(args.extraction)
    with open(args.extraction, newline='') as fh:
        target = float(np.median([float(r[BAND]) for r in csv.DictReader(fh) if r['excluded_D12'] == '0']))
    print(f'{len(pairs)} pairs x {N_REPS} reps per sigma; target median {BAND} = {target:.4f}', flush=True)

    results = {}
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        def evaluate(sigma):
            vals = np.concatenate([v for v in ex.map(run_pair, [(i, p, sigma) for i, p in enumerate(pairs)])])
            results[sigma] = dict(sigma=sigma, n=int(vals.size), sim_median=float(np.median(vals)),
                                  sim_mean=float(vals.mean()), sim_p05=float(np.percentile(vals, 5)),
                                  sim_p95=float(np.percentile(vals, 95)))
            results[sigma]['abs_diff'] = abs(results[sigma]['sim_median'] - target)
            print(f"sigma {sigma:.2f}  sim median {results[sigma]['sim_median']:.4f}", flush=True)

        for s in COARSE:
            evaluate(s)
        below = [s for s in COARSE if results[s]['sim_median'] < target]
        above = [s for s in COARSE if results[s]['sim_median'] >= target]
        if not below or not above:
            raise SystemExit('target not bracketed by the coarse grid: stop and report')
        lo, hi = max(below), min(s for s in above if s > max(below))
        for s in np.round(np.arange(lo + 0.01, hi - 0.005, 0.01), 2):
            evaluate(float(s))

    rows = sorted(results.values(), key=lambda r: r['sigma'])
    best = min(rows, key=lambda r: r['abs_diff'])
    for r in rows:
        r.update(target_median=target, chosen=int(r is best))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=['sigma', 'n', 'sim_median', 'sim_mean', 'sim_p05', 'sim_p95',
                                           'target_median', 'abs_diff', 'chosen'])
        w.writeheader()
        w.writerows(rows)
    print(f"chosen sigma {best['sigma']:.2f}: sim median {best['sim_median']:.4f} vs target {target:.4f}")


if __name__ == '__main__':
    main()
