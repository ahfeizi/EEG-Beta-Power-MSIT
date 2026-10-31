"""Half-length vs full-length per-subject p95 (documentation of the split-half threshold redesign, 2026-10-31).

    python stage4_compare_half_full_thresholds.py <outRoot>/stage4

Reads sim_rough/thresholds_per_subject.json, sim_rough/thresholds_per_subject_half.json and
rough_sigma_per_subject.csv; prints one row per (subject, half size) cell and summary statistics.
Simulated nulls only; nothing from real 13-30 Hz data is read. Writes nothing.
"""
import csv
import json
import sys

import numpy as np
from scipy.stats import spearmanr

R = sys.argv[1]
full = json.load(open(f'{R}/sim_rough/thresholds_per_subject.json'))['thresholds']
hj = json.load(open(f'{R}/sim_rough/thresholds_per_subject_half.json'))
half = hj['thresholds']
sig = {r['subject']: float(r['rough_sigma']) for r in csv.DictReader(open(f'{R}/rough_sigma_per_subject.csv'))}
print({k: v for k, v in hj.items() if k != 'thresholds'})
print(f"{'subject':8} {'sigma':>6} {'full_p95':>9} {'n_half':>8} {'half_p95':>9} {'ratio':>6}")
ratios, diffs, rows = [], [], []
for s in sorted(full):
    f = full[s]['p95']
    for n, v in sorted(half[s].items(), key=lambda x: int(x[0])):
        h = v['p95']
        ratios.append(h / f)
        diffs.append(h - f)
        rows.append((s, sig[s], f, int(n), h))
        print(f"{s:8} {sig[s]:6.2f} {f:9.4f} {n:>8} {h:9.4f} {h / f:6.3f}")
ratios, diffs = np.array(ratios), np.array(diffs)
print(f'cells {ratios.size}; ratio half/full: min {ratios.min():.3f} median {np.median(ratios):.3f} '
      f'mean {ratios.mean():.3f} max {ratios.max():.3f}; n ratio > 1: {(ratios > 1).sum()}')
print(f'diff half-full: min {diffs.min():.4f} median {np.median(diffs):.4f} max {diffs.max():.4f}')
fv = np.array([r[2] for r in rows]); hv = np.array([r[4] for r in rows])
print(f'over cells: full p95 min/median/max {fv.min():.4f}/{np.median(fv):.4f}/{fv.max():.4f}; '
      f'half p95 min/median/max {hv.min():.4f}/{np.median(hv):.4f}/{hv.max():.4f}')
rho = spearmanr([r[1] for r in rows], ratios)              # average ranks for ties (5 subjects at sigma = 0)
print(f'Spearman rho(sigma, ratio) over cells: {rho.statistic:.3f}')
