"""Stage 5 Track A: beta-band ERD% by MSIT+ condition from the two-window trial export (§10b, §10g).

    python stage5_erd_by_condition.py --trial-dir <eegOutRoot>/stage5/trials \
        --overlap-summary <outRoot>/stage5/stage5_window_overlap_summary.json \
        --out-dir <outRoot>/stage5/erd

Reads the <sub>_msit_trials.mat files written by stage5_export_trials_task.m (39 expected) and computes,
for every usable trial, the 13-30 Hz band-average power of the baseline window [-0.5, 0) s and of the
active window [0, 1) s, then ERD% by condition.

SPECTRAL SETTINGS (§10g) - identical in both windows, because ERD% is a ratio and unmatched taper
lengths would bias it through unequal alpha leakage:
    Hann, nperseg = 250 samples (0.5 s), noverlap = 125 (50 %), detrend 'constant', scaling 'density',
    average 'mean', nfft = nperseg (NO zero-padding).
  -> frequency resolution is set by the 0.5 s window: 2 Hz. The bin spacing is also 2 Hz, because nfft is
     not padded. These two numbers coincide here, unlike v1's `pwelch(x, hann(100), [], [], fs)` where a
     0.2 s window (5 Hz resolution) was reported on a zero-padded 1.95 Hz bin grid (nfft = 256).
  -> sub-segmentation is explicit and asserted, not assumed: the 250-sample baseline is exactly ONE
     segment, the 500-sample active window exactly THREE (0-250, 125-375, 250-500).
  -> on the 2 Hz grid the band 13-30 Hz is carried by the bins 14, 16, ..., 30 Hz (9 bins). Identical in
     both windows, so the ratio is unaffected; stated here because it defines the absolute measures too.
  -> documented limitation (§10g): a 0.5 s Hann taper has its first spectral null 4 Hz from centre, so
     10 Hz alpha still leaks toward ~14 Hz. Identical on both sides, it cancels to first order in the
     ratio but dilutes ERD% toward zero where alpha dominates.
ROI averaging follows stage4_core.welch_runs: the PSD is averaged over the 7 ROI channels on LINEAR
power first, then averaged over the band.

ERD%: two estimators are reported.
  erd_pct            PRIMARY, the classic definition (Pfurtscheller & Lopes da Silva, 1999): the band
                     powers are averaged over the trials of a subject x condition cell FIRST, then
                     ERD% = (mean_baseline - mean_active) / mean_baseline * 100.
  erd_pct_trialwise  SECONDARY/diagnostic: the mean over trials of the per-trial ratio. Reported because
                     §10g first specified it; it is a ratio of two noisy single-/three-segment estimates,
                     so it has heavy tails and is biased upward relative to the ratio of means. See the
                     §10g amendment in docs/decision_log.md.

Self-checks, all of which must pass: the Welch segment counts above; scipy's Welch reproduced by an
explicit manual segment average on a synthetic signal (the verification the project's Stage-5 PSD note
asks for); and the total first-in-mini-block count over all in-block trials matched against the
independent events.tsv-based count in stage5_window_overlap_summary.json.

Never overwrites. No value here depends on the Track-B peak-detection results.
"""
import argparse
import csv
import glob
import json
import os

import numpy as np
from scipy.io import loadmat
from scipy.signal import get_window, welch

N_SUBJECTS = 39
ROI = ('C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2')
BETA = (13.0, 30.0)
NPERSEG = 250                      # 0.5 s at 500 Hz (§10g)
NOVERLAP = 125                     # 50 %
N_SEG_EXPECTED = {250: 1, 500: 3}  # samples in the window -> Welch segments
COND_ORDER = ('F0', 'FS', '00', 'S0')


def psd_band(x, fs, band=BETA):
    """x: (n_channels, n_samples, n_trials) in uV - the layout stage5_export_trials_task.m writes for
    `base` (7 x 250 x n) and `act` (7 x 500 x n). Returns (n_trials,) band-average power in uV^2/Hz,
    ROI-averaged on linear power first, then averaged over the bins of `band` (13-30 Hz by default; the
    55-95 Hz control band of sec 10o-2 is passed explicitly, and nothing else about the estimator
    changes)."""
    nch, ns, ntr = x.shape
    assert ns in N_SEG_EXPECTED, f'unexpected window length {ns}'
    x = np.moveaxis(x, 2, 1)                                # -> (n_channels, n_trials, n_samples)
    f, p = welch(x.reshape(nch * ntr, ns), fs=fs, window='hann', nperseg=NPERSEG, noverlap=NOVERLAP,
                 nfft=NPERSEG, detrend='constant', scaling='density', average='mean', axis=-1)
    n_seg = (ns - NOVERLAP) // (NPERSEG - NOVERLAP)
    assert n_seg == N_SEG_EXPECTED[ns], f'{ns} samples gave {n_seg} segments'
    p = p.reshape(nch, ntr, f.size).mean(axis=0)            # ROI mean on linear power
    m = (f >= band[0]) & (f <= band[1])
    return p[:, m].mean(axis=1), f, m


def verify_welch(fs=500.0):
    """The Stage-5 PSD note asks for the segmentation to be verified, not asserted: reproduce scipy's
    Welch output for both window lengths by an explicit manual segment average on a synthetic signal."""
    rng = np.random.default_rng(12345)
    out = {}
    for ns in sorted(N_SEG_EXPECTED):
        x = rng.standard_normal(ns)
        f, p = welch(x, fs=fs, window='hann', nperseg=NPERSEG, noverlap=NOVERLAP, nfft=NPERSEG,
                     detrend='constant', scaling='density', average='mean')
        w = get_window('hann', NPERSEG)
        scale = 1.0 / (fs * (w * w).sum())
        starts = range(0, ns - NPERSEG + 1, NPERSEG - NOVERLAP)
        segs = []
        for a in starts:
            seg = x[a:a + NPERSEG]
            seg = seg - seg.mean()                           # detrend 'constant'
            sp = np.abs(np.fft.rfft(seg * w, n=NPERSEG)) ** 2 * scale
            sp[1:-1] *= 2.0                                  # one-sided, DC and Nyquist not doubled
            segs.append(sp)
        manual = np.mean(segs, axis=0)
        out[ns] = dict(n_segments_manual=len(segs), n_segments_formula=(ns - NOVERLAP) // (NPERSEG - NOVERLAP),
                       max_abs_rel_diff=float(np.max(np.abs(manual - p) / np.maximum(p, 1e-30))),
                       n_bins=int(f.size), bin_spacing_hz=float(f[1] - f[0]))
        assert out[ns]['n_segments_manual'] == N_SEG_EXPECTED[ns], f'{ns}: {len(segs)} segments'
        assert out[ns]['max_abs_rel_diff'] < 1e-10, f'{ns}: scipy vs manual {out[ns]["max_abs_rel_diff"]}'
    return out


def load_trials(path):
    m = loadmat(path)
    rec = dict(subject=str(m['subject'].ravel()[0]), fs=float(m['fs'].item()),
               roi=tuple(str(np.ravel(v)[0]) for v in m['roiLabels'].ravel()),
               cond_names=tuple(str(np.ravel(v)[0]) for v in m['condNames'].ravel()),
               excluded_D12=bool(m['excludedD12'].item()),
               frac_cond=np.ravel(m['fracCond']).astype(float),
               n_cond=np.ravel(m['nCond']).astype(int),
               n_kept_cond=np.ravel(m['nKeptCond']).astype(int))
    assert rec['roi'] == ROI, f"{rec['subject']}: ROI {rec['roi']}"
    assert rec['cond_names'] == COND_ORDER, f"{rec['subject']}: conditions {rec['cond_names']}"
    for k, name in (('trialCond', 'cond'), ('trialBlock', 'block'),
                    ('trialFirstInMiniblock', 'first_mb'), ('trialOutsideBase', 'out_base'),
                    ('trialOutsideAct', 'out_act'), ('trialRejBase', 'rej_base'),
                    ('trialRejAct', 'rej_act'), ('trialUsable', 'usable'),
                    ('trialExported', 'exported'), ('trialLatency', 'latency')):
        rec[name] = np.ravel(m[k]).astype(float)
    for k in ('base', 'act'):
        a = np.asarray(m[k], dtype=np.float64)
        rec[k] = a[:, :, None] if a.ndim == 2 else a
    n_usable = int(rec['usable'].sum())
    if not rec['excluded_D12']:
        assert rec['base'].shape[2] == n_usable and rec['act'].shape[2] == n_usable, \
            f"{rec['subject']}: exported {rec['base'].shape[2]}/{rec['act'].shape[2]} vs usable {n_usable}"
    return rec


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--trial-dir', required=True)
    ap.add_argument('--overlap-summary', required=True,
                    help='stage5_window_overlap_summary.json, for the independent first-in-mini-block count')
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_erd_per_trial.csv', 'stage5_erd_per_subject_condition.csv', 'stage5_erd_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')
    files = sorted(glob.glob(os.path.join(args.trial_dir, 'sub-*_msit_trials.mat')))
    if len(files) != N_SUBJECTS:
        raise SystemExit(f'{len(files)} trial files found, {N_SUBJECTS} expected')
    welch_check = verify_welch()
    os.makedirs(args.out_dir, exist_ok=True)

    per_trial, per_cell, freqs_used = [], [], None
    n_fimb_total = 0
    for path in files:
        rec = load_trials(path)
        sub, fs = rec['subject'], rec['fs']
        n_fimb_total += int(rec['first_mb'].sum())
        pb = pa = None
        if not rec['excluded_D12'] and rec['base'].shape[2]:
            pb, fb, mb = psd_band(rec['base'], fs)
            pa, fa, ma = psd_band(rec['act'], fs)
            assert np.allclose(fb, fa) and np.array_equal(mb, ma)
            freqs_used = [float(v) for v in fb[mb]]
        sub_rows = []
        for i in range(rec['cond'].size):
            j = int(rec['exported'][i])                      # 1-based index into base/act, 0 if not exported
            row = dict(subject=sub, trial=i + 1, condition=COND_ORDER[int(rec['cond'][i]) - 1],
                       block=int(rec['block'][i]), first_in_miniblock=int(rec['first_mb'][i]),
                       outside_baseline=int(rec['out_base'][i]), outside_active=int(rec['out_act'][i]),
                       rejected_baseline=int(rec['rej_base'][i]), rejected_active=int(rec['rej_act'][i]),
                       usable=int(rec['usable'][i]), baseline_power='', active_power='', erd_pct='')
            if j and pb is not None:
                b, a = float(pb[j - 1]), float(pa[j - 1])
                row.update(baseline_power=b, active_power=a,
                           erd_pct=(b - a) / b * 100.0 if b > 0 else '')
            sub_rows.append(row)
        per_trial += sub_rows

        for cname in COND_ORDER:
            for cls, sel in (('all', None), ('first', 1), ('later', 0)):
                sel_rows = [r for r in sub_rows
                            if r['condition'] == cname and r['usable'] == 1
                            and r['baseline_power'] != ''
                            and (sel is None or r['first_in_miniblock'] == sel)]
                n = len(sel_rows)
                cell = dict(subject=sub, condition=cname, miniblock_class=cls, n_trials=n,
                            excluded_D12=int(rec['excluded_D12']))
                if n:
                    b = np.array([r['baseline_power'] for r in sel_rows], dtype=float)
                    a = np.array([r['active_power'] for r in sel_rows], dtype=float)
                    e = np.array([r['erd_pct'] for r in sel_rows], dtype=float)
                    cell.update(baseline_power_mean=float(b.mean()), active_power_mean=float(a.mean()),
                                erd_pct=float((b.mean() - a.mean()) / b.mean() * 100.0),
                                erd_pct_trialwise=float(e.mean()),
                                erd_pct_trialwise_median=float(np.median(e)))
                else:
                    cell.update(baseline_power_mean='', active_power_mean='', erd_pct='',
                                erd_pct_trialwise='', erd_pct_trialwise_median='')
                per_cell.append(cell)
        print(f"{sub}  usable {int(rec['usable'].sum())}  excluded {int(rec['excluded_D12'])}  "
              f"per-condition kept {list(rec['n_kept_cond'])}", flush=True)

    with open(args.overlap_summary) as fh:
        expected_fimb = int(json.load(fh)['n_first_in_miniblock'])
    if n_fimb_total != expected_fimb:
        raise SystemExit(f'first-in-mini-block count {n_fimb_total} from the bundles != {expected_fimb} '
                         f'from events.tsv: the S 11 / block-start rule does not reproduce the S0-3 count')

    for key, rows in (('stage5_erd_per_trial.csv', per_trial),
                      ('stage5_erd_per_subject_condition.csv', per_cell)):
        with open(names[key], 'w', newline='') as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    with open(names['stage5_erd_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_erd_by_condition.py', cond='msit', roi=ROI, beta_band=BETA,
                       nperseg=NPERSEG, noverlap=NOVERLAP, nfft=NPERSEG, window='hann',
                       detrend='constant', scaling='density', average='mean',
                       resolution_hz=500.0 / NPERSEG, bin_spacing_hz=500.0 / NPERSEG,
                       zero_padded=False, band_bins_hz=freqs_used,
                       segments_per_window=N_SEG_EXPECTED, welch_verification=welch_check,
                       primary_estimator='erd_pct (ratio of trial-averaged powers, classic ERD)',
                       secondary_estimator='erd_pct_trialwise (mean of per-trial ratios)',
                       n_subjects=len(files), n_trials_rows=len(per_trial),
                       first_in_miniblock_total=n_fimb_total,
                       first_in_miniblock_expected_from_events_tsv=expected_fimb,
                       n_excluded_D12=sum(1 for c in per_cell if c['excluded_D12']
                                          and c['condition'] == COND_ORDER[0]
                                          and c['miniblock_class'] == 'all')), fh, indent=2)
    print(f"\nWelch verification: {json.dumps(welch_check)}")
    print(f"first-in-mini-block total {n_fimb_total} == events.tsv count {expected_fimb}  OK")
    print('wrote:', ', '.join(os.path.basename(p) for p in names.values()))


if __name__ == '__main__':
    main()
