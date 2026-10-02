# Decision log

Each entry is written **before** the analysis it governs is run. Entries are append-only.
If a decision changes later, add a new dated entry that supersedes the old one; never rewrite an old entry.

Fields: ID · date · stage · question · inputs · procedure · decision rule (which result leads to which conclusion) · outputs.

---

## S0-1 · 2026-10-02 · Stage 0 · Which OpenNeuro version of ds004621 is the local raw copy?

- **Question.** Does the current local raw copy match a published OpenNeuro snapshot, and which one? Audit item #14.
- **Inputs.** The current local raw copy (`bidsRoot`, see `get_paths.m`; read-only); OpenNeuro GraphQL metadata for snapshots 1.0.1, 1.0.2 and 1.0.3.
- **Procedure** (`revision/stage0/stage0_openneuro_version_check.py`):
  - for every `*task-rest*` and `*task-msit*` file of all 42 subjects, compare size and content hash with the snapshot metadata;
  - annexed files: SHA-256 against the `SHA256E` key;
  - non-annexed files: git blob SHA-1, computed in Python;
  - no git command is run in the raw folder.
- **Decision rule.**
  - **0 mismatches against exactly one snapshot:** the local copy is that version.
  - **Mismatches against every snapshot:** the copy is unidentified, and that is reported as a limitation.
  - **The EEG binaries (`.eeg`) are identical across all snapshots:** the version affects event markers only, not the signal.
- **Caveat stated in advance.** The analyses of July–August 2026 read an earlier local copy that no longer exists. This check identifies the current local copy only. Check S0-2 tests indirectly which marker version the existing derivatives contain.
- **Outputs.** `Revision_Output/stage0/openneuro_version_check_<tag>.txt`.

## S0-2 · 2026-10-02 · Stage 0 · Do the rest event markers survive in the existing `_rest_clean.set` files?

- **Question.**
  - Can the two S12-delimited 300 s rest blocks be recovered from the existing derivatives?
  - Which marker version did the derivatives inherit (sub-20 and sub-23 changed in v1.0.3)?
  - Additionally, for #15: the ICA dimensionality actually used.
- **Inputs.** `Rest_Output/sub-XX/sub-XX_rest_clean.set` (read-only). Only the variables `event`, `urevent`, `srate`, `pnts`, `trials`, `xmin`, `icaweights`, `nbchan` and `chanlocs` are loaded; the EEG data are not. Also `Rest_Output/full_qc_summary.csv` and the raw `*_task-rest_events.tsv`.
- **Procedure** (`revision/stage0/stage0_check_rest_markers.m`). For each subject, list:
  - the marker types and counts in `urevent` and in `event`;
  - the urevent latencies of S12, S10 and S11 in seconds, compared with `events.tsv` onsets;
  - the number of epochs;
  - the number of ICA components vs `nbchan` and `nBadChan`;
  - whether Fz, Cz or C4 was among the interpolated channels.
- **Decision rule.**
  - **All three marker types present with latencies matching `events.tsv` (within one sample at 500 Hz):** blocks can be recovered from the derivatives. This is information only; Stage 3 reruns from raw data anyway (decided).
  - **sub-20 or sub-23 marker sets matching the v1.0.3 `events.tsv`:** consistent with the analysis having used v1.0.3.
  - **Any other pattern:** reported as is.
- **Outputs.** `Revision_Output/stage0/rest_markers_in_clean_sets.csv`, `Revision_Output/stage0/rest_markers_log.txt`.

## S0-3 · 2026-10-02 · Stage 0 · Response-to-next-stimulus interval (RSI) in MSIT+

- **Question.** How long after the previous button press does the pre-stimulus window (−200 to 0 ms) start? This is the input for #6 (post-movement beta rebound) and for choosing a within-task comparison window in Stage 5.
- **Inputs.** `<bidsRoot>/sub-XX/eeg/sub-XX_task-msit_events.tsv` for all 42 subjects (read-only).
- **Procedure** (`revision/stage0/stage0_rsi_summary.m`).
  - For every stimulus event (`trial_type == "stimulus"`), find the most recent preceding response event (`trial_type == "response"`). RSI = stimulus onset − response onset.
  - Each stimulus is labelled:
    - with its condition (S5 = F0, S6 = FS, S7 = 00, S8 = S0);
    - by whether it is the first stimulus after an `S 11` / `S 10` / `S 12` marker (first-in-mini-block);
    - by whether the previous trial had **no** response before this stimulus (a missed response, or a response arriving after the next stimulus).
  - Also stored: SOA (stimulus-to-stimulus) and RT (stimulus-to-own-response; first response after the stimulus and before the next stimulus).
- **Descriptive only.** No inferential test, no conclusion about beta. The summary is per subject (median, IQR, min, max) plus pooled percentiles, and the proportion of trials whose previous response falls inside each of 0–0.5, 0.5–1.0, 1.0–1.5 and >1.5 s before stimulus onset.
- **Decision rule (how the output will be used, fixed in advance).** The window choice is deferred to Stage 5 and will be logged there before any spectral analysis. This output only describes the timing. Fixed now:
  - (i) trials whose previous response lies within the −200 to 0 ms window itself will be flagged for exclusion from any pre-stimulus window;
  - (ii) a post-movement beta rebound is commonly described as peaking roughly 0.5–1 s after movement offset (Kilavik et al., 2013, already cited). If the median RSI falls in that range, the Stage 5 design must model or match RSI.
- **Outputs.** `Revision_Output/stage0/rsi_per_trial.csv`, `Revision_Output/stage0/rsi_summary_per_subject.csv`, `Revision_Output/stage0/rsi_summary_pooled.txt`.

---

### Outcomes, Stage 0 (appended 2026-10-02 after the runs; the entries above are unchanged)

- **S0-1 → local copy = OpenNeuro v1.0.3.**
  - 420 rest and MSIT files checked: 0 mismatches against 1.0.3; 4 against 1.0.1 and 1.0.2 (the sub-20 and sub-23 rest `.vmrk` and `events.tsv`).
  - The `.eeg` and `.vhdr` files are byte-identical across all three snapshots, so the version affects markers only.
  - Full SHA-256 of all 84 rest and MSIT `.eeg` binaries also matches v1.0.3: 420/420 files MATCH (`openneuro_version_check_1.0.3_big.txt`).
- **S0-2 → the markers survive in all 42 `_rest_clean.set` files.**
  - The marker sequences equal the v1.0.3 `events.tsv` in every subject; latencies agree within 1 ms.
  - The derivatives carry v1.0.3-specific fingerprints: sub-20 `'S  12'` (two spaces); sub-23 has a boundary at the v1.0.3 "New Segment" sample. This is consistent with the original analysis having used v1.0.3.
  - **sub-25 has only `S 12 | S 12`** (no break markers) in both the raw file and the derivative. Block cropping for sub-25 needs a separate rule in Stage 3a.
  - Side findings for #15 and #9:
    - stored ICA dimension exceeds `nbchan − 1 − nBadChan` in 13 subjects;
    - Fz was interpolated at rest in 14 subjects, Cz in 3, C4 in 2 (17 subjects with ≥ 1 of the three).
- **S0-3 → within-mini-block RSI.**
  - Median 1.361 s (P5 0.967, P95 1.685); per-subject medians 1.241–1.481 s.
  - Under pre-stated rule (ii), the median RSI is **not** within 0.5–1.0 s, so RSI modelling is not mandated by that rule. Whether to add it anyway is a Stage 5 decision.
  - 6 stimuli have a response inside −0.2..0 s (flagged under rule (i)).
  - First-in-mini-block stimuli: 4773 of 16,729 (87–126 per subject).

---

## S2-1 · 2026-10-02 · Stage 2, pass 1 · Does the as-run legacy code reproduce the v1 outputs?

- **Question.** Run unchanged, do the `legacy_v1/` scripts reproduce the v1 outputs behind draft v1? This is the empirical test of the as-run claim; audit item #3 context.
- **Scripts rerun unchanged** (the normal approximation where they used it):
  - `feature_extraction/extract_beta_avgpower_per_channel.m`
  - `feature_extraction/control_band_55_95_power_RS.m`
  - `statistics/beta_channel_stats_emg_test.m`
  - `statistics/effect_size_rankbiserial.m`
  - `statistics/tost_control_band_equivalence.m`
  - `statistics/conflict_specificity_prestim_beta.m`
  - `statistics/trial_counts_per_condition.m`
  - `statistics/sensitivity_nearedge_threshold.m`
  - `exploratory/statComparison_beta_power_MSIT_4Conds.m`
  - `figures/figure3_corrected.m`
- **Not rerun:**
  - preprocessing;
  - `msit_beta_erd_by_condition.m` (it preprocesses from raw);
  - the five peak-detection scripts.
- **Procedure** (`revision/stage2/stage2_pass1_run_legacy.m`, then `stage2_pass1_compare.m`; MATLAB R2022b, same computer):
  - Each script runs in its own function workspace and writes to `<outRoot>/legacy_v1_rerun/`.
  - Inputs are the v1 derivatives (read-only), so each link of the chain (`.set` → rest power → Table 2 / Figure 3) is tested against the exact v1 inputs it used. If every link reproduces, the chain reproduces.
  - Run outcome (ok / error, seconds) → `<outRoot>/stage2/pass1_run_log.csv`.
- **Comparison**, for each expected output (11 CSV, 5 PNG) → `<outRoot>/stage2/pass1_comparison.csv`:
  - (i) SHA-256 vs the **original v1 file** in `derivRoot` / `taskDeriv`. This is the primary reference: the true as-run bytes.
  - (ii) For CSVs, SHA-256 vs `legacy_v1/derivatives/` (stored byte-for-byte since commit 0f36c54).
  - (iii) If (i) differs:
    - CSV: a line-ending-insensitive comparison, then cell by cell (numeric: maximum absolute and relative difference; text: exact);
    - PNG: pixel comparison.
- **Decision rule:**
  - **IDENTICAL** (bytes equal the original): the as-run claim is empirically confirmed for that output.
  - **FORMAT_OR_FP_ONLY** (only line endings differ, numeric differences ≤ 1e-10 relative, or a PNG that is pixel-identical with different bytes): "reproduced up to formatting / floating point". Reported; the as-run claim holds for the numbers.
  - **DIFFERENT** (a larger numeric difference, different rows/columns/text, or different pixels): the as-run claim fails for that output. It is reported and investigated (input change vs code difference) before pass 2 builds on that script. No manuscript number changes.
  - **The script fails to run in batch mode:** "not reproducible as-is" for its outputs. Reported; the legacy code is NOT edited.
  - **PNG outcomes are informational only.** The as-run claim rests on the CSVs.
- **Known case, stated in advance.** `sensitivity_nearedge_threshold.m` reads the FOOOF CSVs rewritten on 2026-09-01; see `legacy_v1/README.md`, note 3. A difference only at thresholds other than 0.5 Hz would point to an input change, not to the script.
- **Outputs.** `<outRoot>/legacy_v1_rerun/*`, `<outRoot>/stage2/pass1_run_log.csv`, `<outRoot>/stage2/pass1_comparison.csv`.

## S2-2 · 2026-10-02 · Stage 2, pass 2 · Were the v1 conclusions sensitive to the Wilcoxon method?

- **Question.** v1 used MATLAB's normal approximation for some Wilcoxon signed-rank tests. If every one were exact, which v1 conclusions would change? Audit item #3.
- **Scope.** Documentation of method sensitivity ONLY. Pass 2 is **not** a source of manuscript numbers: after the full rerun (Stage 3), every manuscript number comes from Stages 4–6 on the new pipeline.
- **Procedure.** New code `revision/stage2/stage2_pass2_exact_wilcoxon.m` reads only v1 CSVs (read-only) and writes to `<outRoot>/stage2/`. Recomputed with `signrank(..., 'method', 'exact')`:
  - (a) channel screening: one-sample signed-rank of the within-subject z-scored beta power for each of the 125 channels, plus Benjamini–Hochberg FDR at q = .05, exactly as in v1 otherwise;
  - (b) the planned FS-vs-00 contrast of pre-stimulus beta at Fz, Cz and C4;
  - (c) Table 2 rest vs task (already exact in v1), as a control check;
  - (d) the exploratory post-hoc pairwise tests of `statComparison_beta_power_MSIT_4Conds.m` (no reported number; for completeness).
- **Page's L:** not recomputed (option (a)). It stays a one-sided normal approximation, to be stated in Methods; Stage 6 redoes the conflict analysis.
- **Output.** One row per test: the v1 p (and its method), the exact p, the difference, and the significance status at the v1 thresholds (nominal α = .05; FDR set membership; Bonferroni .05/3 where v1 used it).
- **Decision rule:**
  - **(c) does not reproduce the v1 p-values exactly:** stop and investigate before interpreting (a), (b) or (d).
  - **The FDR-significant set changes for any of the six candidate channels (Fz, Cz, C4, C3, F3, F4), or F4 (v1 p = .057) crosses .05:** flag for Stage 4 (#9).
  - **Any FS-vs-00 p crosses .05:** flag for Stage 6.
  - **Otherwise:** "the exact method changes no v1 conclusion", with all differences reported.
  - In every case, no manuscript text or number changes in Stage 2.
