"""Stage 5: Figure 3 - rest-to-task power change in the beta and control bands (decision log §10p-2).

    python stage5_figure3.py --per-subject <outRoot>/stage5/rest_vs_task/stage5_rest_vs_task_per_subject.csv \
        --tests <outRoot>/stage5/rest_vs_task/stage5_rest_vs_task_tests.csv --out <path>/figure3_v2.png

No new analysis: this is a plotting job against the two committed tables from
stage5_rest_vs_task_matched.py. Every number drawn is read from them.

LAYOUT, fixed and not data-dependent (Amirhossein, 2026-11-14). The previous figure alternated band
within channel while its caption described a "top row / bottom row" split by band, so a reader following
the caption read three of six panels as the wrong band (audit item #23). This one cannot do that:

    rows    = BAND, top = beta 13-30 Hz, bottom = control 55-95 Hz
    columns = COMPARISON, left = A (pre-stimulus vs rest), middle = B (control window vs rest),
              right = C (pre-stimulus vs control window)

Each panel shows the two windows of its comparison as paired points on a LOG power axis, one grey line
per participant (n = 39), with the group median and interquartile range drawn beside each window. On a
log axis the vertical displacement of a line IS that participant's log ratio, which is the quantity the
statistics are computed on. The ROI average is plotted, never individual channels.

Exact statistics - Holm-corrected p, Bayes factor, equivalence verdict - are deliberately NOT printed
inside the panels; they live in Table 2 and the caption. Each panel is annotated only with its
geometric-mean percent change, which is the quantity the panel depicts.

The script re-reads the figure it has just written and prints the rendered panel order, so the caption
can be checked against what was actually drawn rather than against what was intended.

Never overwrites.
"""
import argparse
import csv
import json
import os

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt                      # noqa: E402
import numpy as np                                   # noqa: E402

BANDS = [('beta_13_30', 'Beta band, 13–30 Hz'),
         ('control_55_95', 'Control band, 55–95 Hz')]
COMPARISONS = [('A', 'A_taskpre_vs_rest', ('rest', 'taskpre'), ('Rest', 'Task\npre-stimulus')),
               ('B', 'B_control_vs_rest', ('rest', 'control'), ('Rest', 'Within-task\ncontrol')),
               ('C', 'C_taskpre_vs_control', ('control', 'taskpre'), ('Within-task\ncontrol',
                                                                      'Task\npre-stimulus'))]
ESTIMATOR = 'mean'           # the pre-specified aggregator; the robust ones are reported in the text


def read_csv(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--per-subject', required=True)
    ap.add_argument('--tests', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')

    per = read_csv(args.per_subject)
    tests = read_csv(args.tests)
    n = len(per)
    assert n == 39, f'{n} participants in the per-subject table, 39 expected'

    def stat(band, comp):
        r = [x for x in tests if x['band'] == band and x['comparison'] == comp
             and x['estimator'] == ESTIMATOR]
        assert len(r) == 1, (band, comp, len(r))
        return r[0]

    fig, axes = plt.subplots(2, 3, figsize=(11.0, 7.4))
    rendered = []
    for ri, (band, band_label) in enumerate(BANDS):
        for ci, (tag, comp, (src_a, src_b), (lab_a, lab_b)) in enumerate(COMPARISONS):
            ax = axes[ri, ci]
            a = np.array([float(x[f'{src_a}_{band}']) for x in per])
            b = np.array([float(x[f'{src_b}_{band}']) for x in per])
            for ya, yb in zip(a, b):
                ax.plot([0, 1], [ya, yb], color='0.72', lw=0.7, zorder=1)
            ax.plot(np.zeros(n), a, 'o', ms=3.2, color='#3B6EA8', alpha=0.75, zorder=2)
            ax.plot(np.ones(n), b, 'o', ms=3.2, color='#C0502A', alpha=0.75, zorder=2)
            for x, v in ((0, a), (1, b)):
                q1, md, q3 = np.percentile(v, [25, 50, 75])
                ax.plot([x + 0.18, x + 0.18], [q1, q3], color='k', lw=1.6, zorder=3,
                        solid_capstyle='butt')
                ax.plot([x + 0.18], [md], 'o', ms=5.5, color='k', zorder=4)
            ax.set_yscale('log')
            ax.set_xlim(-0.35, 1.45)
            ax.set_xticks([0, 1])
            ax.set_xticklabels([lab_a, lab_b], fontsize=8.5)
            s = stat(band, comp)
            pct = float(s['geom_pct_change'])
            ax.set_title(f'{tag}   {pct:+.1f} %', fontsize=10.5, pad=6)
            if ci == 0:
                ax.set_ylabel(f'{band_label}\npower (µV²/Hz, log scale)', fontsize=9)
            ax.tick_params(labelsize=8)
            for sp in ('top', 'right'):
                ax.spines[sp].set_visible(False)
            rendered.append(dict(row=ri + 1, col=ci + 1, band=band, band_label=band_label,
                                 comparison=tag, comparison_key=comp,
                                 left_window=src_a, right_window=src_b,
                                 geom_pct_change=pct, p_holm=float(s['p_holm']),
                                 bf01=float(s['bf01']), equivalent=int(s['equivalent'])))

    fig.suptitle('Rest-to-task power change, seven-channel sensorimotor ROI (n = 39), '
                 'all windows 500 ms, one estimator', fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.955))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    fig.savefig(args.out, dpi=200)
    plt.close(fig)

    meta = os.path.splitext(args.out)[0] + '_panels.json'
    with open(meta, 'w') as fh:
        json.dump(dict(script='stage5_figure3.py', n=n, estimator=ESTIMATOR,
                       layout='rows = band (top beta, bottom control); columns = comparison (A, B, C)',
                       panels=rendered), fh, indent=2)

    print('rendered panel order (check the caption against this, not against the intent):')
    for p in rendered:
        print(f"  row {p['row']} col {p['col']}: {p['band_label']:24s} {p['comparison']}  "
              f"{p['left_window']:8s} -> {p['right_window']:8s}  {p['geom_pct_change']:+6.1f} %  "
              f"p_holm {p['p_holm']:.3g}  BF01 {p['bf01']:.3f}  equivalent {p['equivalent']}")
    print(f'\nwrote: {os.path.basename(args.out)}, {os.path.basename(meta)}')


if __name__ == '__main__':
    main()
