"""Review round 1: split-half reliability of resting CF and BW (IBF, IBB) — decision log §11v (post-hoc).

    python r1_splithalf_icc_cfbw.py --mode extract --stage4 <outRoot>/stage4 --roi-dir <eegOutRoot>/stage4/roi
        --out-dir <outRoot>/review1/splithalf_icc

Mode `extract` (this file's only mode so far):
  1. GATE (§11v D0), entirely in memory. For every one of the 39 rest ROI files the frozen Stage-4 split-half is
     repeated exactly as stage4_peak_detection.py does it (split_half_runs -> welch_runs -> run_pipeline ->
     classify at the subject's own half-length p95), and class_h1/h2 and max_beta_pw_h1/h2 are compared with the
     §9 split_half.csv: class exactly, PW within 1e-9 absolute. The participants classified `peak` in both halves
     must number 20, and ICC(2,1) of their recomputed PW must reproduce `icc_pw` of split_half_summary.json within
     1e-9. Every check is evaluated and reported; if any fails, the script exits with code 1 and writes nothing
     (the out-dir is not even created).
  2. Only if every check passes: for the 20 participants, the tallest beta-range Gaussian of each half
     (core.beta_peaks(peaks)[0], §11v D2b; no cross-half matching) is written, with the D2b descriptives.
No ICC of CF or BW and no bootstrap is computed here (§11v D3 is a later step).

stage4_core, and icc_2_1 from stage4_peak_detection, are imported unchanged (frozen at S4-prereg-frozen).
"""
import argparse
import glob
import json
import os
import sys

import numpy as np

import r1_common as rc                       # puts revision/stage4 on sys.path; imports stage4_core unchanged
from r1_common import core                   # noqa: E402
from stage4_peak_detection import icc_2_1, N_SUBJECTS, PRIMARY   # noqa: E402  (frozen, verified §9)

PW_TOL = 1e-9                                # §11v D0
ICC_TOL = 1e-9                               # §11v D0
N_PEAK_BOTH_EXPECTED = 20                    # §9, §11v D2
BW_BOUND_TOL = 1e-6                          # Hz; "at the 1 or 8 Hz bound" (§11v D2b), see report
CLASS_KEYS = ('class_h1', 'class_h2')
PW_KEYS = ('max_beta_pw_h1', 'max_beta_pw_h2')


def half_fits(rec, thr_half):
    """Repeat stage4_peak_detection.py lines 144-153 for one subject; also keep the fitted peaks."""
    h1, h2 = core.split_half_runs(rec['runs'], rec['fs'])
    th = [thr_half.get(rec['subject'], {}).get(len(h)) for h in (h1, h2)]
    if None in th:
        raise SystemExit(f"{rec['subject']}: no half threshold for {len(h1)} / {len(h2)} epochs")
    hr = [core.run_pipeline(*core.welch_runs(h, rec['fs'])) for h in (h1, h2)]   # = analyse(h, fs)
    out = dict(subject=rec['subject'], n_epochs_h1=len(h1), n_epochs_h2=len(h2))
    for i, (r, t) in enumerate(zip(hr, th), 1):
        out.update({f'thr_p95_h{i}': t, f'r2_h{i}': r['r2'], f'class_h{i}': core.classify(r, t),
                    f'max_beta_pw_h{i}': core.max_beta_pw(r['peaks']), f'peaks_h{i}': r['peaks']})
    return out


def gate(recomputed, stored, icc_stored, n_both_stored):
    """All §11v D0 checks. Returns (passed, report dict, both-peak subjects)."""
    checks, fails = {}, []
    subs_r, subs_s = sorted(recomputed), sorted(stored)
    checks['subjects'] = dict(n_recomputed=len(subs_r), n_stored=len(subs_s), expected=N_SUBJECTS,
                              same_set=subs_r == subs_s)
    if not (len(subs_r) == len(subs_s) == N_SUBJECTS and subs_r == subs_s):
        fails.append('subjects')
    common = [s for s in subs_r if s in stored]

    # input consistency (not a §11v criterion, but a mismatch would make every later check meaningless)
    thr_mis = [(s, k, recomputed[s][k], float(stored[s][k])) for s in common for k in ('thr_p95_h1', 'thr_p95_h2')
               if recomputed[s][k] != float(stored[s][k])]
    ep_mis = [(s, k, recomputed[s][k], int(stored[s][k])) for s in common for k in ('n_epochs_h1', 'n_epochs_h2')
              if recomputed[s][k] != int(stored[s][k])]
    checks['inputs_half_thresholds_and_epoch_counts'] = dict(n_mismatch=len(thr_mis) + len(ep_mis),
                                                             mismatches=thr_mis + ep_mis)
    if thr_mis or ep_mis:
        fails.append('inputs_half_thresholds_and_epoch_counts')

    cls_mis = [(s, k, recomputed[s][k], stored[s][k]) for s in common for k in CLASS_KEYS
               if recomputed[s][k] != stored[s][k]]
    checks['class_exact'] = dict(n_compared=2 * len(common), n_mismatch=len(cls_mis), mismatches=cls_mis)
    if cls_mis:
        fails.append('class_exact')

    dpw = {(s, k): abs(recomputed[s][k] - float(stored[s][k])) for s in common for k in PW_KEYS}
    pw_mis = [(s, k, d) for (s, k), d in dpw.items() if not d <= PW_TOL]        # NaN counts as a failure
    worst = max(dpw.items(), key=lambda kv: kv[1]) if dpw else (None, float('nan'))
    checks['pw_within_tol'] = dict(tol=PW_TOL, n_compared=len(dpw), n_mismatch=len(pw_mis),
                                   max_abs_diff=worst[1], max_at=worst[0], mismatches=pw_mis)
    if pw_mis:
        fails.append('pw_within_tol')

    both = [s for s in subs_r if recomputed[s]['class_h1'] == recomputed[s]['class_h2'] == 'peak']
    checks['n_peak_both'] = dict(recomputed=len(both), expected=N_PEAK_BOTH_EXPECTED, stored_summary=n_both_stored)
    if not len(both) == N_PEAK_BOTH_EXPECTED == n_both_stored:
        fails.append('n_peak_both')

    pw = np.array([[recomputed[s]['max_beta_pw_h1'], recomputed[s]['max_beta_pw_h2']] for s in both],
                  dtype=float).reshape(-1, 2)
    icc = icc_2_1(pw) if len(both) else float('nan')
    checks['icc_pw'] = dict(recomputed=icc, stored=icc_stored, abs_diff=abs(icc - icc_stored), tol=ICC_TOL)
    if not abs(icc - icc_stored) <= ICC_TOL:
        fails.append('icc_pw')

    # informational only (not a criterion): agreement of the fit R^2 with the stored value
    dr2 = [abs(recomputed[s][f'r2_h{i}'] - float(stored[s][f'r2_h{i}'])) for s in common for i in (1, 2)]
    checks['info_max_abs_diff_r2'] = max(dr2) if dr2 else float('nan')
    return not fails, dict(passed=not fails, failed_checks=fails, checks=checks), both


def at_bound(bw):
    return int(abs(bw - core.BW_RANGE[0]) <= BW_BOUND_TOL or abs(bw - core.BW_RANGE[1]) <= BW_BOUND_TOL)


def extract(args):
    sh_csv = os.path.join(args.stage4, 'peak_detection', 'split_half.csv')
    sh_json = os.path.join(args.stage4, 'peak_detection', 'split_half_summary.json')
    half_thr = os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject_half.json')
    outs = {k: os.path.join(args.out_dir, k) for k in
            ('r1_splithalf_gate.json', 'r1_splithalf_cfbw.csv', 'r1_splithalf_descriptives.json')}
    rc.refuse_existing(outs.values())

    # half-length thresholds, read exactly as stage4_peak_detection.py reads them
    with open(half_thr) as fh:
        hj = json.load(fh)
    if hj.get('test_run', True):
        raise SystemExit('half-thresholds file is a TEST run (or lacks test_run)')
    thr_half = {s: {int(n): float(v[PRIMARY]) for n, v in d.items()} for s, d in hj['thresholds'].items()}
    stored = {r['subject']: r for r in rc.read_csv(sh_csv)}
    with open(sh_json) as fh:
        summ = json.load(fh)

    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    recomputed = {}
    for f in files:
        rec = core.load_roi(f)
        if rec['excluded_D12']:                  # as in the frozen script; none in practice (§5)
            continue
        recomputed[rec['subject']] = half_fits(rec, thr_half)
        r = recomputed[rec['subject']]
        print(f"{r['subject']}  halves {r['class_h1']}/{r['class_h2']}", flush=True)

    passed, report, both = gate(recomputed, stored, float(summ['icc_pw']), int(summ['n_peak_both']))
    report['provenance'] = rc.provenance(__file__, dict(split_half_csv=sh_csv, split_half_summary=sh_json,
                                                        half_thresholds=half_thr))
    report['roi_dir'] = args.roi_dir
    report['n_roi_files'] = len(files)
    print(json.dumps({k: report[k] for k in ('passed', 'failed_checks', 'checks')}, indent=2, default=str))
    if not passed:
        print('GATE FAILED: nothing written, CF/BW not extracted.', file=sys.stderr)
        sys.exit(1)

    # ---- gate passed: §11v D2b extraction for the 20 participants ----
    rows = []
    for s in both:
        r = recomputed[s]
        bp = [core.beta_peaks(r[f'peaks_h{i}']) for i in (1, 2)]
        cf1, pw1, bw1 = bp[0][0]
        cf2, pw2, bw2 = bp[1][0]
        rows.append(dict(subject=s, cf_h1=cf1, pw_h1=pw1, bw_h1=bw1, cf_h2=cf2, pw_h2=pw2, bw_h2=bw2,
                         n_beta_h1=len(bp[0]), n_beta_h2=len(bp[1]), abs_dcf=abs(cf1 - cf2),
                         bw_h1_at_bound=at_bound(bw1), bw_h2_at_bound=at_bound(bw2),
                         beta_gaussians_h1=rc.peaks_to_str(r['peaks_h1']),
                         beta_gaussians_h2=rc.peaks_to_str(r['peaks_h2'])))
        # the extracted PW must be the gated PW (same Gaussian)
        assert pw1 == r['max_beta_pw_h1'] and pw2 == r['max_beta_pw_h2'], s
    desc = dict(n=len(rows),
                n_multi_beta_h1=sum(x['n_beta_h1'] > 1 for x in rows),
                n_multi_beta_h2=sum(x['n_beta_h2'] > 1 for x in rows),
                n_multi_beta_either=sum(x['n_beta_h1'] > 1 or x['n_beta_h2'] > 1 for x in rows),
                n_bw_at_bound_h1=sum(x['bw_h1_at_bound'] for x in rows),
                n_bw_at_bound_h2=sum(x['bw_h2_at_bound'] for x in rows),
                n_participants_bw_at_bound_either=sum(x['bw_h1_at_bound'] or x['bw_h2_at_bound'] for x in rows),
                bw_bound_tol_hz=BW_BOUND_TOL,
                note='abs_dcf per participant is in r1_splithalf_cfbw.csv; jackknife ICC range is computed '
                     'with the ICC step (§11v D3), not here')
    os.makedirs(args.out_dir, exist_ok=True)
    with open(outs['r1_splithalf_gate.json'], 'w') as fh:
        json.dump(report, fh, indent=2, default=str)
    rc.write_csv(outs['r1_splithalf_cfbw.csv'], rows)
    with open(outs['r1_splithalf_descriptives.json'], 'w') as fh:
        json.dump(desc, fh, indent=2)
    print(f"GATE PASSED. Written: {', '.join(os.path.basename(p) for p in outs.values())}")
    print(json.dumps({k: v for k, v in desc.items() if k != 'note'}, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--mode', required=True, choices=('extract',))
    ap.add_argument('--stage4', required=True)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    extract(args)


if __name__ == '__main__':
    main()
