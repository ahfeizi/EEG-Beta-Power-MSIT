"""Per-subject split-half thresholds (§3.8; decided 2026-10-31).

    python stage4_simulate_half_threshold.py --extraction <outRoot>/stage4/stage4_extraction_fixedonly.csv
        --rough-sigma <outRoot>/stage4/rough_sigma_per_subject.csv --out-dir <outRoot>/stage4/sim_rough

A split half of a subject (stage4_core.split_half_runs) is n separate 2 s epochs: ceil(n_kept / 2) for
half 1 and floor(n_kept / 2) for half 2, one non-overlapping Welch window each. For every retained subject
and every distinct half size, 1000 null signals (no peak) are simulated with that subject's offset_fixed,
exponent_fixed and its own sigma_i (unchanged: a property of the subject's spectrum, not of the length),
with run lengths = n_half x one epoch, and passed through the identical pipeline (welch_runs ->
run_pipeline(simulated=True)); the threshold is p90 / p95 / p99 (NumPy 'linear') of the null max-PW.
Outputs (out-dir; never overwritten): sim_null_half.csv and thresholds_per_subject_half.json
({subject: {n_epochs: {p90, p95, p99}}}). Each (subject, n_epochs) cell is seeded by
SeedSequence(SEED, spawn_key=(pair, n_epochs)) and saved to parts_half/, so a run can resume.
Simulated data only.
"""
import argparse
import csv
import hashlib
import json
import os
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

import stage4_core as core
import stage4_simulate_threshold as sim

SEED = 20261103
N_REPS = 1000
FIELDS = ['subject', 'pair', 'n_epochs', 'rep', 'rough_sigma', 'fit_failed', 'r2', 'n_beta_peaks', 'max_beta_pw']


def run_cell(i, n_ep, pair, n_reps):
    rng = np.random.default_rng(np.random.SeedSequence(SEED, spawn_key=(i, n_ep)))
    epoch = int(round(core.EPOCH_S * pair['fs']))
    rows = []
    for rep in range(n_reps):
        runs = core.simulate_runs(rng, [epoch] * n_ep, pair['fs'], pair['offset'], pair['exponent'],
                                  rough_sigma=pair['rough_sigma'])
        res = core.run_pipeline(*core.welch_runs(runs, pair['fs']), simulated=True)
        rows.append(dict(subject=pair['subject'], pair=i, n_epochs=n_ep, rep=rep, rough_sigma=pair['rough_sigma'],
                         fit_failed=int(res['fit_failed']), r2=res['r2'],
                         n_beta_peaks=len(core.beta_peaks(res['peaks'])), max_beta_pw=core.max_beta_pw(res['peaks'])))
    return rows


def write_rows(path, rows):
    tmp = path + '.tmp'
    with open(tmp, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--extraction', required=True)
    ap.add_argument('--rough-sigma', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in ('sim_null_half.csv', 'thresholds_per_subject_half.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    parts = os.path.join(args.out_dir, 'parts_half')
    os.makedirs(parts, exist_ok=True)
    pairs = sim.read_pairs(args.extraction, args.rough_sigma)
    epoch = {p['subject']: int(round(core.EPOCH_S * p['fs'])) for p in pairs}
    cells = []
    for i, p in enumerate(pairs):
        n_kept = sum(p['run_lengths']) // epoch[p['subject']]
        for n_ep in sorted({(n_kept + 1) // 2, n_kept // 2}):
            cells.append((i, n_ep))
    part = {c: os.path.join(parts, f'p{c[0]:02d}_n{c[1]:03d}.csv') for c in cells}
    todo = [c for c in cells if not os.path.exists(part[c])]
    print(f'{len(pairs)} subjects, {len(cells)} (subject, half size) cells, {len(todo)} to run', flush=True)
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        fut = {ex.submit(run_cell, i, n, pairs[i], N_REPS): (i, n) for i, n in todo}
        for k, f in enumerate(as_completed(fut), 1):
            write_rows(part[fut[f]], f.result())
            print(f'cell {fut[f]} done ({k}/{len(todo)})', flush=True)

    rows, thr = [], {}
    for i, n in cells:
        r = sim.read_csv(part[(i, n)])
        assert len(r) == N_REPS
        rows += r
        v = np.array([float(x['max_beta_pw']) for x in r])
        thr.setdefault(pairs[i]['subject'], {})[str(n)] = {f'p{q}': float(np.percentile(v, q, method='linear'))
                                                          for q in sim.PERCENTILES}
    write_rows(names['sim_null_half.csv'], rows)
    with open(args.rough_sigma, 'rb') as fh:
        sha = hashlib.sha256(fh.read()).hexdigest()
    ff = sum(int(x['fit_failed']) for x in rows)
    with open(names['thresholds_per_subject_half.json'], 'w') as fh:
        json.dump(dict(thresholds=thr, primary='p95', percentile_method='linear', n_reps=N_REPS, seed=SEED,
                       rough_sigma_file=args.rough_sigma, rough_sigma_sha256=sha, n_null=len(rows),
                       null_fit_failed=ff, fooof_version=core.FOOOF_VERSION, test_run=False), fh, indent=2)
    print(f'done; fit_failed {ff}/{len(rows)}')


if __name__ == '__main__':
    main()
