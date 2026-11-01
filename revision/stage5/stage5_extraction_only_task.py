"""Stage 5 Track B, extraction-only (the task counterpart of revision/stage4/stage4_extraction_only.py).

    python stage5_extraction_only_task.py --roi-dir <eegOutRoot>/stage5/roi \
        --out <outRoot>/stage5/stage5_extraction_task.csv

Reads the <sub>_msit_roi.mat files written by stage5_export_roi_task.m (39 expected) and writes one row
per subject with the same 13 columns as the Stage-4 rest extraction, plus n_blocks (task blocks per
subject, bookkeeping only), so the rest and task tables are directly comparable.

Why a separate file instead of a flag on the Stage-4 script: revision/stage4/ is frozen at tag
S4-prereg-frozen and deposited on Zenodo (DOI 10.5281/zenodo.23843194); it is not edited. The shared
pipeline stage4_core.py is imported unchanged, so the task PSD/fit is computed by exactly the same code
as the rest PSD/fit (same ROI, 2 s Hann Welch windows, 50 % overlap, fixed aperiodic model, 2-40 Hz,
77 bins). stage4_core.load_roi reads only variables that stage5_export_roi_task.m also writes under the
same names, so it needs no change either.

LEAKAGE RULE (as in Stage 4 §3.7): only load_roi, welch_runs, aperiodic_only and noise_floor are called.
No full (periodic) fit, no peak, nothing restricted to 13-30 Hz is computed or stored. The PSD exists only
in memory and is never written or printed. A failed aperiodic-only fit stops the script.
Never overwrites the output.
"""
import argparse
import csv
import glob
import json
import os
import sys

sys.dont_write_bytecode = True      # do not write __pycache__ into the frozen Stage-4 tree
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'stage4'))
import stage4_core as core          # noqa: E402  (imported unchanged from the frozen Stage-4 code)

N_SUBJECTS = 39
COLUMNS = ['subject', 'fs', 'n_pseudoepochs_total', 'n_pseudoepochs_kept', 'n_outside', 'excluded_D12',
           'run_lengths_epochs',
           'R2_fixed', 'BIC_fixed', 'offset_fixed', 'exponent_fixed', 'noise_2_12Hz', 'noise_31_40Hz',
           'n_blocks']


def load_task_roi(path):
    """core.load_roi plus the task-only bookkeeping field nBlocks (no spectral quantity)."""
    rec = core.load_roi(path)
    from scipy.io import loadmat
    m = loadmat(path, variable_names=['nBlocks', 'cond'])
    rec['n_blocks'] = int(m['nBlocks'].item())
    assert str(m['cond'].ravel()[0]) == 'msit', f"{rec['subject']}: not a task export"
    return rec


def extract_one(rec):
    row = dict.fromkeys(COLUMNS, 'NaN')
    row.update(subject=rec['subject'], fs=rec['fs'], n_pseudoepochs_total=rec['n_pseudoepochs_total'],
               n_pseudoepochs_kept=rec['n_pseudoepochs_kept'], n_outside=rec['n_outside'],
               excluded_D12=int(rec['excluded_D12']), n_blocks=rec['n_blocks'],
               run_lengths_epochs=';'.join(str(k) for k in rec['run_len_epochs']))
    if rec['excluded_D12']:
        return row                                         # no spectrum for an excluded subject
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
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_msit_roi.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} task ROI files found, {N_SUBJECTS} expected')
    rows = []
    for f in files:
        rows.append(extract_one(load_task_roi(f)))
        r = rows[-1]
        print(f"{r['subject']}  blocks {r['n_blocks']}  kept {r['n_pseudoepochs_kept']}  "
              f"excluded {r['excluded_D12']}")
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=COLUMNS)
        w.writeheader()
        w.writerows(rows)
    with open(os.path.splitext(args.out)[0] + '_meta.json', 'w') as fh:
        json.dump(dict(script='stage5_extraction_only_task.py', cond='msit',
                       core_module='revision/stage4/stage4_core.py (unchanged)',
                       fooof_version=core.FOOOF_VERSION, roi=core.ROI, epoch_s=core.EPOCH_S,
                       fit_range=core.FIT_RANGE, n_bins=core.N_BINS, aperiodic_mode=core.APERIODIC_MODE,
                       noise_bands=core.NOISE_BANDS, noise_ddof=core.NOISE_DDOF, roi_dir=args.roi_dir,
                       n_files=len(files), n_excluded_D12=sum(r['excluded_D12'] for r in rows)), fh, indent=2)


if __name__ == '__main__':
    main()
