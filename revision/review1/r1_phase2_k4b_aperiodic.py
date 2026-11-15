"""Review round 1, Phase 2 K4b(i): cell-level aperiodic fits for the aperiodic-adjusted outcome (decision log §11k K4b,
§11m).

    python r1_phase2_k4b_aperiodic.py --trials <outRoot>/review1/phase2_real/r1_phase2_trials.csv \
        --trial-dir <eegOutRoot>/stage5/trials --out <outRoot>/review1/phase2_real/r1_phase2_k4b_cells.csv

For each participant x condition cell of the primary set (design first-in-mini-block, retained) and each window,
the trial spectra are recomputed with the §10g estimator (Hann 250, 50 % overlap, nfft = 250, density, ROI mean on
linear power), averaged over the cell's trials, and fitted by fooof 1.1.1 over 2-40 Hz with the frozen Stage-4 peak
settings, aperiodic 'fixed' and 'knee'. The cell's aperiodic band power is the mean of 10^curve over the 13-30 Hz
bins. Gate: every trial's recomputed 13-30 Hz band mean reproduces Track A's per-trial value to 1e-9 relative.
Writes one row per cell. Never overwrites.
"""
import argparse
import json
import os
import sys
import warnings

import numpy as np
from scipy.signal import welch

import r1_common as rc
from r1_common import core

sys.path.insert(0, os.path.join(rc.REPO, 'revision', 'stage5'))
import stage5_erd_by_condition as erd  # noqa: E402  (load_trials, constants; read-only reuse)

with warnings.catch_warnings():
    warnings.simplefilter('ignore', DeprecationWarning)
    from fooof import FOOOF
    from fooof.sim.gen import gen_aperiodic

FIT_RANGE = [2.0, 40.0]


def roi_spectra(x, fs):
    """x: (n_channels, n_samples, n_trials). Returns freqs and (n_trials, n_freqs) ROI-mean PSD - the computation
    inside erd.psd_band, before its band average."""
    nch, ns, ntr = x.shape
    x = np.moveaxis(x, 2, 1)
    f, p = welch(x.reshape(nch * ntr, ns), fs=fs, window='hann', nperseg=erd.NPERSEG, noverlap=erd.NOVERLAP,
                 nfft=erd.NPERSEG, detrend='constant', scaling='density', average='mean', axis=-1)
    return f, p.reshape(nch, ntr, f.size).mean(axis=0)


def fit(freqs, psd, mode):
    fm = FOOOF(aperiodic_mode=mode, verbose=False, **core.FOOOF_SETTINGS)
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        fm.fit(freqs, psd, FIT_RANGE)
    if not fm.has_model:
        return None
    return np.asarray(fm.aperiodic_params_, dtype=float), float(fm.r_squared_)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for a in ('--trials', '--trial-dir', '--out'):
        ap.add_argument(a, required=True)
    args = ap.parse_args()
    meta = os.path.splitext(args.out)[0] + '_meta.json'
    rc.refuse_existing([args.out, meta])
    T = [r for r in rc.read_csv(args.trials) if r['set_primary'] == '1']
    by_sub = {}
    for r in T:
        by_sub.setdefault(r['subject'], []).append(r)
    out, worst = [], 0.0
    for s in sorted(by_sub):
        rec = erd.load_trials(os.path.join(args.trial_dir, f'{s}_msit_trials.mat'))
        fs = rec['fs']
        fb, Pb = roi_spectra(rec['base'], fs)
        fa, Pa = roi_spectra(rec['act'], fs)
        assert np.allclose(fb, fa)
        band = (fb >= erd.BETA[0]) & (fb <= erd.BETA[1])
        for cond in ('00', 'S0', 'F0', 'FS'):
            rows = [r for r in by_sub[s] if r['cond'] == cond]
            idx = []
            for r in rows:
                j = int(rec['exported'][int(r['trial']) - 1])          # 1-based column in base/act
                assert j > 0, f'{s} trial {r["trial"]} not exported'
                for P, key in ((Pb, 'baseline_power'), (Pa, 'active_power')):
                    v = float(P[j - 1, band].mean())
                    worst = max(worst, abs(v - float(r[key])) / float(r[key]))
                idx.append(j - 1)
            cell = dict(subject=s, cond=cond, n_trials=len(idx))
            for P, w in ((Pb, 'base'), (Pa, 'act')):
                m = P[idx].mean(axis=0)
                for mode in ('fixed', 'knee'):
                    res = fit(fb, m, mode)
                    key = f'{w}_{mode}'
                    if res is None:
                        cell.update({f'{key}_ok': 0, f'{key}_ap_band': '', f'{key}_r2': '', f'{key}_params': ''})
                        if mode == 'knee':
                            cell[f'{w}_knee_freq'] = ''
                        continue
                    params, r2 = res
                    curve = gen_aperiodic(fb[band], params, mode)
                    cell.update({f'{key}_ok': 1, f'{key}_ap_band': float(np.mean(10.0 ** curve)), f'{key}_r2': r2,
                                 f'{key}_params': ';'.join(f'{v:.6g}' for v in params)})
                    if mode == 'knee':
                        k, e = params[1], params[2]
                        cell[f'{w}_knee_freq'] = float(k ** (1.0 / e)) if (k > 0 and e > 0) else float('nan')
            kf = [cell.get('base_knee_freq'), cell.get('act_knee_freq')]
            cell['knee_flag'] = int(any(isinstance(v, float) and 13.0 <= v <= 30.0 for v in kf))
            out.append(cell)
    assert worst <= 1e-9, f'gate failed: band power reproduced only to {worst}'
    rc.write_csv(args.out, out)
    summ = dict(rule='decision log §11m (K4b(i))', n_cells=len(out), gate_max_relative_difference=worst,
                failed_fits={k: sum(c[f'{k}_ok'] == 0 for c in out) for k in ('base_fixed', 'base_knee', 'act_fixed', 'act_knee')},
                n_knee_flagged=sum(c['knee_flag'] for c in out),
                provenance=rc.provenance(__file__, dict(trials=args.trials)))
    with open(meta, 'w') as fh:
        json.dump(summ, fh, indent=2)
    print(json.dumps({k: v for k, v in summ.items() if k != 'provenance'}))


if __name__ == '__main__':
    main()
