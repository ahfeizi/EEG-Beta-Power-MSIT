"""Stage 5 diagnostic (DISCLOSURE ONLY): would a knee aperiodic model be preferred for the task spectra?

    python stage5_diag_knee_task.py --roi-dir <eegOutRoot>/stage5/roi \
        --out <outRoot>/stage5/stage5_diag_knee_task.csv

Why this exists: for rest, §6 of docs/decision_log.md found that a ΔBIC rule selected the knee model in
38 of 39 subjects with frequently non-physiological parameters, and the knee model was therefore removed
from the pipeline altogether. The decision was that a knee whose derived frequency lands inside the
13-30 Hz band of interest is not a credible description of background for this analysis regardless of
cause -- a model-choice decision, not a data-dependent selection. It therefore transfers to the task
unchanged, and the frozen pipeline has no knee code path to re-run.

This script reports, per subject, the same quantities §6 used for rest, so the task behaviour is
disclosed rather than assumed:
  R2_fixed, BIC_fixed, offset_fixed, exponent_fixed    (identical to the extraction output)
  R2_knee, BIC_knee, offset_knee, knee, exponent_knee  (fooof aperiodic_mode='knee', k = 3)
  dBIC = BIC_fixed - BIC_knee                          (> 10 would have selected knee under the old rule)
  knee_freq_Hz = knee ** (1 / exponent_knee)           (NaN if knee <= 0 or exponent_knee <= 0)
  knee_freq_in_beta                                    (1 if 13 <= knee_freq_Hz <= 30)

ITS NUMBERS ARE USED IN NO DECISION (the same status as BIC_fixed in §3). It sits outside the pipeline
and cannot affect it. The PSD comes from the shared, unchanged stage4_core.welch_runs, so the fixed-model
columns must reproduce stage5_extraction_only_task.py exactly -- which is itself a useful check.

LEAKAGE RULE: aperiodic-only quantities, as in §6 (which made exactly this inspection on real rest data
before the freeze). No full (periodic) fit, no peak, no band power, nothing restricted to 13-30 Hz is
computed. Never overwrites.
"""
import argparse
import csv
import glob
import json
import os
import sys
import warnings

import numpy as np

sys.dont_write_bytecode = True      # do not write __pycache__ into the frozen Stage-4 tree
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'stage4'))
import stage4_core as core          # noqa: E402  (imported unchanged from the frozen Stage-4 code)

with warnings.catch_warnings():
    warnings.simplefilter('ignore', DeprecationWarning)
    from fooof import FOOOF
    from fooof.core.errors import FitError
    from fooof.sim.gen import gen_aperiodic

N_SUBJECTS = 39
K_KNEE = 3                                                # offset, knee, exponent
BETA = core.BETA
COLUMNS = ['subject', 'n_pseudoepochs_kept',
           'R2_fixed', 'BIC_fixed', 'offset_fixed', 'exponent_fixed',
           'R2_knee', 'BIC_knee', 'offset_knee', 'knee', 'exponent_knee',
           'dBIC_fixed_minus_knee', 'knee_freq_Hz', 'knee_freq_in_beta', 'knee_fit_ok']


def ap_fit(freqs, psd, mode, k):
    """fooof's robust aperiodic-only fit in `mode`, with the §3 BIC = n ln(RSS/n) + k ln(n)."""
    fm = FOOOF(aperiodic_mode=mode, verbose=False, **core.FOOOF_SETTINGS)
    fm.add_data(freqs, psd, list(core.FIT_RANGE))
    n = fm.freqs.size
    assert n == core.N_BINS, f'{n} bins in {core.FIT_RANGE}, {core.N_BINS} expected'
    out = dict(ok=False, params=np.full(k, np.nan), rss=np.nan, bic=np.nan, r2=np.nan)
    try:
        params = fm._robust_ap_fit(fm.freqs, fm.power_spectrum)
    except FitError:
        return out
    curve = gen_aperiodic(fm.freqs, params, mode)
    if not np.all(np.isfinite(curve)):
        return out
    rss = float(np.sum((fm.power_spectrum - curve) ** 2))
    return dict(ok=True, params=np.asarray(params, dtype=float), rss=rss,
                bic=float(n * np.log(rss / n) + k * np.log(n)),
                r2=float(np.corrcoef(fm.power_spectrum, curve)[0, 1] ** 2))


def one(rec):
    row = dict.fromkeys(COLUMNS, 'NaN')
    row.update(subject=rec['subject'], n_pseudoepochs_kept=rec['n_pseudoepochs_kept'], knee_fit_ok=0,
               knee_freq_in_beta='')
    if rec['excluded_D12']:
        return row
    freqs, psd = core.welch_runs(rec['runs'], rec['fs'])
    fx = ap_fit(freqs, psd, 'fixed', core.K_PARAMS)
    assert fx['ok'], f"{rec['subject']}: fixed aperiodic fit failed"
    row.update(R2_fixed=fx['r2'], BIC_fixed=fx['bic'], offset_fixed=fx['params'][0],
               exponent_fixed=fx['params'][1])
    kn = ap_fit(freqs, psd, 'knee', K_KNEE)
    row['knee_fit_ok'] = int(kn['ok'])
    if kn['ok']:
        off, knee, expo = kn['params']
        kf = float(knee) ** (1.0 / float(expo)) if (knee > 0 and expo > 0) else float('nan')
        row.update(R2_knee=kn['r2'], BIC_knee=kn['bic'], offset_knee=off, knee=float(knee),
                   exponent_knee=float(expo), dBIC_fixed_minus_knee=fx['bic'] - kn['bic'],
                   knee_freq_Hz='NaN' if kf != kf else kf,
                   knee_freq_in_beta='' if kf != kf else int(BETA[0] <= kf <= BETA[1]))
    for k, v in row.items():
        if isinstance(v, float):
            row[k] = 'NaN' if v != v else float(v)
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_msit_roi.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} task ROI files found, {N_SUBJECTS} expected')
    rows = [one(core.load_roi(f)) for f in files]
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(rows)
    d = np.array([r['dBIC_fixed_minus_knee'] for r in rows if r['dBIC_fixed_minus_knee'] != 'NaN'],
                 dtype=float)
    kf = [r['knee_freq_Hz'] for r in rows if isinstance(r['knee_freq_Hz'], float)]
    n_sel = int((d > 10).sum())
    n_in_beta = sum(1 for r in rows if r['knee_freq_in_beta'] == 1)
    with open(os.path.splitext(args.out)[0] + '_meta.json', 'w') as fh:
        json.dump(dict(script='stage5_diag_knee_task.py', status='DISCLOSURE ONLY, used in no decision',
                       cond='msit', core_module='revision/stage4/stage4_core.py (unchanged)',
                       fit_range=core.FIT_RANGE, n_bins=core.N_BINS, k_fixed=core.K_PARAMS, k_knee=K_KNEE,
                       n_subjects=len(rows), n_knee_fit_ok=sum(r['knee_fit_ok'] for r in rows),
                       n_dBIC_gt_10=n_sel, n_knee_freq_in_beta=n_in_beta,
                       dBIC_min=float(d.min()) if d.size else None,
                       dBIC_median=float(np.median(d)) if d.size else None,
                       dBIC_max=float(d.max()) if d.size else None), fh, indent=2)
    print(f'{len(rows)} subjects; knee fit ok {sum(r["knee_fit_ok"] for r in rows)}; '
          f'dBIC > 10 (would have selected knee) {n_sel}; knee frequency inside 13-30 Hz {n_in_beta}')
    if d.size:
        print(f'dBIC (fixed - knee): min {d.min():.2f}  median {np.median(d):.2f}  max {d.max():.2f}')
    if kf:
        print(f'knee frequency Hz: min {min(kf):.2f}  median {np.median(kf):.2f}  max {max(kf):.2f}')


if __name__ == '__main__':
    main()
