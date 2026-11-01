"""Stage 5 Track A: empirical verification of the two analysis windows over all 39 subjects.

Read-only. Reads only small text files: the raw `*_task-msit_events.tsv` of the 39 retained subjects
and the Stage-3 block-clipping table. No EEG sample is read; no spectral or 13-30 Hz quantity is
computed anywhere in this script.

Track A uses two windows per trial, both relative to the condition-marker onset t (decision log §10b,
§10g):
    baseline  [t - 500, t)      ms   ->  samples [t - 500, t - 1]    (500 ms)
    active    [t,       t+1000) ms   ->  samples [t,       t + 999]  (1000 ms)
ERD% = (baseline_power - active_power) / baseline_power * 100.

Arithmetic says the windows cannot collide: with the 1733 ms SOA floor (§10b), the next trial's
baseline starts at least 1733 - 500 = 1233 ms after the current onset, while the current active window
ends at 1000 ms, leaving >= 233 ms. This script does not rely on that: it checks every consecutive
trial pair in every block of every subject, the same way the post-onset window was checked.

HARD CHECKS (all must pass, else the script reports FAIL and exits non-zero)
  1. the baseline of trial k+1 does not overlap the active window of trial k (same block)
  2. the baseline of trial k+1 does not overlap the baseline of trial k
  3. every baseline window lies inside its clipped task block
  4. every active window lies inside its clipped task block
  5. baseline and active of the same trial do not overlap (construction check)

DIAGNOSTICS (reported, never gating) - the baseline sits inside the previous trial's post-response
period, which is where post-movement beta rebound (ERS) occurs, so its contamination risk is quantified
rather than assumed:
  - lag from the previous stimulus to the baseline start
  - lag from the previous response to the baseline start, and how often that response falls inside the
    baseline window
  - the same, split by whether a mini-block marker (S 10 / S 11 / S 12) intervened, since those trials
    have much longer SOAs
  - first-in-block trials, whose baseline falls in the 1 s pre-block pad rather than after another trial
  - the Stage-0 (S0-3) first-in-mini-block flag per trial, carried for the planned first-vs-later split

Grid note: the check works on the raw 1000 Hz grid of events.tsv. The pipeline analyses at 500 Hz, where
a window edge can differ by one sample (2 ms); every margin reported here is two orders of magnitude
larger, so the conclusion does not depend on the grid.

Usage
  python stage5_window_overlap_check.py [raw_root] [block_table] [out_dir]
Outputs (in out_dir)
  stage5_window_overlap_per_subject.csv
  stage5_window_overlap_summary.json
"""
import csv
import json
import os
import re
import statistics
import sys

FS = 1000                      # raw grid: events.tsv onset (s) x 1000 = sample
BASELINE_MS = (-500, 0)        # [t-500, t)
ACTIVE_MS = (0, 1000)          # [t, t+1000)
COND = {"S 5": "F0", "S 6": "FS", "S 7": "00", "S 8": "S0"}
MARKS = ("S 10", "S 11", "S 12")
EXCLUDED = {"sub-28", "sub-32", "sub-42"}

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "raw_data", "ds004621")
BLOCKS = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "outputs", "stage3",
                                                            "d4e_d5a3", "d4e_block_clipping.csv")
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(REPO, "outputs", "stage5")


def norm(s):
    return re.sub(r"\s+", " ", s.strip())


def read_events(path):
    ev = []
    with open(path, encoding="latin1") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            ev.append((round(float(r["onset"]) * FS), norm(r["event_type"]), r["trial_type"].strip()))
    return ev


def read_blocks(path):
    out = {}
    with open(path, newline="", encoding="latin1") as fh:
        for r in csv.DictReader(fh):
            if r["task"] != "msit":
                continue
            out.setdefault(r["subject"], []).append(
                (r["block"], round(float(r["new_start_s"]) * FS), round(float(r["new_end_s"]) * FS)))
    for s in out:
        out[s].sort(key=lambda t: t[1])
    return out


def pct(xs, q):
    if not xs:
        return float("nan")
    ys = sorted(xs)
    if len(ys) == 1:
        return float(ys[0])
    i = q / 100 * (len(ys) - 1)
    lo = int(i)
    hi = min(lo + 1, len(ys) - 1)
    return float(ys[lo] + (ys[hi] - ys[lo]) * (i - lo))


def windows(t):
    """Inclusive sample ranges of the two windows of a trial whose onset sample is t."""
    b = (t + BASELINE_MS[0], t + BASELINE_MS[1] - 1)
    a = (t + ACTIVE_MS[0], t + ACTIVE_MS[1] - 1)
    return b, a


def first_in_miniblock(ev):
    """Stage 0 (S0-3): a marker S 10 / S 11 / S 12 lies between the previous stimulus and this one."""
    out, mark_since_prev, seen = {}, False, False
    for p, t, tt in ev:
        if t in MARKS:
            mark_since_prev = True
        elif tt == "stimulus":
            out[p] = (not seen) or mark_since_prev
            seen, mark_since_prev = True, False
    return out


def responses(ev):
    """{stimulus sample: first response sample after it and before the next stimulus} (may be absent)."""
    stim = [p for p, _, tt in ev if tt == "stimulus"]
    nxt = {p: (stim[i + 1] if i + 1 < len(stim) else None) for i, p in enumerate(stim)}
    out = {}
    for p, _, tt in ev:
        if tt != "response":
            continue
        prev = [q for q in stim if q < p]
        if not prev:
            continue
        q = prev[-1]
        if q not in out and (nxt[q] is None or p < nxt[q]):
            out[q] = p
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    blocks = read_blocks(BLOCKS)
    subjects = sorted(s for s in blocks if s not in EXCLUDED)
    assert len(subjects) == 39, f"{len(subjects)} subjects in the block table, 39 expected"

    rows, failures = [], []
    gaps_all, lag_stim_all, lag_resp_all = [], [], []
    n_trials = n_pairs = n_first_in_block = 0
    n_resp_in_baseline = n_resp_known = 0
    by_mark = {True: [], False: []}          # lag from previous response, split by mini-block marker
    n_fimb = 0

    for s in subjects:
        ev = read_events(os.path.join(RAW, s, "eeg", f"{s}_task-msit_events.tsv"))
        assert all(t in COND for _, t, tt in ev if tt == "stimulus"), f"{s}: unexpected stimulus code"
        fimb = first_in_miniblock(ev)
        resp = responses(ev)
        stim_all = [p for p, _, tt in ev if tt == "stimulus"]

        v = dict(overlap_active=0, overlap_baseline=0, baseline_before_block=0, active_after_block=0,
                 self_overlap=0, resp_in_baseline=0)
        gaps, lag_stim, lag_resp = [], [], []
        n_sub = n_fib = 0
        for _, a_blk, b_blk in blocks[s]:
            inb = sorted(p for p in stim_all if a_blk <= p <= b_blk)
            n_sub += len(inb)
            for i, t in enumerate(inb):
                (b0, b1), (a0, a1) = windows(t)
                if b1 >= a0:
                    v['self_overlap'] += 1
                if b0 < a_blk:
                    v['baseline_before_block'] += 1
                if a1 > b_blk:
                    v['active_after_block'] += 1
                if i == 0:
                    n_fib += 1
                    continue
                tp = inb[i - 1]
                (pb0, pb1), (pa0, pa1) = windows(tp)
                gap = b0 - pa1 - 1                       # ms of clear space between the two windows
                gaps.append(gap)
                if b0 <= pa1:
                    v['overlap_active'] += 1
                if b0 <= pb1:
                    v['overlap_baseline'] += 1
                lag_stim.append(b0 - tp)                 # baseline start, re previous stimulus
                if tp in resp:
                    d = b0 - resp[tp]                    # baseline start, re previous response
                    lag_resp.append(d)
                    by_mark[bool(fimb.get(t, False))].append(d)
                    if b0 <= resp[tp] <= b1:
                        v['resp_in_baseline'] += 1
        n_trials += n_sub
        n_first_in_block += n_fib
        n_pairs += len(gaps)
        gaps_all += gaps
        lag_stim_all += lag_stim
        lag_resp_all += lag_resp
        n_resp_known += len(lag_resp)
        n_resp_in_baseline += v.get('resp_in_baseline', 0)
        n_fimb += sum(1 for p in stim_all if fimb.get(p, False))

        bad = {k: n for k, n in v.items() if k != 'resp_in_baseline' and n}
        if bad:
            failures.append(f"{s}: {bad}")
        rows.append(dict(
            subject=s, n_blocks=len(blocks[s]), n_trials_in_blocks=n_sub, n_first_in_block=n_fib,
            n_consecutive_pairs=len(gaps),
            overlap_baseline_vs_prev_active=v['overlap_active'],
            overlap_baseline_vs_prev_baseline=v['overlap_baseline'],
            baseline_before_block_start=v['baseline_before_block'],
            active_after_block_end=v['active_after_block'],
            baseline_active_self_overlap=v['self_overlap'],
            min_gap_ms=min(gaps) if gaps else "", median_gap_ms=round(pct(gaps, 50), 1) if gaps else "",
            min_lag_prev_stim_ms=min(lag_stim) if lag_stim else "",
            min_lag_prev_resp_ms=min(lag_resp) if lag_resp else "",
            median_lag_prev_resp_ms=round(pct(lag_resp, 50), 1) if lag_resp else "",
            n_prev_resp_inside_baseline=v.get('resp_in_baseline', 0),
        ))

    with open(os.path.join(OUT, "stage5_window_overlap_per_subject.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    ok = not failures
    summary = dict(
        verdict="PASS" if ok else "FAIL", failures=failures,
        baseline_window_ms=list(BASELINE_MS), active_window_ms=list(ACTIVE_MS),
        n_subjects=len(rows), n_trials_in_blocks=n_trials, n_consecutive_pairs=n_pairs,
        n_first_in_block=n_first_in_block, n_first_in_miniblock=n_fimb,
        hard_checks=dict(
            overlap_baseline_vs_prev_active=sum(r['overlap_baseline_vs_prev_active'] for r in rows),
            overlap_baseline_vs_prev_baseline=sum(r['overlap_baseline_vs_prev_baseline'] for r in rows),
            baseline_before_block_start=sum(r['baseline_before_block_start'] for r in rows),
            active_after_block_end=sum(r['active_after_block_end'] for r in rows),
            baseline_active_self_overlap=sum(r['baseline_active_self_overlap'] for r in rows)),
        gap_ms=dict(min=min(gaps_all), p01=pct(gaps_all, 1), median=pct(gaps_all, 50),
                    max=max(gaps_all), mean=round(statistics.mean(gaps_all), 1)),
        lag_prev_stimulus_to_baseline_start_ms=dict(
            min=min(lag_stim_all), median=pct(lag_stim_all, 50), max=max(lag_stim_all)),
        lag_prev_response_to_baseline_start_ms=dict(
            n=n_resp_known, min=min(lag_resp_all), p05=pct(lag_resp_all, 5),
            median=pct(lag_resp_all, 50), p95=pct(lag_resp_all, 95), max=max(lag_resp_all)),
        prev_response_inside_baseline=dict(
            n=n_resp_in_baseline, of=n_resp_known,
            fraction=round(n_resp_in_baseline / n_resp_known, 6) if n_resp_known else None),
        lag_prev_response_by_miniblock_marker={
            ('first_in_miniblock' if k else 'later_in_miniblock'): dict(
                n=len(v2), median=pct(v2, 50), min=min(v2), max=max(v2))
            for k, v2 in by_mark.items() if v2},
        inputs=dict(raw_root=RAW, block_table=BLOCKS))
    with open(os.path.join(OUT, "stage5_window_overlap_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)

    print(f"VERDICT: {summary['verdict']}   ({len(rows)} subjects, {n_trials} trials in blocks, "
          f"{n_pairs} consecutive pairs)")
    print("hard checks (all must be 0):")
    for k, n in summary['hard_checks'].items():
        print(f"  {k:38s} {n}")
    g = summary['gap_ms']
    print(f"clear space between prev active end and baseline start (ms): min {g['min']}  "
          f"p01 {g['p01']:.0f}  median {g['median']:.0f}  max {g['max']}")
    ls = summary['lag_prev_stimulus_to_baseline_start_ms']
    print(f"baseline start after PREVIOUS STIMULUS (ms): min {ls['min']}  median {ls['median']:.0f}  "
          f"max {ls['max']}")
    lr = summary['lag_prev_response_to_baseline_start_ms']
    print(f"baseline start after PREVIOUS RESPONSE (ms): min {lr['min']}  p05 {lr['p05']:.0f}  "
          f"median {lr['median']:.0f}  p95 {lr['p95']:.0f}  max {lr['max']}  (n={lr['n']})")
    pr = summary['prev_response_inside_baseline']
    print(f"previous response falls INSIDE the baseline window: {pr['n']} of {pr['of']} "
          f"({0 if pr['fraction'] is None else pr['fraction'] * 100:.3f} %)")
    for k, v2 in summary['lag_prev_response_by_miniblock_marker'].items():
        print(f"  {k:20s} n {v2['n']:6d}  median lag {v2['median']:.0f} ms  "
              f"min {v2['min']}  max {v2['max']}")
    print(f"first-in-block trials (baseline in the 1 s pre-block pad): {n_first_in_block}")
    if failures:
        print("FAILURES:", *failures, sep="\n  ")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
