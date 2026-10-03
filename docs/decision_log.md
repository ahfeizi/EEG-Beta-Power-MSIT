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

### Outcome S2-1 (appended 2026-10-02 after the run; the rule above is unchanged)

- **Run.** All 10 legacy scripts ran unchanged in MATLAB batch mode without error (`pass1_run_log.csv`).
- **CSV outputs: 11/11 IDENTICAL.** SHA-256 equals the original v1 file and the `legacy_v1/derivatives/` copy for:
  - `beta_avgpower_per_channel.csv`, `rest_control_band_power.csv`;
  - `beta_distinct_channels_stats.csv`, `beta_emg_contamination_test.csv`;
  - `beta_power_effect_sizes_rankbiserial.csv`, `Table2_with_effect_sizes.csv`;
  - `control_band_TOST_equivalence.csv`;
  - `prestim_beta_conflict_specificity.csv`, `trial_counts_per_condition.csv`;
  - `nearEdge_sensitivity_analysis.csv`;
  - `msit_beta_condition_comparison_summary.csv`.
- **Conclusion under the rule.**
  - The as-run claim is **empirically confirmed** for every CSV these scripts produce, including the chain `.set` → rest power → Table 2 inputs.
  - The known case is resolved: the near-edge sensitivity output is byte-identical at **all** thresholds, so the 2026-09-01 rewrite of the FOOOF CSVs changed nothing that the script reads.
- **PNG outputs (informational only):**
  - **FORMAT_OR_FP_ONLY** (pixel-identical, file bytes differ): `fig_control_band_TOST.png`, `fig_prestim_conflict_specificity.png`, `fig_nearEdge_threshold_sensitivity.png`.
  - **DIFFERENT**, in image height only:
    - `fig3_rest_vs_task_beta_and_control_CORRECTED.png` (1758×2773 vs 1752×2773);
    - `beta_avgpower_heatmap_subject_x_channel.png` (1616×949 vs 1441×949).
  - This is consistent with a different figure geometry when rendering in batch mode. For Figure 3, the panel titles (percent changes and p-values) and the plotted points are identical on visual inspection. Under S2-1, PNGs do not bear on the as-run claim.
- **Next.** Pass 2 (S2-2) may build on these scripts: no DIFFERENT CSV outcome.

### Outcome S2-2 (appended 2026-10-02 after the run; the rule above is unchanged)

- **Code note.** The first run stopped at the summary-printing helper, after the four result CSVs had been written. The helper was fixed (commit 3d3c2e9, reporting only) and the script was rerun in full; the results below are from that rerun.
- **Replication of v1 (relative tolerance 1e-12):**
  - (a) 125/125 channel p-values and the v1 FDR set reproduced;
  - (b) 3/3 FS-vs-00 p-values reproduced;
  - (c) 3/3 Table 2 p-values reproduced.
- **Rule (c), control check: passed.** The exact p equals the saved v1 p, with relative differences ≤ 2.2e-15.
- **Rule (a):**
  - The FDR-significant set is identical: 90/125 channels under both methods; no channel changes status, none of Fz/Cz/C4/C3/F3/F4 included.
  - F4: v1 p = 0.05655, exact p = 0.0568; it does not cross .05.
  - The exact p is smaller than the approximate p for the very small p-values (for example C3: 3.6e-08 → 2.5e-11) and nearly unchanged near .05.
- **Rule (b):** no FS-vs-00 p crosses .05:
  - Fz 0.1225 → 0.1249
  - Cz 0.171 → 0.1747
  - C4 0.3987 → 0.4061
- **(d), exploratory:** 18 post-hoc tests; 0 FDR-significant and 0 nominally significant under both methods.
- **VERDICT under S2-2: the exact method changes no v1 conclusion.**
  - No flag for Stage 4 or Stage 6.
  - As stated in the rule, these values are not manuscript numbers.
  - Files: `<outRoot>/stage2/pass2_a..d_*.csv`, `pass2_summary.txt`.

---

# Stage 3a: design of the harmonised preprocessing pipeline

Design decisions are recorded one by one as they are made. The pipeline runs only after the whole design is approved (then a 3-subject test, then all 42 subjects).

**Fixed requirement.** Preprocessing delivers **continuous** cleaned data with all events, for both conditions. Epoching and analysis windows are chosen in Stages 5–6, so no window choice is locked in here.

## S3a-D1 · 2026-10-02 · Output format, sampling rate, storage

- **Format (option b).** Per subject and condition (rest, MSIT+), save:
  - (1) the final cleaned **continuous** EEGLAB `.set`, with all original events (stimuli, responses, S10/S11/S12, boundaries), the rest block labels, the ICA matrices and the list of removed components;
  - (2) the continuous data **just before component removal** (after channel repair and re-referencing), with the ICA weights and the ICLabel class probabilities.

  Reason: the ICLabel thresholds (D10), and any sensitivity analysis on them, can be re-applied without rerunning ICA, the most expensive step. Cost: about twice the storage.
- **Target sampling rate: 500 Hz** (raw: 1000 Hz).
  - 250 Hz was rejected: a Nyquist of 125 Hz leaves no room for the 55–95 Hz control band plus a ~100 Hz low-pass and its transition band.
  - 1000 Hz was rejected: twice the storage and ICA time, with no gain for beta or the control band.
  - 500 Hz is the same as v1, and leaves room for a higher-frequency EMG index if D4 allows it.
- **Storage (option i).** Large EEG files go to a new path field `eegOutRoot` (`get_paths.m`; locally a folder outside the raw-data folder on the data drive). Tables, reports and small figures stay under `outRoot`.
- **Disk-space gate.** Before the 3-subject test and again before the 42-subject run, check the free space on both drives. **Stop** if:
  - the `eegOutRoot` drive would have < 15 GB left after the projected output, or
  - the `outRoot` drive has < 5 GB free.

## S3a-D2 · 2026-10-02 · Channel set and reference

- **Facts.**
  - All 84 raw files (42 subjects × rest/MSIT+) have the same 127 EEG channels.
  - Only `TP9 LEFT EAR` and `TP10 RIGHT EAR` have no entry in EEGLAB's `standard-10-5-cap385` template; their true placement (mastoid vs earlobe) is unknown.
  - The online reference is FCz, which is not in the recording.
  - No digitised positions exist, so all channel locations come from the `standard-10-5-cap385` template.
- **D2a: drop TP9/TP10** (as in v1). Template coordinates could be wrong for these two, which would distort interpolation, topographies and ICLabel. They are not analysis channels.
- **D2b: recover FCz at re-referencing.**
  - FCz is added as a zero-valued channel with its template coordinates.
  - The data are then re-referenced to the common average with FCz declared as the original reference (`pop_reref` with `refloc`).
  - The average then includes the reference site, and FCz gets its signal back. The final montage is 126 channels: 125 recorded + FCz.
  - **Consequence for D9:** after average referencing (and after interpolating any removed channels), the data rank is lower than the channel count. ICA must use the actual rank.

## S3a-D3 · 2026-10-02 · Cropping to the analysed data (rest; task rule pending as D3e)

- **Facts** (from the raw `*_task-rest_events.tsv` of all 42 subjects).
  - In the 41 subjects with all four markers:
    - S12₁→S10 = 300.003–300.007 s;
    - S10→S11 = 55.014–55.015 s;
    - S11→S12₂ = 5.016–5.017 s;
    - at least 312.7 s of data follow S12₂.
  - **sub-25** has only two `S 12` markers:
    - S12₁→S12₂ = 357.79 s, 2.25 s shorter than the others' 360.04 s;
    - only 298.19 s of data follow S12₂.
- **D3a, block timing.** Rest block k = [S12ₖ, S12ₖ + 300.0 s), clipped at the end of the recording. S10 is used only as a consistency check: it must equal S12₁ + 300 s within 0.01 s, otherwise the subject is flagged and processing stops for that subject.
- **D3b, when to crop.** Crop after filtering and line-noise removal and **before** bad-channel detection, ASR and ICA. Cleaning decisions then rest only on the analysed data, and filtering before cropping keeps filter edge effects out of the blocks.
  - The same principle applies to MSIT+; its exact cropping rule is decision S3a-D3e, approved separately.
  - The data quantity for ICA is addressed in D8.
- **D3c, sub-25.**
  - Block 1 = [S12₁, S12₁ + 297.75 s), i.e. 300 s minus the 2.25 s gap deficit. This excludes any break data, whether the deficit arose in block 1 or in the break.
  - Block 2 = [S12₂, end of recording) = 298.19 s (truncated).
  - sub-25 is flagged in QC. The split-half reliability analysis reports results with and without sub-25.
- **D3d, block identity.**
  - Events `rest_b1_start`, `rest_b1_end`, `rest_b2_start` and `rest_b2_end` are inserted, with a `boundary` event between the blocks.
  - `EEG.etc.restBlocks` stores each block's original start time in the raw file (s), its duration (s) and the sub-25 flag.
- **Rule for Stages 4–6 (binding).** Spectral segments (Welch windows or any other segment) must **never cross a boundary event**: segment within blocks only.

## S3a-D3e · 2026-10-03 · Cropping MSIT+ to task blocks (symmetric with rest, D3b)

- **Facts** (from the raw `*_task-msit_events.tsv` of all 42 subjects).
  - Every task block (about 10 mini-blocks) ends with `S 10` (start of a break). There are 12 blocks in 39 subjects, 11 in sub-17 and sub-38, and 9 in sub-21.
  - The last response → `S 10` interval is 1.88–5.71 s.
  - `S 10` → next stimulus is usually 10.02 s (short break), up to 178.5 s (between runs).
  - `S 12` ("beginning of the run") occurs 2–4 times per subject, only at run transitions, never before the first stimulus.
  - The first stimulus comes 3.2–67.1 s after the recording starts; 26.9–110.6 s of data follow the last response.
  - Inside blocks, the largest gap between consecutive trial events is normally ≤ 4.4 s. Five unmarked pauses of 19.4–56.1 s occur (sub-17, sub-23 ×2, sub-29, sub-38), almost certainly breaks with a missing `S 10`.
- **D3e-1, block boundaries.** The task recording is split into blocks at every `S 10` or `S 12` marker **and** at every gap > 10 s between consecutive trial events (stimulus or response).
- **D3e-2, block extent.** Each block = [first stimulus − 1.0 s, last trial event + 1.5 s].
  - The 1.5 s end margin is below the shortest observed last response → `S 10` interval (1.88 s), so no break data enter.
  - The 1.0 s start margin covers pre-stimulus windows of up to 1 s.
  - Cropping happens after filtering and line-noise removal and before bad-channel detection, ASR and ICA (D3b).
- **D3e-3, a block must contain ≥ 1 stimulus.** Any segment produced by the rule that contains no stimulus (for example a stray response during a break) is discarded and logged in QC.
- **D3e-4, block identity.**
  - Events `task_bN_start` and `task_bN_end` are inserted, with a `boundary` event between blocks.
  - `EEG.etc.taskBlocks` stores, per block: the original start time in the raw file (s), the duration (s), the number of stimuli, and a flag if the block was split by the 10 s rule.
  - The S3a-D3 rule (no spectral segment crosses a boundary) applies.
- **Rule for Stages 5–6 (binding).**
  - The first trial of each task block is preceded by a break, not by the previous trial's ITI. **Default:** exclude it from all pre-stimulus analyses, and report the count per subject.
  - Note: every block-first trial is also a first-in-mini-block trial, so this slightly reduces the first-in-mini-block (unpredictable-condition) trial count available in Stage 6. Stage 0 found 87–126 first-in-mini-block stimuli per subject; about one block-first trial per block is removed from that set.
