"""Stage 5: empirical survey of the within-task control window (late ITI), over all 39 subjects.

Read-only. Reads only the raw `*_task-msit_events.tsv` of the 39 retained subjects and the Stage-3
block-clipping table, through the readers of stage5_window_overlap_check.py so the parsing is identical.
No EEG sample is read and no spectral or 13-30 Hz quantity is computed anywhere in this script.

Why. `revision_plan.md` Stage 5, audit items #5 and #6, and CLAUDE.md step 1 ask for the pre-stimulus
window to be compared against a within-task control window of the SAME length, so that rest and task share
one spectral estimator and the pre-stimulus elevation can be shown to be specific to the pre-stimulus
moment rather than a general within-task level. Amirhossein decided (2026-11-08) that the control window
is a LATE ITI window, not a post-response window: the post-response interval is the beta-rebound (ERS)
period, which sec 10g already identified as the contaminator of the later-trial baselines, so using it as a
"control" would measure a different physiological state instead of a neutral within-task level.

He also required the window's length and position to be established empirically over all 39 subjects
rather than assumed, exactly as the pre-stimulus window was in sec 10g. This script does that and nothing
else: it decides no analysis and computes no power.

The geometry. For a trial at onset t whose previous in-block trial is at onset p, the free interval
between the previous ACTIVE window and this trial's BASELINE window is
    gap = [p + 1000, t - 500)        length  gap_ms = (t - p) - 1500
so a control window of length L fits only where gap_ms >= L. sec 10g's own diagnostics already show the
problem this script must size: the median gap is 534 ms, so a 500 ms window does not fit in a typical ITI.
The long intervals are at the mini-block boundaries (the dataset paper gives an inter-mini-block interval
of 2.5-4.4 s), which is why the survey reports every quantity separately for trials that are
first-in-mini-block and trials that are not.

What it reports, per subject and pooled, for each candidate length L in CANDIDATE_L:
  - how many trial pairs have gap_ms >= L at all, split by mini-block class
  - with the window CENTRED in the gap: its clearance from the previous active window, from the previous
    response, and from the upcoming onset (the quantity that decides whether the window is neutral)
  - with the window placed LATE (immediately before the baseline) and EARLY (immediately after the previous
    active window), the same clearances, so the placement choice is made on measured numbers
  - per-condition counts, and whether every subject could keep >= 50 % of each condition's trials, the
    project-wide D12 rule the export would apply
  - how often the previous response falls inside the candidate window, which would put a movement artefact
    and the ERS peak straight into the control estimate
  - whether the window lies inside the clipped task block

Grid note: like stage5_window_overlap_check.py this works on the raw 1000 Hz grid of events.tsv, while the
pipeline analyses at 500 Hz where an edge can move by one sample (2 ms). Every margin reported here is
orders of magnitude larger.

Usage
  python stage5_iti_window_survey.py <raw_root> <block_table> <out_dir>
Outputs (in out_dir; never overwritten)
  stage5_iti_window_per_subject.csv
  stage5_iti_window_summary.json
"""
import csv
import json
import os
import statistics
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stage5_window_overlap_check as wc      # noqa: E402  (same readers, same parsing)

FS = wc.FS                                    # 1000, the events.tsv grid
BASELINE_MS = wc.BASELINE_MS                  # (-500, 0)
ACTIVE_MS = wc.ACTIVE_MS                      # (0, 1000)
COND = wc.COND
CANDIDATE_L = (250, 300, 400, 500)            # ms; 500 matches the baseline window exactly
PLACEMENTS = ("late", "centred", "early")
MIN_FRAC_KEPT = 0.5                           # the project-wide per-condition rule


def place(gap_lo, gap_hi, L, how):
    """Inclusive sample range of a control window of length L inside the free interval [gap_lo, gap_hi).
    'late' sits against the baseline, 'early' against the previous active window, 'centred' in the middle.
    Returns None if it does not fit."""
    if gap_hi - gap_lo < L:
        return None
    if how == "late":
        a = gap_hi - L
    elif how == "early":
        a = gap_lo
    else:
        a = gap_lo + (gap_hi - gap_lo - L) // 2
    return a, a + L - 1


def summarise(xs):
    if not xs:
        return None
    return dict(n=len(xs), min=min(xs), p05=round(wc.pct(xs, 5), 1), median=round(wc.pct(xs, 50), 1),
                p95=round(wc.pct(xs, 95), 1), max=max(xs), mean=round(statistics.fmean(xs), 1))


def main():
    raw = sys.argv[1] if len(sys.argv) > 1 else wc.RAW
    blocks_path = sys.argv[2] if len(sys.argv) > 2 else wc.BLOCKS
    out = sys.argv[3] if len(sys.argv) > 3 else wc.OUT
    per_csv = os.path.join(out, "stage5_iti_window_per_subject.csv")
    sum_json = os.path.join(out, "stage5_iti_window_summary.json")
    for p in (per_csv, sum_json):
        if os.path.exists(p):
            raise SystemExit(f"output exists, not overwritten: {p}")

    blocks = wc.read_blocks(blocks_path)
    subjects = sorted(s for s in blocks if s not in wc.EXCLUDED)
    assert len(subjects) == 39, f"{len(subjects)} subjects in the block table, 39 expected"
    os.makedirs(out, exist_ok=True)

    rows = []
    pooled = {}          # (L, placement, class) -> dict of lists
    gap_by_class = {"first": [], "later": []}
    n_pairs = 0

    def cell(L, how, cls):
        return pooled.setdefault((L, how, cls), dict(clear_prev_active=[], clear_prev_resp=[],
                                                     clear_next_onset=[], resp_inside=0, n=0,
                                                     outside_block=0))

    for sub in subjects:
        ev = wc.read_events(os.path.join(raw, sub, "eeg", f"{sub}_task-msit_events.tsv"))
        fimb = wc.first_in_miniblock(ev)
        resp = wc.responses(ev)
        stim = [(p, t) for p, t, tt in ev if tt == "stimulus"]
        row = dict(subject=sub)
        fit = {(L, c): 0 for L in CANDIDATE_L for c in ("first", "later")}
        cond_tot, cond_fit = {}, {}
        for blk, b0, b1 in blocks[sub]:
            inside = [(p, t) for p, t in stim if b0 <= p <= b1]
            inside.sort()
            for i in range(1, len(inside)):
                p_prev, t_prev = inside[i - 1]
                p_cur, t_cur = inside[i]
                if t_cur not in COND:
                    continue
                n_pairs += 1
                cls = "first" if fimb.get(p_cur, False) else "later"
                cname = COND[t_cur]
                cond_tot[(cname, cls)] = cond_tot.get((cname, cls), 0) + 1
                gap_lo = p_prev + ACTIVE_MS[1]                 # first free sample after the active window
                gap_hi = p_cur + BASELINE_MS[0]                # first sample of the baseline window
                gap_by_class[cls].append(gap_hi - gap_lo)
                for L in CANDIDATE_L:
                    w = place(gap_lo, gap_hi, L, "late")
                    if w is not None:
                        fit[(L, cls)] += 1
                        cond_fit[(cname, cls, L)] = cond_fit.get((cname, cls, L), 0) + 1
                    for how in PLACEMENTS:
                        w = place(gap_lo, gap_hi, L, how)
                        if w is None:
                            continue
                        c = cell(L, how, cls)
                        c["n"] += 1
                        c["clear_prev_active"].append(w[0] - gap_lo)
                        c["clear_next_onset"].append(p_cur - w[1] - 1)
                        if not (b0 <= w[0] and w[1] <= b1):
                            c["outside_block"] += 1
                        r = resp.get(p_prev)
                        if r is not None:
                            c["clear_prev_resp"].append(w[0] - r)
                            if w[0] <= r <= w[1]:
                                c["resp_inside"] += 1
        for L in CANDIDATE_L:
            for cls in ("first", "later"):
                row[f"fit_L{L}_{cls}"] = fit[(L, cls)]
        for L in CANDIDATE_L:
            fr = []
            for (cname, cls), tot in cond_tot.items():
                if cls == "first":
                    fr.append(cond_fit.get((cname, cls, L), 0) / tot if tot else 0.0)
            row[f"min_cond_frac_first_L{L}"] = round(min(fr), 4) if fr else ""
            fr2 = [cond_fit.get((cname, cls, L), 0) / tot
                   for (cname, cls), tot in cond_tot.items() if tot]
            row[f"min_cond_frac_all_L{L}"] = round(min(fr2), 4) if fr2 else ""
        rows.append(row)

    with open(per_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), restval="")
        w.writeheader()
        w.writerows(rows)

    summary = dict(n_subjects=len(subjects), n_consecutive_pairs=n_pairs,
                   baseline_window_ms=list(BASELINE_MS), active_window_ms=list(ACTIVE_MS),
                   candidate_lengths_ms=list(CANDIDATE_L), placements=list(PLACEMENTS),
                   gap_ms={k: summarise(v) for k, v in gap_by_class.items()},
                   cells={}, per_subject_min_fraction={},
                   inputs=dict(raw_root=raw, block_table=blocks_path))
    for (L, how, cls), c in sorted(pooled.items()):
        summary["cells"][f"L{L}_{how}_{cls}"] = dict(
            n_fitting=c["n"], outside_block=c["outside_block"], prev_response_inside=c["resp_inside"],
            clearance_from_prev_active_ms=summarise(c["clear_prev_active"]),
            clearance_from_prev_response_ms=summarise(c["clear_prev_resp"]),
            clearance_to_next_onset_ms=summarise(c["clear_next_onset"]))
    for L in CANDIDATE_L:
        for key in (f"min_cond_frac_first_L{L}", f"min_cond_frac_all_L{L}"):
            v = [r[key] for r in rows if r[key] != ""]
            summary["per_subject_min_fraction"][key] = dict(
                min=min(v), median=round(wc.pct(v, 50), 4), max=max(v),
                n_subjects_below_half=sum(x < MIN_FRAC_KEPT for x in v))
    with open(sum_json, "w") as fh:
        json.dump(summary, fh, indent=1)

    print(f"{len(subjects)} subjects, {n_pairs} consecutive in-block trial pairs")
    for cls in ("first", "later"):
        g = summary["gap_ms"][cls]
        print(f"  gap_ms {cls:6s}: n {g['n']:6d}  min {g['min']:5d}  median {g['median']:7.1f}  "
              f"p95 {g['p95']:7.1f}  max {g['max']:5d}")
    print()
    hdr = f"{'cell':22s} {'n fit':>6s} {'prev-act':>9s} {'prev-resp':>10s} {'to onset':>9s} {'resp in':>8s}"
    print(hdr)
    for k, c in summary["cells"].items():
        a = c["clearance_from_prev_active_ms"]
        r = c["clearance_from_prev_response_ms"]
        o = c["clearance_to_next_onset_ms"]
        print(f"{k:22s} {c['n_fitting']:6d} "
              f"{(a['median'] if a else float('nan')):9.0f} "
              f"{(r['median'] if r else float('nan')):10.0f} "
              f"{(o['median'] if o else float('nan')):9.0f} "
              f"{c['prev_response_inside']:8d}")
    print()
    for k, v in summary["per_subject_min_fraction"].items():
        print(f"{k:28s} min {v['min']:.3f}  median {v['median']:.3f}  "
              f"subjects below 0.5: {v['n_subjects_below_half']}")
    print(f"\nwrote: {os.path.basename(per_csv)}, {os.path.basename(sum_json)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
