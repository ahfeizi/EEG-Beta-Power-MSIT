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

## S3a-D4 · 2026-10-03 · Filters and order

- **Facts** (from the installed code: EEGLAB 2023.0, firfilt 2.8).
  - `pop_eegfiltnew` designs windowed-sinc (Hamming), zero-phase FIR filters.
  - For a high-pass with passband edge E < 2 Hz, the transition band is E, so the −6 dB point is at E/2.
  - `pop_resample` (1000 → 500 Hz) applies its own Kaiser anti-aliasing filter (fc = 0.9, df = 0.2 of the new Nyquist): passband up to about 200 Hz, −6 dB at about 225 Hz, stopband at 250 Hz.
  - The `pop_resample` code warns that resampling data with a DC offset can create edge transients; the raw files have large DC offsets and drifts.
- **D4a, high-pass:** passband edge 0.5 Hz (−6 dB at 0.25 Hz). This removes drift ahead of bad-channel detection and ASR and leaves a flat passband well below any spectral fit range. The separate 1 Hz copy used to fit ICA is handled in D9.
- **D4b, low-pass:** no separate low-pass; the data keep content up to the anti-aliasing passband (about 200 Hz).
  - Reason: the 100–200 Hz range is kept for a possible stronger EMG index (audit #10, the EMG limitation). It cannot be recovered later, whereas a band can always be selected at analysis time.
  - Consequence for D5: line noise must be removed at 50, 100, 150 and 200 Hz.
- **D6 default, fixed now:** bad-channel detection runs on a temporary copy low-passed at 100 Hz, and its result (the list of channels) is applied to the full-band data. Otherwise high-frequency EMG would decide which channels get interpolated, which interacts directly with the paper's EMG question. ASR is open (D7).
- **D4c, order:**
  1. high-pass 0.5 Hz at 1000 Hz (DC and drift removed before resampling);
  2. resample to 500 Hz;
  3. line-noise removal (D5);
  4. crop to blocks (D3, D3e).

  Filtering is applied to the whole continuous recording; firfilt filters each side of a raw `boundary` event separately.
- **D4d, design reporting:** the Methods report the filter type, window, order, passband edge, −6 dB point, transition band and zero-phase application.
- **Filter-edge rule:** to be proposed as S3a-D4e. It depends on the exact filter half-length and on the block positions relative to recording edges and raw boundaries.

## S3a-D4e · 2026-10-04 · Filter-edge rule: blocks are clipped away from segment edges

- **Facts** (installed code: EEGLAB 2023.0, firfilt 2.8, bva-io 1.75, EEG-BIDS 10.5; raw text files only).
  - Filters applied to the continuous data before cropping (designed with the installed code by `revision/stage3/stage3_filter_halflengths.m`, saved by `stage3_compute_H.m` to `<outRoot>/stage3/filter_halflengths.csv`):
    - D4a high-pass at 1000 Hz (`pop_eegfiltnew`, passband edge 0.5 Hz): order 6600, half-length 3300 samples = 3.300 s;
    - `pop_resample` anti-aliasing filter (1000 → 500 Hz, Kaiser): order 66 at 1000 Hz, half-length 33 samples = 0.033 s.
  - firfilt and `pop_resample` pad each continuous segment with its edge value. A segment is delimited by the recording start/end and by every `boundary` event.
  - bva-io (`parsebvmrk.m`) turns every `New Segment` and `DC Correction` marker into a `boundary` event. Every other marker gets its description as event type, so `Stimulus` markers described `boundary` (EEGLAB's own export of boundary events; the `.vmrk` files say "Data created from the EEGLAB software") are boundaries too. There are no `DC Correction` markers. `pop_loadbv` keeps each marker's position as its latency (integer; the first sample of the new segment for a boundary).
  - Survey of all 84 `.vhdr`/`.vmrk` files (`revision/stage3/stage3_raw_boundaries_d4e.py` → `<outRoot>/stage3/raw_boundaries.csv`): **15 internal raw boundaries in 7 recordings**: sub-17 MSIT+ (2), sub-19 MSIT+ (1), sub-23 rest (1), sub-23 MSIT+ (4), sub-25 rest (3), sub-29 MSIT+ (2), sub-38 MSIT+ (2). The other 77 recordings are one continuous segment. `SamplingInterval` is 1000 µs in all 84 headers.
  - `events.tsv` contains none of these boundaries. Apart from them, its rows equal the `.vmrk` stimulus markers exactly (sample = onset × 1000) in all 84 recordings.
  - `pop_importbids` with `bidsevent` = on replaces `EEG.event` with the `events.tsv` rows (`bids_importeventfile.m`), so it would drop every raw boundary. It also sets latency = onset × srate + 1, one sample later than the `.vmrk` position.
  - `pop_resample` (installed code) splits the data at every boundary, resamples each segment separately, and maps each event's latency relative to its own segment start. Synthetic test (`revision/stage3/stage3_verify_boundary_handling.m`; high-pass then resample; 3 segments of 10001/10002/9998 samples with DC jumps up to 1500 µV; boundaries at integer latencies, one duplicated): all 4 checks PASS.
    - Boundary latencies after resampling equal the independently computed segment starts.
    - Stimulus latencies keep their time relative to their segment start.
    - Joint result = each segment processed alone (max difference 0 µV), so neither filter crosses a boundary.
    - A 10 Hz sine of the original time is still aligned with its events at ≥ H from the edges (max error 0.00066).
    - `eeg_checkset` removes the duplicated boundary (warning only; one boundary per position remains).
  - sub-25 rest: the first raw boundary lies 300.004 s after S12₁, where S10 falls in the other subjects (300.003–300.007 s). Block 1 is therefore continuous for a full 300 s; the 2.25 s deficit of D3c lies in the break, which is split into segments of 54.091 s and 0.192 s. Under D4e-1, block 1 ends at boundary − H (earlier than S12₁ + 297.75 s), so the D3c choice no longer changes the data.
- **D4e-1, rule (option A).** Every block (rest, D3; task, D3e) is clipped so that it lies entirely at least H from every segment edge (recording start/end, every raw boundary):
  - start = max(start under D3/D3e, previous edge + H);
  - end = min(end under D3/D3e, next edge after the start − H). A raw boundary inside a block is that block's next edge.
  - If a raw boundary inside a block had stimuli after it within the block, the block would need to be split. No rule exists for that case: the pipeline stops for that subject. It does not occur in the 42 subjects.
- **D4e-2, H = the sum of the half-lengths of every filter applied to the continuous data before cropping.** The filters run in cascade, so a sample is free of every filter's edge padding only at ≥ the sum from an edge.
  - Now **3.333 s** (3.300 + 0.033).
  - H is never hard-coded: `stage3_filter_halflengths.m` designs each filter with the installed code from `stage3_params.m`, and the pipeline and the survey read H from it.
  - D5 adds its line-noise step to that function. A step that is not a simple FIR (e.g. CleanLine, ZapLine) must state its effective contribution to H.
- **D4e-3, logging.** Every clip (samples clipped at each end, and the reason) is stored in `EEG.etc.restBlocks` / `EEG.etc.taskBlocks` and in the QC, with the stimuli that fall outside the clipped block.
- **D4e-4, loading (approved with conditions).** Raw boundaries must survive loading, so the pipeline loads each recording with `pop_loadbv` (events and boundaries from the `.vmrk`), with these binding conditions:
  - `pop_loadbv` does not import BIDS metadata. Channel labels and types (`*_channels.tsv`) and electrode positions (template, S3a-D2) are applied separately and verified against `*_channels.tsv`; any mismatch stops the subject.
  - The event check is sample-exact: every non-boundary event must equal an `events.tsv` row (latency = onset × 1000, same `event_type`) and vice versa. Any mismatch stops the subject.
  - Boundary handling by `pop_resample` was confirmed in the installed code and by the synthetic test above.
- **Effect** (H = 3.333 s; `<outRoot>/stage3/d4e_block_clipping.csv`). 13 of 588 blocks are clipped (3 rest, 10 task); 575 are unchanged.

  | Subject | Block | Clipped at start (s) | Clipped at end (s) | Edge | New duration (s) | Stimuli lost |
  |---|---|---|---|---|---|---|
  | sub-05 | task 1 | 0.403 | 0 | recording start | 81.268 | 0 |
  | sub-17 | task 1 | 0.566 | 0 | recording start | 78.546 | 0 |
  | sub-17 | task 3 | 0 | 1.234 | raw boundary | 91.763 | 0 |
  | sub-22 | rest 1 | 1.388 | 0 | recording start | 298.612 | – |
  | sub-23 | task 10 | 0 | 1.479 | raw boundary | 46.749 | 0 |
  | sub-23 | task 11 | 0 | 4.395 | raw boundary inside block | 57.337 | 2 |
  | sub-25 | rest 1 | 0 | 1.079 | raw boundary | 296.671 | – |
  | sub-25 | rest 2 | 0 | 3.333 | recording end | 294.858 | – |
  | sub-25 | task 1 | 1.160 | 0 | recording start | 78.501 | 1 |
  | sub-28 | task 1 | 0.214 | 0 | recording start | 87.459 | 0 |
  | sub-29 | task 1 | 0 | 3.701 | raw boundary inside block | 59.898 | 1 |
  | sub-38 | task 9 | 0 | 1.558 | raw boundary | 75.963 | 0 |
  | sub-38 | task 10 | 0.320 | 0 | raw boundary | 91.225 | 0 |

  - sub-23 task 11: the boundary comes 0.439 s after the last stimulus (its response falls in the gap). sub-29 task 1: the boundary comes 1.133 s after the last response.
  - **Lost stimuli** (`<outRoot>/stage3/d4e_lost_stimuli.csv`): 4, all listed. None is first-in-mini-block except sub-25's, which is block-first and already excluded under D3e.

    | Subject | Block | Onset (s) | Condition | First in mini-block | Block-first |
    |---|---|---|---|---|---|
    | sub-23 | task 11 | 1161.939 | F0 | no | no |
    | sub-23 | task 11 | 1164.189 | F0 | no | no |
    | sub-25 | task 1 | 3.174 | FS | yes | yes |
    | sub-29 | task 1 | 88.513 | 00 | no | no |

  - **Trials per subject × condition** (`<outRoot>/stage3/d4e_trials_by_condition.csv`; raw event counts, before any artifact rejection; kept = inside the clipped block and not block-first):
    - sub-23 F0: 98 stimuli, 5 block-first, 2 lost → 91 kept (24 first-in-mini-block, 67 later). Other conditions: no loss.
    - sub-29 00: 110 stimuli, 3 block-first, 1 lost → 106 kept (27 first-in-mini-block, 79 later). Other conditions: no loss.
    - Smallest kept count over all 42 subjects, per condition (both affected subjects lie above it): F0 66 (sub-21), FS 79 (sub-15), 00 79 (sub-21), S0 68 (sub-21). First-in-mini-block: F0 17 (sub-21), FS 20 (sub-17), 00 22 (six subjects), S0 17 (sub-21).
  - **No minimum trial count has been set yet** (it belongs to D12). Whether any subject × condition falls below it is checked when D12 is decided, from `d4e_trials_by_condition.csv` and the post-rejection counts.
  - Also confirmed: 3 segments without a stimulus are discarded under D3e-3 (sub-07, sub-24, sub-37 MSIT+, one each).

## S3a-D5-0 · 2026-10-04 · Line-noise diagnostic (outcome-blind), before the D5 choice

- **Question.** How strong and how stable is line noise at 50, 100, 150 and 200 Hz in each recording? The answer selects the recordings for testing D5 option (b) and decides whether (a′) is admissible.
- **Approval.** Reading the binary `.eeg` files is approved for this diagnostic only (2026-10-04).
- **Outcome-blind constraint (binding).**
  - Spectra are computed only at f₀ − 3 … f₀ + 3 Hz around f₀ ∈ {50, 100, 150, 200}, by a direct DFT at exactly those frequencies.
  - Nothing is computed, saved or printed in 13–30 Hz or 55–95 Hz. The script asserts this.
- **Facts fixed beforehand.**
  - Target rate after resampling: 500 Hz (S3a-D1), so the Nyquist frequency is 250 Hz and all four frequencies lie below it.
  - The anti-aliasing passband of `pop_resample` ends at about 200 Hz (S3a-D4). Its gain at 197–203 Hz is computed from the installed design and reported.
  - Planned order (S3a-D4c): high-pass 0.5 Hz at 1000 Hz → resample to 500 Hz → line-noise removal (D5, on each raw segment) → crop to blocks (D3/D3e/D4e).
- **Inputs.**
  - The raw `.vhdr`/`.eeg` of all 84 recordings, loaded with `pop_loadbv` in groups of 16 channels (memory).
  - The D4e block extents (`<outRoot>/stage3/d4e_block_clipping.csv`).
- **Procedure** (`revision/stage3/stage3_d5_0_line_noise.m`).
  1. Insert the block start/end as events, then resample to 500 Hz with `pop_resample` (boundaries respected, as in the pipeline). No high-pass: its gain at ≥ 47 Hz is unity, so each chunk is linearly detrended instead.
  2. Cut each clipped block into non-overlapping 10 s chunks; a remainder < 10 s is dropped.
  3. Per chunk and channel: Hann window, one-sided PSD at f₀ ± 3 Hz in 0.1 Hz steps (= the 10 s DFT bins).
  4. **Floor:** a straight line (dB vs Hz) fitted to the flank bins 1.5 ≤ |f − f₀| ≤ 3 Hz.
  5. **Peak excess** = max over |f − f₀| ≤ 0.5 Hz of (PSD dB − floor). **Peak frequency** = that bin, refined by parabolic interpolation of the dB values.
  6. Per recording × channel × f₀:
     - `excess_db`: excess on the chunk-averaged PSD (the primary strength measure), with its peak frequency;
     - per-chunk excess: median and maximum;
     - **amplitude CV** across chunks of √(max(PSD_peak − floor_peak, 0));
     - **frequency drift** (SD and range of the per-chunk peak frequency), computed over chunks whose excess is ≥ 6 dB (NaN if fewer than 2).
  7. Kept channels = the 125 left after S3a-D2a (TP9/TP10 dropped). TP9/TP10 are computed but reported separately.
- **Decision rules.**
  - **R1, (a′) admissibility.** Frequency f₀ is *absent* if `excess_db` < 3 dB in every kept channel of every recording. (a′) is admissible only if 150 and/or 200 Hz are absent; otherwise every line frequency below Nyquist enters D5.
  - **R2, worst recordings.** Severity S = max over f₀ of the median over kept channels of `excess_db`. The 3 recordings with the highest S are the "worst" set for testing option (b), alongside the 3 D14 test subjects (not yet chosen). If a worst recording belongs to a D14 test subject, the next one in rank is taken. Instability (amplitude CV, drift) is reported descriptively but is not used for selection.
  - **R3, notch width check for fallback (a).** If any chunk with excess ≥ 6 dB has its peak more than 0.5 Hz from f₀, the default ±2 Hz notch of option (a) is re-examined before (a) could be used.
  - The (b) residual criterion is proposed after D5-0 and logged before the (b) test runs.
- **Outputs** (`<outRoot>/stage3/d5_0/`):
  - `line_noise_by_channel.csv` (one row per recording × channel × f₀);
  - `line_noise_by_recording.csv`;
  - `run_info.txt` (time, SHA-256 of this entry's text as read by the script, the anti-aliasing gains).
