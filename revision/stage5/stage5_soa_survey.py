"""Stage 5 / Track A: stimulus-onset asynchrony (SOA) survey of the MSIT+ condition markers.

Read-only. Reads only small text files: the raw `*_task-msit_events.tsv` of the 39 retained
subjects and the Stage-3 block-clipping table (`d4e_block_clipping.csv`). No EEG samples are
read; no spectral or 13-30 Hz quantity is computed anywhere in this script.

Why: Stage 4 used 2 s Welch windows for rest. Track A of Stage 5 needs one segment per trial,
starting at the condition marker, so the segment length is bounded by the shortest interval
between two consecutive condition markers (the SOA) inside the analysed task blocks. A sample
of sub-01 suggested 870-1070 ms; this script pins the true minimum down over all 39 subjects
so the Track-A segment length can be fixed with a documented safety margin.

Definitions
  condition markers  S 5 = F0, S 6 = FS, S 7 = 00, S 8 = S0 (task-msit_events.json; Dzianok
                     et al. 2022, GigaScience, Table 3). These are exactly the events.tsv rows
                     with trial_type == "stimulus".
  analysed blocks    the clipped task blocks of S3a-D3e/D4e, read from the block table:
                     inclusive onset window [new_start_s, new_end_s] per `task_b<k>` row.
                     Stimuli outside their clipped block (`d4e_lost_stimuli.csv`) are not in
                     the rebuilt data and are excluded here by the same window test.
  SOA                difference between two consecutive condition-marker onsets *within one
                     block*. Gaps across a block boundary are not SOAs and are excluded.
  forward window     the candidate Track-A segment [onset, onset + dur). A trial is "clipped"
                     if onset + dur - 1 sample exceeds the block's last sample, and "overlapped"
                     if the next condition marker in the same block starts before the window
                     ends.
  RT                 onset of the first events.tsv "response" row after a stimulus and before
                     the next stimulus (reported for context only; not used to pick the window).

Usage
  python stage5_soa_survey.py [raw_root] [block_table] [out_dir]
    raw_root     local ds004621 copy (= bidsRoot in config_local.m)
    block_table  <outRoot>/stage3/d4e_d5a3/d4e_block_clipping.csv (the table the Stage-3 run used)
    out_dir      output folder (= <outRoot>/stage5)
Outputs (in out_dir)
  stage5_soa_per_subject.csv   one row per subject: block/trial counts and SOA statistics
  stage5_soa_candidates.csv    one row per candidate duration: clipped/overlapped trial counts
  stage5_soa_summary.json      pooled SOA statistics, RT statistics and the run's inputs
"""
import csv
import json
import os
import re
import statistics
import sys

FS = 1000                      # raw grid of events.tsv onsets (s) x 1000 = samples
COND = {"S 5": "F0", "S 6": "FS", "S 7": "00", "S 8": "S0"}
# the 39 subjects retained after Stage 3 (S3a-close: sub-28, sub-32, sub-42 excluded)
EXCLUDED = {"sub-28", "sub-32", "sub-42"}
# candidate Track-A segment lengths (ms), evaluated against the real SOA distribution
CANDIDATES = (500, 600, 650, 700, 800, 900, 1000, 1100, 1200, 1400, 1500, 1700, 1733, 1800, 2000)

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "raw_data", "ds004621")
BLOCKS = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "outputs", "stage3",
                                                            "d4e_d5a3", "d4e_block_clipping.csv")
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(REPO, "outputs", "stage5")


def norm(s):
    return re.sub(r"\s+", " ", s.strip())


def read_events(path):
    """Return [(sample, event_type, trial_type)] from one events.tsv, in file order."""
    ev = []
    with open(path, encoding="latin1") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            ev.append((round(float(r["onset"]) * FS), norm(r["event_type"]), r["trial_type"].strip()))
    return ev


def read_blocks(path):
    """Return {subject: [(label, first sample, last sample)]} for the msit task blocks."""
    out = {}
    with open(path, newline="", encoding="latin1") as fh:
        for r in csv.DictReader(fh):
            if r["task"] != "msit":
                continue
            a = round(float(r["new_start_s"]) * FS)
            b = round(float(r["new_end_s"]) * FS)
            out.setdefault(r["subject"], []).append((r["block"], a, b))
    for s in out:
        out[s].sort(key=lambda t: t[1])
    return out


def pct(xs, q):
    """Percentile with NumPy's 'linear' interpolation (the project's convention, Q7 of S4-impl)."""
    if not xs:
        return float("nan")
    ys = sorted(xs)
    if len(ys) == 1:
        return float(ys[0])
    i = q / 100 * (len(ys) - 1)
    lo = int(i)
    hi = min(lo + 1, len(ys) - 1)
    return float(ys[lo] + (ys[hi] - ys[lo]) * (i - lo))


def main():
    os.makedirs(OUT, exist_ok=True)
    blocks = read_blocks(BLOCKS)
    subjects = sorted(s for s in blocks if s not in EXCLUDED)
    assert len(subjects) == 39, f"{len(subjects)} subjects in the block table, 39 expected"

    rows, all_soa, all_rt, problems = [], [], [], []
    clipped = {d: 0 for d in CANDIDATES}      # trials whose forward window leaves the block
    overlapped = {d: 0 for d in CANDIDATES}   # trials whose forward window reaches the next stimulus
    n_trials_total = 0

    for s in subjects:
        ev = read_events(os.path.join(RAW, s, "eeg", f"{s}_task-msit_events.tsv"))
        stim = [(p, t) for p, t, tt in ev if tt == "stimulus"]
        assert all(t in COND for _, t in stim), f"{s}: unexpected stimulus code"
        # response times, for context only: first response after a stimulus, before the next one
        nxt = {}
        for i, (p, _) in enumerate(stim):
            nxt[p] = stim[i + 1][0] if i + 1 < len(stim) else None
        rts = []
        for p, t, tt in ev:
            if tt != "response":
                continue
            prev = [q for q, _ in stim if q < p]
            if not prev:
                continue
            q = prev[-1]
            if (nxt[q] is None or p < nxt[q]) and not any(r for r in rts if r[0] == q):
                rts.append((q, p - q))
        rt_vals = [d for _, d in rts]

        soa, n_in = [], 0
        for _, a, b in blocks[s]:
            inb = sorted(p for p, _ in stim if a <= p <= b)
            n_in += len(inb)
            for i, p in enumerate(inb):
                for d in CANDIDATES:
                    if p + round(d / 1000 * FS) - 1 > b:
                        clipped[d] += 1
                    if i + 1 < len(inb) and inb[i + 1] - p < round(d / 1000 * FS):
                        overlapped[d] += 1
            soa += [inb[i + 1] - inb[i] for i in range(len(inb) - 1)]
        if not soa:
            problems.append(f"{s}: no within-block SOA")
            continue
        n_trials_total += n_in
        all_soa += soa
        all_rt += rt_vals
        rows.append({
            "subject": s, "n_blocks": len(blocks[s]), "n_stim_total": len(stim),
            "n_stim_in_blocks": n_in, "n_soa": len(soa),
            "soa_min_ms": min(soa), "soa_p01_ms": round(pct(soa, 1), 1),
            "soa_p05_ms": round(pct(soa, 5), 1), "soa_median_ms": round(pct(soa, 50), 1),
            "soa_p95_ms": round(pct(soa, 95), 1), "soa_max_ms": max(soa),
            "rt_n": len(rt_vals),
            "rt_median_ms": round(pct(rt_vals, 50), 1) if rt_vals else "",
            "rt_p95_ms": round(pct(rt_vals, 95), 1) if rt_vals else "",
        })

    with open(os.path.join(OUT, "stage5_soa_per_subject.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    with open(os.path.join(OUT, "stage5_soa_candidates.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["duration_ms", "n_trials", "n_clipped_by_block_end", "n_overlapping_next_stim",
                    "frac_usable"])
        for d in CANDIDATES:
            bad = clipped[d] + overlapped[d]       # upper bound: a trial could be both
            w.writerow([d, n_trials_total, clipped[d], overlapped[d],
                        round(1 - bad / n_trials_total, 6)])

    summary = {
        "n_subjects": len(rows), "n_trials_in_blocks": n_trials_total, "n_soa": len(all_soa),
        "soa_min_ms": min(all_soa), "soa_p01_ms": pct(all_soa, 1), "soa_p05_ms": pct(all_soa, 5),
        "soa_median_ms": pct(all_soa, 50), "soa_mean_ms": round(statistics.mean(all_soa), 1),
        "soa_p95_ms": pct(all_soa, 95), "soa_max_ms": max(all_soa),
        "soa_min_per_subject_min_ms": min(r["soa_min_ms"] for r in rows),
        "rt_n": len(all_rt),
        "rt_median_ms": pct(all_rt, 50) if all_rt else None,
        "rt_p05_ms": pct(all_rt, 5) if all_rt else None,
        "rt_p95_ms": pct(all_rt, 95) if all_rt else None,
        "candidates_ms": list(CANDIDATES),
        "clipped_by_block_end": clipped, "overlapping_next_stim": overlapped,
        "inputs": {"raw_root": RAW, "block_table": BLOCKS},
        "problems": problems,
    }
    with open(os.path.join(OUT, "stage5_soa_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)

    print(f"subjects {len(rows)}  trials in blocks {n_trials_total}  SOAs {len(all_soa)}")
    print(f"SOA ms: min {summary['soa_min_ms']}  p01 {summary['soa_p01_ms']:.1f}  "
          f"p05 {summary['soa_p05_ms']:.1f}  median {summary['soa_median_ms']:.1f}  "
          f"p95 {summary['soa_p95_ms']:.1f}  max {summary['soa_max_ms']}")
    print(f"smallest per-subject min SOA: {summary['soa_min_per_subject_min_ms']} ms")
    if all_rt:
        print(f"RT ms (context only): p05 {summary['rt_p05_ms']:.1f}  "
              f"median {summary['rt_median_ms']:.1f}  p95 {summary['rt_p95_ms']:.1f}  n {len(all_rt)}")
    print("duration_ms  clipped  overlapping  frac_usable")
    for d in CANDIDATES:
        bad = clipped[d] + overlapped[d]
        print(f"{d:>11}  {clipped[d]:>7}  {overlapped[d]:>11}  {1 - bad / n_trials_total:.6f}")
    if problems:
        print("PROBLEMS:", *problems, sep="\n  ")


if __name__ == "__main__":
    main()
