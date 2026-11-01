"""Stage 5 Track B: peak detection on real MSIT+ task data (the task counterpart of
revision/stage4/stage4_peak_detection.py).

    python stage5_peak_detection_task.py --frozen-tag S5-task-peak-frozen \
        --roi-dir <eegOutRoot>/stage5/roi \
        --thresholds <outRoot>/stage5/sim_task/thresholds_per_subject.json \
        --half-thresholds <outRoot>/stage5/sim_task/thresholds_per_subject_half.json \
        --out-dir <outRoot>/stage5/peak_detection_task

GATE (the Stage-5 equivalent of Stage 4 §3.7). Stage 5 is exploratory and needs no second Zenodo deposit
(Amirhossein's call, decision log §10), so there is no DOI to check. The freeze-then-run discipline is
kept and made mechanical instead: the script refuses to run unless
  1. --frozen-tag names a git tag that exists and dereferences to a commit,
  2. that commit is HEAD, so the running code is exactly the tagged code,
  3. `revision/stage5` and `revision/stage4` have no uncommitted changes, and
  4. the tag name already appears in docs/decision_log.md,
i.e. the code was committed, tagged and documented before the first look at any real 13-30 Hz task
quantity. The threshold files must also not be test runs.

Everything downstream of the gate is the Stage-4 analysis, unchanged: the shared pipeline
(revision/stage4/stage4_core.py, imported as-is) computes the PSD and the fooof fit, the peak criterion is
the subject's own per-subject p95 (p90/p99 as the threshold-grid sensitivity), poor fit is R^2 < 0.90 or a
failed full fit, the tallest beta Gaussian is the primary peak, the alpha-harmonic flag is the same
exploratory 2 x IAF +- 2 Hz rule, and split-half is odd/even kept epochs against the subject's own
half-length p95. A failed aperiodic-only fit stops the script.
Thresholds come from the frozen Stage-4 calibration scripts run on the task extraction table (they are
parameterised by --extraction / --sim-dir and need no change for task data), so the task thresholds are
produced by exactly the deposited implementation.

Outputs (out-dir; never overwritten): peaks_primary.csv, peaks_all_in_range.csv, sensitivity_counts.csv,
split_half.csv, split_half_summary.json, run_meta.json.
"""
import argparse
import csv
import glob
import json
import os
import subprocess
import sys

import numpy as np

sys.dont_write_bytecode = True      # do not write __pycache__ into the frozen Stage-4 tree
STAGE4 = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'stage4')
sys.path.insert(0, STAGE4)
import stage4_core as core          # noqa: E402  (imported unchanged from the frozen Stage-4 code)

N_SUBJECTS = 39
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DECISION_LOG = os.path.join(REPO, 'docs', 'decision_log.md')
GATED_TREES = ('revision/stage5', 'revision/stage4')
THR_NAMES = ('p90', 'p95', 'p99')
PRIMARY = 'p95'


def git(*a):
    r = subprocess.run(['git', '-C', REPO, *a], capture_output=True, text=True)
    return r.stdout.strip(), r.returncode


def check_frozen(tag):
    """Refuse to run unless the code is committed, tagged with `tag`, clean, and the tag is documented."""
    if not tag or tag.strip() != tag:
        raise SystemExit(f'--frozen-tag must be a git tag name, got {tag!r}')
    commit, rc = git('rev-parse', '--verify', f'{tag}^{{commit}}')
    if rc != 0 or not commit:
        raise SystemExit(f'tag {tag!r} does not exist: commit and tag the Stage-5 code first')
    head, _ = git('rev-parse', 'HEAD')
    if commit != head:
        raise SystemExit(f'tag {tag!r} is at {commit[:8]}, HEAD is at {head[:8]}: run the tagged code')
    dirty, _ = git('status', '--porcelain', '--', *GATED_TREES)
    if dirty:
        raise SystemExit(f'uncommitted changes under {", ".join(GATED_TREES)}:\n{dirty}')
    with open(DECISION_LOG, encoding='utf-8') as fh:
        if tag not in fh.read():
            raise SystemExit(f'{tag} is not documented in {DECISION_LOG}: log the freeze first')
    return dict(frozen_tag=tag, commit=commit)


def icc_2_1(x):
    """ICC(2,1): two-way random effects, absolute agreement, single measures (Koo & Li, 2016).
    x: (n subjects, k measurements). NaN if n < 2. Identical to the Stage-4 implementation."""
    n, k = x.shape
    if n < 2:
        return float('nan')
    grand = x.mean()
    ms_r = k * np.sum((x.mean(axis=1) - grand) ** 2) / (n - 1)          # between subjects
    ms_c = n * np.sum((x.mean(axis=0) - grand) ** 2) / (k - 1)          # between halves
    sse = np.sum((x - x.mean(axis=1, keepdims=True) - x.mean(axis=0, keepdims=True) + grand) ** 2)
    ms_e = sse / ((n - 1) * (k - 1))
    return float((ms_r - ms_e) / (ms_r + (k - 1) * ms_e + k * (ms_c - ms_e) / n))


def analyse(runs, fs):
    freqs, psd = core.welch_runs(runs, fs)
    return core.run_pipeline(freqs, psd)                  # real data: raises on a failed fixed fit


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--frozen-tag', required=True)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--thresholds', required=True)
    ap.add_argument('--half-thresholds', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    gate = check_frozen(args.frozen_tag)                  # before any data is read

    with open(args.thresholds) as fh:
        tj = json.load(fh)
    if tj.get('test_run', True):
        raise SystemExit('thresholds file is a TEST run (or lacks test_run): use the full calibration')
    thr_all = {s: {name: float(v[name]) for name in THR_NAMES} for s, v in tj['thresholds'].items()}
    with open(args.half_thresholds) as fh:
        hj = json.load(fh)
    if hj.get('test_run', True):
        raise SystemExit('half-thresholds file is a TEST run (or lacks test_run)')
    thr_half = {s: {int(n): float(v[PRIMARY]) for n, v in d.items()} for s, d in hj['thresholds'].items()}
    names = {k: os.path.join(args.out_dir, k) for k in
             ('peaks_primary.csv', 'peaks_all_in_range.csv', 'sensitivity_counts.csv', 'split_half.csv',
              'split_half_summary.json', 'run_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_msit_roi.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} task ROI files found, {N_SUBJECTS} expected')
    os.makedirs(args.out_dir, exist_ok=True)

    primary, allpk, half = [], [], []
    for f in files:
        rec = core.load_roi(f)
        row = dict(subject=rec['subject'], excluded_D12=int(rec['excluded_D12']),
                   n_pseudoepochs_kept=rec['n_pseudoepochs_kept'])
        if rec['excluded_D12']:
            row.update({f'class_{t}': 'excluded_D12' for t in THR_NAMES})
            primary.append(row)
            continue
        if rec['subject'] not in thr_all:
            raise SystemExit(f"{rec['subject']}: no per-subject threshold in {args.thresholds}")
        thr = thr_all[rec['subject']]
        row.update({f'thr_{t}': thr[t] for t in THR_NAMES})
        res = analyse(rec['runs'], rec['fs'])
        bp = core.beta_peaks(res['peaks'])                # tallest first
        iaf, harm = core.alpha_harmonic(res['peaks'])
        row.update(fit_ok=int(res['fit_ok']), r2_full=res['r2'],
                   poor_fit=int(core.classify(res, 0.0) == 'poor_fit'), n_beta_peaks=len(bp),
                   primary_cf=bp[0, 0] if len(bp) else '', primary_pw=bp[0, 1] if len(bp) else '',
                   primary_bw=bp[0, 2] if len(bp) else '', iaf='' if np.isnan(iaf) else iaf,
                   primary_alpha_harmonic=int(harm[0]) if len(bp) else '',
                   **{f'class_{t}': core.classify(res, thr[t]) for t in THR_NAMES})
        primary.append(row)
        for rank, (pk, h) in enumerate(zip(bp, harm), 1):
            allpk.append(dict(subject=rec['subject'], rank=rank, cf=pk[0], pw=pk[1], bw=pk[2],
                              alpha_harmonic=int(h), **{f'pw_ge_{t}': int(pk[1] >= thr[t]) for t in THR_NAMES}))

        # split-half at the subject's half-length primary threshold (Stage 4 §3.8 / §7c)
        h1, h2 = core.split_half_runs(rec['runs'], rec['fs'])
        th = [thr_half.get(rec['subject'], {}).get(len(h)) for h in (h1, h2)]
        if None in th:
            raise SystemExit(f"{rec['subject']}: no half threshold for {len(h1)} / {len(h2)} epochs")
        hr = [analyse(h, rec['fs']) for h in (h1, h2)]
        half.append(dict(subject=rec['subject'], n_epochs_h1=len(h1), n_epochs_h2=len(h2),
                         **{f'{k}_h{i}': v for i, (r, t) in enumerate(zip(hr, th), 1) for k, v in
                            (('thr_p95', t), ('r2', r['r2']),
                             ('class', core.classify(r, t)), ('max_beta_pw', core.max_beta_pw(r['peaks'])))}))
        print(f"{rec['subject']}  {row[f'class_{PRIMARY}']}  halves {half[-1]['class_h1']}/{half[-1]['class_h2']}", flush=True)

    def write(path, rows, fields):
        with open(path, 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=fields, restval='')
            w.writeheader()
            w.writerows(rows)

    write(names['peaks_primary.csv'], primary,
          ['subject', 'excluded_D12', 'n_pseudoepochs_kept', 'fit_ok', 'r2_full', 'poor_fit',
           'n_beta_peaks', 'primary_cf', 'primary_pw', 'primary_bw', 'iaf', 'primary_alpha_harmonic']
          + [f'thr_{t}' for t in THR_NAMES] + [f'class_{t}' for t in THR_NAMES])
    write(names['peaks_all_in_range.csv'], allpk,
          ['subject', 'rank', 'cf', 'pw', 'bw', 'alpha_harmonic'] + [f'pw_ge_{t}' for t in THR_NAMES])
    sens = [dict(threshold=t, per_subject=1, primary=int(t == PRIMARY),
                 **{f'n_{c}': sum(r[f'class_{t}'] == c for r in primary)
                    for c in ('peak', 'no_peak', 'poor_fit', 'excluded_D12')}) for t in THR_NAMES]
    write(names['sensitivity_counts.csv'], sens, list(sens[0]))
    write(names['split_half.csv'], half, list(half[0]) if half else ['subject'])

    poor_either = [r for r in half if 'poor_fit' in (r['class_h1'], r['class_h2'])]
    evaluable = [r for r in half if r not in poor_either]
    agree = sum(r['class_h1'] == r['class_h2'] for r in evaluable)
    both = [r for r in evaluable if r['class_h1'] == r['class_h2'] == 'peak']
    pw = np.array([[r['max_beta_pw_h1'], r['max_beta_pw_h2']] for r in both], dtype=float).reshape(-1, 2)
    with open(names['split_half_summary.json'], 'w') as fh:
        json.dump(dict(cond='msit', threshold=PRIMARY, threshold_per_subject_half_length=True,
                       n_subjects=len(half),
                       n_poor_fit_h1=sum(r['class_h1'] == 'poor_fit' for r in half),
                       n_poor_fit_h2=sum(r['class_h2'] == 'poor_fit' for r in half),
                       n_poor_fit_either=len(poor_either), n_evaluable=len(evaluable), n_agree=agree,
                       agreement_rate=agree / len(evaluable) if evaluable else None,
                       icc_type='ICC(2,1) two-way random, absolute agreement, single measures',
                       n_peak_both=len(both), icc_pw=icc_2_1(pw) if len(both) else None), fh, indent=2)
    with open(names['run_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_peak_detection_task.py', cond='msit',
                       core_module='revision/stage4/stage4_core.py (unchanged)', gate=gate,
                       thresholds_file=args.thresholds, thresholds=thr_all,
                       half_thresholds_file=args.half_thresholds, half_thresholds=hj['thresholds'],
                       fooof_version=core.FOOOF_VERSION, roi_dir=args.roi_dir, n_files=len(files),
                       tags_at_head=git('tag', '--points-at', 'HEAD')[0].split()), fh, indent=2)


if __name__ == '__main__':
    main()
