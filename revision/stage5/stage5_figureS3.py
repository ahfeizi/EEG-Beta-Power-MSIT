"""Stage 5: Supplementary Figure S3 - pre-stimulus beta power by condition and trial class.

    python stage5_figureS3.py --cells <outRoot>/stage5/erd/stage5_erd_per_subject_condition.csv \
        --out <path>/figureS3_v2.png

No new analysis: it plots `baseline_power_mean` from the committed §10l cell table.

This replaces the earlier supplementary figure, which had three content errors rather than cosmetic ones
(decision log §10q and the audit):
  1. it pooled every trial, so it could not separate the trials in which the upcoming condition was
     unpredictable from those in which it was not - the distinction the mini-blocked design forces;
  2. its x-axis label asserted a four-level conflict ordering `00 < S0 < F0 < FS` as established fact,
     which §10q showed is misattributed: the ordering holds on reaction times in an independent sample
     but not on accuracy, and the pre-registered analysis therefore uses three levels;
  3. its three panel x-labels overlapped at the panel boundaries (audit item #31).

What this one does instead:
  - **splits by trial class**, first-in-mini-block (where the condition is unpredictable, the class the
    primary analysis uses) against later-in-mini-block, instead of pooling;
  - **asserts no ordering between the two single-conflict conditions.** The conditions are displayed in
    the conventional order and annotated only with the number of conflict sources each carries - 0, 1, 1
    and 2 - which is the three-level structure §10k licensed and nothing more;
  - uses one shared x-label for the figure, so no label can collide with its neighbour.

Per-participant grey lines with the group median and interquartile range, matching Figure 3 rather than
the earlier mean +- SEM, because the distributions are heavy-tailed.

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

COND_ORDER = ('00', 'S0', 'F0', 'FS')
N_CONFLICT = {'00': 0, 'S0': 1, 'F0': 1, 'FS': 2}
CLASSES = [('first', 'First in mini-block\n(upcoming condition unpredictable)'),
           ('later', 'Later in mini-block\n(upcoming condition predictable)')]
METRIC = 'baseline_power_mean'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cells', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    if os.path.exists(args.out):
        raise SystemExit(f'output exists, not overwritten: {args.out}')

    with open(args.cells, newline='') as fh:
        rows = list(csv.DictReader(fh))
    data = {}
    for r in rows:
        if r['condition'] not in COND_ORDER:
            continue
        data.setdefault(r['miniblock_class'], {}).setdefault(r['subject'], {})[r['condition']] = \
            float(r[METRIC])

    fig, axes = plt.subplots(1, 2, figsize=(10.2, 4.9), sharey=True)
    rendered = []
    for ci, (cls, label) in enumerate(CLASSES):
        ax = axes[ci]
        subs = sorted(s for s, d in data[cls].items() if len(d) == len(COND_ORDER))
        m = np.array([[data[cls][s][c] for c in COND_ORDER] for s in subs])
        x = np.arange(len(COND_ORDER))
        for row in m:
            ax.plot(x, row, color='0.74', lw=0.7, zorder=1)
        for j in range(len(COND_ORDER)):
            q1, md, q3 = np.percentile(m[:, j], [25, 50, 75])
            ax.plot([x[j] + 0.16, x[j] + 0.16], [q1, q3], color='k', lw=1.7, zorder=3,
                    solid_capstyle='butt')
            ax.plot([x[j] + 0.16], [md], 'o', ms=5.5, color='k', zorder=4)
            ax.plot(np.full(m.shape[0], x[j]), m[:, j], 'o', ms=3.0, color='#3B6EA8', alpha=0.7,
                    zorder=2)
        ax.set_yscale('log')
        ax.set_xticks(x)
        ax.set_xticklabels([f'{c}\n({N_CONFLICT[c]})' for c in COND_ORDER], fontsize=9)
        ax.set_xlim(-0.45, len(COND_ORDER) - 0.35)
        ax.set_title(f'{label}\nn = {len(subs)}', fontsize=10)
        if ci == 0:
            ax.set_ylabel('Pre-stimulus beta power,\n13–30 Hz (µV²/Hz, log scale)', fontsize=9.5)
        ax.tick_params(labelsize=8.5)
        for sp in ('top', 'right'):
            ax.spines[sp].set_visible(False)
        rendered.append(dict(panel=ci + 1, miniblock_class=cls, n=len(subs),
                             conditions=list(COND_ORDER),
                             medians={c: float(np.median(m[:, j])) for j, c in enumerate(COND_ORDER)}))

    fig.supxlabel('MSIT+ condition, with the number of conflict sources in parentheses '
                  '(no ordering is asserted between the two single-conflict conditions)', fontsize=9.5)
    fig.suptitle('Pre-stimulus beta power by condition and trial class, seven-channel ROI',
                 fontsize=11.5)
    fig.tight_layout(rect=(0, 0.03, 1, 0.94))
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    fig.savefig(args.out, dpi=200)
    plt.close(fig)

    meta = os.path.splitext(args.out)[0] + '_panels.json'
    with open(meta, 'w') as fh:
        json.dump(dict(script='stage5_figureS3.py', metric=METRIC,
                       layout='one row, two panels: left = first in mini-block, right = later',
                       ordering_asserted='none between S0 and F0; conditions annotated with the number '
                                         'of conflict sources only',
                       panels=rendered), fh, indent=2)

    print('rendered panels (check the caption against this, not against the intent):')
    for p in rendered:
        meds = '  '.join(f"{c} {p['medians'][c]:.4f}" for c in COND_ORDER)
        print(f"  panel {p['panel']}: {p['miniblock_class']:6s} n={p['n']}   {meds}")
    print(f"\nwrote: {os.path.basename(args.out)}, {os.path.basename(meta)}")


if __name__ == '__main__':
    main()
