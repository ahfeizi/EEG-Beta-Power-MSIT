"""Review round 1: §10l core statistics without the 17 trials Track A mislabels as first-in-mini-block
(decision log §11d-3).

    python r1_erd_sensitivity_flag17.py --erd-dir <outRoot>/stage5/erd \
        --behaviour-summary <outRoot>/review1/behaviour_next_stimulus/r1_behaviour_summary.json \
        --out-dir <outRoot>/review1/erd_flag17

1. Gate: the subject x condition x class cells rebuilt from stage5_erd_per_trial.csv by the §10g/§10l rule
   (usable trials with a power value; erd_pct = ratio of the trial-averaged powers; erd_pct_trialwise = mean
   and median of the per-trial ratios) must reproduce stage5_erd_per_subject_condition.csv to 1e-9 relative.
2. The 17 trials (subject, trial) listed in the behaviour summary are REMOVED and the cells rebuilt.
3. revision/stage5/stage5_erd_stats.py is run unchanged on the new cells.
4. Verdicts are compared with the published §10l outputs under the §11d-3 rule:
   (a) Friedman and three-level Page's L verdicts at alpha = .05 unchanged, every metric x class;
   (b) the set of Holm-significant pairs unchanged, every metric x class;
   (c) |delta Kendall's W| < 0.01 for erd_pct in every class.
Never overwrites; the published §10l files are only read.
"""
import argparse
import json
import os
import subprocess
import sys

import numpy as np

import r1_common as rc

STATS = os.path.join(rc.REPO, 'revision', 'stage5', 'stage5_erd_stats.py')
COND_ORDER = ('F0', 'FS', '00', 'S0')
CLASSES = (('all', None), ('first', 1), ('later', 0))
ALPHA = 0.05
W_TOL = 0.01
NUM = ('baseline_power_mean', 'active_power_mean', 'erd_pct', 'erd_pct_trialwise', 'erd_pct_trialwise_median')


def build_cells(trials, drop=frozenset()):
    by = {}
    for r in trials:
        if (r['subject'], int(r['trial'])) in drop:
            continue
        if r['usable'] != '1' or r['baseline_power'] == '':
            continue
        by.setdefault(r['subject'], []).append(r)
    cells = []
    for s in sorted({r['subject'] for r in trials}):
        rows = by.get(s, [])
        for c in COND_ORDER:
            for cls, sel in CLASSES:
                sr = [r for r in rows if r['condition'] == c and (sel is None or int(r['first_in_miniblock']) == sel)]
                cell = dict(subject=s, condition=c, miniblock_class=cls, n_trials=len(sr), excluded_D12=0)
                if sr:
                    b = np.array([float(r['baseline_power']) for r in sr])
                    a = np.array([float(r['active_power']) for r in sr])
                    e = np.array([float(r['erd_pct']) for r in sr])
                    cell.update(baseline_power_mean=float(b.mean()), active_power_mean=float(a.mean()),
                                erd_pct=float((b.mean() - a.mean()) / b.mean() * 100.0),
                                erd_pct_trialwise=float(e.mean()), erd_pct_trialwise_median=float(np.median(e)))
                else:
                    cell.update({k: '' for k in NUM})
                cells.append(cell)
    return cells


def verdicts(d):
    om = {(r['metric'], r['miniblock_class']): r for r in rc.read_csv(os.path.join(d, 'stage5_erd_stats_omnibus.csv'))}
    tr = {(r['metric'], r['miniblock_class']): r for r in rc.read_csv(os.path.join(d, 'stage5_erd_stats_trend.csv'))}
    pw = {}
    for r in rc.read_csv(os.path.join(d, 'stage5_erd_stats_pairwise.csv')):
        pw.setdefault((r['metric'], r['miniblock_class']), set())
        if r['p_holm'] not in ('', 'nan') and float(r['p_holm']) < ALPHA:
            pw[(r['metric'], r['miniblock_class'])].add(r['pair'])
    return om, tr, pw


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--erd-dir', required=True)
    ap.add_argument('--behaviour-summary', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    out_cells = os.path.join(args.out_dir, 'stage5_erd_per_subject_condition_minus17.csv')
    out_cmp = os.path.join(args.out_dir, 'r1_erd_flag17_comparison.csv')
    out_sum = os.path.join(args.out_dir, 'r1_erd_flag17_summary.json')
    stats_dir = os.path.join(args.out_dir, 'stats')
    rc.refuse_existing([out_cells, out_cmp, out_sum, stats_dir])
    os.makedirs(args.out_dir, exist_ok=True)
    inputs = dict(per_trial=os.path.join(args.erd_dir, 'stage5_erd_per_trial.csv'),
                  cells=os.path.join(args.erd_dir, 'stage5_erd_per_subject_condition.csv'),
                  behaviour_summary=args.behaviour_summary, stage5_erd_stats=STATS)

    trials = rc.read_csv(inputs['per_trial'])
    with open(args.behaviour_summary) as fh:
        drop = frozenset((s, int(t)) for s, t, _, _ in json.load(fh)['flag_differences'])
    assert len(drop) == 17, f'{len(drop)} trials listed, 17 expected (§11d-2)'
    flagged = {(r['subject'], int(r['trial'])): r for r in trials if (r['subject'], int(r['trial'])) in drop}
    assert len(flagged) == 17 and all(r['first_in_miniblock'] == '1' for r in flagged.values())
    n_drop_usable = sum(r['usable'] == '1' for r in flagged.values())

    # 1. gate: reproduce the published cells exactly
    orig = {(r['subject'], r['condition'], r['miniblock_class']): r for r in rc.read_csv(inputs['cells'])}
    rebuilt = build_cells(trials)
    assert len(rebuilt) == len(orig)
    worst = 0.0
    for c in rebuilt:
        o = orig[(c['subject'], c['condition'], c['miniblock_class'])]
        assert int(o['n_trials']) == c['n_trials'], f'{c["subject"]} {c["condition"]} n_trials'
        for k in NUM:
            if c[k] == '' or o[k] == '':
                assert c[k] == '' and o[k] == '', f'{c["subject"]} {k} missing on one side'
                continue
            worst = max(worst, abs(c[k] - float(o[k])) / max(abs(float(o[k])), 1e-300))
    assert worst <= 1e-9, f'gate failed: max relative difference {worst}'

    # 2-3. without the 17, then the unchanged stats script
    cells = build_cells(trials, drop)
    rc.write_csv(out_cells, cells)
    subprocess.run([sys.executable, STATS, '--cells', out_cells, '--out-dir', stats_dir], check=True)

    # 4. compare
    om0, tr0, pw0 = verdicts(args.erd_dir)
    om1, tr1, pw1 = verdicts(stats_dir)
    cmp_rows, fails = [], []
    for key in sorted(om0):
        m, cls = key
        f0, f1 = float(om0[key]['friedman_p']), float(om1[key]['friedman_p'])
        l0, l1 = float(tr0[key]['page_p']), float(tr1[key]['page_p'])
        w0, w1 = float(om0[key]['kendall_w']), float(om1[key]['kendall_w'])
        row = dict(metric=m, miniblock_class=cls, n0=om0[key]['n_subjects'], n1=om1[key]['n_subjects'],
                   friedman_p_published=f0, friedman_p_minus17=f1, kendall_w_published=w0, kendall_w_minus17=w1,
                   delta_w=w1 - w0, page_p_published=l0, page_p_minus17=l1,
                   holm_sig_pairs_published=';'.join(sorted(pw0.get(key, ()))),
                   holm_sig_pairs_minus17=';'.join(sorted(pw1.get(key, ()))))
        row['a_verdicts_same'] = int((f0 < ALPHA) == (f1 < ALPHA) and (l0 < ALPHA) == (l1 < ALPHA))
        row['b_pairs_same'] = int(pw0.get(key, set()) == pw1.get(key, set()))
        row['c_w_ok'] = int(m != 'erd_pct' or abs(w1 - w0) < W_TOL)
        if not (row['a_verdicts_same'] and row['b_pairs_same'] and row['c_w_ok']):
            fails.append(key)
        cmp_rows.append(row)
    rc.write_csv(out_cmp, cmp_rows)
    summary = dict(rule='decision log §11d-3', gate_max_relative_difference=worst, n_trials_removed=17,
                   n_removed_that_were_usable=n_drop_usable, removed=sorted(drop),
                   negligible=not fails, failing_metric_class=fails,
                   provenance=rc.provenance(__file__, inputs))
    with open(out_sum, 'w') as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps({k: v for k, v in summary.items() if k not in ('provenance', 'removed')}, indent=1))


if __name__ == '__main__':
    main()
