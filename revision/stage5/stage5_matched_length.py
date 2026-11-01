"""Stage 5: length-matched task thresholds, required by §10d rule 5 (which fired — see §10h).

    python stage5_matched_length.py \
        --task-extraction <outRoot>/stage5/stage5_extraction_task.csv \
        --rest-extraction <outRoot>/stage4/stage4_extraction_fixedonly.csv \
        --rough-sigma <outRoot>/stage5/rough_sigma_task_per_subject.csv \
        --out-dir <outRoot>/stage5/sim_task_matched

Why this exists. §10h measured task detection power to be up to 8.7 percentage points above rest's at
the same injected peak height, because the task yields ~1.68x more pseudo-epochs per subject (§10e), so a
raw rest-vs-task peak-prevalence comparison would partly reflect data quantity rather than physiology.
§10d rule 5, written before either power curve existed, therefore requires a length-matched secondary
analysis: each subject's task kept-epoch sequence truncated in time order, preserving its contiguous-run
structure, to that subject's rest n_kept, with thresholds recalibrated at those run lengths.

What it does.
  1. Builds the matched run lengths per subject: walk the task run_lengths_epochs in order, taking whole
     runs until the subject's rest n_kept is reached, cutting the last run to the remainder. Writes
     stage5_extraction_task_matched.csv - the task extraction table with run_lengths_epochs replaced and
     the matching bookkeeping appended, so the truncation is auditable rather than implicit.
  2. Simulates the NULL cell only, 1000 repetitions per subject, by calling the frozen
     stage4_simulate_threshold.run_cell(pair_idx, 0, pair, n_reps) verbatim - so the generator, the Welch
     estimator, the fooof fit and the peak extraction are the deposited implementation, unchanged.
     §10d rule 5 asks for thresholds, not a second power curve, so the ten injected levels are not
     re-run (§10h records that decision and its rejected alternative).
  3. Writes thresholds_per_subject_matched.json in the same shape as
     stage4_per_subject_thresholds.py's output, so stage5_peak_detection_task.py reads it unchanged.
Resumable: each subject's cell is saved to parts_matched/ as soon as it completes, exactly as the frozen
script does, and a rerun skips the cells already present.

truncate_runs() is also imported by stage5_peak_detection_task.py, so the thresholds and the
classification are guaranteed to use the same definition of the matched subset.

Known, accepted consequence of calling run_cell verbatim (as in §10d): its seed depends only on
(pair index, condition), so each subject's matched null shares its roughness draws with that subject's
full-length null. The run lengths differ, so the signals differ; the two nulls are paired rather than
independent, which for a full-vs-matched comparison is if anything favourable.

Simulated data only. No real 13-30 Hz quantity is read or written here. Never overwrites.
"""
import argparse
import csv
import json
import os
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed

import numpy as np

sys.dont_write_bytecode = True      # do not write __pycache__ into the frozen Stage-4 tree
STAGE4 = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'stage4')
sys.path.insert(0, STAGE4)
import stage4_core as core                    # noqa: E402  (frozen, unchanged)
import stage4_simulate_threshold as sim       # noqa: E402  (frozen, unchanged)

N_REPS = sim.N_REPS                           # 1000, from the frozen script
PERCENTILES = sim.PERCENTILES                 # (90, 95, 99)
NULL_COND = 0                                 # run_cell's null condition


def matched_lengths(run_len_epochs, target):
    """Truncate a run-length list in time order to `target` epochs, cutting the last run to the
    remainder. Returns (lengths, total). Whole runs are kept whole until the target is reached."""
    out, tot = [], 0
    for L in run_len_epochs:
        if tot >= target:
            break
        take = min(int(L), target - tot)
        if take > 0:
            out.append(take)
            tot += take
    return out, tot


def n_welch_windows(run_len_epochs):
    """Welch windows the frozen welch_runs places in these runs: a run of k 2 s epochs at 50 % overlap
    gives 2k - 1 windows. Used only to show that matching on epochs also matches the window count."""
    return int(sum(2 * int(k) - 1 for k in run_len_epochs))


def truncate_runs(runs, run_len_epochs, target, fs):
    """The matched subset of a subject's exported ROI runs: the same truncation as matched_lengths,
    applied to the time series. runs: list of (n_channels, n_samples). Returns (runs, lengths)."""
    epoch = int(round(core.EPOCH_S * fs))
    lens, tot = matched_lengths(run_len_epochs, target)
    out = []
    for r, L in zip(runs, lens):
        out.append(np.asarray(r)[:, :L * epoch])
    assert sum(lens) == tot
    return out, lens


def read_rows(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def build_matched_extraction(task_csv, rest_csv, out_csv):
    """Write the task extraction table with run_lengths_epochs truncated to each subject's rest n_kept."""
    task = read_rows(task_csv)
    rest = {r['subject']: r for r in read_rows(rest_csv)}
    problems, rows = [], []
    for r in task:
        sub = r['subject']
        if sub not in rest:
            problems.append(f'{sub}: no rest extraction row')
            continue
        if r['excluded_D12'] != '0' or rest[sub]['excluded_D12'] != '0':
            problems.append(f'{sub}: excluded by D12 in task or rest')
            continue
        full = [int(k) for k in r['run_lengths_epochs'].split(';')]
        target = int(rest[sub]['n_pseudoepochs_kept'])
        if sum(full) < target:
            problems.append(f'{sub}: task has {sum(full)} kept epochs, fewer than rest\'s {target}')
            continue
        lens, tot = matched_lengths(full, target)
        assert tot == target
        row = dict(r)
        row['run_lengths_epochs'] = ';'.join(str(k) for k in lens)
        row.update(n_epochs_target_rest=target, n_epochs_matched=tot,
                   n_epochs_task_full=sum(full), n_runs_task_full=len(full), n_runs_matched=len(lens),
                   n_windows_matched=n_welch_windows(lens),
                   n_windows_rest=n_welch_windows([int(k) for k in
                                                   rest[sub]['run_lengths_epochs'].split(';')]),
                   n_windows_task_full=n_welch_windows(full))
        rows.append(row)
    if problems:
        raise SystemExit('cannot build the matched table:\n  ' + '\n  '.join(problems))
    with open(out_csv, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--task-extraction', required=True)
    ap.add_argument('--rest-extraction', required=True)
    ap.add_argument('--rough-sigma', required=True)
    ap.add_argument('--out-dir', required=True)
    ap.add_argument('--workers', type=int, default=os.cpu_count())
    args = ap.parse_args()
    os.makedirs(args.out_dir, exist_ok=True)
    matched_csv = os.path.join(args.out_dir, 'stage5_extraction_task_matched.csv')
    thr_json = os.path.join(args.out_dir, 'thresholds_per_subject_matched.json')
    null_csv = os.path.join(args.out_dir, 'sim_null_matched.csv')
    for p in (thr_json, null_csv):
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    if os.path.exists(matched_csv):
        raise SystemExit(f'output exists, not overwritten: {matched_csv}')

    rows = build_matched_extraction(args.task_extraction, args.rest_extraction, matched_csv)
    wm = [r['n_windows_matched'] for r in rows]
    wr = [r['n_windows_rest'] for r in rows]
    rel = [abs(a - b) / b for a, b in zip(wm, wr)]
    print(f'{len(rows)} subjects matched; epochs {min(r["n_epochs_matched"] for r in rows)}-'
          f'{max(r["n_epochs_matched"] for r in rows)}')
    print(f'Welch windows: matched {min(wm)}-{max(wm)}, rest {min(wr)}-{max(wr)}; '
          f'relative difference max {max(rel) * 100:.2f} %, median {np.median(rel) * 100:.2f} %')

    pairs = sim.read_pairs(matched_csv, args.rough_sigma)
    parts = os.path.join(args.out_dir, f'parts_matched_r{N_REPS}')
    os.makedirs(parts, exist_ok=True)
    part = {i: os.path.join(parts, f'p{i:02d}_c00.csv') for i in range(len(pairs))}
    todo = [i for i in range(len(pairs)) if not os.path.exists(part[i])]
    print(f'{len(pairs)} pairs, {N_REPS} null repetitions each; '
          f'{len(pairs) - len(todo)} of {len(pairs)} cells already done')
    with ProcessPoolExecutor(max_workers=args.workers) as ex:
        fut = {ex.submit(sim.run_cell, i, NULL_COND, pairs[i], N_REPS): i for i in todo}
        for k, f in enumerate(as_completed(fut), 1):
            sim.write_csv(part[fut[f]], f.result())
            print(f'cell {fut[f]} done ({k}/{len(todo)})', flush=True)

    null = [r for i in range(len(pairs)) for r in sim.read_csv(part[i])]
    assert len(null) == len(pairs) * N_REPS, f'{len(null)} null rows'
    sim.write_csv(null_csv, null)

    thr, failed = {}, 0
    for i, p in enumerate(pairs):
        v = np.array([float(r['max_beta_pw']) for r in sim.read_csv(part[i])])
        assert v.size == N_REPS
        thr[p['subject']] = {f'p{q}': float(np.percentile(v, q, method='linear')) for q in PERCENTILES}
        failed += sum(int(r['fit_failed']) for r in sim.read_csv(part[i]))
    with open(thr_json, 'w') as fh:
        json.dump(dict(thresholds=thr, primary='p95', percentile_method='linear',
                       n_null_per_subject=N_REPS, test_run=False, matched_to='rest n_pseudoepochs_kept',
                       matched_extraction=matched_csv, rough_sigma_file=args.rough_sigma,
                       seed=sim.SEED, null_cond=NULL_COND, fooof_version=core.FOOOF_VERSION,
                       null_fit_failed=int(failed),
                       null_fit_failed_rate=failed / (len(pairs) * N_REPS),
                       note='null cells only; §10d rule 5 asks for thresholds, not a second power curve'),
                  fh, indent=2)
    v = sorted(d['p95'] for d in thr.values())
    print(f'matched p95: min {v[0]:.4f}  median {np.median(v):.4f}  max {v[-1]:.4f}')
    print(f'null fit_failed: {failed} of {len(pairs) * N_REPS}')
    print('wrote:', os.path.basename(matched_csv), os.path.basename(null_csv),
          os.path.basename(thr_json))


if __name__ == '__main__':
    main()
