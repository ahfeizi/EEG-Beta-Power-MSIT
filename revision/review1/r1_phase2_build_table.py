"""Review round 1, Phase 2: the real trial table for the mixed models (decision log §11m).

    python r1_phase2_build_table.py --erd <outRoot>/stage5/erd/stage5_erd_per_trial.csv \
        --behaviour <outRoot>/review1/behaviour_next_stimulus/r1_behaviour_trials.csv \
        --raw <bidsRoot> --out <outRoot>/review1/phase2_real/r1_phase2_trials.csv

Joins Track A's per-trial band powers to the behavioural trial table on (subject, trial), adds mb_pos (position
since the last S 10 / S 11 / S 12 marker over all events.tsv stimuli) and the set memberships of §11m. Stops on any
mismatch. Reads only CSV/TSV text files. Never overwrites.
"""
import argparse
import csv
import json
import os

import r1_common as rc

EV = {'S 5', 'S 6', 'S 7', 'S 8'}
MARKS = {'S 10', 'S 11', 'S 12'}


def norm(s):
    return ' '.join(s.split())


def mb_positions(path):
    """{onset in ms: position since the last marker (1-based)} over every stimulus of the events.tsv."""
    out, pos = {}, 0
    with open(path, encoding='latin1') as fh:
        for r in csv.DictReader(fh, delimiter='\t'):
            t = norm(r['event_type'])
            if t in MARKS:
                pos = 0
            elif t in EV:
                pos += 1
                out[round(float(r['onset']) * 1000)] = pos
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for a in ('--erd', '--behaviour', '--raw', '--out'):
        ap.add_argument(a, required=True)
    args = ap.parse_args()
    meta_path = os.path.splitext(args.out)[0] + '_meta.json'
    rc.refuse_existing([args.out, meta_path])
    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    A = {(r['subject'], r['trial']): r for r in rc.read_csv(args.erd)}
    B = {(r['subject'], r['trial']): r for r in rc.read_csv(args.behaviour)}
    assert len(A) == len(B) == 15492 and set(A) == set(B), 'trial keys differ'
    rows, mbcache = [], {}
    for k in sorted(B, key=lambda k: (k[0], int(k[1]))):
        a, b = A[k], B[k]
        assert a['condition'] == b['condition'] and a['usable'] == b['eeg_usable'], f'{k}: mismatch'
        s = k[0]
        if s not in mbcache:
            mbcache[s] = mb_positions(os.path.join(args.raw, s, 'eeg', f'{s}_task-msit_events.tsv'))
        mbp = mbcache[s][round(float(b['onset_s']) * 1000)]
        first = int(b['first_in_miniblock_design'])
        assert (mbp == 1) == (first == 1), f'{k}: mb_pos {mbp} vs design flag {first}'
        usable = a['usable'] == '1'
        responded = b['outcome'] in ('correct', 'error')
        retained = b['retained_phase2'] == '1'
        if retained:
            assert usable and a['active_power'] != '' and b['outcome'] == 'correct'
        rt = float(b['rt_ms']) if b['rt_ms'] != '' else float('nan')
        rows.append(dict(
            subject=s, trial=int(k[1]), cond=a['condition'], block=int(a['block']), trial_index=int(k[1]),
            mb_pos=mbp, first_design=first, active_power=a['active_power'], baseline_power=a['baseline_power'],
            rt_ms=b['rt_ms'], outcome=b['outcome'], correct=int(b['outcome'] == 'correct'),
            eeg_usable=int(usable), retained=int(retained),
            set_primary=int(retained and first == 1),
            set_later=int(retained and first == 0),
            set_k4a=int(usable and responded and first == 1 and a['active_power'] != ''),
            set_k4c=int(retained and first == 1 and rt <= 1000.0)))
    rc.write_csv(args.out, rows)
    n = {k: sum(r[k] for r in rows) for k in ('retained', 'set_primary', 'set_later', 'set_k4a', 'set_k4c')}
    assert n['retained'] == 14671 and n['set_primary'] == 4093 and n['set_later'] == 10578, n
    with open(meta_path, 'w') as fh:
        json.dump(dict(rule='decision log §11m', n_rows=len(rows), counts=n,
                       provenance=rc.provenance(__file__, dict(erd=args.erd, behaviour=args.behaviour))), fh, indent=2)
    print(json.dumps(n))


if __name__ == '__main__':
    main()
