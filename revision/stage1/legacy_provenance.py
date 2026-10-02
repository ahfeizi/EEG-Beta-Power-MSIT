"""Stage 1: provenance dates for legacy_v1/README.md (read-only).

For every as-run v1 script, compare the last-modified time of its as-run copy with the
last-modified times of the output files it wrote. If the script was modified AFTER an
output, the code may differ from what produced that output ("as-run" not guaranteed).

Usage:
  python legacy_provenance.py <scripts_dir> <rest_dir> <msit_dir> <diag_dir> <out_dir>
    scripts_dir  folder holding the as-run script copies (*.m)
    rest_dir     v1 rest derivatives folder (derivRoot)
    msit_dir     v1 MSIT+ derivatives folder (taskDeriv)
    diag_dir     folder the subject-inclusion diagnostics wrote to (cfg.outDir as run)
    out_dir      output folder (<outRoot>/stage1)
Outputs: legacy_provenance.csv, legacy_provenance.md
"""
import csv
import datetime as dt
import glob
import os
import sys

# script -> list of (folder key, glob pattern) for the outputs it wrote (from its write lines)
OUTPUTS = {
    "preprocess_rest_eeglab_staged_Pilot": [("rest", "sub-*/sub-*_rest_clean.set"), ("rest", "sub-*/sub-*_qc.mat"),
                                            ("rest", "full_qc_summary.csv"), ("rest", "pilot_qc_summary.csv")],
    "msit_beta_erd_by_condition": [("msit", "msit_beta_erd_by_condition.csv")],
    "Extract_beta_detrend_SGF_full42": [("rest", "beta_features_full42_detrend_sgf.csv"), ("rest", "beta_features_full42_with_qc.csv")],
    "extract_beta_alphamasked_full42": [("rest", "beta_features_full42_alphamasked.csv"), ("rest", "beta_features_full42_alphamasked_with_qc.csv")],
    "extract_IBF_full42": [("rest", "beta_features_full42_fixed.csv"), ("rest", "beta_features_full42_knee.csv")],
    "extract_IBF_SGF": [("rest", "beta_features_full42_sgf.csv")],
    "extract_beta_avgpower_per_channel": [("rest", "beta_avgpower_per_channel.csv"), ("rest", "beta_avgpower_heatmap_subject_x_channel.png")],
    "control_band_55_95_power_RS": [("rest", "rest_control_band_power.csv")],
    "beta_power_topoplot_all_channels": [("rest", "beta_power_all_channels_all_subjects.csv"), ("rest", "beta_power_topoplot_grandaverage.png"),
                                         ("rest", "beta_power_topoplot_per_subject_grid.png")],
    "beta_channel_stats_emg_test": [("rest", "beta_distinct_channels_stats.csv"), ("rest", "beta_emg_contamination_test.csv")],
    "effect_size_rankbiserial": [("msit", "beta_power_effect_sizes_rankbiserial.csv"), ("msit", "Table2_with_effect_sizes.csv")],
    "tost_control_band_equivalence": [("msit", "control_band_TOST_equivalence.csv"), ("msit", "fig_control_band_TOST.png")],
    "conflict_specificity_prestim_beta": [("msit", "prestim_beta_conflict_specificity.csv"), ("msit", "fig_prestim_conflict_specificity.png")],
    "trial_counts_per_condition": [("msit", "trial_counts_per_condition.csv")],
    "sensitivity_nearedge_threshold": [("rest", "nearEdge_sensitivity_analysis.csv"), ("rest", "fig_nearEdge_threshold_sensitivity.png")],
    "figure3_corrected": [("msit", "fig3_rest_vs_task_beta_and_control_CORRECTED.png")],
    "plot_all_subjects_spectrum_grid": [("rest", "all_subjects_detrended_spectrum_grid.png")],
    "scalpmap_merged": [("rest", "scalpmap_merged.png")],
    "preprocess_rest_eeglab_staged": [("rest", "triage_summary.csv")],
    "diagnose_flagged_subjects_new2": [("diag", "sub-*_T1_*.png"), ("diag", "sub-*_T2_*.png")],
    "extract_IBF_SGF_detrend": [("rest", "beta_features_pilot_detrend_sgf.csv")],
    "extract_IBF_rawPSD": [("rest", "IBF_features_rawPSD.csv"), ("rest", "PeakTable.csv"), ("rest", "ROI_IBF.csv")],
    "IBF_peak_15_40": [],
    "extract_beta_per_channel_raw": [("rest", "beta_features_per_channel_raw.csv"), ("rest", "all_subjects_*_raw_spectrum_grid.png")],
    "extract_beta_local_peak_per_channel": [("rest", "beta_local_peaks_per_channel.csv")],
    "heatmap_localPeak_perSub_Chan": [("rest", "beta_peak_heatmap_subject_x_channel.png")],
    "reCapHeatmap": [("rest", "beta_avgpower_heatmap_capped.png")],
    "scalpmap_labeled_channels": [("rest", "scalpmap_distinct_channels.png"), ("rest", "scalpmap_candidate_verdict.png")],
    "IBF_scatter_plot": [("rest", "IBF_scatter_edge_vs_interior.png")],
    "msit_beta_power_by_condition": [("msit", "msit_beta_power_by_condition.csv")],
    "statComparison_beta_power_MSIT_4Conds": [("msit", "msit_beta_condition_comparison_summary.csv")],
    "extract_IBF": [("rest", "beta_features_full42_fixed.csv")],
}


def ts(path):
    return dt.datetime.fromtimestamp(os.path.getmtime(path))


def fmt(t):
    return t.strftime("%Y-%m-%d %H:%M:%S") if t else ""


def main():
    scripts_dir, rest_dir, msit_dir, diag_dir, out_dir = sys.argv[1:6]
    dirs = {"rest": rest_dir, "msit": msit_dir, "diag": diag_dir}
    rows = []
    for name, pats in OUTPUTS.items():
        s_t = ts(os.path.join(scripts_dir, name + ".m"))
        files = []
        for key, pat in pats:
            files += glob.glob(os.path.join(dirs[key], pat))
        if not files:
            verdict = "no output file found"
            o_min = o_max = None
        else:
            times = [ts(f) for f in files]
            o_min, o_max = min(times), max(times)
            if s_t > o_max:
                verdict = "SCRIPT MODIFIED AFTER ALL OUTPUTS"
            elif s_t > o_min:
                verdict = "SCRIPT MODIFIED AFTER SOME OUTPUTS"
            else:
                verdict = "script older than all outputs"
        rows.append({"script": name + ".m", "script_mtime": fmt(s_t), "n_output_files": len(files),
                     "outputs_oldest": fmt(o_min), "outputs_newest": fmt(o_max), "verdict": verdict})

    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "legacy_provenance.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(out_dir, "legacy_provenance.md"), "w", encoding="utf-8") as fh:
        fh.write("| Script | Script modified | Output files | Oldest output | Newest output | Verdict |\n|---|---|---|---|---|---|\n")
        for r in rows:
            fh.write(f"| `{r['script']}` | {r['script_mtime']} | {r['n_output_files']} | {r['outputs_oldest']} | "
                     f"{r['outputs_newest']} | {r['verdict']} |\n")
    for r in rows:
        print(f"{r['script']:42s} {r['script_mtime']}  n={r['n_output_files']:3d}  {r['outputs_oldest']:19s} .. {r['outputs_newest']:19s}  {r['verdict']}")


if __name__ == "__main__":
    main()
