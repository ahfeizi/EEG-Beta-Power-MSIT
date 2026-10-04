"""Stage 3a / decision S3a-D4e: raw data boundaries and the filter-edge clipping of every block.

Read-only. Reads only small text files of the raw dataset (*.vhdr, *.vmrk, *_events.tsv) for
task-rest and task-msit of all 42 subjects. No EEG samples are read.

What it does:
  1. Lists every raw boundary. EEGLAB's BrainVision loader (bva-io, parsebvmrk.m) turns every
     "New Segment" and "DC Correction" marker into a `boundary` event, and gives every other
     marker its description as event type, so a marker described "boundary" (EEGLAB's own export
     of a boundary event) is a `boundary` event too. firfilt and pop_resample then filter each
     continuous segment separately. events.tsv contains none of these markers.
  2. Checks that the events.tsv rows match the non-boundary .vmrk stimulus markers
     (position = onset * 1000).
  3. Builds the blocks of S3a-D3 (rest) and S3a-D3e (task), then applies S3a-D4e:
     every block is clipped so that it lies at least H from every segment edge
     (recording start/end and every internal raw boundary):
       start = max(start under the rule, previous edge + H)
       end   = min(end under the rule, next edge after the start - H)
     A raw boundary inside a block is the "next edge". If any stimulus lies after it within the
     block, the block would have to be split: this is reported as STOP (no rule exists for it).

  4. Counts, per subject and MSIT+ condition, the stimuli lost by the clipping, the block-first
     stimuli (excluded from pre-stimulus analyses under D3e) and the stimuli kept, separately for
     first-in-mini-block and later trials (definition as in Stage 0, S0-3: a marker S 10/S 11/S 12
     lies between the previous stimulus and this one, or it is the first stimulus of the recording).

H is not typed in: it is read from <out_dir>/filter_halflengths.csv, written by stage3_compute_H.m
(sum of the half-lengths of every filter applied before cropping, designed with the installed EEGLAB).

Sample convention (1-based, as in the .vmrk and in EEGLAB): sample n has onset n / fs in events.tsv.
A boundary marker at sample L starts a new segment at sample L. With a filter half-length of G
samples, an output sample i of segment [a, b] contains no padding iff a + G <= i <= b - G.
Block extents are inclusive sample ranges. This survey works on the raw 1000 Hz grid; the pipeline
clips on the 500 Hz grid after resampling, so its block edges may differ by one 500 Hz sample.

Usage:
  python stage3_raw_boundaries_d4e.py [raw_root] [out_dir]
    raw_root   local ds004621 copy (= bidsRoot in config_local.m)
    out_dir    output folder (= <outRoot>/stage3); must contain filter_halflengths.csv
Outputs (in out_dir):
  raw_boundaries.csv              one row per internal raw boundary
  d4e_block_clipping.csv          one row per block, before and after clipping
  d4e_lost_stimuli.csv            one row per stimulus outside its clipped block
  d4e_trials_by_condition.csv     one row per subject x MSIT+ condition
"""
import csv
import math
import os
import re
import sys

# Paths: pass them on the command line (see Usage). The defaults mirror get_paths.m.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "raw_data", "ds004621")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "outputs", "stage3")
with open(os.path.join(OUT, "filter_halflengths.csv"), newline="") as _fh:
    H = sum(float(r["half_s"]) for r in csv.DictReader(_fh))   # S3a-D4e: sum over the filter cascade

FS = 1000                      # raw sampling rate (Hz); asserted against every .vhdr below
G = math.ceil(H * FS - 1e-9)   # H in raw samples, rounded up
COND = {"S 5": "F0", "S 6": "FS", "S 7": "00", "S 8": "S0"}   # task-msit_events.json
MARKS = ("S 10", "S 11", "S 12")
BOUNDARY_TYPES = ("new segment", "dc correction")   # parsebvmrk.m: these become `boundary`


def is_boundary(ty, desc):
    """True if parsebvmrk.m would give this marker the EEGLAB event type `boundary`."""
    return ty.lower() in BOUNDARY_TYPES or desc.lower() == "boundary"


def norm(s):
    return re.sub(r"\s+", " ", s.strip())


def read_vhdr(path):
    """Return (DataPoints, SamplingInterval in microseconds)."""
    dp = si = None
    with open(path, encoding="latin1") as fh:
        for line in fh:
            if line.startswith("DataPoints="):
                dp = int(line.split("=", 1)[1])
            elif line.startswith("SamplingInterval="):
                si = float(line.split("=", 1)[1])
    return dp, si


def read_vmrk(path):
    """Return a list of (mk number, type, description, position) from [Marker Infos]."""
    out, inside = [], False
    with open(path, encoding="latin1") as fh:
        for line in fh:
            line = line.rstrip("\r\n")
            if line.startswith("["):
                inside = line.strip().lower() == "[marker infos]"
                continue
            if not inside or not line.startswith("Mk"):
                continue
            key, val = line.split("=", 1)
            f = val.split(",")
            out.append((int(key[2:]), f[0], norm(f[1]), int(float(f[2]))))
    return out


def read_events(path):
    """Return a list of (sample, event_type, trial_type) from events.tsv."""
    ev = []
    with open(path, encoding="latin1") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            ev.append((round(float(r["onset"]) * FS), norm(r["event_type"]), r["trial_type"].strip()))
    return ev


def rest_blocks(s, ev, n):
    """S3a-D3a/D3c. Returns [(label, first sample, last sample)] and a list of check notes."""
    notes = []
    s12 = [p for p, t, _ in ev if t == "S 12"]
    s10 = [p for p, t, _ in ev if t == "S 10"]
    if s == "sub-25":
        dur1 = round(297.75 * FS)                         # D3c
    else:
        dur1 = 300 * FS
        if len(s10) != 1 or abs(s10[0] - (s12[0] + 300 * FS)) > 0.01 * FS:
            notes.append("S10 check failed")              # D3a consistency check
    b1 = (s12[0], s12[0] + dur1 - 1)
    b2 = (s12[1], min(s12[1] + 300 * FS - 1, n))          # clipped at the end of the recording
    return [("rest_b1",) + b1, ("rest_b2",) + b2], notes


def task_blocks(ev):
    """S3a-D3e-1..3. Returns [(label, first sample, last sample, n stimuli, split by 10 s rule,
    stimulus samples)] and the number of discarded segments."""
    blocks, cur, prev, split_next = [], [], None, False   # blocks: (start, end, n stim, split, stimuli)
    raw = []                                              # (events, split_by_gap)
    for p, t, tt in ev:
        if t in ("S 10", "S 12"):
            if cur:
                raw.append((cur, split_next))
            cur, prev, split_next = [], None, False
            continue
        if tt in ("stimulus", "response"):
            if prev is not None and p - prev > 10 * FS:
                raw.append((cur, split_next))
                cur, split_next = [], True
            cur.append((p, tt))
            prev = p
    if cur:
        raw.append((cur, split_next))
    dropped = 0
    for b, split in raw:
        stim = [p for p, tt in b if tt == "stimulus"]
        if not stim:                                      # D3e-3
            dropped += 1
            continue
        blocks.append((min(stim) - 1 * FS, max(p for p, _ in b) + round(1.5 * FS), len(stim), split,
                       tuple(stim)))
    labelled = [(f"task_b{k}",) + b for k, b in enumerate(blocks, 1)]
    return labelled, dropped


def first_in_miniblock(ev):
    """Stage 0 (S0-3) definition. Returns {stimulus sample: True/False}."""
    out, mark_since_prev, seen = {}, False, False
    for p, t, tt in ev:
        if t in MARKS:
            mark_since_prev = True
        elif tt == "stimulus":
            out[p] = (not seen) or mark_since_prev
            seen, mark_since_prev = True, False
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    brows, crows, problems, lost_rows, cond_rows = [], [], [], [], []
    for i in range(1, 43):
        s = f"sub-{i:02d}"
        for task in ("rest", "msit"):
            base = os.path.join(RAW, s, "eeg", f"{s}_task-{task}")
            n, si = read_vhdr(base + "_eeg.vhdr")
            if si != 1e6 / FS:
                problems.append(f"{s} {task}: SamplingInterval {si}")
            mk = read_vmrk(base + "_eeg.vmrk")
            ev = read_events(base + "_events.tsv")

            # events.tsv vs .vmrk stimulus markers
            vm = sorted((p, d) for _, ty, d, p in mk
                        if ty.lower() == "stimulus" and d and not is_boundary(ty, d))
            tv = sorted((p, t) for p, t, _ in ev)
            if vm != tv:
                problems.append(f"{s} {task}: events.tsv != vmrk ({len(tv)} vs {len(vm)} events)")

            # segments: boundaries inside (1, n]; a boundary at sample 1 is the recording start
            bnd = sorted({p for _, ty, d, p in mk if is_boundary(ty, d)})
            outside = [p for p in bnd if p < 1 or p > n]
            if outside:
                problems.append(f"{s} {task}: boundary outside data range {outside}")
            internal = [p for p in bnd if 1 < p <= n]
            edges = [1] + internal + [n + 1]
            segs = [(edges[k], edges[k + 1] - 1) for k in range(len(edges) - 1)]
            for p in internal:
                mkn = [f"Mk{m}:{'NewSegment' if ty.lower() == 'new segment' else ty + '/' + d}"
                       for m, ty, d, q in mk if q == p and is_boundary(ty, d)]
                brows.append({"subject": s, "task": task, "marker": ";".join(mkn),
                              "sample": p, "onset_s": f"{p / FS:.3f}", "datapoints": n,
                              "seg_before_s": f"{(p - 1 - edges[edges.index(p) - 1] + 1) / FS:.3f}",
                              "seg_after_s": f"{(edges[edges.index(p) + 1] - p) / FS:.3f}"})

            if task == "rest":
                blocks, notes = rest_blocks(s, ev, n)
                blocks = [b + (None, False, ()) for b in blocks]
                dropped = 0
            else:
                blocks, dropped = task_blocks(ev)
                notes = []
            for nt in notes:
                problems.append(f"{s} {task}: {nt}")
            if dropped:
                problems.append(f"{s} {task}: {dropped} segment(s) without stimulus discarded (D3e-3)")

            kept_stim, block_first, lost_stim = set(), set(), set()
            for lab, a, e, nstim, split, stims in blocks:
                row = {"subject": s, "task": task, "block": lab, "n_stim": "" if nstim is None else nstim,
                       "split_10s": int(split), "start_s": f"{a / FS:.3f}", "end_s": f"{e / FS:.3f}",
                       "dur_s": f"{(e - a + 1) / FS:.3f}"}
                sa = [k for k, (x, y) in enumerate(segs) if x <= a <= y]
                if not sa:
                    row.update(status="STOP_START_OUTSIDE_DATA")
                    problems.append(f"{s} {task} {lab}: block start outside the recorded data")
                    crows.append(row)
                    continue
                # D4e: the segment is the one containing the block start; its end is the NEXT edge
                # after the start (recording end or the first raw boundary inside the block).
                x, y = segs[sa[0]]
                inside = [p for p in internal if a < p <= e]  # raw boundaries inside the block
                stim_after = [p for p, _, tt in ev if tt == "stimulus" and y < p <= e]
                if stim_after:                                # data on both sides: would need a split
                    row.update(status="STOP_STIMULI_AFTER_RAW_BOUNDARY")
                    problems.append(f"{s} {task} {lab}: stimuli after a raw boundary inside the block")
                    crows.append(row)
                    continue
                a2, e2 = max(a, x + G), min(e, y - G)
                cs, ce = a2 - a, e - e2                      # samples clipped at each end
                why_s = "" if cs == 0 else ("recording_start" if x == 1 else "raw_boundary")
                why_e = "" if ce == 0 else ("recording_end" if y == n else
                                            ("raw_boundary_inside_block" if inside else "raw_boundary"))
                st = [p for p, _, tt in ev if tt == "stimulus" and a <= p <= e]
                row.update(seg_start_s=f"{x / FS:.3f}", seg_end_s=f"{y / FS:.3f}",
                           raw_bnd_inside_block=";".join(f"{p / FS:.3f}" for p in inside),
                           clip_start_s=f"{cs / FS:.3f}", clip_start_reason=why_s,
                           clip_end_s=f"{ce / FS:.3f}", clip_end_reason=why_e,
                           new_start_s=f"{a2 / FS:.3f}", new_end_s=f"{e2 / FS:.3f}",
                           new_dur_s=f"{(e2 - a2 + 1) / FS:.3f}",
                           stim_before_new_start=sum(p < a2 for p in st) if task == "msit" else "",
                           stim_after_new_end=sum(p > e2 for p in st) if task == "msit" else "",
                           status="CLIPPED" if (cs or ce) else "unchanged")
                crows.append(row)
                if stims:                                    # task blocks: per-stimulus status
                    block_first.add(min(stims))
                    for p in stims:
                        inside_new = a2 <= p <= e2
                        (kept_stim if inside_new else lost_stim).add(p)
                        if not inside_new:
                            lost_rows.append({"subject": s, "block": lab, "sample": p, "onset_s": f"{p / FS:.3f}",
                                              "where": "before_new_start" if p < a2 else "after_new_end"})

            if task == "msit":
                fimb = first_in_miniblock(ev)
                code = {p: t for p, t, tt in ev if tt == "stimulus"}
                for r in lost_rows:
                    if r["subject"] == s:
                        r.update(code=code[r["sample"]], condition=COND[code[r["sample"]]],
                                 first_in_miniblock=int(fimb[r["sample"]]),
                                 block_first=int(r["sample"] in block_first))
                for c_code, c in COND.items():
                    st = [p for p, t in code.items() if t == c_code]
                    use = [p for p in st if p in kept_stim and p not in block_first]   # usable pre-stimulus
                    cond_rows.append({
                        "subject": s, "condition": c, "n_stim": len(st),
                        "n_block_first": sum(p in block_first for p in st),
                        "n_lost_d4e": sum(p in lost_stim for p in st),
                        "n_lost_d4e_not_block_first": sum(p in lost_stim and p not in block_first for p in st),
                        "n_kept": len(use),
                        "n_kept_first_in_miniblock": sum(fimb[p] for p in use),
                        "n_kept_later": sum(not fimb[p] for p in use)})
                    if len(st) != sum(p in kept_stim or p in lost_stim for p in st):
                        problems.append(f"{s} {c}: stimuli outside every block")

    with open(os.path.join(OUT, "raw_boundaries.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["subject", "task", "marker", "sample", "onset_s", "datapoints",
                                           "seg_before_s", "seg_after_s"])
        w.writeheader()
        w.writerows(brows)
    cols = ["subject", "task", "block", "n_stim", "split_10s", "start_s", "end_s", "dur_s", "seg_start_s",
            "seg_end_s", "raw_bnd_inside_block", "clip_start_s", "clip_start_reason", "clip_end_s",
            "clip_end_reason", "new_start_s", "new_end_s", "new_dur_s", "stim_before_new_start",
            "stim_after_new_end", "status"]
    with open(os.path.join(OUT, "d4e_block_clipping.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, restval="")
        w.writeheader()
        w.writerows(crows)

    with open(os.path.join(OUT, "d4e_lost_stimuli.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["subject", "block", "sample", "onset_s", "where", "code", "condition",
                                           "first_in_miniblock", "block_first"])
        w.writeheader()
        w.writerows(lost_rows)
    ccols = ["subject", "condition", "n_stim", "n_block_first", "n_lost_d4e", "n_lost_d4e_not_block_first",
             "n_kept", "n_kept_first_in_miniblock", "n_kept_later"]
    with open(os.path.join(OUT, "d4e_trials_by_condition.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=ccols)
        w.writeheader()
        w.writerows(cond_rows)

    print(f"H = {H:.4f} s ({G} samples at {FS} Hz), from filter_halflengths.csv")
    print(f"internal raw boundaries: {len(brows)} in "
          f"{len({(r['subject'], r['task']) for r in brows})} recordings")
    for r in brows:
        print(f"  {r['subject']} {r['task']:4s} {r['marker']:42s} at {r['onset_s']:>9s} s "
              f"(segment before {r['seg_before_s']} s, after {r['seg_after_s']} s)")
    print(f"blocks: {len(crows)}; clipped: {sum(r['status'] == 'CLIPPED' for r in crows)}")
    for r in crows:
        if r["status"] != "unchanged":
            print("  " + ", ".join(f"{k}={r.get(k, '')}" for k in
                                   ("subject", "task", "block", "dur_s", "clip_start_s", "clip_start_reason",
                                    "clip_end_s", "clip_end_reason", "new_dur_s", "stim_before_new_start",
                                    "stim_after_new_end", "status")))
    print("stimuli outside their clipped block:")
    for r in lost_rows:
        print("  " + ", ".join(f"{k}={r[k]}" for k in ("subject", "block", "onset_s", "where", "condition",
                                                         "first_in_miniblock", "block_first")))
    print("kept pre-stimulus trials (not block-first, inside the clipped block), min over 42 subjects:")
    for c in COND.values():
        rows = [r for r in cond_rows if r["condition"] == c]
        for k in ("n_kept", "n_kept_first_in_miniblock", "n_kept_later"):
            m = min(r[k] for r in rows)
            print(f"  {c} {k}: min {m} ({', '.join(r['subject'] for r in rows if r[k] == m)})")
    print("checks:", "none failed" if not problems else "")
    for p in problems:
        print("  " + p)


if __name__ == "__main__":
    main()
