"""Review round 1, Item 1: RT and accuracy of the 39 analysed participants, by MSIT+ condition and mini-block
class, from their own behavioural logs (decision log §11a).

    python r1_behaviour.py --raw <bidsRoot> --logs <E: ds004621>/sourcedata --block-table <d4e_block_clipping.csv> \
        --trackA-trials <outRoot>/stage5/erd/stage5_erd_per_trial.csv --trackA-mat <eegOutRoot>/stage5/trials \
        --out-dir <outRoot>/review1/behaviour

Reads only text files and the Track A trial-metadata variables (trialLatency/trialCond/trialBlock); no EEG
sample is read. Join: Track A trial i <-> the i-th in-block events.tsv stimulus (block table, §10g) <-> its log
stimulus (condition sequence + onset timing). Every join is verified and the script stops on any mismatch.
Outcome per trial, first match wins: no_log -> omission -> late (> window) -> error -> correct.
--window next_stimulus (primary, §11d-1): the response window runs to the next stimulus, so 'late' cannot
occur; this is the stage5_soa_survey.py RT convention. --window reqdur900: the task's 900 ms ReqDur (§11a).
Mini-block class in every summary = the design flag (§11d-2); Track A's flag is carried per trial.
Flags: multiple_responses (> 1 response within 900 ms), anticipatory (first response < 150 ms).
RT set = correct and not anticipatory. Retained for Phase 2 = Track A usable and in the RT set.
"""
import argparse
import csv
import glob
import json
import os
from collections import Counter, defaultdict

import numpy as np
from scipy.io import loadmat

import r1_common as rc

EXCLUDED = {'sub-28', 'sub-32', 'sub-42'}
EV = {'S 5': 'F0', 'S 6': 'FS', 'S 7': '00', 'S 8': 'S0'}            # whitespace-normalised, §10k
CONDS = ('00', 'S0', 'F0', 'FS')
CODES = {'00': ('100', '020', '003'), 'S0': ('010', '001', '200', '002', '300', '030'),
         'F0': ('122', '133', '121', '323', '113', '223'),
         'FS': ('311', '131', '322', '232', '212', '221', '331', '313', '211', '112', '332', '233')}
CODE2COND = {c: k for k, v in CODES.items() for c in v}
NONSTIM = ('ITI', 'break', '777', '666')
REQDUR_MS = 900.0           # the task's own ReqDur (9000 x 0.1 ms)
WINDOWS = {'next_stimulus': float('inf'), 'reqdur900': REQDUR_MS}   # §11d-1; set in main()
WINDOW_MS = None
ANTICIP_MS = 150.0
MATCH_TOL_S = 0.020         # log <-> events.tsv onset tolerance
LAT_TOL_S = 0.004           # Track A trialLatency <-> events.tsv within-block interval tolerance
RUN_ACCEPT = 0.95           # a log run is accepted if >= 95 % of its stimuli match
CLASSES = ('all', 'first', 'later')
OUTCOMES = ('correct', 'error', 'late', 'omission', 'no_log')


def norm(s):
    return ' '.join(s.split())


def target_digit(code3):
    """The MSIT target: the digit whose value differs from the other two."""
    c = Counter(code3)
    once = [d for d, k in c.items() if k == 1]
    if len(c) == 2 and len(once) == 1:
        return once[0]
    raise ValueError(f'no unique target digit in {code3}')


def read_log(path):
    """Stimulus trials of one Presentation log: code, condition, onset (s), target, responses (button, RT ms),
    Presentation's own Stim Type. Responses are those after the stimulus picture and before the next stimulus
    picture of the same log."""
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().splitlines()
    assert lines[0].startswith('Subject\tTrial\tEvent Type\tCode\tTime'), path
    trials, buttons = [], Counter()
    for ln in lines[1:]:
        p = ln.split('\t')
        if len(p) < 5 or not p[4].strip().lstrip('-').isdigit():
            continue
        et, code, t = p[2], p[3], int(p[4])
        if et == 'Picture' and code not in NONSTIM:
            c3 = code.zfill(3)
            trials.append(dict(code=c3, cond=CODE2COND[c3], t=t / 1e4, target=target_digit(c3),
                               pres=p[11] if len(p) > 11 else '', log_trial=int(p[1]), resp=[]))
        elif et == 'Response' and trials:
            buttons[code] += 1
            trials[-1]['resp'].append((code, (t / 1e4 - trials[-1]['t']) * 1000.0))
    assert set(buttons) <= {'1', '2', '3'}, f'{path}: response codes {buttons}'
    return trials


def align_run(lt, lc, et, ec):
    """Best constant offset mapping log onsets lt onto events.tsv onsets et (same condition, within 20 ms).
    Candidate offsets: each of the first 5 log stimuli against every events stimulus."""
    best = (0, None)
    for j in range(min(5, len(lt))):
        for k in range(len(et)):
            if lc[j] != ec[k]:
                continue
            x = lt + (et[k] - lt[j])
            pos = np.clip(np.searchsorted(et, x), 1, len(et) - 1)
            near = np.where(np.abs(et[pos - 1] - x) < np.abs(et[pos] - x), pos - 1, pos)
            ok = (np.abs(et[near] - x) <= MATCH_TOL_S) & (np.array(ec)[near] == np.array(lc))
            if ok.sum() > best[0]:
                best = (int(ok.sum()), (near, ok))
    return best


def first_flags(ev):
    """S0-3 (§10g): first stimulus, or an S 10/S 11/S 12 marker since the previous stimulus."""
    out, mark, seen = [], False, False
    for t, typ in ev:
        if typ in ('S 10', 'S 11', 'S 12'):
            mark = True
        elif typ in EV:
            out.append((not seen) or mark)
            seen, mark = True, False
    return out


def stats(v):
    v = np.asarray(v, float)
    return (float(v.mean()), float(v.std(ddof=1)) if v.size > 1 else float('nan'), int(v.size))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    for a in ('--raw', '--logs', '--block-table', '--trackA-trials', '--trackA-mat', '--out-dir'):
        ap.add_argument(a, required=True)
    ap.add_argument('--window', required=True, choices=sorted(WINDOWS))
    args = ap.parse_args()
    global WINDOW_MS
    WINDOW_MS = WINDOWS[args.window]
    outs = {k: os.path.join(args.out_dir, k) for k in
            ('r1_behaviour_trials.csv', 'r1_behaviour_subject_condition.csv', 'r1_behaviour_group.csv',
             'r1_behaviour_counts.csv', 'r1_behaviour_crosstab.csv', 'r1_behaviour_alignment.csv',
             'r1_behaviour_summary.json')}
    rc.refuse_existing(outs.values())
    os.makedirs(args.out_dir, exist_ok=True)

    blocks = defaultdict(list)
    for r in rc.read_csv(args.block_table):
        if r['task'] == 'msit':
            blocks[r['subject']].append((float(r['new_start_s']), float(r['new_end_s'])))
    subjects = sorted(s for s in blocks if s not in EXCLUDED)
    assert len(subjects) == 39
    tA = defaultdict(list)
    for r in rc.read_csv(args.trackA_trials):
        tA[r['subject']].append(r)
    assert sorted(tA) == subjects

    trials_out, align_rows, all_logged, flag_diff = [], [], [], []
    for s in subjects:
        # events.tsv stimuli and the S0-3 first-in-mini-block flag
        with open(os.path.join(args.raw, s, 'eeg', f'{s}_task-msit_events.tsv'), encoding='latin1') as fh:
            ev = [(float(r['onset']), norm(r['event_type'])) for r in csv.DictReader(fh, delimiter='\t')]
        stim = [(t, EV[typ]) for t, typ in ev if typ in EV]
        fflag = first_flags(ev)
        et = np.array([t for t, _ in stim])
        ec = [c for _, c in stim]

        # in-block stimuli (block table on the 1 kHz grid, as in stage5_window_overlap_check.py)
        inb = []
        for a, b in sorted(blocks[s]):
            a_, b_ = round(a * 1000), round(b * 1000)
            inb += [i for i, t in enumerate(et) if a_ <= round(t * 1000) <= b_]
        rows = tA[s]
        assert len(inb) == len(rows), f'{s}: {len(inb)} in-block stimuli vs {len(rows)} Track A trials'
        assert [ec[i] for i in inb] == [r['condition'] for r in rows], f'{s}: condition sequence differs'
        # Track A's flag (stage5_export_trials_task.m) is "first trial of a clipped block, or S 11 since the
        # previous trial"; the design flag (S0-3 on the full events.tsv) is "first stimulus, or a marker since
        # the previous stimulus". They may differ only at the first trial of a block whose start D4e clipped
        # (its mini-block began before the clip): verified here, and both flags are carried.
        design = [int(fflag[i]) for i in inb]
        for k, r in enumerate(rows):
            if design[k] != int(r['first_in_miniblock']):
                assert design[k] == 0 and (k == 0 or rows[k - 1]['block'] != r['block']), \
                    f'{s} trial {r["trial"]}: flags differ away from a block start'
                flag_diff.append((s, int(r['trial']), r['block'], r['condition']))
        m = loadmat(os.path.join(args.trackA_mat, f'{s}_msit_trials.mat'),
                    variable_names=['trialLatency', 'trialBlock', 'fs'])
        lat = m['trialLatency'].ravel() / float(m['fs'].item())
        blk = m['trialBlock'].ravel()
        assert blk.tolist() == [int(r['block']) for r in rows], f'{s}: block index differs'
        same = blk[1:] == blk[:-1]
        dev = np.abs(np.diff(lat) - np.diff(et[inb]))[same]
        assert dev.size == 0 or dev.max() <= LAT_TOL_S, f'{s}: trialLatency drift {dev.max():.4f} s'

        # logs -> events.tsv stimuli
        logs = sorted(glob.glob(os.path.join(args.logs, s, 'logfiles', f'{s}_task-msit_log_*.log')))
        assert len(logs) == 4, f'{s}: {len(logs)} MSIT logs'
        ev2log = {}
        for li, path in enumerate(logs, 1):
            lg = read_log(path)
            all_logged += [dict(subject=s, cond=t['cond'], target=t['target'], resp=t['resp'], pres=t['pres'])
                           for t in lg]
            n, best = align_run(np.array([t['t'] for t in lg]), [t['cond'] for t in lg], et, ec)
            accepted = n >= RUN_ACCEPT * len(lg)
            span = ''
            if accepted:
                near, ok = best
                for j in np.flatnonzero(ok):
                    k = int(near[j])
                    assert k not in ev2log, f'{s}: events stimulus {k} matched twice'
                    ev2log[k] = (li, lg[j])
                span = f'{et[near[ok]].min():.1f}-{et[near[ok]].max():.1f}'
            align_rows.append(dict(subject=s, log_run=li, n_log_stimuli=len(lg), n_matched=n,
                                   accepted=int(accepted), events_span_s=span))

        for r, i in zip(rows, inb):
            out = dict(subject=s, trial=r['trial'], condition=r['condition'], block=r['block'],
                       first_in_miniblock=int(r['first_in_miniblock']), first_in_miniblock_design=int(fflag[i]),
                       onset_s=et[i])
            o_any = int(r['outside_baseline']) or int(r['outside_active'])
            rb, ra = int(r['rejected_baseline']), int(r['rejected_active'])
            out['eeg_usable'] = int(r['usable'])
            out['eeg_reason'] = ('usable' if int(r['usable']) else 'outside' if o_any else
                                 'D12_both' if rb and ra else 'D12_baseline' if rb else 'D12_active')
            assert (out['eeg_reason'] == 'usable') == bool(out['eeg_usable']), f'{s} trial {r["trial"]}'
            if i not in ev2log:
                out.update(log_run='', log_trial='', stim_code='', target='', first_button='', rt_ms='',
                           n_resp_in_window=0, pres_stim_type='', outcome='no_log',
                           multiple_responses=0, anticipatory=0, after_900ms=0)
            else:
                li, t = ev2log[i]
                inwin = [x for x in t['resp'] if x[1] <= WINDOW_MS]
                fb, frt = t['resp'][0] if t['resp'] else ('', None)
                outcome = ('omission' if not t['resp'] else 'late' if frt > WINDOW_MS else
                           'error' if fb != t['target'] else 'correct')
                out.update(log_run=li, log_trial=t['log_trial'], stim_code=t['code'], target=t['target'],
                           first_button=fb, rt_ms='' if frt is None else round(frt, 1),
                           n_resp_in_window=len(inwin), pres_stim_type=t['pres'], outcome=outcome,
                           multiple_responses=int(len(inwin) > 1),
                           anticipatory=int(frt is not None and frt < ANTICIP_MS),
                           after_900ms=int(frt is not None and frt > REQDUR_MS))
            out['in_rt_set'] = int(out['outcome'] == 'correct' and not out['anticipatory'])
            out['retained_phase2'] = int(out['in_rt_set'] and out['eeg_usable'])
            trials_out.append(out)
    rc.write_csv(outs['r1_behaviour_trials.csv'], trials_out)
    rc.write_csv(outs['r1_behaviour_alignment.csv'], align_rows)

    def cls_ok(t, c):
        return c == 'all' or (c == 'first') == bool(t['first_in_miniblock_design'])

    # subject x condition x class
    sc = []
    for s in subjects:
        for cond in CONDS:
            for c in CLASSES:
                T = [t for t in trials_out if t['subject'] == s and t['condition'] == cond and cls_ok(t, c)]
                L = [t for t in T if t['outcome'] != 'no_log']
                R = [float(t['rt_ms']) for t in T if t['in_rt_set']]
                sc.append(dict(subject=s, condition=cond, trial_class=c, n_inblock=len(T), n_log=len(L),
                               n_correct=sum(t['outcome'] == 'correct' for t in L),
                               accuracy=sum(t['outcome'] == 'correct' for t in L) / len(L) if L else float('nan'),
                               n_rt=len(R), rt_mean=float(np.mean(R)) if R else float('nan'),
                               rt_median=float(np.median(R)) if R else float('nan'),
                               n_retained_phase2=sum(t['retained_phase2'] for t in T)))
    rc.write_csv(outs['r1_behaviour_subject_condition.csv'], sc)

    # group summary: mean +/- SD over participants of the participant means and of the participant medians
    grp = []
    for c in CLASSES:
        for cond in CONDS:
            X = [r for r in sc if r['condition'] == cond and r['trial_class'] == c]
            mm, ms, n1 = stats([r['rt_mean'] for r in X])
            dm, ds, _ = stats([r['rt_median'] for r in X])
            am, asd, _ = stats([r['accuracy'] for r in X])
            grp.append(dict(sample='inblock_39', trial_class=c, condition=cond, n_participants=n1,
                            rt_of_means_mean=mm, rt_of_means_sd=ms, rt_of_medians_mean=dm, rt_of_medians_sd=ds,
                            accuracy_mean=am, accuracy_sd=asd,
                            trials_rt_total=sum(r['n_rt'] for r in X)))
    # secondary (rule 8): every logged trial of the 39, regardless of EEG blocks; same outcome rules
    for cond in CONDS:
        pm, pd, pa = [], [], []
        for s in subjects:
            T = [t for t in all_logged if t['subject'] == s and t['cond'] == cond]
            cor = [t for t in T if t['resp'] and t['resp'][0][1] <= WINDOW_MS and t['resp'][0][0] == t['target']]
            R = [t['resp'][0][1] for t in cor if t['resp'][0][1] >= ANTICIP_MS]
            pm.append(np.mean(R)); pd.append(np.median(R)); pa.append(len(cor) / len(T))
        mm, ms, n1 = stats(pm)
        dm, ds, _ = stats(pd)
        am, asd, _ = stats(pa)
        grp.append(dict(sample='all_logged_39', trial_class='all', condition=cond, n_participants=n1,
                        rt_of_means_mean=mm, rt_of_means_sd=ms, rt_of_medians_mean=dm, rt_of_medians_sd=ds,
                        accuracy_mean=am, accuracy_sd=asd, trials_rt_total=''))
    rc.write_csv(outs['r1_behaviour_group.csv'], grp)

    # counts by stage and by reason, per condition x class
    cnt = []
    for c in CLASSES:
        for cond in CONDS + ('total',):
            T = [t for t in trials_out if (cond == 'total' or t['condition'] == cond) and cls_ok(t, c)]
            d = dict(trial_class=c, condition=cond, n_inblock=len(T),
                     n_eeg_usable=sum(t['eeg_usable'] for t in T))
            for k in ('outside', 'D12_baseline', 'D12_active', 'D12_both'):
                d[f'eeg_{k}'] = sum(t['eeg_reason'] == k for t in T)
            for k in OUTCOMES:
                d[f'beh_{k}'] = sum(t['outcome'] == k for t in T)
            d['flag_multiple_responses'] = sum(t['multiple_responses'] for t in T)
            d['flag_anticipatory'] = sum(t['anticipatory'] for t in T)
            d['flag_after_900ms'] = sum(t['after_900ms'] for t in T)
            d['correct_after_900ms'] = sum(t['after_900ms'] and t['outcome'] == 'correct' for t in T)
            d['anticipatory_among_correct'] = sum(t['anticipatory'] and t['outcome'] == 'correct' for t in T)
            d['n_rt_set'] = sum(t['in_rt_set'] for t in T)
            d['n_retained_phase2'] = sum(t['retained_phase2'] for t in T)
            cnt.append(d)
    rc.write_csv(outs['r1_behaviour_counts.csv'], cnt)

    # cross-tab: behavioural outcome x EEG reason (all trials)
    xt = []
    for o in OUTCOMES:
        d = dict(outcome=o)
        for k in ('usable', 'outside', 'D12_baseline', 'D12_active', 'D12_both'):
            d[k] = sum(t['outcome'] == o and t['eeg_reason'] == k for t in trials_out)
        xt.append(d)
    rc.write_csv(outs['r1_behaviour_crosstab.csv'], xt)

    L = [t for t in trials_out if t['outcome'] != 'no_log']
    agree = Counter((t['outcome'] == 'correct', t['pres_stim_type'] == 'hit') for t in L)
    rts = [float(t['rt_ms']) for t in L if t['rt_ms'] != '']
    summary = dict(
        rule='decision log §11a, amended §11d', window=args.window, window_ms=WINDOW_MS,
        window_label=('next stimulus: the stage5_soa_survey.py RT convention' if args.window == 'next_stimulus'
                      else 'task ReqDur 900 ms (Presentation response window)'),
        n_after_900ms=sum(t['after_900ms'] for t in trials_out), n_subjects=len(subjects), n_inblock=len(trials_out),
        n_with_log=len(L), n_no_log=len(trials_out) - len(L),
        no_log_by_subject=dict(Counter(t['subject'] for t in trials_out if t['outcome'] == 'no_log')),
        log_runs_not_accepted=[(r['subject'], r['log_run'], r['n_matched'], r['n_log_stimuli'])
                               for r in align_rows if not r['accepted']],
        presentation_hit_agreement={f'ours_correct={a}, pres_hit={b}': n for (a, b), n in sorted(agree.items())},
        first_response_rt_ms_range=[min(rts), max(rts)],
        n_retained_phase2=sum(t['retained_phase2'] for t in trials_out),
        class_flag_used='first_in_miniblock_design (§11d-2); Track A flag carried as first_in_miniblock',
        n_flag_differences=len(flag_diff), flag_differences=flag_diff,
        palucha_note=('Palucha et al. (2025) report mean +/- SD per condition without stating whether the '
                      'per-participant value is a mean or a median; both are given here and neither is claimed '
                      'as the like-for-like comparison.'),
        provenance=rc.provenance(__file__, dict(block_table=args.block_table, trackA_trials=args.trackA_trials)))
    with open(outs['r1_behaviour_summary.json'], 'w') as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps({k: v for k, v in summary.items() if k != 'provenance'}, indent=1))


if __name__ == '__main__':
    main()
