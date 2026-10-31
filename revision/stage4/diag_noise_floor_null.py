"""Diagnostic (not part of the frozen pipeline; decided 2026-10-31): residual roughness of simulated null
signals vs real data.

    python diag_noise_floor_null.py --extraction <outRoot>/stage4/stage4_extraction_fixedonly.csv --out <csv> [--reps 10]

For every retained subject, simulates `reps` null signals (no peak) with that subject's offset_fixed,
exponent_fixed and run lengths, using the frozen stage4_core generator and estimator, and computes the
same two noise floors as the extraction-only script (aperiodic_only + noise_floor: SD of the fixed
aperiodic-only residual in 2-12 and 31-40 Hz). No full fit, no peak, nothing restricted to 13-30 Hz.
Writes one row per simulated signal and prints real vs simulated summaries. Never overwrites the output.
"""
import argparse
import csv
import os

import numpy as np

import stage4_core as core
import stage4_simulate_threshold as sim

SEED = 20261031                                           # separate from the calibration seed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--extraction', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--reps', type=int, default=10)
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')
    pairs = sim.read_pairs(args.extraction)
    with open(args.extraction, newline='') as fh:
        real = {r['subject']: r for r in csv.DictReader(fh)}
    rows = []
    for i, p in enumerate(pairs):
        rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i,)))
        for rep in range(args.reps):
            freqs, psd = core.welch_runs(core.simulate_runs(rng, p['run_lengths'], p['fs'], p['offset'],
                                                            p['exponent']), p['fs'])
            a = core.aperiodic_only(freqs, psd)
            assert a['ok'], f"{p['subject']} rep {rep}: aperiodic-only fit failed"
            rows.append(dict(subject=p['subject'], rep=rep, **core.noise_floor(a)))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    print(f'{len(pairs)} subjects x {args.reps} null simulations, seed {SEED}')
    for band in core.NOISE_BANDS:
        s = np.array([r[band] for r in rows])
        rv = np.array([float(real[p['subject']][band]) for p in pairs])
        per = {p['subject']: np.array([r[band] for r in rows if r['subject'] == p['subject']]) for p in pairs}
        above = sum(float(real[k][band]) > v.max() for k, v in per.items())
        ratio = np.array([float(real[k][band]) / v.mean() for k, v in per.items()])
        print(f'{band}: real mean {rv.mean():.4f} range {rv.min():.4f}-{rv.max():.4f} | '
              f'sim mean {s.mean():.4f} range {s.min():.4f}-{s.max():.4f} | '
              f'real > max of own {args.reps} sims: {above}/{len(pairs)} | '
              f'real/sim-mean ratio median {np.median(ratio):.2f} range {ratio.min():.2f}-{ratio.max():.2f}')


if __name__ == '__main__':
    main()
