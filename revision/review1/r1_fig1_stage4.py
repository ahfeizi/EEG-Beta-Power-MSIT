"""Review round 1: Figure 1 redrawn from the Stage-4 classification — decision log §11y (descriptive).

    python r1_fig1_stage4.py --mode gate --stage4 <outRoot>/stage4 --roi-dir <eegOutRoot>/stage4/roi
        --out-dir <outRoot>/review1/fig1_stage4

    python r1_fig1_stage4.py --mode export (same arguments)            # Python 3.12: fooof 1.1.1, no matplotlib
    python r1_fig1_stage4.py --mode draw --stage4 <outRoot>/stage4 --out-dir <outRoot>/review1/fig1_stage4
                                                                        # Python 3.15: matplotlib, no fooof

The figure is made in two steps because no installed interpreter has both fooof 1.1.1 and matplotlib, and neither
environment is changed (decided by Amirhossein, 2026-11-16, option A).

Mode `export` (§11y G0 + data for G1): requires r1_fig1_gate.json to record a pass, runs the same checks again in
  memory (collect) and, only if they pass, writes fig1_stage4_plotted.csv (every curve point of both curves and
  every beta-range Gaussian marker of the 39 participants, floats at full precision) and fig1_stage4_export.json
  (provenance: this run's gate result, script SHA-256, input SHA-256s, the CSV's SHA-256, band and grid).
Mode `draw` (§11y G1-G8): imports no fooof. Reads only fig1_stage4_plotted.csv, peaks_primary.csv and
  peaks_all_in_range.csv (plus the export record). Refuses to draw unless the export record shows a passing gate,
  the same script SHA-256 as the running file, and matching SHA-256s for the CSV and both inputs, and unless the
  CSV's markers equal peaks_all_in_range.csv. Then draws the 5 x 8 grid and writes fig1_stage4.png (200 dpi), .pdf,
  fig1_stage4_drawn.csv (every drawn element, with threshold end points, clip marks and clipped flags) and
  fig1_stage4_panels.json (read back from the drawn figure's axes). Never overwrites.

Mode `gate` (§11y G0). For each of the 39 rest ROI files: load_roi -> welch_runs ->
  (a) the frozen pipeline, core.run_pipeline (aperiodic-only check, then core.full_fit), and
  (b) the wrapper fit, core._fooof() with fm.fit(freqs, psd, list(core.FIT_RANGE)) -- the call core.full_fit makes --
      from which fm.freqs, fm._spectrum_flat and fm._peak_fit (private fooof 1.1.1 attributes) are taken.
  Checks, all evaluated and reported:
  - inputs: thr_p95 in peaks_primary.csv equals the p95 of thresholds_per_subject.json (exactly);
  - wrapper fm.peak_params_ equals core.full_fit's peaks exactly (np.array_equal), and its R^2 equals it exactly;
  - peaks_primary.csv: class_p95 and n_beta_peaks exactly; primary_cf / primary_pw / primary_bw and r2_full within
    1e-9 (empty fields where the participant has no beta-range Gaussian must stay empty);
  - peaks_all_in_range.csv: per participant, the same number of rows, and rank by rank cf / pw / bw within 1e-9 and
    pw_ge_p95 exactly;
  - the curves are finite and on the 77-bin fit grid.
  If any check fails: exit code 1, nothing written (the out-dir is not created). If all pass: only
  r1_fig1_gate.json (the check report and provenance) is written. Nothing is drawn in this mode.

stage4_core is imported unchanged (frozen at S4-prereg-frozen).
"""
import argparse
import csv
import glob
import hashlib
import json
import os
import sys

import numpy as np

rc = core = None                             # loaded by _load_core() in gate/export only (draw has no fooof)


def _load_core():
    global rc, core
    import r1_common                         # puts revision/stage4 on sys.path; imports stage4_core unchanged
    rc, core = r1_common, r1_common.core


N_SUBJECTS = 39
TOL = 1e-9                                   # §11y G0
PRIMARY_NUM = ('primary_cf', 'primary_pw', 'primary_bw')


def wrapper_fit(freqs, psd):
    """The core.full_fit call, keeping the model object so its curves can be read (§11y G0)."""
    fm = core._fooof()
    fm.fit(freqs, psd, list(core.FIT_RANGE))
    if not fm.has_model:
        return None
    return dict(peaks=np.reshape(fm.peak_params_, (-1, 3)), r2=float(fm.r_squared_), freqs=np.array(fm.freqs),
                spectrum_flat=np.array(fm._spectrum_flat), peak_fit=np.array(fm._peak_fit))


def close(a, b):
    return abs(a - b) <= TOL                 # False for NaN


def inputs(args):
    return dict(peaks_primary=os.path.join(args.stage4, 'peak_detection', 'peaks_primary.csv'),
                peaks_all_in_range=os.path.join(args.stage4, 'peak_detection', 'peaks_all_in_range.csv'),
                thresholds=os.path.join(args.stage4, 'sim_rough', 'thresholds_per_subject.json'))


def gate(args):
    _load_core()
    out = os.path.join(args.out_dir, 'r1_fig1_gate.json')
    rc.refuse_existing([out])
    report, _ = collect(args)
    print(json.dumps({k: report[k] for k in ('passed', 'failed_checks', 'n_roi_files', 'max_abs_diff',
                                             'n_in_range_rows_checked', 'failures')}, indent=2, default=str))
    if not report['passed']:
        print('GATE FAILED: nothing written.', file=sys.stderr)
        sys.exit(1)
    os.makedirs(args.out_dir, exist_ok=True)
    with open(out, 'w') as fh:
        json.dump(report, fh, indent=2, default=str)
    print(f'GATE PASSED. Written: {os.path.basename(out)}')


def collect(args):
    """All §11y G0 checks, in memory. Returns (report, per-subject data for plotting). Writes nothing."""
    _load_core()
    paths = inputs(args)
    pp_csv, pa_csv, thr_json = paths['peaks_primary'], paths['peaks_all_in_range'], paths['thresholds']
    data = {}

    primary = {r['subject']: r for r in rc.read_csv(pp_csv)}
    allpk = {}
    for r in rc.read_csv(pa_csv):
        allpk.setdefault(r['subject'], []).append(r)
    for s in allpk:
        allpk[s].sort(key=lambda r: int(r['rank']))
    with open(thr_json) as fh:
        tj = json.load(fh)
    if tj.get('test_run', True):
        raise SystemExit('thresholds file is a TEST run (or lacks test_run)')

    fails = {k: [] for k in ('subjects', 'thr_input', 'wrapper_peaks', 'wrapper_r2', 'class_p95', 'n_beta_peaks',
                             'primary_values', 'r2_full', 'in_range_count', 'in_range_values', 'in_range_flag',
                             'curves')}
    max_diff = {'primary_values': 0.0, 'r2_full': 0.0, 'in_range_values': 0.0}
    files = sorted(glob.glob(os.path.join(args.roi_dir, 'sub-*_rest_roi.mat')))
    seen = []
    for f in files:
        rec = core.load_roi(f)
        s = rec['subject']
        seen.append(s)
        if s not in primary:
            fails['subjects'].append((s, 'not in peaks_primary.csv'))
            continue
        p = primary[s]
        thr = float(p['thr_p95'])
        if thr != float(tj['thresholds'][s]['p95']):
            fails['thr_input'].append((s, thr, tj['thresholds'][s]['p95']))

        freqs, psd = core.welch_runs(rec['runs'], rec['fs'])
        ref = core.run_pipeline(freqs, psd)                 # the frozen path (real data: raises on failure)
        w = wrapper_fit(freqs, psd)
        if w is None or not np.array_equal(w['peaks'], ref['peaks']):
            fails['wrapper_peaks'].append(s)
            continue
        if w['r2'] != ref['r2']:
            fails['wrapper_r2'].append((s, w['r2'], ref['r2']))

        cls = core.classify(ref, thr)
        if cls != p['class_p95']:
            fails['class_p95'].append((s, cls, p['class_p95']))
        bp = core.beta_peaks(ref['peaks'])
        if len(bp) != int(p['n_beta_peaks']):
            fails['n_beta_peaks'].append((s, len(bp), p['n_beta_peaks']))
        for j, k in enumerate(PRIMARY_NUM):
            if len(bp) == 0:
                if p[k] != '':
                    fails['primary_values'].append((s, k, 'no beta Gaussian recomputed', p[k]))
                continue
            d = abs(bp[0, j] - float(p[k]))
            max_diff['primary_values'] = max(max_diff['primary_values'], d)
            if not d <= TOL:
                fails['primary_values'].append((s, k, float(bp[0, j]), p[k]))
        d = abs(ref['r2'] - float(p['r2_full']))
        max_diff['r2_full'] = max(max_diff['r2_full'], d)
        if not d <= TOL:
            fails['r2_full'].append((s, ref['r2'], p['r2_full']))

        rows = allpk.get(s, [])
        if len(rows) != len(bp):
            fails['in_range_count'].append((s, len(bp), len(rows)))
        else:
            for pk, r in zip(bp, rows):
                for j, k in enumerate(('cf', 'pw', 'bw')):
                    d = abs(pk[j] - float(r[k]))
                    max_diff['in_range_values'] = max(max_diff['in_range_values'], d)
                    if not d <= TOL:
                        fails['in_range_values'].append((s, r['rank'], k, float(pk[j]), r[k]))
                if int(pk[1] >= thr) != int(r['pw_ge_p95']):
                    fails['in_range_flag'].append((s, r['rank'], int(pk[1] >= thr), r['pw_ge_p95']))

        if not (w['freqs'].size == core.N_BINS and np.all(np.isfinite(w['spectrum_flat']))
                and np.all(np.isfinite(w['peak_fit']))):
            fails['curves'].append(s)
        print(f"{s}  class {cls}  n_beta {len(bp)}", flush=True)
        data[s] = dict(freqs=w['freqs'], spectrum_flat=w['spectrum_flat'], peak_fit=w['peak_fit'], beta_peaks=bp)

    if not (len(seen) == N_SUBJECTS and sorted(seen) == sorted(primary)):
        fails['subjects'].append(('set', len(seen), len(primary)))
    passed = not any(fails.values())
    report = dict(passed=passed, failed_checks=[k for k, v in fails.items() if v], n_roi_files=len(files),
                  tol=TOL, max_abs_diff=max_diff, failures=fails,
                  n_in_range_rows_checked=sum(len(v) for v in allpk.values()),
                  provenance=rc.provenance(__file__, paths), roi_dir=args.roi_dir)
    return report, data


# ---------------------------------------------------------------------------------------------------------
# Modes `export` (Python 3.12) and `draw` (Python 3.15), §11y G1-G8.
# Sources in `draw`: curves = fig1_stage4_plotted.csv (written by `export` from the gated wrapper fit); class,
# threshold, R^2 = peaks_primary.csv; markers (CF, PW and the filled/open flag) = peaks_all_in_range.csv.
# ---------------------------------------------------------------------------------------------------------
X_RANGE = (2.0, 40.0)                        # G2: the fitted range
BAND = (13.0, 30.0)                          # = stage4_core.BETA, inclusive (checked in `export`, recorded)
Y_PAD = 0.10                                 # G3: 10 % of the range on each side
N_COLS, N_ROWS = 5, 8                        # G4
N_BINS = 77                                  # = stage4_core.N_BINS (checked in `export`, recorded)
EXPORT_OUT = ('fig1_stage4_plotted.csv', 'fig1_stage4_export.json')
FIG_OUT = ('fig1_stage4.png', 'fig1_stage4.pdf', 'fig1_stage4_drawn.csv', 'fig1_stage4_panels.json')
DPI = 200                                    # G7, as Figure 3
STYLE = dict(data=dict(color='0.35', lw=0.6), model=dict(color='black', lw=1.4),
             thr=dict(color='tab:red', lw=1.0, ls='--'), band='#dbe7f3', grey='0.65', marker_size=4.0)


def sha256(path):
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def read_csv(path):                          # no r1_common in `draw` (it imports fooof)
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def write_csv(path, rows):
    tmp = path + '.tmp'
    with open(tmp, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def refuse_existing(paths):
    for p in paths:
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')


def export(args):
    """Gate in memory; only if it passes, write every curve point and every marker, and the export record."""
    _load_core()
    outs = {k: os.path.join(args.out_dir, k) for k in EXPORT_OUT}
    refuse_existing(outs.values())
    gate_json = os.path.join(args.out_dir, 'r1_fig1_gate.json')
    with open(gate_json) as fh:
        if not json.load(fh).get('passed'):
            raise SystemExit('r1_fig1_gate.json does not record a pass: nothing exported')
    if tuple(core.BETA) != BAND or core.N_BINS != N_BINS:
        raise SystemExit(f'band / bins differ from stage4_core: {core.BETA}, {core.N_BINS}')
    report, data = collect(args)
    print(json.dumps({k: report[k] for k in ('passed', 'failed_checks', 'n_roi_files', 'max_abs_diff',
                                             'n_in_range_rows_checked')}, indent=2, default=str))
    if not report['passed']:
        print('GATE FAILED in this run: nothing exported.', file=sys.stderr)
        sys.exit(1)
    rows = []
    for s in sorted(data):
        d = data[s]
        for name, key in (('data_residual', 'spectrum_flat'), ('periodic_component', 'peak_fit')):
            rows += [dict(subject=s, element=name, rank='', freq_hz=float(f), value=float(v), bw_hz='')
                     for f, v in zip(d['freqs'], d[key])]
        for rank, (cf, pw, bw) in enumerate(d['beta_peaks'], 1):
            rows.append(dict(subject=s, element='gaussian', rank=rank, freq_hz=float(cf), value=float(pw),
                             bw_hz=float(bw)))
    write_csv(outs['fig1_stage4_plotted.csv'], rows)
    record = dict(section='§11y', gate_passed_this_run=True, gate_report=report,
                  gate_json=dict(path=gate_json, sha256=sha256(gate_json)),
                  plotted_csv=dict(path=outs['fig1_stage4_plotted.csv'], sha256=sha256(outs['fig1_stage4_plotted.csv']),
                                   n_rows=len(rows)),
                  script_sha256=sha256(__file__), band_hz=BAND, n_bins=N_BINS, n_subjects=len(data),
                  inputs={k: dict(path=v, sha256=sha256(v)) for k, v in inputs(args).items()})
    with open(outs['fig1_stage4_export.json'], 'w') as fh:
        json.dump(record, fh, indent=2, default=str)
    print(f"EXPORT DONE. Written: {', '.join(EXPORT_OUT)}  ({len(rows)} rows, {len(data)} participants)")


def load_export(args):
    """`draw`: verify the export record, then read the curves and markers back from the CSV."""
    rec_path = os.path.join(args.out_dir, 'fig1_stage4_export.json')
    csv_path = os.path.join(args.out_dir, 'fig1_stage4_plotted.csv')
    if not os.path.exists(rec_path):
        raise SystemExit('no export record: run --mode export first; nothing drawn')
    with open(rec_path) as fh:
        rec = json.load(fh)
    problems = []
    if rec.get('gate_passed_this_run') is not True or not rec.get('gate_report', {}).get('passed'):
        problems.append('export record does not show a passing gate')
    if rec.get('script_sha256') != sha256(__file__):
        problems.append('script SHA-256 differs from the export run (re-run --mode export with this version)')
    if rec.get('plotted_csv', {}).get('sha256') != sha256(csv_path):
        problems.append('fig1_stage4_plotted.csv differs from the exported file')
    for k, v in inputs(args).items():
        if rec.get('inputs', {}).get(k, {}).get('sha256') != sha256(v):
            problems.append(f'{k} differs from the file the export was checked against')
    if tuple(rec.get('band_hz', ())) != BAND or rec.get('n_bins') != N_BINS:
        problems.append('band / bins differ from the export record')
    if problems:
        raise SystemExit('refusing to draw: ' + '; '.join(problems))
    data, marks = {}, {}
    for r in read_csv(csv_path):
        s = r['subject']
        if r['element'] == 'gaussian':
            marks.setdefault(s, []).append((int(r['rank']), float(r['freq_hz']), float(r['value']), float(r['bw_hz'])))
            continue
        d = data.setdefault(s, dict(freqs=[], freqs_model=[], spectrum_flat=[], peak_fit=[]))
        if r['element'] == 'data_residual':
            d['freqs'].append(float(r['freq_hz']))
            d['spectrum_flat'].append(float(r['value']))
        elif r['element'] == 'periodic_component':
            d['freqs_model'].append(float(r['freq_hz']))
            d['peak_fit'].append(float(r['value']))
        else:
            raise SystemExit(f"unknown element {r['element']!r} in the CSV: nothing drawn")
    for s, d in data.items():
        for k in d:
            d[k] = np.array(d[k])
        if not (d['freqs'].size == d['spectrum_flat'].size == d['peak_fit'].size == N_BINS
                and np.array_equal(d['freqs'], d['freqs_model'])):
            raise SystemExit(f'{s}: curves in the CSV are not {N_BINS} matching bins: nothing drawn')
    return rec, data, marks


def shared_ylim(data):
    """G3: min / max of the data residual within 13-30 Hz over all 39 participants, padded by 10 % of the range."""
    vals = np.concatenate([d['spectrum_flat'][(d['freqs'] >= BAND[0]) & (d['freqs'] <= BAND[1])]
                           for d in data.values()])
    lo, hi = float(vals.min()), float(vals.max())
    pad = Y_PAD * (hi - lo)
    return lo - pad, hi + pad, lo, hi


def clip_runs(freqs, y, lo, hi):
    """G3 clip marks: one mark per contiguous run of bins outside [lo, hi], at the run's most extreme bin."""
    marks = []
    for side, out in (('top', y > hi), ('bottom', y < lo)):
        idx = np.flatnonzero(out)
        if not idx.size:
            continue
        for run in np.split(idx, np.flatnonzero(np.diff(idx) > 1) + 1):
            k = run[np.argmax(y[run])] if side == 'top' else run[np.argmin(y[run])]
            marks.append((side, float(freqs[k]), float(y[k])))
    return marks


def panel_order(primary, allpk):
    """G4: classified participants by margin = max beta-range PW (0 if none) - own p95, descending (ties by ID);
    poor-fit participants last (by ID). Checks that margin >= 0 exactly for `peak` and < 0 for `no_peak`."""
    margin = {}
    for s, p in primary.items():
        if p['class_p95'] == 'poor_fit':
            continue
        mx = max([float(r['pw']) for r in allpk.get(s, [])], default=0.0)
        margin[s] = mx - float(p['thr_p95'])
        if (margin[s] >= 0) != (p['class_p95'] == 'peak'):
            raise SystemExit(f'{s}: margin {margin[s]} inconsistent with class {p["class_p95"]}')
    classified = sorted(margin, key=lambda s: (-margin[s], s))
    poor = sorted(s for s, p in primary.items() if p['class_p95'] == 'poor_fit')
    return classified + poor, margin


def draw(args):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.lines import Line2D
    from matplotlib.patches import Patch

    outs = {k: os.path.join(args.out_dir, k) for k in FIG_OUT}
    refuse_existing(outs.values())
    rec, data, marks = load_export(args)             # refuses on any provenance mismatch

    paths = inputs(args)
    primary = {r['subject']: r for r in read_csv(paths['peaks_primary'])}
    allpk = {}
    for r in read_csv(paths['peaks_all_in_range']):
        allpk.setdefault(r['subject'], []).append(r)
    # the CSV's markers must be the pre-registered in-range Gaussians, rank by rank
    if sorted(data) != sorted(primary) or len(data) != N_SUBJECTS:
        raise SystemExit('participants in the CSV differ from peaks_primary.csv: nothing drawn')
    for s in primary:
        a = sorted(marks.get(s, []))
        b = sorted((int(r['rank']), float(r['cf']), float(r['pw']), float(r['bw'])) for r in allpk.get(s, []))
        if len(a) != len(b) or any(x[0] != y[0] or max(abs(x[j] - y[j]) for j in (1, 2, 3)) > TOL
                                   for x, y in zip(a, b)):
            raise SystemExit(f'{s}: markers in the CSV differ from peaks_all_in_range.csv: nothing drawn')
    order, margin = panel_order(primary, allpk)
    if len(order) != N_SUBJECTS or len(order) >= N_COLS * N_ROWS:
        raise SystemExit(f'{len(order)} participants for a {N_COLS} x {N_ROWS} grid with a legend cell')
    ylo, yhi, rlo, rhi = shared_ylim(data)

    fig, axes = plt.subplots(N_ROWS, N_COLS, figsize=(7.5, 10.8), sharex=True, sharey=True)
    plotted = []
    for i, s in enumerate(order):
        ax = axes.flat[i]
        p, d = primary[s], data[s]
        poor = p['class_p95'] == 'poor_fit'
        f = d['freqs']
        ax.axvspan(BAND[0], BAND[1], color=STYLE['band'], lw=0, zorder=0)
        dcol = STYLE['grey'] if poor else STYLE['data']['color']
        mcol = STYLE['grey'] if poor else STYLE['model']['color']
        ax.plot(f, d['spectrum_flat'], color=dcol, lw=STYLE['data']['lw'], zorder=2)
        ax.plot(f, d['peak_fit'], color=mcol, lw=STYLE['model']['lw'], zorder=3)
        for k in range(f.size):
            plotted.append(dict(subject=s, panel=i, element='data_residual', freq_hz=f[k],
                                value=d['spectrum_flat'][k], filled='', clipped=int(not ylo <= d['spectrum_flat'][k] <= yhi)))
            plotted.append(dict(subject=s, panel=i, element='periodic_component', freq_hz=f[k],
                                value=d['peak_fit'][k], filled='', clipped=int(not ylo <= d['peak_fit'][k] <= yhi)))
        for name, y in (('data_residual', d['spectrum_flat']), ('periodic_component', d['peak_fit'])):
            for side, fx, fy in clip_runs(f, y, ylo, yhi):
                ax.plot(fx, yhi if side == 'top' else ylo, marker='^' if side == 'top' else 'v',
                        color=dcol if name == 'data_residual' else mcol, ms=3, clip_on=False, zorder=5)
                plotted.append(dict(subject=s, panel=i, element=f'clip_mark_{name}_{side}', freq_hz=fx,
                                    value=fy, filled='', clipped=1))
        if not poor:
            thr = float(p['thr_p95'])
            ax.hlines(thr, BAND[0], BAND[1], colors=STYLE['thr']['color'], linestyles=STYLE['thr']['ls'],
                      lw=STYLE['thr']['lw'], zorder=4)
            plotted += [dict(subject=s, panel=i, element='threshold_p95', freq_hz=x, value=thr, filled='',
                             clipped=int(not ylo <= thr <= yhi)) for x in BAND]
            if not ylo <= thr <= yhi:                # G3: a clipped threshold line is marked like any clipped value
                side = 'top' if thr > yhi else 'bottom'
                fx = (BAND[0] + BAND[1]) / 2         # the line is horizontal: one mark at the middle of 13-30 Hz
                ax.plot(fx, yhi if side == 'top' else ylo, marker='^' if side == 'top' else 'v',
                        color=STYLE['thr']['color'], ms=3, clip_on=False, zorder=5)
                plotted.append(dict(subject=s, panel=i, element=f'clip_mark_threshold_p95_{side}', freq_hz=fx,
                                    value=thr, filled='', clipped=1))
        for r in sorted(allpk.get(s, []), key=lambda r: int(r['rank'])):
            cf, pw = float(r['cf']), float(r['pw'])
            filled = (not poor) and int(r['pw_ge_p95']) == 1
            y = min(max(pw, ylo), yhi)
            ax.plot(cf, y, marker='o', ms=STYLE['marker_size'], mew=0.9, zorder=6, clip_on=False,
                    mec=mcol, mfc=mcol if filled else 'white')
            plotted.append(dict(subject=s, panel=i, element='gaussian', freq_hz=cf, value=pw,
                                filled=int(filled), clipped=int(y != pw)))
        ax.set_title(s, fontsize=7, pad=2, color=STYLE['grey'] if poor else 'black')
        if poor:
            ax.text(0.5, 0.92, f"poor fit (R² = {float(p['r2_full']):.2f})\nnot classified",
                    transform=ax.transAxes, ha='center', va='top', fontsize=5.5, color='0.35')
        ax.tick_params(labelsize=6, length=2, pad=1)

    ax.set_xlim(*X_RANGE)
    ax.set_ylim(ylo, yhi)
    ax.set_xticks([10, 20, 30, 40])
    for ax in axes.flat[len(order):]:
        ax.set_axis_off()
    leg = axes.flat[N_COLS * N_ROWS - 1]
    leg.legend(handles=[
        Line2D([], [], **STYLE['data']), Line2D([], [], **STYLE['model']),
        Line2D([], [], marker='o', ls='', mfc='black', mec='black', ms=STYLE['marker_size']),
        Line2D([], [], marker='o', ls='', mfc='white', mec='black', ms=STYLE['marker_size']),
        Line2D([], [], **STYLE['thr']), Patch(color=STYLE['band']),
        Line2D([], [], marker='^', ls='', color='0.35', ms=3)],
        labels=['data residual', 'periodic component', 'Gaussian ≥ own p95', 'Gaussian < own p95',
                'own p95 threshold', '13–30 Hz', 'clipped value'],
        loc='center', fontsize=5.5, frameon=False)
    fig.supxlabel('Frequency (Hz)', fontsize=8)
    fig.supylabel('log₁₀ power relative to the aperiodic fit', fontsize=8)
    fig.tight_layout(pad=0.4, h_pad=0.5, w_pad=0.3)

    os.makedirs(args.out_dir, exist_ok=True)
    fig.savefig(outs['fig1_stage4.png'], dpi=DPI)
    fig.savefig(outs['fig1_stage4.pdf'])

    # G7: the panel record is read back from the drawn figure (axis titles and grid positions), not from `order`
    rendered = []
    for ax in fig.axes:
        if not ax.axison or not ax.get_title():
            continue
        ss = ax.get_subplotspec()
        s = ax.get_title()
        rendered.append(dict(row=ss.rowspan.start + 1, col=ss.colspan.start + 1, subject=s,
                             class_p95=primary[s]['class_p95'],
                             thr_p95=None if primary[s]['class_p95'] == 'poor_fit' else float(primary[s]['thr_p95']),
                             margin=margin.get(s), n_gaussian_markers=len(allpk.get(s, []))))
    plt.close(fig)
    if [r['subject'] for r in sorted(rendered, key=lambda r: (r['row'], r['col']))] != order:
        raise SystemExit('rendered panel order differs from the intended order')
    write_csv(outs['fig1_stage4_drawn.csv'], plotted)
    with open(outs['fig1_stage4_panels.json'], 'w') as fh:
        json.dump(dict(section='§11y', x_range_hz=X_RANGE, band_hz=BAND,
                       y_limits=[ylo, yhi], y_rule='min/max of the data residual in 13-30 Hz over all 39, '
                       '+/- 10 % of the range', residual_min_max_13_30=[rlo, rhi], grid=[N_ROWS, N_COLS],
                       n_by_class={c: sum(r['class_p95'] == c for r in rendered)
                                   for c in ('peak', 'no_peak', 'poor_fit')},
                       panels=sorted(rendered, key=lambda r: (r['row'], r['col'])),
                       provenance=dict(script_sha256=sha256(__file__),
                                       export_record=dict(path=os.path.join(args.out_dir, 'fig1_stage4_export.json'),
                                                          sha256=sha256(os.path.join(args.out_dir,
                                                                                     'fig1_stage4_export.json'))),
                                       inputs={k: dict(path=v, sha256=sha256(v)) for k, v in paths.items()},
                                       matplotlib_version=matplotlib.__version__, numpy_version=np.__version__,
                                       python=sys.version.split()[0])), fh, indent=2)
    print('rendered panel order (row, col, subject, class):')
    for r in sorted(rendered, key=lambda r: (r['row'], r['col'])):
        print(f"  {r['row']},{r['col']}  {r['subject']}  {r['class_p95']}")
    print('written:', ', '.join(FIG_OUT))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--mode', required=True, choices=('gate', 'export', 'draw'))
    ap.add_argument('--stage4', required=True)
    ap.add_argument('--roi-dir', help='gate / export only')
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    if args.mode in ('gate', 'export') and not args.roi_dir:
        ap.error(f'--mode {args.mode} needs --roi-dir')
    dict(gate=gate, export=export, draw=draw)[args.mode](args)


if __name__ == '__main__':
    main()
