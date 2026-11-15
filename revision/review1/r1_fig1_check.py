"""Review round 1 (decision log §11i): does each no_peak participant's spectrum rise or fall monotonically
through 13-30 Hz, as the Figure 1 caption says?

    python r1_fig1_check.py --curves <outRoot>/review1/fig1_check/r1_fig1_curves.csv \
        --roi-dir <eegOutRoot>/stage4/roi --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/fig1_check

On the bins with 13 <= f <= 30 Hz, counts interior strict local maxima (a bin greater than both neighbours;
neighbours may lie just outside the band) and sign changes of the first difference.
  primary    the curves Figure 1 plots (r1_fig1_curves.m: v1 data, all-channel mean, linear log-log detrend
             with 7-13 Hz masked)
  secondary  the Stage-4 ROI Welch PSD minus its fooof fixed aperiodic-only fit (the spectrum the criterion saw)
Rule: the caption is correct as written only if all 14 no_peak participants have zero local maxima in the
primary curves.
"""
import argparse
import json
import os

import numpy as np

import r1_common as rc
from r1_common import core

BAND = (13.0, 30.0)


def counts(f, y):
    f, y = np.asarray(f, float), np.asarray(y, float)
    o = np.argsort(f)
    f, y = f[o], y[o]
    idx = np.flatnonzero((f >= BAND[0]) & (f <= BAND[1]))
    n_max, heights = 0, []
    for i in idx:
        if 0 < i < len(y) - 1 and y[i] > y[i - 1] and y[i] > y[i + 1]:
            n_max += 1
            heights.append(float(y[i] - max(y[i - 1], y[i + 1])))
    d = np.sign(np.diff(y[idx]))
    d = d[d != 0]
    return n_max, int(np.sum(d[1:] != d[:-1])), (max(heights) if heights else 0.0), float(f[idx[0]]), \
        float(f[idx[-1]]), len(idx)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for a in ('--curves', '--roi-dir', '--stage4', '--out-dir'):
        ap.add_argument(a, required=True)
    args = ap.parse_args()
    out_csv = os.path.join(args.out_dir, 'r1_fig1_check.csv')
    out_json = os.path.join(args.out_dir, 'r1_fig1_check_summary.json')
    rc.refuse_existing([out_csv, out_json])
    peaks = os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv')
    cls = rc.read_classes(peaks)

    cur = {}
    for r in rc.read_csv(args.curves):
        cur.setdefault(r['subject'], ([], []))
        cur[r['subject']][0].append(float(r['f']))
        cur[r['subject']][1].append(float(r['detr']))

    rows = []
    for s in sorted(cls):
        c1 = counts(*cur[s])
        rec = core.load_roi(os.path.join(args.roi_dir, f'{s}_rest_roi.mat'))
        f, psd = core.welch_runs(rec['runs'], rec['fs'])
        ap_ = core.aperiodic_only(f, psd)
        c2 = counts(ap_['freqs'], ap_['logpow'] - ap_['curve'])
        rows.append(dict(subject=s, class_p95=cls[s],
                         fig1_n_local_max=c1[0], fig1_n_sign_changes=c1[1], fig1_max_bump_height=c1[2],
                         fig1_band_bins=f'{c1[3]}-{c1[4]} ({c1[5]})',
                         stage4_n_local_max=c2[0], stage4_n_sign_changes=c2[1], stage4_max_bump_height=c2[2],
                         stage4_band_bins=f'{c2[3]}-{c2[4]} ({c2[5]})'))
    rc.write_csv(out_csv, rows)

    def grp(c, key):
        v = [r[key] for r in rows if r['class_p95'] == c]
        return dict(n=len(v), n_zero=sum(x == 0 for x in v), min=min(v), median=float(np.median(v)), max=max(v))

    np14 = [r for r in rows if r['class_p95'] == 'no_peak']
    summary = dict(
        rule='decision log §11i', n_no_peak=len(np14),
        caption_correct_as_written=all(r['fig1_n_local_max'] == 0 for r in np14),
        no_peak_with_local_max_fig1=[(r['subject'], r['fig1_n_local_max']) for r in np14 if r['fig1_n_local_max']],
        no_peak_with_local_max_stage4=[(r['subject'], r['stage4_n_local_max']) for r in np14 if r['stage4_n_local_max']],
        fig1_local_max={c: grp(c, 'fig1_n_local_max') for c in ('no_peak', 'peak')},
        stage4_local_max={c: grp(c, 'stage4_n_local_max') for c in ('no_peak', 'peak')},
        provenance=rc.provenance(__file__, dict(curves=args.curves, peaks_primary=peaks)))
    with open(out_json, 'w') as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps({k: v for k, v in summary.items() if k != 'provenance'}, indent=1))


if __name__ == '__main__':
    main()
