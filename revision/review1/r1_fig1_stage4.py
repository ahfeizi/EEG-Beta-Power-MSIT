"""Review round 1: Figure 1 redrawn from the Stage-4 classification — decision log §11y (descriptive).

    python r1_fig1_stage4.py --mode gate --stage4 <outRoot>/stage4 --roi-dir <eegOutRoot>/stage4/roi
        --out-dir <outRoot>/review1/fig1_stage4

Mode `gate` (§11y G0; this file's only mode so far). For each of the 39 rest ROI files: load_roi -> welch_runs ->
  (a) the frozen pipeline, core.run_pipeline (aperiodic-only check, then core.full_fit), and
  (b) the wrapper fit, core._fooof() with fm.fit(freqs, psd, list(core.FIT_RANGE)) -- the call core.full_fit makes --
      from which fm.freqs, fm._spectrum_flat and fm._peak_fit (private fooof 1.1.1 attributes) are taken.
  Checks, all evaluated and reported:
  - inputs: thr_p95 in peaks_primary.csv equals the p95 of thresholds_per_subject.json (exactly);
  - wrapper fm.peak_params_ equals core.full_fit's peaks exactly (np.array_equal), and its R^2 equals it exactly;
  - peaks_primary.csv: class_p95 and n_beta_peaks exactly; primary_cf / primary_pw / primary_bw and r2_full within
    1e-9 (empty fields where the participant has no beta-range Gaussian must stay empty);
  - peaks_all_in_range.csv: per participant, the same number of rows, and rank by rank cf / pw / bw within 1e-9 and
    pw_ge_p95 exactly;
  - the curves are finite and on the 77-bin fit grid.
  If any check fails: exit code 1, nothing written (the out-dir is not created). If all pass: only
  r1_fig1_gate.json (the check report and provenance) is written. Nothing is drawn in this mode.

stage4_core is imported unchanged (frozen at S4-prereg-frozen).
"""
import argparse
import glob
import json
import os
import sys

import numpy as np

import r1_common as rc                       # puts revision/stage4 on sys.path; imports stage4_core unchanged
from r1_common import core                   # noqa: E402

N_SUBJECTS = 39
TOL = 1e-9                                   # §11y G0
PRIMARY_NUM = ('primary_cf', 'primary_pw', 'primary_bw')


def wrapper_fit(freqs, psd):
    """The core.full_fit call, keeping the model object so its curves can be read (§11y G0)."""
    fm = core._fooof()
    fm.fit(freqs, psd, list(core.FIT_RANGE))
    if not fm.has_model:
        return None
    return dict(peaks=np.reshape(fm.peak_params_, (-1, 3)), r2=float(fm.r_squared_), freqs=np.array(fm.freqs),
                spectrum_flat=np.array(fm._spectrum_flat), peak_fit=np.array(fm._peak_fit))


def close(a, b):
    return abs(a - b) <= TOL                 # False for NaN


def gate(args):
    pp_csv = os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv')
    pa_csv = os.path.join(args.stage4, 'peak_detection', 'peaks_all_in_range.csv')
    thr_json = os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject.json')
    out = os.path.join(args.out_dir, 'r1_fig1_gate.json')
    rc.refuse_existing([out])

    primary = {r['subject']: r for r in rc.read_csv(pp_csv)}
    allpk = {}
    for r in rc.read_csv(pa_csv):
        allpk.setdefault(r['subject'], []).append(r)
    for s in allpk:
        allpk[s].sort(key=lambda r: int(r['rank']))
    with open(thr_json) as fh:
        tj = json.load(fh)
    if tj.get('test_run', True):
        raise SystemExit('thresholds file is a TEST run (or lacks test_run)')

    fails = {k: [] for k in ('subjects', 'thr_input', 'wrapper_peaks', 'wrapper_r2', 'class_p95', 'n_beta_peaks',
                             'primary_values', 'r2_full', 'in_range_count', 'in_range_values', 'in_range_flag',
                             'curves')}
    max_diff = {'primary_values': 0.0, 'r2_full': 0.0, 'in_range_values': 0.0}
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    seen = []
    for f in files:
        rec = core.load_roi(f)
        s = rec['subject']
        seen.append(s)
        if s not in primary:
            fails['subjects'].append((s, 'not in peaks_primary.csv'))
            continue
        p = primary[s]
        thr = float(p['thr_p95'])
        if thr != float(tj['thresholds'][s]['p95']):
            fails['thr_input'].append((s, thr, tj['thresholds'][s]['p95']))

        freqs, psd = core.welch_runs(rec['runs'], rec['fs'])
        ref = core.run_pipeline(freqs, psd)                 # the frozen path (real data: raises on failure)
        w = wrapper_fit(freqs, psd)
        if w is None or not np.array_equal(w['peaks'], ref['peaks']):
            fails['wrapper_peaks'].append(s)
            continue
        if w['r2'] != ref['r2']:
            fails['wrapper_r2'].append((s, w['r2'], ref['r2']))

        cls = core.classify(ref, thr)
        if cls != p['class_p95']:
            fails['class_p95'].append((s, cls, p['class_p95']))
        bp = core.beta_peaks(ref['peaks'])
        if len(bp) != int(p['n_beta_peaks']):
            fails['n_beta_peaks'].append((s, len(bp), p['n_beta_peaks']))
        for j, k in enumerate(PRIMARY_NUM):
            if len(bp) == 0:
                if p[k] != '':
                    fails['primary_values'].append((s, k, 'no beta Gaussian recomputed', p[k]))
                continue
            d = abs(bp[0, j] - float(p[k]))
            max_diff['primary_values'] = max(max_diff['primary_values'], d)
            if not d <= TOL:
                fails['primary_values'].append((s, k, float(bp[0, j]), p[k]))
        d = abs(ref['r2'] - float(p['r2_full']))
        max_diff['r2_full'] = max(max_diff['r2_full'], d)
        if not d <= TOL:
            fails['r2_full'].append((s, ref['r2'], p['r2_full']))

        rows = allpk.get(s, [])
        if len(rows) != len(bp):
            fails['in_range_count'].append((s, len(bp), len(rows)))
        else:
            for pk, r in zip(bp, rows):
                for j, k in enumerate(('cf', 'pw', 'bw')):
                    d = abs(pk[j] - float(r[k]))
                    max_diff['in_range_values'] = max(max_diff['in_range_values'], d)
                    if not d <= TOL:
                        fails['in_range_values'].append((s, r['rank'], k, float(pk[j]), r[k]))
                if int(pk[1] >= thr) != int(r['pw_ge_p95']):
                    fails['in_range_flag'].append((s, r['rank'], int(pk[1] >= thr), r['pw_ge_p95']))

        if not (w['freqs'].size == core.N_BINS and np.all(np.isfinite(w['spectrum_flat']))
                and np.all(np.isfinite(w['peak_fit']))):
            fails['curves'].append(s)
        print(f"{s}  class {cls}  n_beta {len(bp)}", flush=True)

    if not (len(seen) == N_SUBJECTS and sorted(seen) == sorted(primary)):
        fails['subjects'].append(('set', len(seen), len(primary)))
    passed = not any(fails.values())
    report = dict(passed=passed, failed_checks=[k for k, v in fails.items() if v], n_roi_files=len(files),
                  tol=TOL, max_abs_diff=max_diff, failures=fails,
                  n_in_range_rows_checked=sum(len(v) for v in allpk.values()),
                  provenance=rc.provenance(__file__, dict(peaks_primary=pp_csv, peaks_all_in_range=pa_csv,
                                                          thresholds=thr_json)),
                  roi_dir=args.roi_dir)
    print(json.dumps({k: report[k] for k in ('passed', 'failed_checks', 'n_roi_files', 'max_abs_diff',
                                             'n_in_range_rows_checked', 'failures')}, indent=2, default=str))
    if not passed:
        print('GATE FAILED: nothing written.', file=sys.stderr)
        sys.exit(1)
    os.makedirs(args.out_dir, exist_ok=True)
    with open(out, 'w') as fh:
        json.dump(report, fh, indent=2, default=str)
    print(f'GATE PASSED. Written: {os.path.basename(out)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--mode', required=True, choices=('gate',))
    ap.add_argument('--stage4', required=True)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    gate(args)


if __name__ == '__main__':
    main()
