"""Stage 4 extraction-only script (docs/zenodo_preregistration_stage4.md, §3.7).

    python stage4_extraction_only.py --roi-dir <eegOutRoot>/stage4/roi --out <outRoot>/stage4/stage4_extraction.csv

Reads the <sub>_rest_roi.mat files written by stage4_export_roi.m (39 expected) and writes one row per
subject with exactly the §3.7 columns: bookkeeping, the fixed aperiodic-only fit statistics and parameters,
and the two noise floors (fixed model only, no knee, no model selection; decided 2026-10-30).

LEAKAGE RULE (§3.7): only load_roi, welch_runs, aperiodic_only and noise_floor are called.
No full (periodic) fit, no peak, nothing restricted to 13-30 Hz is computed or stored. The PSD exists only
in memory and is never written or printed.
A failed aperiodic-only fit stops the script (decided 2026-10-30). Never overwrites the output.
"""
import argparse
import csv
import glob
import json
import os

import stage4_core as core

N_SUBJECTS = 39
COLUMNS = ['subject', 'fs', 'n_pseudoepochs_total', 'n_pseudoepochs_kept', 'n_outside', 'excluded_D12',
           'run_lengths_epochs',
           'R2_fixed', 'BIC_fixed', 'offset_fixed', 'exponent_fixed', 'noise_2_12Hz', 'noise_31_40Hz']


def extract_one(rec):
    row = dict.fromkeys(COLUMNS, 'NaN')
    row.update(subject=rec['subject'], fs=rec['fs'], n_pseudoepochs_total=rec['n_pseudoepochs_total'],
               n_pseudoepochs_kept=rec['n_pseudoepochs_kept'], n_outside=rec['n_outside'],
               excluded_D12=int(rec['excluded_D12']),
               run_lengths_epochs=';'.join(str(k) for k in rec['run_len_epochs']))
    if rec['excluded_D12']:
        return row                                         # §3.1.1: no spectrum for an excluded subject
    freqs, psd = core.welch_runs(rec['runs'], rec['fs'])
    ap = core.aperiodic_only(freqs, psd)
    if not ap['ok']:
        raise RuntimeError(f"{rec['subject']}: aperiodic-only fit failed: stop and report")
    off_f, exp_f = ap['params']
    row.update(R2_fixed=ap['r2'], BIC_fixed=ap['bic'], offset_fixed=off_f, exponent_fixed=exp_f,
               **core.noise_floor(ap))
    for k, v in row.items():                               # plain floats
        if isinstance(v, float):                           # (np.float64 is a float subclass)
            row[k] = 'NaN' if v != v else float(v)
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--roi-dir', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} ROI files found, {N_SUBJECTS} expected')
    rows = []
    for f in files:
        rows.append(extract_one(core.load_roi(f)))
        r = rows[-1]
        print(f"{r['subject']}  kept {r['n_pseudoepochs_kept']}  excluded {r['excluded_D12']}")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(rows)
    with open(os.path.splitext(args.out)[0] + '_meta.json', 'w') as fh:
        json.dump(dict(script='stage4_extraction_only.py', fooof_version=core.FOOOF_VERSION, roi=core.ROI,
                       fit_range=core.FIT_RANGE, n_bins=core.N_BINS, aperiodic_mode=core.APERIODIC_MODE,
                       noise_bands=core.NOISE_BANDS, noise_ddof=core.NOISE_DDOF, roi_dir=args.roi_dir,
                       n_files=len(files), n_excluded_D12=sum(r['excluded_D12'] for r in rows)), fh, indent=2)


if __name__ == '__main__':
    main()
