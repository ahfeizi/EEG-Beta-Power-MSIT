"""Per-subject calibration of the simulation roughness parameter sigma_i (decided 2026-10-31).

    python stage4_calibrate_rough_sigma.py --extraction <outRoot>/stage4/stage4_extraction_fixedonly.csv --out <csv>

For each subject retained by D12, sigma_i is chosen so that the median noise_31_40Hz of 50 null signals
simulated with that subject's offset_fixed, exponent_fixed and run lengths (frozen generator, rough_sigma =
sigma_i) matches the subject's own real noise_31_40Hz. Each simulated signal goes through welch_runs ->
aperiodic_only -> noise_floor, exactly as the extraction-only script.
Search per subject: coarse grid 0, 0.05, ..., 0.50; then steps of 0.01 inside the coarse interval where the
simulated median crosses the real value; sigma_i minimises |simulated median - real|.
  floor: real value below the simulated median at sigma = 0 -> sigma_i = 0, flagged floor = 1.
  above 0.50: the coarse grid is extended in steps of 0.05 up to 1.00, flagged extended = 1; if still not
  bracketed, sigma_i is NaN, flagged ceiling = 1, and the simulation script refuses to run.
Common random numbers: subject i uses the same seed at every sigma. Aperiodic statistics only: no full
fit, no peak, nothing restricted to 13-30 Hz. Writes one row per subject (and a second CSV with every
point tested). Never overwrites.
"""
import argparse
import csv
import os
from concurrent.futures import ProcessPoolExecutor

import numpy as np

import stage4_core as core
import stage4_simulate_threshold as sim

SEED = 20261102
N_REPS = 50
COARSE = tuple(round(0.05 * i, 2) for i in range(11))
EXTENDED = tuple(round(0.05 * i, 2) for i in range(11, 21))
BAND = 'noise_31_40Hz'


def sim_median(i, pair, sigma):
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i,)))
    vals = []
    for _ in range(N_REPS):
        runs = core.simulate_runs(rng, pair['run_lengths'], pair['fs'], pair['offset'], pair['exponent'],
                                  rough_sigma=sigma)
        a = core.aperiodic_only(*core.welch_runs(runs, pair['fs']))
        assert a['ok'], f"{pair['subject']}: aperiodic-only fit failed"
        vals.append(core.noise_floor(a)[BAND])
    return float(np.median(vals))


def calibrate(args):
    i, pair, real = args
    pts = {}

    def ev(s):
        pts[s] = sim_median(i, pair, s)

    for s in COARSE:
        ev(s)
    res = dict(subject=pair['subject'], real_noise_31_40Hz=real, floor=0, extended=0, ceiling=0)
    if real < pts[0.0]:
        res.update(rough_sigma=0.0, floor=1)
    else:
        if real > pts[COARSE[-1]]:
            res['extended'] = 1
            for s in EXTENDED:
                ev(s)
                if pts[s] >= real:
                    break
        grid = sorted(pts)
        above = [s for s in grid if pts[s] >= real]
        if not above:
            res.update(rough_sigma=float('nan'), ceiling=1)
        else:
            hi = min(above)
            lo = max(s for s in grid if s < hi)
            for s in np.round(np.arange(lo + 0.01, hi - 0.005, 0.01), 2):
                ev(float(s))
            res['rough_sigma'] = min(pts, key=lambda s: abs(pts[s] - real))
    best = res['rough_sigma']
    res.update(sim_median_at_sigma=pts.get(best, float('nan')), n_points=len(pts))
    return res, [dict(subject=pair['subject'], sigma=s, sim_median=pts[s], real_noise_31_40Hz=real)
                 for s in sorted(pts)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--extraction', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    args = ap.parse_args()
    out_pts = os.path.splitext(args.out)[0] + '_points.csv'
    for p in (args.out, out_pts):
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    pairs = sim.read_pairs(args.extraction, rough_sigma_csv=None)
    with open(args.extraction, newline='') as fh:
        real = {r['subject']: float(r[BAND]) for r in csv.DictReader(fh)}
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        out = list(ex.map(calibrate, [(i, p, real[p['subject']]) for i, p in enumerate(pairs)]))
    rows = [r for r, _ in out]
    pts = [q for _, ps in out for q in ps]
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    for path, data in ((args.out, rows), (out_pts, pts)):
        with open(path, 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(data[0]))
            w.writeheader()
            w.writerows(data)
    s = np.array([r['rough_sigma'] for r in rows], dtype=float)
    print(f'{len(rows)} subjects; floor {sum(r["floor"] for r in rows)}, extended {sum(r["extended"] for r in rows)}, '
          f'ceiling {sum(r["ceiling"] for r in rows)}; sigma median {np.nanmedian(s):.2f} '
          f'range {np.nanmin(s):.2f}-{np.nanmax(s):.2f}')


if __name__ == '__main__':
    main()
