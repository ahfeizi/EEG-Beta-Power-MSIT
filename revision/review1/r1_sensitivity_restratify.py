"""Review round 1, Item 3A: detection probability by CF, BW and PW from the EXISTING Stage-4 injected
simulations (decision log §11c). Reads sim_rough/sim_injected.csv (390,000 rows, §7b) and never rewrites it.

    python r1_sensitivity_restratify.py --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/sens_restrat

Detection = max_beta_pw >= the subject's own p95: the pipeline's rule, which counts ANY qualifying beta peak,
whether or not near the injected CF (§4 Q7). A CF-matched rate cannot be computed from this file (it stores
only the maximum beta PW), which is what 3B is for.
Strata: CF 14 +/- 1, 18 +/- 1, 22 +/- 1, 26 +/- 1, 29 +/- 1 Hz (the last = [28, 30]); BW [1, 3), [3, 5),
[5, 8]; the ten PW levels. Pooled over all 39 subjects and over the 14 no_peak subjects; Clopper-Pearson 95 %.
"""
import argparse
import json
import os

import numpy as np

import r1_common as rc

CF_CENTRES = (14.0, 18.0, 22.0, 26.0, 29.0)
CF_HALF = 1.0
BW_BINS = ((1.0, 3.0), (3.0, 5.0), (5.0, 8.0))       # [lo, hi); the last bin is closed at 8


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--stage4', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    inputs = dict(sim_injected=os.path.join(args.stage4, 'sim_rough', 'sim_injected.csv'),
                  thresholds=os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject.json'),
                  peaks_primary=os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv'))
    outs = {k: os.path.join(args.out_dir, k) for k in
            ('r1_sens_restrat_curve.csv', 'r1_sens_restrat_by_pw.csv', 'r1_sens_restrat_summary.json')}
    rc.refuse_existing(outs.values())
    os.makedirs(args.out_dir, exist_ok=True)

    thr = rc.read_thresholds(inputs['thresholds'])
    cls = rc.read_classes(inputs['peaks_primary'])
    rows = rc.read_csv(inputs['sim_injected'])
    assert len(rows) == 390000, f'{len(rows)} rows, 390000 expected (§7b)'
    subj = np.array([r['subject'] for r in rows])
    cf = np.array([float(r['cf_injected']) for r in rows])
    bw = np.array([float(r['bw_injected']) for r in rows])
    pw = np.array([float(r['level_pw']) for r in rows])
    det = np.array([float(r['max_beta_pw']) >= thr[r['subject']] for r in rows])
    nopk = np.array([cls[s] == 'no_peak' for s in subj])
    assert len(set(subj[nopk])) == 14
    levels = sorted(set(pw.tolist()))

    # check: the unstratified pooled curve must reproduce §7b's per-subject-threshold power curve
    check = {f'{lv:.2f}': float(det[np.isclose(pw, lv)].mean()) for lv in levels}

    out, bypw = [], []
    for group, gm in (('all39', np.ones(len(rows), bool)), ('no_peak14', nopk)):
        for lv in levels:
            m = gm & np.isclose(pw, lv)
            lo, hi = rc.cp_ci(det[m].sum(), m.sum())
            bypw.append(dict(group=group, pw=lv, n=int(m.sum()), p_detect=float(det[m].mean()), ci_low=lo, ci_high=hi))
        for c in CF_CENTRES:
            for b0, b1 in BW_BINS:
                mb = (bw >= b0) & ((bw < b1) if b1 < 8.0 else (bw <= b1))
                for lv in levels:
                    m = gm & (np.abs(cf - c) <= CF_HALF) & mb & np.isclose(pw, lv)
                    k, n = int(det[m].sum()), int(m.sum())
                    lo, hi = rc.cp_ci(k, n)
                    out.append(dict(group=group, cf_centre=c, cf_lo=c - CF_HALF, cf_hi=min(c + CF_HALF, 30.0),
                                    bw_lo=b0, bw_hi=b1, pw=lv, pct_above_aperiodic=100 * (10 ** lv - 1),
                                    n=n, n_detected=k, p_detect=k / n if n else float('nan'),
                                    ci_low=lo, ci_high=hi))
    rc.write_csv(outs['r1_sens_restrat_curve.csv'], out)
    rc.write_csv(outs['r1_sens_restrat_by_pw.csv'], bypw)
    with open(outs['r1_sens_restrat_summary.json'], 'w') as fh:
        json.dump(dict(rule='decision log §11c (3A)', detection='max_beta_pw >= own p95 (any beta peak)',
                       n_rows=len(rows), cf_centres=CF_CENTRES, cf_half_width=CF_HALF, bw_bins=BW_BINS,
                       no_peak_subjects=sorted(set(subj[nopk])), unstratified_check_all39=check,
                       provenance=rc.provenance(__file__, inputs)), fh, indent=2)
    print(json.dumps(check))


if __name__ == '__main__':
    main()
