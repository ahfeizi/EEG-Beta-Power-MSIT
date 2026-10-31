"""Stage 4 peak detection on real rest data (docs/zenodo_preregistration_stage4.md, §3.1.1-3.5.2, §3.8).

    python stage4_peak_detection.py --doi 10.5281/zenodo.NNNNNNN --roi-dir <eegOutRoot>/stage4/roi
        --thresholds <outRoot>/stage4/sim_rough/thresholds_per_subject.json --out-dir <outRoot>/stage4/peaks

GATE (§3.7): refuses to run unless --doi is a Zenodo DOI that already appears in docs/decision_log.md and
is not the v1 archive DOI. Frozen at tag S4-prereg-frozen; to be run by Amirhossein only after the DOI of
the pre-registration is logged.

Thresholds are per subject (decided 2026-10-31, option (ii)): each subject's p90 / p95 / p99 of its own
1000 null simulations, from thresholds_per_subject.json (stage4_per_subject_thresholds.py); every retained
subject must have its own entry.
Per subject retained by D12: welch_runs -> run_pipeline (full fooof fit, fixed aperiodic model) -> peak
criterion at the subject's primary (p95) threshold and at its p90 / p99 (§3.5.2); poor fit (R^2 < 0.90 or failed full
fit) = indeterminate (§3.5.1); tallest beta Gaussian = primary peak; alpha-harmonic flag (§3.5).
Split-half (§3.8): odd / even kept epochs, full pipeline per half at the subject's p95; agreement rate among subjects
not poor-fit in either half; ICC(2,1) of the primary-peak PW among subjects with a peak in both halves.
A failed aperiodic-only fit stops the script (real data, decided 2026-10-30).
Not implemented here (decided 2026-10-30): the single-channel secondary results of §3.3. If added later, as
a clearly labelled exploratory analysis, they carry the same 13-30 Hz information and must sit behind the
same check_doi gate.

Outputs (out-dir; never overwritten): peaks_primary.csv, peaks_all_in_range.csv, sensitivity_counts.csv,
split_half.csv, split_half_summary.json, run_meta.json.
"""
import argparse
import csv
import glob
import json
import os
import re
import subprocess

import numpy as np

import stage4_core as core

N_SUBJECTS = 39
V1_DOI = '10.5281/zenodo.22232799'                        # prior (v1) archive: never accepted by the gate
DOI_RE = re.compile(r'^10\.5281/zenodo\.\d+$')
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DECISION_LOG = os.path.join(REPO, 'docs', 'decision_log.md')
THR_NAMES = ('p90', 'p95', 'p99')
PRIMARY = 'p95'


def check_doi(doi):
    if not DOI_RE.match(doi):
        raise SystemExit(f'--doi must look like 10.5281/zenodo.<number>, got {doi!r}')
    if doi == V1_DOI:
        raise SystemExit('--doi is the v1 archive DOI, not the Stage-4 pre-registration DOI')
    with open(DECISION_LOG, encoding='utf-8') as fh:
        if doi not in fh.read():
            raise SystemExit(f'{doi} is not logged in {DECISION_LOG}: log the pre-registration DOI first')


def git_state():
    def git(*a):
        return subprocess.run(['git', '-C', REPO, *a], capture_output=True, text=True).stdout.strip()
    return dict(commit=git('rev-parse', 'HEAD'), tags_at_head=git('tag', '--points-at', 'HEAD').split(),
                dirty=bool(git('status', '--porcelain', '--', 'revision/stage4')))


def icc_2_1(x):
    """ICC(2,1): two-way random effects, absolute agreement, single measures (Koo & Li, 2016).
    x: (n subjects, k measurements). NaN if n < 2."""
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
    ap.add_argument('--doi', required=True)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--thresholds', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    check_doi(args.doi)                                   # before any data is read

    with open(args.thresholds) as fh:
        tj = json.load(fh)
    if tj.get('test_run', True):
        raise SystemExit('thresholds file is a TEST run (or lacks test_run): use the full calibration')
    thr_all = {s: {name: float(v[name]) for name in THR_NAMES} for s, v in tj['thresholds'].items()}
    names = {k: os.path.join(args.out_dir, k) for k in
             ('peaks_primary.csv', 'peaks_all_in_range.csv', 'sensitivity_counts.csv', 'split_half.csv',
              'split_half_summary.json', 'run_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} ROI files found, {N_SUBJECTS} expected')
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

        # §3.8 split-half at the primary threshold
        h1, h2 = core.split_half_runs(rec['runs'], rec['fs'])
        hr = [analyse(h, rec['fs']) for h in (h1, h2)]
        half.append(dict(subject=rec['subject'], thr_p95=thr[PRIMARY], n_epochs_h1=len(h1), n_epochs_h2=len(h2),
                         **{f'{k}_h{i}': v for i, r in enumerate(hr, 1) for k, v in
                            (('r2', r['r2']),
                             ('class', core.classify(r, thr[PRIMARY])), ('max_beta_pw', core.max_beta_pw(r['peaks'])))}))
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
        json.dump(dict(threshold=PRIMARY, threshold_per_subject=True, n_subjects=len(half),
                       n_poor_fit_h1=sum(r['class_h1'] == 'poor_fit' for r in half),
                       n_poor_fit_h2=sum(r['class_h2'] == 'poor_fit' for r in half),
                       n_poor_fit_either=len(poor_either), n_evaluable=len(evaluable), n_agree=agree,
                       agreement_rate=agree / len(evaluable) if evaluable else None,
                       icc_type='ICC(2,1) two-way random, absolute agreement, single measures',
                       n_peak_both=len(both), icc_pw=icc_2_1(pw) if len(both) else None), fh, indent=2)
    with open(names['run_meta.json'], 'w') as fh:
        json.dump(dict(script='stage4_peak_detection.py', doi=args.doi, thresholds_file=args.thresholds,
                       thresholds=thr_all, fooof_version=core.FOOOF_VERSION, roi_dir=args.roi_dir,
                       n_files=len(files), git=git_state()), fh, indent=2)


if __name__ == '__main__':
    main()
