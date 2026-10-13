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

## S3a-D5-0-amend1 · 2026-10-06 · D5-0 script: exact-heading locator for the entry hash (computation unchanged)

- **Placement.** This amendment sits directly under S3a-D5-0 as its own `## ` entry. A `###` note inside S3a-D5-0 would become part of that entry's hashed text and change its hash. S3a-D5-0 itself is unchanged.
- **Defect.** `entryHash` (`stage3_d5_0_line_noise.m:207–218` at commit `0150366`) located the entry with `strfind(txt, '## S3a-D5-0')` and asserted exactly one match.
  - Since S3a-D5-0-exc was logged, that string also matches the `-exc`, `-crash` and `-hist` headings (and now this one), so the assembly step would stop at line 151.
  - It never reached that line: the 2026-10-04 assembly stopped earlier, on the sub-13 label assert.
- **Change: the locator only.**
  - New function `revision/stage3/stage3_log_entry.m`: it finds the single line starting with `## <ID> ` followed by a non-space character (the `·` separator), and errors unless exactly one line matches.
  - The text rule and the hash are unchanged: text from the heading to the next line starting with `## `, CR removed, SHA-256 of the UTF-8 bytes.
  - The D5-0 computation (chunking, DFT, `linePeaks`, R1–R3) is not touched.
- **run_info.txt** of the D5-0 run records the hashes of S3a-D5-0, S3a-D5-opt and S3a-INF-1.
- **Test:** `revision/stage3/test_decision_log_ids.m`. Every level-2 heading of the log must carry an ID followed by a separator, and every ID must resolve to exactly one heading.
- **Equivalence check** (prepared 2026-10-06): the old `entryHash`, applied to the log as committed in `c137f53` (where its locator still matched once), and the new function, applied to the same file and to the current log, must give the same S3a-D5-0 hash. Result (two separate runs, identical output): all three equal `265005415f3af701d8f266af2ee2264a61cca44bf3e470754b6e5037ebfb603a`. So the S3a-D5-0 text is unchanged since `c137f53`, and the new locator gives the old hash. The ID test passed: 22 level-2 headings, 22 IDs, each resolving to exactly one heading; the separator decodes as U+00B7.

## S3a-D2-reopen · 2026-10-04 · Digitised electrode positions exist: the D2 fact is contradicted, D2 reopened

- **Facts** (`sourcedata/`: file names, and the `.bvct`/`.bvef` XML only; reading both approved 2026-10-04).
  - `sourcedata/` holds only `sub-XX/coords/` and `sub-XX/logfiles/`: 39 `sub-XX_captrak.bvct`, 3 `sub-XX_captrak.bvef` (sub-12, sub-23, sub-24), and task logs (168 MSIT+, 168 oddball, 82 SRT). There are no original Recorder files (`.eeg`/`.vhdr`/`.vmrk`/`.ahdr`/workspace).
  - Each `.bvef` has 132 entries with integer-rounded spherical coordinates only (Theta/Phi/Radius; no X/Y/Z). The values differ between the three subjects, so they are individual, but their provenance (digitised or not) is unknown.
    - Entries named Nasion, LPA and RPA are present, with subject-specific integer spherical values. Whether they are digitised fiducials is unknown.
    - Signs differ between files (e.g. Fz is (−57, −89) in sub-12 and (58, 90) in sub-23). Hypothesis: the same point in two representations, since in BESA-style spherical coordinates (θ, φ) ≡ (−θ, φ + 180), and (−57, −89) → (57, 91) ≈ (58, 90) after rounding. To be verified by converting to X/Y/Z before any use.
    - GND, Nasion, LPA and RPA have no Number; the others are numbered 1–128 with FCz = 64. Their order by Number equals the `channels.tsv` order, and the `.vhdr` of these three subjects equals `channels.tsv`.
  - Each `.bvct` (BrainVision CapTrak, file version 1.10) has 132 digitised points (X/Y/Z): the 127 recorded EEG labels, FCz (the online reference), GND, and the fiducials Nasion, LPA and RPA. There are no head-shape points. `<Channel>` is 0 for every point, so a position is not linked to a data column. Cap sizes: 52 cm (6 subjects), 54 cm (16), 56 cm (13), 58 cm (4). `RecordingDateTime` is empty.
  - Each `.bvct` also contains an ActiCap `ElectrodeLayout` (132 entries, identical in all 39 files) with Group (splitter box) and Number (0–31).
- **Consequence.** The S3a-D2 statement "No digitised positions exist, so all channel locations come from the `standard-10-5-cap385` template" is wrong.
  - 39 subjects: CapTrak-digitised X/Y/Z plus digitised fiducials.
  - sub-12, sub-23, sub-24: only individual but integer-rounded spherical coordinates (`.bvef`), of unknown provenance, with fiducial entries of unknown provenance.
  - If individual positions are used, this quality difference between the two groups must be reported.

  **D2 is reopened**, in particular:
  - individual CapTrak positions vs the template;
  - TP9/TP10, whose positions are digitised.

  D2a/D2b stay in force until a new entry supersedes them. The coordinate frame and units of the `.bvct` must be established before any use.

## S3a-D4e-4-issue · 2026-10-04 · Channel labels differ between .vhdr and channels.tsv (sub-13, sub-41, sub-42): open

- **Facts.**
  - All 84 `*_channels.tsv` list the 127 channels in the same order. That order equals the manufacturer's ActiCap order (Group, Number) from the `.bvct` layout, with slot (3, 0) = FCz (the reference) absent.
  - 78 of the 84 `.vhdr` have exactly this order.
  - The `.vhdr` of three subjects deviate. In each subject the rest and MSIT+ headers are identical and the label set equals `channels.tsv`.
    - sub-13: positions 121/124 swapped (FFT8h ↔ FCC6h).
    - sub-41: positions 5/6 swapped (FC5 ↔ FT9).
    - sub-42: FFC2h is at position 127 instead of 93; positions 93–126 are shifted up by one.
- **The open question:** why does the data order deviate from the manufacturer order in these three subjects?
  - (a) The data columns were reordered before export, and the `.vhdr` labels are right.
  - (b) The data are in manufacturer order, and the `.vhdr` labels were changed.
- Text files cannot decide between them.
  - For (a): the `channels.tsv` of these subjects did not inherit the deviations, so it was not generated from these headers. And sub-42's pattern (one channel moved to the end) matches an EEGLAB remove-and-append (the files were exported from EEGLAB).
  - Neither fact shows which label describes each data column, and the `.bvct` `<Channel>` field cannot (all 0).
- **Status:** open. Stage 3 keeps the D4e-4 stop-on-mismatch for these three subjects until a decision is logged. A possible resolution, an outcome-blind neighbour-correlation test, is proposed separately and has not been run.

## S3a-D5-0-exc · 2026-10-04 · D5-0 exception: provisional .vhdr labels for sub-13, sub-41, sub-42

- D5-0's channel check stops on these subjects. **For D5-0 only**, their channels are labelled as in the `.vhdr`, and every output row of these recordings carries `labels_provisional = 1`.
- No D5-0 rule outcome depends on which labelling is correct:
  - kept channels = all but TP9/TP10, which sit at positions 10/21 in both files;
  - R1 and R3 use maxima over kept channels, and R2 uses medians over kept channels.
- Stage 3 is not affected: the stop-on-mismatch rule stays.

## S3a-D4e-4-test · 2026-10-04 · Proposed (not run): label test for sub-13/41/42 and a rank / predictability check on all 84 recordings

- **Status: pre-registration draft. Nothing has run.** Both tests read binary `.eeg` files: test N reads 6 recordings, test P all 84. Each needs explicit approval.
- **Outcome-blind constraint (both tests).**
  - Data are band-passed to 1–10 Hz (`pop_eegfiltnew`, within raw segments) before any computation.
  - Only time-domain channel × channel statistics (correlations, covariances, regressions) are computed. No spectrum is computed, and nothing in 13–30 Hz or 55–95 Hz is computed, saved or printed.
  - Note: 1–10 Hz includes 8–10 Hz (alpha). If alpha must also be avoided, 1–7 Hz is the alternative.
- **Common preparation.**
  1. Load with `pop_loadbv` (by channel groups for memory), resample to 500 Hz (`pop_resample`, boundary-aware), band-pass 1–10 Hz.
  2. Keep only the D4e-clipped blocks. A further margin equal to the band-pass half-length is dropped at each block edge; that half-length is computed by `stage3_filter_halflengths`-style design, not typed in.
  3. Cut into non-overlapping 10 s chunks.
  4. TP9/TP10 are excluded from all statistics. FCz is absent (online reference).
- **Test N, neighbour correlation (sub-13, sub-41, sub-42; rest and MSIT+ analysed separately).**
  - Common-average reference over the 125 channels; it does not depend on the labelling.
  - Per chunk, a 125 × 125 Pearson correlation; per recording, the median over chunks of Fisher z.
  - **Neighbours** of a label: its k = 6 nearest labels by Euclidean distance in the subject's own CapTrak X/Y/Z (`.bvct`; all three subjects have one), excluding TP9/TP10/FCz/GND/fiducials. k = 4 and k = 8 are reported as sensitivity.
  - **Hypotheses:** H_vhdr (data column j has `.vhdr` label j) and H_tsv (data column j has `channels.tsv` label j).
  - **Affected labels:** those whose column differs between the hypotheses (sub-13: FFT8h, FCC6h; sub-41: FC5, FT9; sub-42: the 35 labels at positions 93–127). None of Fz, Cz, C4 is affected.
  - **Score** of label L under H: s_H(L) = mean z between column_H(L) and column_H(N) over the neighbours N of L.
  - **Reference distribution:** s(U) for every unaffected label U (identical under both hypotheses).
  - **Decision rule**, per subject:
    - H is **supported** if, in both rest and MSIT+, (i) every affected label has s_H(L) ≥ the 5th percentile of s(U), and (ii) under the other hypothesis at least one affected label falls below that percentile.
    - The labelling is then fixed to H for that subject, and the D4e-4 stop is lifted for it.
    - If both or neither hypothesis meets (i)–(ii), or rest and MSIT+ disagree, the result is **ambiguous**: the affected channels are treated as unreliable for that subject (handling decided under D6/D11), and the stop stays until that decision.
    - Expected power: high for sub-42 (35 shifted labels), lower for sub-41 (FC5 and FT9 are close and share neighbours), where an ambiguous result is plausible.
- **Test P, rank and predictability (all 84 recordings).**
  - On the 125 channels, as recorded (no re-referencing), concatenated chunks:
    - **Covariance eigenvalues:** report the 5 smallest relative to the median eigenvalue (dB). A **deficient dimension** is an eigenvalue < −60 dB relative to the median.
    - **Average reference before export:** per chunk, the RMS of the channel mean divided by the median channel SD. A value < 1e-4 in every chunk means the data were exported average-referenced.
    - **Predictability:** per channel c, 1 − R² of an OLS regression of c on the other 124 channels, from the inverse covariance. A channel is **near-perfectly predicted** (consistent with interpolation) if 1 − R² < 1e-4 (−40 dB). The full distribution is reported, so the gap from naturally correlated neighbours is visible.
    - **Predictor check** for each near-perfectly predicted channel: its 6 largest standardised weights, and whether they are its spatial neighbours. For sub-13/41/42 this is evaluated under both labellings. If an exported channel was interpolated from its true neighbours, the labelling under which the predictors are its neighbours is evidence for (a) or (b).
  - **Consequence for D9:** the number of deficient dimensions per recording (after TP9/TP10 removal) is carried into the ICA rank decision.
  - **Consequence for D11:** channels found to be interpolated before export are listed per subject.
- **Outputs (if approved):** `<outRoot>/stage3/d4e4_test/neighbour_scores.csv`, `rank_predictability_by_recording.csv`, `predictability_by_channel.csv`.

## S3a-D5-0-crash · 2026-10-04 · D5-0 run: MATLAB heap corruption, four system crashes, hardware hypothesis

- **Status: diagnostic record. No decision.** No D5-0 line-noise value has been inspected; the checks below look only at file structure, exit codes and system logs.
- **Machine.** Intel i7-4720HQ (4 cores / 8 threads); MATLAB R2022b with MKL 2021.3 (AVX2); 12 GB RAM in two unmatched Samsung DDR3-1600 SODIMMs (4 GB `M471B5173EB0-YK0` + 8 GB `M471B5273DH0-CK0`).
- **D5-0 run** (driver: one fresh MATLAB process per recording, at most 2 tries; `<outRoot>/stage3/d5_0/driver_log.txt`, 14:26–16:52):
  - 78/84 recordings cached in `per_recording/`.
  - sub-13, sub-41, sub-42 (6 recordings) stopped on the channel-label assert. The run used the script as it was before the S3a-D5-0-exc edit (file saved 16:55:45, after the driver ended).
  - The final assembly call computed and saved `sub-06_msit.mat` (16:52:36), which had failed twice in the driver, then stopped on the sub-13 label assert. No CSV and no `run_info.txt` exist.
- **MATLAB heap corruption** (`0xc0000374`, faulting module `ntdll.dll`; Windows Application log, event 1000): 10 events between 14:22 and 17:33.
  - 1 in the earlier single-session run (14:22, `run_log_stderr.txt`).
  - 7 in the driver, all on MSIT+: sub-06 (both tries), sub-11, sub-17 (try 1; try 2 succeeded), sub-24, sub-26, sub-42 (try 1). In 3 of them (sub-11, sub-24, sub-26) the process crashed **after** saving its `.mat`. No rest run crashed (36 rest runs in the driver).
  - 2 in the bisection probes below.
  - Confound: MSIT+ recordings are both the longest jobs (75–108 chunks vs 58–60 for rest) and the ones with many events. Recording type alone cannot separate a load effect from an event-handling effect.
- **Bisection on sub-06 MSIT+** (`d50_probe.m` in the session scratchpad; a fresh MATLAB per run; results discarded, nothing written to `<outRoot>`):

  | Mode | Stages run | Runs | Heap crashes | Runtime |
  |---|---|---|---|---|
  | load | `pop_loadbv` per 16-channel group | 3 | 0 | ~4 s |
  | loadevt | + block events, `eeg_checkset` | 3 | 0 | ~5 s |
  | resample | + `pop_resample` | 3 | 0 | ~100 s |
  | nostim | resample with stimulus events removed | 3 | 0 | ~20 s |
  | synth | random data, detrend + DFT product only | 6 | 0 | ~5 s |
  | nodft | full pipeline without the DFT product | 6 | 0 | 101–121 s |
  | full | as D5-0 | 8 completed + 1 cut by the shutdown | 2 | 106–127 s |

  - Where the error appeared: in `full_3` it was printed right after "resampling event latencies…"; in `b2_full_2` it came **after** `PROBE_DONE`, i.e. at process exit, after all computation.
  - Heap corruption is detected at a later heap operation, not where it happens, and `-batch` output can be buffered. So these runs do **not** localise the fault to the chunk loop. They show only that the crashes occurred in `full` runs. With 2 crashes in 8 `full` runs and 0 in 6 `nodft` runs, `full` and `nodft` cannot be told apart.
  - Event handling in `pop_resample` takes most of the runtime (resample ~100 s vs nostim ~20 s).
- **System crashes** (System log: Kernel-Power 41 and WER 1001). Four unclean restarts in about 27 h:

  | Restart | Bugcheck | Meaning | Activity at the time |
  |---|---|---|---|
  | 2026-10-03 16:31:57 | 0x7F, arg 0x8 | unexpected kernel-mode trap (double fault) | not determined |
  | 2026-10-03 21:39:56 | 0x7E, 0xC0000005 | kernel-mode access violation | not determined (no file writes found 21:00–21:40) |
  | 2026-10-04 14:12:13 | 0x3B, 0xC000001D | **illegal instruction in kernel mode** | single-session D5-0 run; its log stops at 14:11:26 in the middle of resampling, with no MATLAB error |
  | 2026-10-04 19:32:44 | 0 (none) | no bugcheck: power cut, thermal trip or hard hang; no power-button press recorded | D5-0 probe `b2_full_6`; last file write 17:40:15, in the middle of resampling |

  - Event 6008 gives 17:32:20 as the time of the last shutdown, but files were written until 17:40:15. That 6008 time is a heartbeat, not the crash time.
  - Only one kernel dump remains (`C:\Windows\MEMORY.DMP`, 14:12:16); each new dump overwrites the previous one.
- **Hypotheses.**
  - **H-HW (hardware):** instability under sustained heavy load, from RAM, CPU/VRM heat or the power supply. This explains both the nondeterministic user-mode heap corruption (the same recording passes or fails) and the kernel crashes.
    - Supporting: four kernel crashes with four different codes, including an illegal instruction in kernel mode; two of the four happened during D5-0 load.
    - User-mode MATLAB code cannot by itself bugcheck the kernel.
    - Not proven: a faulty driver could also produce varied bugchecks.
  - **H-SW (software):** a bug in MATLAB, MKL or EEGLAB on the multithreaded or event-resampling path. This explains the heap corruption but not the kernel crashes, unless both causes are present.
- **Integrity after the 19:32 restart** (checked 2026-10-04):
  - `git fsck --full --strict` was clean in all three repositories (root, `eeg-beta-project`, `Paper`). The only dangling objects are the empty blob (`eeg-beta-project`) and one unreferenced 46,872-byte blob (`Paper`).
  - The uncommitted files are intact: `docs/decision_log.md` (no NUL bytes, ends on a complete line) and `revision/stage3/stage3_d5_0_line_noise.m` (untracked, complete through its final `end`).
  - No project file changed in the 30 min before the crash. The only writes were scratchpad probe logs.
  - All 78 `per_recording/*.mat` files load, and each was checked for: the expected variables; 127 labels identical to `channels.tsv`; 244 grid frequencies; one equal `nChunk` per 16-channel group; `avgP`, `exc`, `fpk` and `amp` of the expected shape, all finite and with positive `avgP`.
  - SHA-256 hashes of the 78 files were recorded (`d50_cache_sha256_2026-10-04.txt`, currently in the session scratchpad; to move to `<outRoot>/stage3/d5_0/` if approved), so any later change can be detected.
  - **Limit:** these checks cannot detect a value that is finite but wrong. Under H-HW, a recording that saved without a crash could still be silently corrupted. A recompute-and-compare check is needed before any D5-0 value is used.
- **Consequence.** D5-0 outputs are not used, and no heavy MATLAB job runs, until (i) H-HW is tested and (ii) a recompute check passes. The test design is proposed separately and logged before it runs.

## S3a-HW-1 · 2026-10-06 · Hardware change: CPU thermal paste replaced

- **Fact** (reported by Amirhossein): the CPU thermal paste was replaced on 2026-10-06, before the thermal ladder (first log row 19:40:46). The exact time or interval was not provided.
- **Consequence for the crash record.** Every crash datum in S3a-D5-0-crash (the 10 MATLAB heap-corruption events and the 4 unclean restarts), and every D5-0 run of 2026-10-04, **predates this change**.
  - The acceptance test of S3a-INF-1 (§8) evaluates the system **after** this change.
  - The thermal ladder of S3a-INF-1 (§6; logs from 19:40 to 20:28 on 2026-10-06) was run after it.
  - Whether the synthetic runs of S3a-D5-opt (finished 18:59 on 2026-10-06) ran before or after the change is not recorded. This has no practical bearing: those runs are filter design and synthetic signals only, and their replicas A and B were identical.
- No conclusion about H-HW (S3a-D5-0-crash) is drawn from the change itself.

## S3a-D5-0-hist · 2026-10-06 · D5-0: historical files moved into the repository; the executed script version

- **Moved** on 2026-10-06, unchanged (same-volume moves), from Claude Code session scratchpads under `%TEMP%` to `revision/stage3/historical/d5_0_2026-10-04/` (marked historical in its `README.md`):
  - `run_d5_0.ps1`: the D5-0 driver (14:26–16:52 local, 2026-10-04);
  - `d50_probe.m`: the crash-bisection probe;
  - `check_d50_cache.m`, `check_d50_cache.log`: the structural check of the 78 cached files cited in S3a-D5-0-crash;
  - `d50_cache_sha256_2026-10-04.txt`: SHA-256 of the 78 cached files. This supersedes the location `<outRoot>/stage3/d5_0/` proposed in S3a-D5-0-crash;
  - `d5_notch_design.m` and `d5_notch_design_output_2026-10-04.txt`: the synthetic design of the option (a) kernels (S3a-D5-opt). The output was captured verbatim from the session transcript; it was never saved to a file at the time.
- **The exact executed version of `stage3_d5_0_line_noise.m` was not recorded.** The driver ran the version before the S3a-D5-0-exc edit (saved 16:55:45 local, after the driver ended). No hash or commit of that version exists. In this strict sense it is lost.
  - A reconstruction exists: `stage3_d5_0_line_noise_pre_exc_reconstructed.m` (SHA-256 `9ea3b34f…742ca`), rebuilt from the tool calls in the session transcript (one `Write`, two `Edit`s).
  - Re-applying the logged `-exc` patch to the reconstruction gives a file byte-identical to the current `revision/stage3/stage3_d5_0_line_noise.m`. So the logged edits account for the whole file.
  - It cannot be shown that nothing else changed the file on disk between 14:02 and 16:55 local. The reconstruction is the most likely executed version, not a verified one.
- `revision/stage3/stage3_d5_0_line_noise.m` stays in place: S3a-D5-0 names that path, and its `entryHash` finds `docs/decision_log.md` relative to its own folder.
- None of these files produces a number used anywhere. The 78 cached D5-0 files remain unused (S3a-D5-0-crash).

### Note (2026-10-06, appended; the entry above is unchanged)
- The D5 option scenario files behind the data-cost figures quoted in the 2026-10-04 session were moved unchanged (SHA-256 identical before and after) to `revision/stage3/historical/d5_0_2026-10-04/d5_option_scenarios/`:
  - `notch4/`: option (a), 32 blocks clipped, 35 stimuli lost;
  - `notch2/`: option (a′), 23 blocks clipped, 15 stimuli lost.
- Each folder holds the survey outputs and the **hand-edited** `filter_halflengths.csv` (the notch rows were typed in). The figures stay unverified and unused.

## S3a-D5-opt · 2026-10-06 · D5 options (a), (a′) and (b) defined; residual criterion of (b)

- **Status: definition, logged before any D5-0 value is inspected.** The 78 per-recording files cached on 2026-10-04 exist, but no value in them has been read, and they are not used (S3a-D5-0-crash). The D5-0 recompute (S3a-INF-1) runs only after this entry is committed.
- **History.** The options were proposed on 2026-10-04 (session transcript) and not logged until now. Amirhossein's provisional choices of 2026-10-04:
  - (b) is the provisional choice;
  - if (b) fails its residual criterion, (a) is used for **all** recordings (no mixing of methods across subjects);
  - (b′) (CleanLine on the whole recording) and (c) (ZapLine-plus) are dropped;
  - (a′) is admissible only if D5-0 R1 shows that 150 and 200 Hz are absent. Both lie below Nyquist at 500 Hz, so the "above Nyquist" alternative does not arise.
- **Common to all options.**
  - Applied at 500 Hz after resampling and before cropping (S3a-D4c).
  - Applied to each raw segment separately. A segment is delimited by the recording start/end and every raw boundary (S3a-D4e).
  - Line frequencies F_L = {50, 100, 150, 200} Hz (S3a-D4b), all below Nyquist (250 Hz).

### (a) FIR band-stop at every f₀ in F_L
- `pop_eegfiltnew(EEG, 'locutoff', f0-2, 'hicutoff', f0+2, 'revfilt', 1)`, firfilt 2.8 default design: windowed sinc, Hamming window, zero-phase. Four separate filters in cascade. firfilt filters each segment separately.
- **Transition width 2 Hz.** `pop_eegfiltnew.m:221–230`: for a band-stop, maxDf = (hicutoff − locutoff)/2 = 2 Hz and df = min(max(0.25·maxDf, 2), maxDf) = 2 Hz.
  - So the passband edges are f₀ ± 2 Hz, the −6 dB points f₀ ± 1 Hz, and the full stop-band attenuation is reached only at f₀ itself.
  - Order = 3.3/(df/fs), rounded up to even, = 826.
- **Design values** (synthetic run, `historical/d5_0_2026-10-04/d5_notch_design_output_2026-10-04.txt`):
  - per filter: order 826, half-length 413 samples = 0.826 s;
  - gain at f₀: −47.014 / −46.431 / −46.721 / −46.866 dB at 50 / 100 / 150 / 200 Hz;
  - gain −6.051 and −6.049 dB at 49 and 51 Hz, and −0.033 and −0.032 dB at 48 and 52 Hz;
  - |gain| ≤ 0.011 dB at the points evaluated in 13–30 and 55–95 Hz (13, 20, 30, 55, 60, 90, 95 Hz). This was checked at those points only, not on a dense grid (open point ii).
- **H:** contribution 4 × 0.826 = 3.304 s, so H = 3.333 + 3.304 = **6.637 s**. When (a) is adopted, the notches are added to `stage3_filter_halflengths.m` and H is recomputed there.
- **Data cost under D4e** (blocks clipped, stimuli lost) must be recomputed with that H before (a) is used. **The figures quoted on 2026-10-04 are UNVERIFIED and are not used:** (a) 32 blocks clipped, 35 stimuli lost (16 block-first) in 17 subjects; (a′) 23 blocks, 15 stimuli (7 block-first) in 8 subjects.
  - They come from files that exist only in a Claude Code session scratchpad under `%TEMP%` (`…/1680c193…/scratchpad/notch4/` and `notch2/`), not in the repository or `outRoot`.
  - Those files were produced by the committed survey script (`stage3_raw_boundaries_d4e.py`) from a **hand-edited** `filter_halflengths.csv` whose notch rows (0.826 s each) were typed in, not produced by `stage3_filter_halflengths.m`.

### (a′) as (a), at 50 and 100 Hz only
- H contribution 2 × 0.826 = 1.652 s, so H = 4.985 s.
- Admissible only under D5-0 R1 (150 and 200 Hz absent).

### (b) CleanLine 2.1, new implementation (`cleanLineNoise`), on each raw segment
- Called directly by our wrapper, not via `cleanline.m`/`pop_cleanline` (whose default `newversion` is false). The parameters are the `cleanline.m` defaults of the new path (`cleanline.m:150–213`), except the line frequencies:
  - `lineFrequencies` [50 100 150 200]; `p` 0.01; `fScanBandWidth` 2 Hz; `taperBandWidth` 2 Hz;
  - `taperWindowSize` 4 s; `taperWindowStep` 1 s; `tau` 100; `pad` 2; `fPassBand` [0 250]; `maximumIterations` 10;
  - all EEG channels present at that pipeline step.
- **Mechanism** (`removeLinesMovingWindow.m`, `fitSignificantFrequencies.m`):
  - In each 4 s window, a multitaper F-test is computed.
  - For each f₀, the most significant frequency within f₀ ± 1 Hz (± `fScanBandWidth`/2) is taken. If it is significant at p < 0.01, a sinusoid with fitted amplitude and phase at that frequency is subtracted. Otherwise nothing is removed.
  - Consecutive windows (3 s overlap) are blended with a sigmoid (tau 100).
  - The procedure is repeated up to 10 times. An f₀ drops out once it is no longer significant or its dB reduction becomes negative.
- **Segment rules.**
  - A segment shorter than 4 s is not processed: `cleanLineNoise` needs one full window. The wrapper asserts that such a segment overlaps no block. Known case: sub-25 rest, a 0.192 s break segment.
  - The last < 1 s of each segment (less than one window step) is left uncleaned. Blocks lie ≥ H = 3.333 s from every segment edge (D4e), so that tail never enters a block.
  - **H contribution 0** (not a convolution; nothing crosses a segment edge).
- **Determinism.** No random numbers. Channels are processed with `parfor` (`cleanLineNoise.m:57`), which runs serially only if no pool exists and `Pool.AutoCreate` is false (asserted under S3a-INF-1).
- **Outcome-blindness.** `cleanLineNoise` internally computes multitaper spectra over `fPassBand` to judge its dB reduction. These are not saved, printed or inspected.

### Residual criterion for (b): decided 2026-10-06
- **Decision (Amirhossein, 2026-10-06):** R-b1 = 3 dB excess, R-b2 = flank change ≤ 0.5 dB.
  - **Both values are conventions, not calibrated values.** 3 dB is the R1 "absent" threshold; 0.5 dB is a tolerance for "no change".
  - Synthetic calibration B (below) shows that the control band is insensitive to a residual of 1–6 dB excess: the rise of 55–60 / 90–95 Hz power is ≤ 0.043 dB in every variant. It therefore supports the 3 dB value for the control band, but does not derive it.
- **Test set:** the 3 D14 test subjects (rest and MSIT+) plus the 3 worst recordings by D5-0 R2.
- **Measure:** exactly the D5-0 measure, on the data before and after (b). That means the same 10 s chunks inside the clipped blocks, Hann window, DFT at f₀ ± 3 Hz, straight-line floor on 1.5 ≤ |f − f₀| ≤ 3 Hz, and excess = maximum over |f − f₀| ≤ 0.5 Hz.
- **(b) passes** if, in every tested recording, for every kept channel and every f₀:
  - **R-b1 (residual):** the chunk-averaged excess after (b) is < **3 dB** (the R1 "absent" threshold);
  - **R-b2 (no harm next to the line):** the mean PSD over the flank bins (1.5 ≤ |f − f₀| ≤ 3 Hz) changes by at most **0.5 dB** between before and after.
- The per-chunk median and maximum residual excess are reported descriptively.
- If (b) fails, (a) is used for all recordings. Its residual is reported with the same measure, but it is not a pass/fail test.
- Outcome-blind as in D5-0: nothing in 13–30 or 55–95 Hz is computed, saved or printed.

### Open point (i): is removal at 150 and 200 Hz needed? Decided 2026-10-06: (i-1)
- **Facts.**
  - Both frequencies lie below Nyquist.
  - The `pop_resample` anti-aliasing filter (1000 → 500 Hz) has its **passband edge at 200 Hz** (fc 225 Hz, transition 200–250 Hz, design deviation 0.002, i.e. ≤ 0.017 dB in the passband). It therefore does **not** remove a 200 Hz line; attenuation starts above 200 Hz.
  - The exact gains at 197–203 Hz are not determined (`run_info.txt` was never written). They can be computed from the design without data.
- **Where 150/200 Hz lines matter:**
  - any EMG index above 100 Hz (the reason D4b keeps 100–200 Hz);
  - ASR (D7), ICA (D9) and ICLabel (D10), which see the full band (line peaks can be captured as "Line Noise" components).
- **Where they do not matter:** D6 (bad channels, run on the 100 Hz low-passed copy), and power in 13–30 or 55–95 Hz with the estimators used so far (far from those bands).
- **Options.**
  - **(i-1) Keep all four line frequencies (current D4b).**
    - What happens: line removal (D5) runs at 50, 100, 150 and 200 Hz in every recording; the data keep content up to the anti-aliasing passband edge (200 Hz).
    - Gain: the 100–200 Hz range stays available for a stronger EMG index (audit #10); ASR, ICA and ICLabel see data without line peaks at 150/200 Hz, if the removal works.
    - Cost: under (b), none in H. Under (a), 1.652 s of extra H (H = 6.637 s instead of 4.985 s), and two more 4 Hz spectral holes.
  - **(i-2) Drop 150 and 200 Hz now.**
    - What happens: line removal runs at 50 and 100 Hz only; lines at 150/200 Hz stay in the data.
    - Consequence: no index above 100 Hz can be computed without contamination. ASR, ICA and ICLabel see full-band data with any 150/200 Hz lines (possible "Line Noise" components).
    - Optional add-on: low-pass only the copy used to **fit** ICA (as the 1 Hz high-passed copy, D9), and apply the unmixing to the full-band data. ASR is not covered by this add-on.
    - Cost: under (a), it saves 1.652 s of H compared with (i-1); under (b), it saves nothing.
  - **(i-3) Let D5-0 R1 decide (rule already fixed for (a′)).**
    - What happens: 150 and 200 Hz are dropped only if D5-0 shows them absent (`excess_db` < 3 dB in every kept channel of every recording); otherwise (i-1).
    - Consequence: the choice is data-driven but outcome-blind (D5-0 sees only f₀ ± 3 Hz).
  - **(i-4) Low-pass the continuous data before ASR/ICA** (none of (i-1)–(i-3) does this for ASR).
    - What happens: a `pop_eegfiltnew` low-pass is applied to the continuous data at 500 Hz, before cropping (in the D4c chain after resampling, together with D5). Its stop-band ends below 148 Hz, so 150/200 Hz lines are removed by the low-pass, and D5 needs only 50 and 100 Hz.
    - Consequence: **this reverses D4b** (no content kept above about the cutoff, so no EMG index above it). The design and its H cost (half-length at 500 Hz) for two candidate passband edges, 100 Hz (as v1 and the D6 copy) and the highest default-design edge whose stop-band ends below 148 Hz, are computed in the synthetic run below; no value is typed in.
    - A variant that low-passes only the copies used to *fit* ASR and ICA is possible for ICA, but not cleanly for ASR, which corrects the data it is calibrated on.
- **Cost summary.** Under (b), including 150/200 Hz costs no H and removes nothing where no significant line exists. Under (a), it costs 1.652 s of H. Under (i-4), the low-pass adds its half-length to H (computed below).
- **Decision (Amirhossein, 2026-10-06): option (i-1).**
  - D4b is kept: no low-pass, and 100–200 Hz is retained for the EMG index. (i-4) is rejected.
  - 150 and 200 Hz are removed with the same method that D5 selects for 50 and 100 Hz: (b), or (a) if (b) fails its residual criterion.
  - **Rationale:**
    - D4b's EMG rationale stands.
    - ASR's default spectral-shaping filter weights 80–250 Hz ×3 in its statistics (`asr_calibrate.m:125–134`: `yulewalk` design amplitudes [3 0.75 0.33 0.33 1 1 3 3] at [0 2 3 13 16 40 80 250] Hz for 500 Hz). Residual harmonics would therefore inflate ASR statistics.
    - The harmonics would also contaminate the EMG index.
    - ICLabel's PSD features cover 1–100 Hz (`eeg_rpsd(EEG, 100)`, `ICL_feature_extractor.m:48`) and are unaffected.
  - **Consequence for the options:**
    - F_L = {50, 100, 150, 200} Hz under (b) and under the fallback (a).
    - (a′), (i-2) and (i-3) are withdrawn.
    - **D5-0 R1 becomes report-only.** This is a direct consequence of the (i) decision, made before any D5-0 output was viewed. R1 is still computed and reported, but its outcome no longer changes the line frequencies.

### Open point (ii): synthetic check that the 50 Hz stop band does not reach 55 Hz (logged as a test before it runs)
- **(a), frequency response.** Compute the response of the full pre-cropping chain (D4a high-pass, anti-aliasing filter, the four notches) on a 0.01 Hz grid.
  - Proposed pass rule: |gain| ≤ 0.05 dB for every f in [53, 95] Hz and [13, 30] Hz.
  - This concerns filter design only, not data.
- **(a) and (b), time domain.** Synthetic signal:
  - a 50 Hz line, also at 50 ± 0.3 Hz and with slow frequency drift;
  - unit sinusoids at 53, 55, 60, 75 and 95 Hz;
  - white noise;
  - generated at 1000 Hz and passed through the D4c chain.
  - Proposed pass rule: the least-squares amplitude of each test sinusoid changes by ≤ 0.05 dB.
  - For (b) additionally: the 50 Hz line is reduced to an excess < 3 dB, and a sinusoid at 51.5 Hz (outside the ±1 Hz scan band) is left unchanged.
- **Stage 5 caveat (not a filter property).**
  - With a 0.2 s Hann window, the main lobe spans ± 2/T = ±10 Hz around any line. **Both edges of the 55–95 Hz control band are therefore exposed:** a residual 50 Hz component leaks into 55–60 Hz, and a residual 100 Hz component into 90–95 Hz, whatever the filters' transition bands.
  - The D5 residual therefore matters for the control band, and the residual criterion of (b) is calibrated against this leakage (synthetic calibration B below). Stage 5 must take it into account.

### Synthetic calibrations (filter design and synthetic signals only, no EEG); logged 2026-10-06 before they run
- **Script:** `revision/stage3/stage3_d5_opt_synthetic.m` (a function of its output folder). Settings as in S3a-INF-1 §1 (`maxNumCompThreads(2)`, `MKL_CBWR=AUTO`, `rng(1,'twister')`).
- **Duplicate execution:** run twice in separate `matlab -batch` processes (A, B). A third process compares the two result files with `isequaln`. The results are reported only if A = B; otherwise nothing is reported and the mismatch is logged.
- **Output:** `<outRoot>/stage3/d5_opt_synthetic/run_A|run_B/` (`results.mat`, `table_A_attenuation.csv`, `table_B_leakage.csv`, `table_i4_lowpass.csv`, `run_info.txt` with the fingerprint).
- **A. Attenuation of (a)/(a′) near the line.** The kernels are designed exactly as in (a) (`pop_eegfiltnew`, ±2 Hz band-stop, at 500 Hz, on a zero-valued synthetic dataset). The gain (dB) of the (a) cascade (4 notches) and of the (a′) cascade (50 and 100 Hz) is reported at f₀ and at f₀ ± 0.1, 0.2, 0.5 and 1.0 Hz, for f₀ = 50 and 100 Hz (`freqz`). Descriptive; no rule.
- **(i-4) low-pass design.** `pop_eegfiltnew(…, 'hicutoff', E)` at 500 Hz, default design, for E = 100 Hz, and for the largest integer E whose stop-band edge (E + default transition width) is < 148 Hz. Reported per E: order, transition width, −6 dB cutoff, stop-band edge, half-length (samples, s), and the resulting H. Descriptive; no rule.
- **B. Leakage of a residual line into the control-band edges.**
  - **Residual line of X dB:** a sinusoid at exactly f₀ (50.0 or 100.0 Hz), with amplitude a(X) such that its **expected** D5-0 excess is X dB above a white background. That is, (N₀ + Pₛ)/N₀ = 10^(X/10), where Pₛ is the line's PSD at the peak bin under the D5-0 estimator (10 s Hann window, the D5-0 PSD scaling). Pₛ is computed from the actual window, not typed in.
  - **Stage 5 estimator (not yet decided; two variants):**
    - primary = the v1 estimator: `pwelch(x, hann(100), [], [], 500)` on 100-sample segments (one segment, default nfft = 256);
    - variant = the same window without zero-padding (nfft = 100).
    - Band power = mean PSD over the bins with 55 ≤ f ≤ 60 Hz and with 90 ≤ f ≤ 95 Hz (the v1 inclusive rule).
  - **Raise** = 10·log10(E[band power with line] / E[band power without line]). It is computed for each line (50, 100 Hz) × band (55–60, 90–95 Hz) × X ∈ {1, 2, 3, 6} dB, in two ways:
    - **(1) exact expectation** from the window (random phase, so the cross-terms vanish) for a white background. For 1/f^α backgrounds (α = 1, 2, normalised to N₀ at f₀), the line term is exact, but the background at each bin is approximated by its value at the bin (smoothing by the window is ignored);
    - **(2) Monte Carlo** for the white background: 20,000 segments, random phase, Gaussian noise, `rng(1)`. Reported as a check on (1).
  - X ∈ {10, 15, 20, 30} dB are added **descriptively**, to show where 0.5 dB is crossed.
- **Proposal rule for the (b) residual threshold (Amirhossein decides after seeing it):** the largest X in {1, 2, 3, 6} dB for which the raise is ≤ 0.5 dB in both bands, for both lines, under the white background, using the primary estimator. The variant estimator and the 1/f^α backgrounds are reported as sensitivity analyses. If they change the answer, that is stated.

### Outcome of the synthetic calibrations (appended 2026-10-06 after the runs; the procedure above is unchanged)
- **Run.** Replicas A and B in separate processes, 2026-10-06 (A finished 18:59:45). Both exited 0. `results.mat` is `isequaln` between A and B for every field, and the three CSV tables are byte-identical. Files: `<outRoot>/stage3/d5_opt_synthetic/run_A|run_B/`.
  - Environment: MATLAB R2022b, MKL 2021.3, `version('-blas')` "CNR branch AVX2", 2 threads, `MKL_CBWR=AUTO`, firfilt 2.8.
  - Values below are rounded to 3 decimals for display; exact values are in the CSV files.
- **A. Gain (dB) of the band-stop cascades near the line** (`table_A_attenuation.csv`):

  | f₀ | option | −1.0 | −0.5 | −0.2 | −0.1 | 0 | +0.1 | +0.2 | +0.5 | +1.0 Hz |
  |---|---|---|---|---|---|---|---|---|---|---|
  | 50 | (a) | −6.051 | −18.203 | −33.146 | −41.122 | −47.014 | −41.146 | −33.162 | −18.202 | −6.049 |
  | 50 | (a′) | −6.049 | −18.203 | −33.146 | −41.121 | −47.013 | −41.144 | −33.160 | −18.202 | −6.048 |
  | 100 | (a) | −6.045 | −18.197 | −33.041 | −40.826 | −46.431 | −40.871 | −33.072 | −18.201 | −6.048 |
  | 100 | (a′) | −6.046 | −18.195 | −33.039 | −40.825 | −46.431 | −40.871 | −33.072 | −18.200 | −6.045 |

  - Meaning: a line 0.5 Hz off f₀ is attenuated by only about 18 dB, and one 1 Hz off by about 6 dB. This is relevant to D5-0 R3 (peak drift > 0.5 Hz).
- **(i-4) Low-pass designs** (`table_i4_lowpass.csv`; default `pop_eegfiltnew` low-pass at 500 Hz):

  | Passband edge | Order | Transition | −6 dB | Stop-band edge | Half-length | Gain 150 / 200 Hz | H with (b) | H with (a′) |
  |---|---|---|---|---|---|---|---|---|
  | 100 Hz | 66 | 25.000 Hz | 112.500 Hz | 125.000 Hz | 33 samples = 0.066 s | −60.659 / −82.300 dB | 3.399 s | 5.051 s |
  | 118 Hz (largest integer edge with stop-band < 148 Hz) | 56 | 29.464 Hz | 132.732 Hz | 147.464 Hz | 28 samples = 0.056 s | −53.449 / −96.888 dB | 3.389 s | 5.041 s |

  - H is the current 3.333 s (`stage3_filter_halflengths.m`) plus the low-pass half-length, plus 1.652 s for the two notches of (a′).
- **B. Rise (dB) of control-band-edge power caused by a residual line with expected D5-0 excess X** (`table_B_leakage.csv`; white background; exact expectation, with the Monte Carlo value in brackets):

  | Estimator | Line → band | X = 1 | 2 | 3 | 6 dB |
  |---|---|---|---|---|---|
  | primary (nfft 256) | 50 Hz → 55–60 | 0.001 (0.001) | 0.002 (0.002) | 0.004 (0.004) | 0.011 (0.011) |
  | primary (nfft 256) | 100 Hz → 90–95 | 0.001 (0.001) | 0.003 (0.003) | 0.005 (0.005) | 0.015 (0.015) |
  | variant (nfft 100) | 50 Hz → 55–60 | 0.003 (0.003) | 0.006 (0.007) | 0.011 (0.011) | 0.033 (0.033) |
  | variant (nfft 100) | 100 Hz → 90–95 | 0.003 (0.003) | 0.006 (0.006) | 0.011 (0.011) | 0.033 (0.033) |

  - Cross terms (50 Hz → 90–95 Hz, 100 Hz → 55–60 Hz): < 1e-4 dB.
  - 1/f^α backgrounds (α = 1, 2): the largest rise at X = 6 dB over every estimator, line and band is 0.043 dB (variant estimator, 50 Hz → 55–60 Hz, α = 2).
  - Descriptive, X > 6 dB: the 0.5 dB rise is first exceeded between X = 20 and 30 dB with the primary estimator (100 Hz → 90–95 Hz: 0.484 dB at X = 20, 3.402 dB at X = 30), and between X = 15 and 20 dB with the variant estimator (0.327 dB at X = 15, 0.978 dB at X = 20; with α = 2 for 50 Hz: 0.425 and 1.245 dB).
  - Monte Carlo agrees with the expectation to within 0.0004 dB for X ≤ 6 (largest absolute difference 0.000324 dB).
- **Proposal under the pre-registered rule: X = 6 dB**, the largest tested value. The rule is **not binding** within {1, 2, 3, 6}. Every rise is ≤ 0.043 dB across all variants, so the sensitivity analyses do not change the answer. **Not adopted:** Amirhossein kept 3 dB as a convention (see "Residual criterion for (b): decided 2026-10-06").
- **Limits of this calibration** (stated, not resolved):
  - It covers only leakage into the control band through a 0.2 s Hann estimator, for a stationary line.
  - It does not cover the other reasons for a residual criterion: line components in ICA/ICLabel (D9/D10), an index above 100 Hz, and the noise bias of the D5-0 measure. That bias exists because the maximum over 11 bins of a chunk-averaged noisy PSD is > 0 dB even without a line; it is not computed here.
  - A threshold above 3 dB therefore needs a separate argument for those purposes.

## S3a-D1-amend · 2026-10-06 · Large outputs and a verified raw working copy move to D:; E: is no longer read by jobs

- **Facts** (2026-10-06; volume and file metadata only, no file content read):
  - **C:** Samsung SSD 860 EVO 250 GB (SATA), system drive. 22,550,908,928 bytes free (21.0 GiB; 26.7 GiB on 2026-10-05).
  - **D:** Lexar 256 GB SSD, SATA (internal), NTFS, 238.0 GiB. 107,495,354,368 bytes free (100.1 GiB).
  - **E:** WD Elements, USB HDD, 931.5 GiB, 71.0 GiB free. It holds the raw data and has 4 pending sectors (reported by Amirhossein, 2026-10-05).
  - **Raw dataset size** (`ds004621` on E:, from file sizes):
    - excluding `.git`: 1,340 files, 93,735,671,334 bytes (87.298 GiB); `.git` itself is 2,818 files, 2,047,791 bytes;
    - **Stage 3 scope:** the 420 rest/MSIT+ files of S0-1 = 44,629,968,968 bytes (41.565 GiB), of which the 84 `.eeg` = 44,627,213,768 bytes;
    - `sourcedata/sub-XX/coords`: 42 files, 2,751,515 bytes; top-level files: 14, 45,486 bytes.
  - `BinaryFormat=IEEE_FLOAT_32` in the one header checked (sub-06 MSIT+); the other headers were not checked.
  - `pop_saveset` writes EEG data as float32 (`pop_saveset.m:228`).
  - NTFS last-access updates were enabled (`fsutil behavior query disablelastaccess` = 2, "System Managed"). Reading a file on E: could therefore let Windows update its last-access time stamp; this applies to every read before the change below.
  - **Changed 2026-10-06 (Amirhossein): `fsutil behavior set disablelastaccess 1`.** This is a **global** setting (all NTFS volumes, not E: only). After a restart on 2026-10-06, `fsutil behavior query disablelastaccess` shows "DisableLastAccess = 1 (User Managed, Last Access Time Updates DISABLED)".
    - From then on, reads on E: no longer update last-access time stamps. The raw copy (below) has not run yet, so it runs under this setting.
- **Decision (Amirhossein, 2026-10-06).**
  - **D1-amend-1, location.** `eegOutRoot` = a new folder on D: (proposed `D:\Revision_EEG`). This replaces `E:\Revision_EEG` of S3a-D1 option (i). Small tables, reports and figures stay under `outRoot` on C:.
  - **D1-amend-2, raw working copy.** The Stage 3 scope (420 rest/MSIT+ files, the CapTrak coords, the top-level files) is copied once to D: (proposed `D:\Revision_Raw\ds004621`, same relative layout).
    - The full dataset is not copied: 87.3 GiB would leave about 12.8 GiB on D:, below the 15 GB gate before any output exists.
    - After verification, `bidsRoot` in `config_local.m` (gitignored) points to the copy. Stage 3 jobs read only the copy. E: stays the read-only original: it is not read by jobs and never written.
  - **D1-amend-3, approval scope (Q3).** `.eeg` bytes on E: are read only to copy them and to hash them. Their content is not parsed.
- **Copy and verification procedure** (`revision/stage3/stage3_raw_copy_verify.py`; three separate runs; nothing runs without approval):
  1. `manifest`: the OpenNeuro 1.0.3 snapshot metadata for every file in scope is fetched with the S0-1 query and frozen in `<outRoot>/stage3/raw_copy/reference_manifest_1.0.3.tsv`.
     - S0-1 stored no hashes, only per-file statuses, so the reference ids are fetched again.
     - Reference kind as in S0-1: SHA-256 (the git-annex key) for annexed files, the **git blob SHA-1** for non-annexed files.
     - Network access is approved for this step only (public OpenNeuro 1.0.3 metadata; Amirhossein, 2026-10-06). Every raw API response is saved verbatim, with its request and a time stamp, as `reference_raw_responses_1.0.3_<timestamp>.jsonl` next to the manifest. The SHA-256 of both files goes to `reference_manifest_1.0.3.tsv.sha256`.
  2. `copy`: each file is read once from E:. The same bytes are hashed (SHA-256 and git-blob SHA-1) and written to `*.partial` on D:, then fsync'ed.
     - The file is renamed to its final name only if its size and reference hash match.
     - Failures (mismatch, read error) are deleted and logged. There is no retry inside a run; a later run copies only the missing files.
  3. `verify`: a separate run, preferably after a reboot so that files are read from the disk and not from the Windows file cache. Every file on D: is re-read and compared with the reference and with its copy-time SHA-256.
- **Decision rule.**
  - **All files match both, and D: holds no unexpected file:** `verified_manifest.tsv` (relative path, size, SHA-256) is written, and `bidsRoot` is switched to the copy.
  - **Otherwise:** the failing files are copied again in a new run. A file that fails in two runs stops the procedure and is reported. E: is never written.
  - **Every Stage 3 job** hashes (SHA-256) every raw file it reads and compares it with `verified_manifest.tsv`. A mismatch fails the job, with no retry, until the copy is re-verified.
- **Space check** (upper-bound arithmetic from file sizes; not a measurement):
  - After the copy, D: has 62,862,588,399 bytes (58.5 GiB) free.
  - One continuous version of all 84 recordings, uncropped, at 500 Hz, 126 channels, float32, is at most 44,627,213,768 × (500/1000) × (126/127) = 22,137,909,192 bytes (20.6 GiB). S3a-D1 option (b) keeps two versions: ≤ 41.2 GiB.
  - That leaves ≥ 18,586,770,015 bytes (17.3 GiB, 18.6 GB), above the 15 GB gate. This holds **only if** replica B is deleted as soon as A = B is verified (S3a-INF-1) and nothing else is stored on D:.
  - The margin is narrow. The S3a-D1 gate stays binding, now evaluated on D: (≥ 15 GB left after the projected output) and on C: (≥ 5 GB free), before the 3-subject test and before the 42-subject run.

## S3a-INF-1 · 2026-10-06 · Proposed (not run): crash-tolerant A/B execution of every heavy Stage 3 job; first use = full D5-0 recompute

- **Status: pre-registration draft. Nothing has run.** It governs every heavy MATLAB job until the H-HW hypothesis of S3a-D5-0-crash is resolved.
  - The 2026-10-04 D5-0 cache (78/84) is not used and is **not compared** with the new results: it was computed with a different thread count, so a difference would not show corruption.
  - **Thread count of earlier runs** (observed by Amirhossein, 2026-10-06): `maxNumCompThreads` returned **4** before being set to 2. Earlier runs, including the 2026-10-04 D5-0 cache, therefore used 4 threads.
- **Outcome-blind:** neither the runner nor the comparison computes, saves or prints anything in 13–30 or 55–95 Hz. A comparison reports only three things: equal (yes/no), the number of differing elements, and the maximum absolute difference.
- **Decisions applied (Amirhossein, 2026-10-06):** ID approved; Q2 → S3a-D1-amend; Q3 → S3a-D1-amend; Q4–Q9 below; Q10 handled by Amirhossein outside this entry (power plan, Windows Update, HWiNFO licence).

### 1. Process isolation, identical configuration, inputs and outputs
- **Runner.** An outer runner in Windows PowerShell 5.1 (`Invoke-Stage3Batch.ps1`). One command starts or resumes a batch (`-BatchId`).
- **One job = one fresh `matlab -batch` process.** Jobs run sequentially, never two at once. Replicas are run in the order A, then B (then C, §4).
- **Environment**, set by the runner for the child process only (no system setting changes): `MKL_CBWR=AUTO`.
  - **Unverified:** no MathWorks documentation was found that R2022b honours `MKL_CBWR`.
  - Intel documents that a call to `mkl_cbwr_set` overrides the variable; whether MATLAB makes such a call is unknown.
  - Non-STRICT CNR assumes a constant thread count.
  - Code outside MKL (FFTW, MATLAB-internal multithreaded built-ins, Signal Processing MEX files) is not covered.
  - Observation (2026-10-06): the version string reports a CNR branch with and without MKL_CBWR; whether CNR mode is active is not established; synthetic A=B is first empirical evidence only.
  - Acceptance (§8) decides empirically.
- **At job start** (`stage3_job.m`):
  - `maxNumCompThreads(2)`;
  - `rng(SEED_GLOBAL, 'twister')` with **SEED_GLOBAL = 1**;
  - write the environment fingerprint, which must be identical across replicas (otherwise the comparison is invalid and the job counts as failed). It contains:
    - `version`, `version('-blas')`, `version('-lapack')`, `maxNumCompThreads`, `getenv('MKL_CBWR')`, `fftw('planner')`;
    - `which` for `eeglab`, `pop_loadbv`, `pop_resample`, `resample` and the job function;
    - SHA-256 of `path`, of `~/eeg_options.m` and of `runner_config.psd1`;
    - `isempty(gcp('nocreate'))` and `parallel.Settings().Pool.AutoCreate`.
  - **Asserted:** no parallel pool exists, `Pool.AutoCreate == false` (set by Amirhossein), and `option_parallel == 0`.
- **Inputs.** Raw files come only from the verified D: copy (S3a-D1-amend). Before use, each job checks the SHA-256 of every raw file it reads against `verified_manifest.tsv`. E: is not read.
- **Outputs.**
  - Replicas, state and journal go to `<eegOutRoot>/stage3_runs/<BatchId>/` on D:.
  - The final summary is also copied to `<outRoot>/stage3/runs/` on C:.
  - Nothing is written to E:.

### 2. Determinism audit (installed code, EEGLAB 2023.0) and seeds
- **Seeds (Q4).** SEED_GLOBAL = 1. Per-step seeds are fixed constants listed in `runner_config.psd1`. The step's constant is set (`rng(seed, 'twister')`) immediately before every step that draws random numbers.
  - Where a function reseeds internally, its internal seed governs that function. In the current code this applies to `clean_channels` (`rng('default')`), PICARD (5489), `runica` with `'reset_randomseed','no'` (`rand('state',0)`) and ICLabel (`rng('default')`). These internal seeds are recorded in `runner_config.psd1` as "internal".
  - Our constant then governs the code that follows the function. This matters especially after ICLabel's `rng('shuffle')`.

| Step / function | Source of nondeterminism | Handling |
|---|---|---|
| `pop_loadbv` (bva-io 1.75), `eeg_checkset` | none found (no RNG, no parfor) | none |
| `pop_resample` → Signal Processing `resample` (`option_donotusetoolboxes=0`) | internal multithreading of `resample`/`upfirdn`: not determined | fixed threads; empirical |
| D5-0: `detrend`, `E.' * x` (complex GEMM), `A \ Ld` | MKL BLAS/LAPACK; summation order may depend on thread count or code branch | threads = 2, `MKL_CBWR=AUTO`; empirical |
| firfilt (`pop_eegfiltnew`) | none found | none |
| CleanLine 2.1 (D5 option b) | `parfor` (`cleanLineNoise.m:57`); PCT is installed | assert no pool and `AutoCreate=false` |
| `clean_channels` (D6) | random channel subsets (`:179`, `rand` at `:190`); reseeded by `rng('default')` because `reset_rng` defaults to true (`:68`, `:113–114`) | deterministic; internal seed recorded |
| ASR calibration cache (D7) | `clean_asr.m:170–175` calls `hlp_diskcache` (a cache on disk, shared across processes) if that function exists; on 2026-10-06 `which('hlp_diskcache','-all')` after `eeglab('nogui')` returned nothing, so the direct branch with `maxmem` is used | assert in the fingerprint that `which('hlp_diskcache')` is empty |
| ASR (D7) | `asr_process.m:131–133` falls back to `hlp_memfree` (free RAM) when `maxmem` is too small, so chunking can depend on RAM; `asr_calibrate.m:120–121` likewise if `maxmem` is absent | pass an explicit `MaxMem`; assert the fallback branch is not taken. Riemannian variant: `rng(0)`, only if used |
| `runica` (D9) | `reset_randomseed` defaults to true → `rand('state', sum(100*clock))` (`runica.m:203`, `:800–804`): **nondeterministic** | pass `'reset_randomseed','no'` |
| PICARD 2.0 (D9) | fixed seed 5489; sets the global stream (`picard.m:275–276`) | deterministic; recorded |
| `pop_runica` | `parfor` (`:349`) only if `option_parallel = 1`; the home `eeg_options.m` has 0 | assert |
| ICLabel 1.6 (D10) | `eeg_rpsd.m:26–33`: `rng('default')`, `randperm`, then `rng('shuffle')`, which leaves the global RNG clock-seeded; `eeg_autocorr_welch.m:17–20` likewise if `pct_data ≠ 100` | reseed with the next step's constant before any later draw |
| ICA in general | iterative; floating-point differences can be amplified | A/B is the test |
| EEGLAB options and path | home `eeg_options.m` (`option_single=0`, `option_parallel=0`); other EEGLAB copies exist on disk (2023.1, 2024.2, a second 2023.0) | fingerprint (§1) |

### 3. Comparison (a separate fresh MATLAB process, `stage3_compare.m`)
- **Content only**, by `load` into variables, never on `.mat` bytes.
- For each numeric array: `isequaln`. If it is false, report the number of differing elements (NaN = NaN counts as equal; NaN vs a number counts as different) and the maximum absolute difference over finite pairs.
- **Fields compared for D5-0:** `res.label`, `res.avgP`, `res.exc`, `res.fpk`, `res.amp`, `nChunk`, `F`, `d`, `f0s` (all the variables in the file).
- **Fields compared for future Stage 3 `.set` files:**
  - `data`, `srate`, `nbchan`, `pnts`, `xmin`;
  - `chanlocs` (labels and X/Y/Z);
  - `event` (type, latency, duration);
  - `etc.restBlocks` / `etc.taskBlocks`;
  - the removed-channel list;
  - `icaweights`, `icasphere`, `icawinv`, `icachansind`;
  - the ICLabel classifications and the rejected-component list.
- **Fields excluded:** `history`, `filename`, `filepath`, `datfile`, `setname`, `comments`, `saved`, any time stamp in `etc`, and `icaact` (derived).
- A "different" verdict is recomputed once by a second compare process before C is started.

### 4. Mismatch rule
- **A = B:** the recording is **verified**. A is canonical, and its SHA-256 is recorded in the state file. **B is deleted at once** (space, S3a-D1-amend).
- **A ≠ B:** run C. If C equals A or B, the recording is **verified, flagged** (the matching pair is kept as canonical; the odd replica is deleted). Otherwise it is **quarantined**.
- **Stop the batch** when ≥ 2 recordings have had A ≠ B, **including those that C resolved (Q6)**, or when any kernel crash occurs after batch start (§7).

### 5. State, atomicity, resume
- **State file per recording** (`state/<rec>.json`). Status is one of `pending`, `running`, `A_done`, `B_done`, `C_done`, `verified`, `flagged`, `failed`, `quarantined`. The file also holds attempts per replica, PIDs, start/end times, exit codes, failure reasons, flags, and the canonical output's SHA-256 at verification.
- **Atomic writes.** The runner writes `*.tmp` and then calls `[IO.File]::Replace`. MATLAB writes `*.partial.mat` and moves it to the final name only after `save` returns.
- **Success** means exit code 0, the final-name file present, and a `DONE` marker line in the job log. A crash after saving still counts as a failed attempt, and its output is deleted.
- **Resume after an interruption.** Every `running` entry is reset: its partial and final files are deleted and the attempt counts as failed.
- **Resume after a kernel crash (Q9).** Each verified recording is checked:
  - its canonical output must still have the recorded SHA-256, and it must load;
  - otherwise the recording returns to `pending`.
- **Journal.** An append-only `journal.csv`, one line per job event, flushed after each line. A truncated last line after a crash is ignored.

### 6. Retry, timeout, thermal and disk gates
- **Retries:** up to 2 per replica after a crash, a non-zero exit, a timeout or a thermal abort (≤ 3 attempts). When they are exhausted, the recording is `failed`. Acceptance mode has no retries (§8).
- **Timeout:** 3 × the expected duration per recording type. The expected duration is the median replica time from acceptance: sub-06 MSIT+ × 11 for MSIT+, sub-06 rest × 3 for rest (§8).
- **Kill:** `taskkill /PID <pid> /T /F` on the process tree. Acceptance checks that the recorded PID belongs to the computing process.
- **Thermal**, read from the last row of the HWiNFO CSV (the file is opened with shared read):
  - **(i) Before each job:** a cool-down of COOLDOWN_S = **120 s**, then wait until CPU package ≤ GATE_C = **70 °C (final, 2026-10-06)** or until 10 min have passed (logged as `gate_timeout`).
  - **(ii) During a job:** if every sample in the last 30 s is ≥ 95 °C and those samples cover ≥ 28 s, the job is killed and logged as `thermal_abort`, counted as a failed attempt.
  - **(iii) Stale CSV** (last row older than 60 s):
    - a job that is running is allowed to finish, and its recording is flagged `thermal_unmonitored`;
    - no new job starts until the CSV is fresh again (logged; Q5).
  - The runner logs the start/end time, PID, exit code and attempt of every job, so the job log can be joined with the temperature log.
- **HWiNFO log format (runner requirement).** HWiNFO can add columns in the middle of a log.
  - **Header fingerprint:** at batch start, the runner records a fingerprint (SHA-256) of the full HWiNFO header line. It **stops the batch** if the header changes during the batch.
  - **Temperature column:** the **first occurrence** of `CPU Package [°C]`, which is the DTS group ("CPU [#0]: Intel Core i7-4720HQ: DTS", index 72 in the 2026-10-06 logs; the second occurrence, index 92, is the "Enhanced" group). The runner **stops** if that name does not occur exactly twice in the header. Lookup by name alone is not used.
  - **Field-count rule (kept):** any row whose field count differs from the header's is treated as stale (pause and log). After a mid-log insertion every later row is stale, so the runner stays paused until HWiNFO logging is restarted. Amirhossein disables non-essential sensors in HWiNFO logging.
  - Rows whose first field is not a date are ignored. HWiNFO writes the header line again, plus a sensor-group line, at the end of a log.
  - Verified in `test.CSV` (2026-10-06): the header has 295 fields; data rows 1–180 have 295 and rows 181–457 have 296. Comparing the header with the end-of-log header shows a single inserted column: `iGPU VID [V]` at index 294 (last column). Columns 0–293 are unchanged.
  - The DTS column reads up to 2 °C higher than the Enhanced column in these logs (max 84 vs 83 °C in step 2, 95 vs 93 °C in step 1).
- **Maximum processor state = 85 % (AC and DC)**, set by Amirhossein in the Windows power plan according to the ladder rule below.
- **Ladder rule** (stated in chat before the tests on 2026-10-06, not committed beforehand):
  - Steps of 99 → 85 → 70 % maximum processor state, 15 min each, with a fixed MATLAB load (2 threads, 2000×2000 matrix multiply).
  - A step passes if the maximum CPU Package (DTS) is ≤ 90 °C, the mean over the last 10 min of load is ≤ 85 °C, and no thermal-throttling flag is ever Yes.
  - Choose the highest passing step; if none passes, no heavy work.
  - Applied: step 1 fails (maximum 95.0 °C > 90 °C); step 2 passes all three conditions. 85 % is therefore the highest passing step, and step 3 (70 %) was not needed.
- **Thermal ladder** (2 threads, after the thermal-paste change S3a-HW-1). The values were recomputed from the HWiNFO logs (a scratch Python script in the session scratchpad, not in the repository; run twice with identical output) and agree with Amirhossein's reading. CPU Package = the DTS column.

  | Step | Max processor state | Log (2026-10-06) | Load period | Max CPU Package | Mean, last 10 min of load | Samples ≥ 90 °C | CPU limit-reason fields = Yes | Median package power | Median total CPU usage | Verdict |
  |---|---|---|---|---|---|---|---|---|---|---|
  | 1 | 99 % | `cputhermo.CSV`, 19:40:46–20:11:28 | not separated (usage ≥ 15 % spans 8.0–1827.2 s, with 378 rows below 15 % inside) | 95.0 °C (4 samples, first at 1006.5 s; the HWiNFO screenshot also shows 95 °C) | – | 52 | IA Limit Reasons: 1 row; GT Limit Reasons: 2 rows | – | – | FAIL |
  | 2 | 85 % | `test.CSV`, 20:13:03–20:28:18 | 2.0–906.7 s (Total CPU Usage ≥ 15 %; 1 row below inside) | 84.0 °C at 501.6 s | 78.337 °C (307.0–906.7 s, n = 300) | 0 | none | 18.207 W | 28.3 % | PASS |

  - The dGPU fields "GPU Performance Limiters" and "Performance Limit - Utilization" are Yes in every row of both logs. They belong to the NVIDIA GTX 950M, not the CPU.
  - **Log files.** The originals are on Amirhossein's Desktop. Copies, byte-identical to the originals, are in `<outRoot>/thermal_ladder/` (not in the repository):
    - `cputhermo.CSV` (step 1), 1,195,000 bytes, SHA-256 `14fc6be84f85d0d4ec3627338abb99adf9305de3a95ec5d58c2875f0a9a8a32f`;
    - `test.CSV` (step 2), 614,003 bytes, SHA-256 `9f6968e748d38758c779f8531d09fa53c89ee8c7a2f8edf2014681bc62ae9484`.
  - No column whose name contains "Throttling" was Yes in either log. The CPU limit-reason fields listed in the table are the only CPU-side Yes values.
- **Disk:** before each job, D: free space must be ≥ 15 GB + 3 × the largest replica output so far, and C: must have ≥ 5 GB free. Otherwise the batch pauses.

### 7. System events
- **After each batch, and on resume:** count, since batch start, the WHEA-Logger events (all IDs), BugCheck (WER-SystemErrorReporting 1001), Kernel-Power 41, and Application Error 1000 with `MATLAB.exe`. Per job, count Application Error 1000 within its time window.
- **Any Kernel-Power 41 or BugCheck 1001 after batch start:** the batch state becomes `STOPPED_KERNEL`, and resume refuses to continue. Amirhossein starts a new batch explicitly; verified recordings carry over under the Q9 rule (§5).

### 8. Acceptance mode (before any batch)
- **Runs:** sub-06 MSIT+ × 11, under the rules of §1–§6, **without retries**.
- **System state:** acceptance evaluates the system **after** the thermal-paste change (S3a-HW-1), at maximum processor state 85 %. All earlier crash data (S3a-D5-0-crash) predate that change.
- **Pass** requires all of the following:
  - all 11 replicas finish with exit code 0;
  - **0 MATLAB crashes**: no Application Error 1000 for `MATLAB.exe` in the acceptance window and no non-zero exit (Q7);
  - 0 timeouts and 0 thermal aborts;
  - 0 kernel crashes;
  - all 11 outputs content-identical, and all fingerprints identical.
- **Rationale (Q7)** (arithmetic, not data):
  - At the earlier crash rate of about 25% per run, allowing 2 crashes in 11 would pass with probability ≈ 0.455 even if nothing had changed.
  - With tolerance 0 that probability is 0.75¹¹ ≈ 0.042.
- **Timing calibration (not a pass criterion):** sub-06 rest × 3, same settings. The medians set the timeouts (§6). Any crash during calibration is still reported.
- **Fail with differing replicas:** nondeterminism and hardware corruption cannot be told apart, so no batch runs. The next step (for example `maxNumCompThreads(1)`) is logged before it runs.

### 9. Summary (written once, at batch end or stop)
- `summary.csv`, one row per recording, with:
  - final state, attempts per replica, crashes, thermal aborts and flags;
  - the comparison result (equal / number differing / max |diff| per field);
  - the maximum package temperature over its jobs.
- `summary.txt` header: batch id, start/end times, system-event counts, and the SHA-256 of `runner_config.psd1` and of this entry.
- Amirhossein reads only the summary. There is no polling during runs.

### 10. Files to create (implementation session; none exists yet)
- **Runner:**
  - `revision/infra/Invoke-Stage3Batch.ps1`: runner with Batch and Acceptance modes;
  - `revision/infra/runner_config.psd1`: all thresholds and seeds of this entry;
  - `revision/infra/stage3_job.m`, `stage3_env_fingerprint.m`, `stage3_compare.m`.
- **D5-0 in function form:**
  - `revision/stage3/stage3_d5_0_compute_one.m`: the per-recording computation of `stage3_d5_0_line_noise.m` (lines 52–106), unchanged arithmetic, with an explicit output path. The original script is not edited.
  - `revision/stage3/test_stage3_d5_0_compute_one.m`: **equivalence test on synthetic data only**. It is described below.
- **Implementation-session scope (E):**
  - `revision/infra/Test-ThermalLadder.ps1` (+ a MATLAB load function): a stepwise load test with temperature logging, for Amirhossein's revision of GATE_C;
  - `revision/infra/stage3_burnin.m`: a deterministic burn-in. The same synthetic workload runs in two separate processes, and the results are compared bitwise;
  - `revision/infra/Get-Stage3SystemEvents.ps1`: the §7 event counts.
- **The equivalence test (C):**
  - It writes synthetic BrainVision files (seeded random data, 127 channels with the real labels, one raw boundary, a synthetic `channels.tsv`) and a synthetic D4e block table to a temporary folder.
  - It runs the **unchanged** `stage3_d5_0_line_noise.m`, and also the pre-`-exc` reconstruction, from a temporary copy of the `revision/stage3` layout whose own `get_paths.m` points at the synthetic folders. It then runs `stage3_d5_0_compute_one.m` on the same files.
  - It is run under the identical configuration of §1, both in one process and across two processes.
  - **Pass:** `isequaln` on every variable of §3 (D5-0). Otherwise the function is not used.
- **Entry-hash locator:** fixed under S3a-D5-0-amend1 (`stage3_log_entry.m`, exact heading line; the D5-0 computation is unchanged).
  - Every entry hash that S3a-INF-1 records (§9) uses the same rule: exact header line, CR removed, text up to the next `\n## `.

## S3a-INF-1-clar1 · 2026-10-06 · Clarifications of S3a-INF-1 for the implementation (Amirhossein's answers, 2026-10-06)

- **Status:** decisions made in chat on 2026-10-06, before the implementation was run on any real data. S3a-INF-1 is unchanged; where this entry is more specific, it governs.
- **1. Burn-in workload** (S3a-INF-1 §10 named only "the same synthetic workload"). Each iteration runs one D5 block and one GEMM block:
  - **D5 block:** the D5-0 kernel on seeded synthetic data, as `d50_probe` 'synth': 8 groups × 97 chunks of 16 channels × 10 s at 500 Hz; per chunk, linear detrend, Hann window, DFT product `E.' * x`, one-sided PSD scaling and `linePeaks`.
  - **GEMM block:** a 2000 × 2000 matrix multiply (2 threads), the thermal-ladder load.
  - **Rationale:** the D5-0 kernel tests bitwise reproducibility of the exact MKL path of the batch; GEMM gives the heaviest sustained load, maximising the chance of exposing silent hardware errors.
  - **Comparison:** within each process, each block's result is compared bitwise with that block's iteration-1 result. Across the two processes, every iteration's result hash and the final results are compared bitwise. Mismatch counts are reported per block type and per comparison kind.
- **2. "Burn-in 60 min" = a fixed iteration count, about 60 min per process.**
  - The count is calibrated once with a short timed run (a few iterations of each block type) and then fixed so that one process takes about 60 min at 85 % maximum processor state.
  - The count and the calibration result are recorded in a note below this entry **before** the real burn-in runs.
  - A then B run sequentially, with the runner's cool-down and GATE_C gate between them.
- **3. Burn-in timeout:** 3 × (calibrated time per iteration × fixed count), about 180 min per process. A timeout fails acceptance, as for other jobs. The computed value is recorded with the count.
- **4. Acceptance timeout:** fixed 30 min per job during acceptance (hang detection only; a timeout still fails acceptance per §8). Reason: the 127 s probe ran with 4 threads at 99 %; with 2 threads at 85 %, runs may be roughly 2× or more slower, so 3 × 127 s = 381 s risks false timeouts. Every replica's wall time is recorded.
- **5. Batch timeouts via `timeouts.json`** (S3a-INF-1 §6: 3 × the acceptance median per recording type):
  - written only from an acceptance run whose verdict is PASS, and only from successfully completed replicas (MSIT+ from sub-06 × 11, rest from sub-06 rest × 3); it records the source summary paths and their SHA-256;
  - Batch mode refuses to start unless it finds a PASS acceptance summary and a `timeouts.json` derived from it (matching hashes), with an entry for every recording type in the batch. Both SHA-256 values go into the batch summary.
- **6. Disagreeing compares** (§3: a "different" verdict is recomputed by a second compare process). If the two compares disagree:
  - the recording is treated as different (sent to C) and flagged `compare_inconsistent` in state and summary;
  - it counts toward the ≥ 2 stop rule exactly like an A ≠ B mismatch (a deterministic compare giving two answers on the same files is itself evidence of a silent error);
  - in acceptance mode, any `compare_inconsistent` event fails acceptance.
- **7. Pre-checks at batch start** (stop if any is not met; all checks and results go into the batch summary header):
  1. acceptance: a sub-06 MSIT+ × 11 acceptance summary with verdict PASS, plus the burn-in (PASS) and the sub-06 rest × 3 results it covers;
  2. maximum processor state: AC and DC both 85 % (`powercfg`, read-only);
  3. raw copy: `verified_manifest.tsv` exists, `bidsRoot` points to the D: copy, and the post-reboot `verify` mode completed with all files matching (its report's SHA-256 is recorded);
  4. configuration match: the environment fingerprint and the relevant runner configuration fields (threads, `MKL_CBWR`, MATLAB/EEGLAB paths and versions, maximum processor state) are identical to those recorded in the passing acceptance;
  5. acceptance recency: the acceptance runs started after the S3a-HW-1 hardware change.
- **8. Scope of the implementation session:** S3a-INF-1 infrastructure and `stage3_d5_0_compute_one.m` only.
  - The D4e-4 label test (S3a-D4e-4-test) and a D5-0 assembly step (R1–R3 from the canonical A/B outputs) are deferred.
  - The runner's job interface stays generic (job type = a MATLAB function plus parameters, with an output-path contract, used for A/B/C and compare), so that both can later run under the same runner with A/B verification without changing the infrastructure.
- **9. Facts found during the implementation (2026-10-06):**
  - **Launch:** `bin\win64\MATLAB.exe -batch … -logfile …` launched directly runs in a single process (no child process), so the recorded PID is the computing process. The exit code is passed through, and `-logfile` captures the output.
  - **`parallel.Settings` `Pool.AutoCreate` was still 1 (true)** in a probe on 2026-10-06. The §1 assertion makes every real job fail until it is set to false.
  - **Power plan:** `powercfg` reports maximum processor state AC 85 %, DC 85 %.
- **10. Implementation choices (approved by Amirhossein, 2026-10-07), with his additions:**
  1. **Header change during a job:** the job runs to its end, flagged `thermal_unmonitored`, and the batch then stops (`STOPPED_HWINFO_HEADER`).
  2. **Failed compare process:** one retry; if it fails again, the recording is `failed`. **Addition:** a crashed compare counts as a MATLAB crash and fails acceptance.
  3. **Acceptance after a failure:** all replicas still run, to collect the full crash record. The verdict is unaffected.
  4. **The 10 min gate timer** counts only while the HWiNFO log is fresh.
  5. **`StepSeeds`** is empty; D5-0 and the burn-in reseed with SEED_GLOBAL. **Addition:** the runner refuses a job that declares a random step (`randomSteps`) without a seed in `StepSeeds`.
  6. **The `set` compare kind** is not bound. **Addition:** the runner refuses `.set` compares until their specification is logged.
  - Also: Acceptance and BurnIn modes exit with code 4 on a FAIL verdict, so that a chained command stops.
- **11. Burn-in balance (Amirhossein, 2026-10-07): not changed.**
  - The GEMM block takes about 4 % of the iteration time (0.370 of 8.250 s, below). So the burn-in does **not** achieve a sustained ladder-level load.
  - Acceptance (sub-06 MSIT+ × 11) remains the primary hardware test.
- **12. Burn-in calibration** (run 2026-10-07; synthetic only; recorded here before the real burn-in, per item 2):
  - **Run:** `Invoke-Stage3Batch.ps1 -Mode BurnIn -Calibrate -Iterations 3`, at maximum processor state AC/DC 85 % (`powercfg`).
    - It used the **test configuration** with a fake HWiNFO log, because HWiNFO was not running and `Pool.AutoCreate` was still true (which the real configuration asserts). It therefore measures time only.
    - The calibration batch lies in the session scratchpad and is not used by the runner.
  - **Per iteration:** D5 8.22, 7.93 and 7.49 s; GEMM 0.37, 0.39 and 0.35 s. Mean 8.250 s (D5 7.880 s, GEMM 0.370 s); 0 within-process mismatches.
  - **Fixed iteration count:** N = round(3600 / 8.250) = **436**, i.e. 3597 s expected per process.
  - **Burn-in timeout:** ⌈3 × 436 × 8.250⌉ = **10791 s** per process.
  - Both values are in `runner_config.psd1` (`BurnInIterations = 436`, `BurnInIterationSeconds = 8.25`). BurnIn mode then needs neither `-Iterations` nor `-CalibrationBatch`.

## S3a-INF-1-amend1 · 2026-10-09 · Hardware fault accepted: processing continues on this laptop under A/B verification; thermal monitoring and the burn-in prerequisite removed

- **Status:** decision by Amirhossein, 2026-10-09, before any acceptance run on real data. It amends S3a-INF-1 and S3a-INF-1-clar1; where they differ, this entry governs.
- **Evidence** (batch folders under `D:\Revision_EEG\stage3_runs\`; Windows Application log, Application Error 1000):

  | Burn-in replica | End | Wall time | Max CPU Package (DTS) | Exit code | Application Error 1000 (MATLAB.exe) |
  |---|---|---|---|---|---|
  | `burnin_4` A | crash | 546.4 s | 77 °C | −1073740940 (0xC0000374) | 2026-10-07T11:12:36, `ntdll.dll`, 0xc0000374 |
  | `burnin_4` B | crash | 3152.1 s | 83 °C | −1073740940 (0xC0000374) | 2026-10-07T12:07:08, `ntdll.dll`, 0xc0000374 |
  | `burnin_6` A | crash | 1567.4 s | 80 °C | −1073740940 (0xC0000374) | 2026-10-07T12:56:10, `ntdll.dll`, 0xc0000374 |
  | `burnin_6` B | **not a heap-corruption crash**: after iteration 396/436 (≈ 48 min) MATLAB stopped with `Error writing to output stream` in `fprintf` | – | not recorded | not recorded | none |

  - `burnin_4`: verdict FAIL, 0/2 replicas completed (`summary.txt` SHA-256 `df7e686778e3fcb0c19983ecabd34e8c98780b942853e514838abe463041ac5b`; `acceptance.json` `9c2cbb4f73453b81de5d0dc2b2d7fb936762e41866d7be68e7872598e47dc2ff`).
  - `burnin_6`: no summary was written. The batch is still `RUNNING` and replica B is still marked `running`, so the runner process ended while B was running; the runner's end is not recorded. The output-stream error fits a lost stdout pipe after the runner ended. This is an inference, not verified. (`journal.csv` SHA-256 `99c1552e01e0e2d56e4aba4d0d2cc84add975930e5b1c023f73c2063b5637d55`; B `job.log` `76b8e691ec3d70f88fb010a3b5bd3fc7610d43d090ea4a6192da762ab4f4c9e9`.)
  - **The files therefore show 3 heap-corruption crashes (0xC0000374) in 3 burn-in replicas that ended inside MATLAB.** Amirhossein's count of 4/4 includes `burnin_6` B, which the files do not show as a heap corruption.
  - Iterations printed before the end, with within-process mismatches (D5 and GEMM vs iteration 1):
    - `burnin_4` A: 75, all 0;
    - `burnin_4` B: 436 of 436, all 0, so the crash came after the last iteration;
    - `burnin_6` A: 207, all 0;
    - `burnin_6` B: 396, all 0.
  - Kernel crashes: Kernel-Power 41 at 2026-10-07T10:33:30, plus the four system crashes of S3a-D5-0-crash.
  - **Reported by Amirhossein, not in the files:** the crashes also occurred with the 8 GB memory module removed. No other machine is available.
- **Decision (Amirhossein).** Heavy jobs run on this laptop. Correctness rests on A/B(/C) content verification; MATLAB crashes are tolerated and counted.
  1. **Thermal monitoring removed:** HWiNFO log, temperature gate (GATE_C), thermal abort, staleness and header rules (S3a-INF-1 §6 (i)–(iii), "HWiNFO log format"; clar1 10.1, 10.4).
     - Reason: Amirhossein's judgment that temperature is ruled out as the cause. The crashes occurred at maxima of 77–83 °C, below the 95 °C abort level.
     - **Kept:** the fixed 120 s cool-down before every job, the disk gate, and maximum processor state 85 % (pre-check 2).
  2. **Burn-in dropped from the prerequisites** (clar1 items 5 and 7.1, and the burn-in part of 7.5). `Timeouts` mode and the pre-checks no longer require a burn-in. BurnIn mode remains available (one attempt per replica, verdict rule unchanged).
  3. **Attempts:** at most **5 per replica** (`MaxAttemptsPerReplica = 5`) in Batch and Acceptance modes. This replaces "up to 2 retries" (§6) and "without retries" (§8).
     - A failed compare process is retried up to 5 times per verdict. This replaces clar1 10.2: a compare crash no longer fails acceptance by itself.
  4. **Acceptance** (sub-06 MSIT+ × 11; replaces the §8 pass rule and its Q7 rationale). Crashes, timeouts and kernel crashes are tolerated and counted.
     - **PASS requires all of the following:**
       - (a) ≥ **9** of the 11 replicas completed (`AcceptanceMinCompleted = 9`);
       - (b) every completed replica content-identical to the reference replica (the first completed one), each confirmed by a successful compare;
       - (c) **0** `compare_inconsistent` events;
       - (d) identical environment fingerprints. Kept from §1/§8: a fingerprint mismatch means a different environment, not a crash.
     - **Reported:** attempts, crashed attempts (non-zero exit or no DONE marker), timeouts, Application Error 1000 count, kernel events, and the **crash rate per job-hour** = crashed attempts / total wall-clock hours of all attempts.
     - Rest × 3 stays a timing run (all replicas, up to 5 attempts each).
     - **Decision rule:**
       - PASS → `Timeouts` → D5-0 batch.
       - FAIL → the chain stops, and the next step is logged here before it runs. As in §8, differing replicas mean nondeterminism and corruption cannot be told apart.
  5. **Stop rules** (replace §4's "≥ 2 recordings with A ≠ B" and clar1 6's counting rule):
     - no stop for A ≠ B; C decides, and a resolved recording is `flagged`;
     - a `compare_inconsistent` compare is treated as different and flagged, with no stop;
     - the batch stops at **≥ 3 quarantined** recordings (`STOPPED_QUARANTINE`).
  6. **Kernel crash** (replaces §7 `STOPPED_KERNEL` and the new-batch carry-over of §5 Q9): resume with **the same command and BatchId**.
     - On resume, if Kernel-Power 41 + BugCheck 1001 since batch start has increased since the last check:
       - every `verified`/`flagged` recording's canonical output is re-hashed. If the file is missing or its SHA-256 differs from the value recorded at verification, the recording is reset;
       - every recording in `A_done`, `B_done` or `C_done` is reset;
       - `failed` and `quarantined` recordings are unchanged.
     - In Acceptance mode, each completed replica is re-hashed against the SHA-256 recorded at its completion. A mismatching replica is reset, and its compares are set aside (kept in the record; any `compare_inconsistent` among them still counts).
     - **Reset** means: outputs deleted, status `pending`, a fresh attempt budget, flag `reset_after_kernel_crash`.
     - A state file that cannot be read is moved aside, and its recording starts again.
     - The runner flushes every state file to disk before the atomic rename.
  7. **Chain:** `revision/infra/Invoke-Stage3Chain.ps1` runs acceptance MSIT+ × 11 → rest × 3 → `Timeouts` → D5-0 job list (84 recordings) → D5-0 batch, under fixed BatchIds (`acc_msit_1`, `acc_rest_1`, `d5_0_1`). The same command resumes it after any crash.
- **Unchanged:**
  - outcome-blindness;
  - the process configuration (§1);
  - the comparison fields (§3);
  - the A/B/C rule (§4, apart from its stop rule);
  - the timeout rule (3 × the acceptance median; clar1 4 and 5);
  - pre-checks 2–4, and pre-check 5 for MSIT+ and rest.

## S3a-INF-1-amend2 · 2026-10-10 · Timeouts for job types other than D5-0 (first users: D5-0 assembly, D4e-4 test)

- **Status:** implementation choice made under Amirhossein's session waiver of 2026-10-10 ("continue … unless a decision is genuinely mine"). It applies the **unchanged** timeout rule (3 × the median wall time of a timing run; S3a-INF-1 §6, clar1 items 4–5) to new job types. Amirhossein may revise it.
- **Problem.** `timeouts.json` holds `msit` and `rest` from the D5-0 acceptance and timing runs. New job types do different work, so those values do not apply to them.
- **Rule.**
  - Each new job type has recording types of its own: `d5_0_asm`, `d4e4_rest`, `d4e4_msit`.
  - Per type, a timing run: `Acceptance -TimingOnly`, 3 replicas, of one representative job (D4e-4: sub-06 rest and sub-06 MSIT+, as for D5-0; the assembly: its single job). As in acceptance, each replica has the fixed `AcceptanceTimeoutS` (30 min, hang detection only).
  - Mode `JobTimeouts` writes `<EegOutRoot>\stage3_runs\timeouts_<name>.json`: timeout = ⌈3 × median wall time of the successful replicas⌉ per type, with the source files and their SHA-256. It refuses a source that is not a 3-replica timing run with at least one successful replica, or that started before the S3a-HW-1 bound.
  - Batch mode `-JobTimeouts <file>` adds these types to the timeouts of `timeouts.json`. Pre-check 1 also verifies the source hashes of this file and counts its types as covered. **`timeouts.json` itself (behind `d5_0_1`) is not changed.**
  - Pre-checks 2–5 are unchanged; the MSIT+ acceptance (`acc_msit_1`) still certifies the environment.
- **Chain:** `revision/infra/Invoke-Stage3JobTypeChain.ps1` runs timing run(s) → `JobTimeouts` → Batch; the same command resumes it.
- The outputs of the timing replicas are not used.

## S3a-D5-0-asm · 2026-10-10 · D5-0 assembly as a runner job type (R1–R3 as committed)

- **Status:** implementation; no rule is changed. Rules applied exactly as committed: S3a-D5-0 (R1–R3), S3a-D5-0-amend1 (entry locator; the three hashes in `run_info.txt`), S3a-D5-0-exc (provisional `.vhdr` labels for sub-13/41/42), S3a-D5-opt (open point (i), decision (i-1): **R1 report-only**).
- **Inputs:** the canonical `out.mat` of each of the 84 recordings of batch `d5_0_1` only. Each file is checked against the SHA-256 recorded in its state file before it is loaded. The batch must be `DONE`, with every recording `verified`. The 78 files cached on 2026-10-04 (`<outRoot>/stage3/d5_0/per_recording/`) are not read.
- **Job function** `revision/stage3/stage3_d5_0_assemble.m`: the table and rule arithmetic is copied unchanged from `stage3_d5_0_line_noise.m`. Equivalence on synthetic data: `test_stage3_d5_0_assemble.m` (the unchanged script and the job function + export give byte-identical CSVs and equal R1–R3 values).
- **Run:** A/B in two processes (batch `d5asm_1`, compare kind `all`), timeouts per S3a-INF-1-amend2.
- **Outputs** (`<outRoot>/stage3/d5_0/`, written by `stage3_d5_0_export.m` from the verified canonical output; an existing file is never overwritten):
  - `line_noise_by_channel.csv`, `line_noise_by_recording.csv`, `run_info.txt` (as named in S3a-D5-0);
  - additionally `line_noise_rules_by_recording.csv`: per recording the R1 maxima and ≥ 3 dB counts per f₀, R2 severity S and rank, the R3 maximum offset, and the provisional-label flag (derived from the recording table only).
- `run_info.txt` records the SHA-256 of S3a-D5-0, S3a-D5-opt and S3a-INF-1 (amend1), and additionally of S3a-D5-0-amend1, S3a-D5-0-exc and this entry.
- **Reporting.** R1: report-only. R2: the full ranking; the step "if a worst recording belongs to a D14 test subject, the next one in rank is taken" is **pending**, because the D14 test subjects are not chosen. **These rules do not select the D5 option:** (b) stays provisional, pending its residual test (S3a-D5-opt); R3 matters only if (a) is used.
- Outcome-blind as S3a-D5-0: only the f₀ ± 3 Hz grid is read.

## S3a-D4e-4-test-approval · 2026-10-10 · S3a-D4e-4-test approved to run; band 1–10 Hz as committed; implementation

- **Approval (Amirhossein, 2026-10-10, in chat):** reading the binary `.eeg` files of the verified D: copy (`D:\Revision_Raw\ds004621`) for this test: test N, 6 recordings (sub-13, sub-41, sub-42; rest and MSIT+); test P, all 84 recordings. This covers the timing replicas of S3a-INF-1-amend2 (sub-06 rest and MSIT+, 3 each).
- **Band: 1–10 Hz, as committed.** Amirhossein's reasons: alpha is not covered by the outcome-blind rule (13–30 and 55–95 Hz), and keeping the committed band avoids reopening the pre-registration.
- S3a-D4e-4-test is not edited by this note. The S3a-D4e-4-issue stop stays until the test's rules are applied and logged.
- **Implementation (no rule changed):** job function `revision/stage3/stage3_d4e4_compute_one.m`, one job per recording (84), A/B, batch `d4e4_1`, compare kind `all`. It computes the statistics of tests P and N per recording. The decision rules (test N needs rest **and** MSIT+; test P's predictor-neighbour check) are applied by a later assembly step from the verified outputs, logged before it runs.
- **Details fixed by the implementation where the entry is silent:**
  - band-pass half-length: from the installed `pop_eegfiltnew` default design at 500 Hz, computed in the job and stored in each output;
  - eigenvalues of the covariance of the concatenated chunks (mean removed, symmetrised); a non-positive eigenvalue counts as deficient (−∞ dB);
  - the average-reference ratio is computed on the 125 channels as registered; the same ratio over all 127 channels is stored as an additional, descriptive value;
  - predictability: 1 − R² = 1 / (Σ_cc (Σ⁻¹)_cc); standardised weights W_cj = −(Σ⁻¹)_cj / (Σ⁻¹)_cc · σ_j / σ_c; the 6 largest |W| per channel and rcond(Σ) are stored;
  - test N: the Fisher-z diagonal is excluded, and the median over chunks is taken per pair. Neighbours are taken among the 125 recorded labels, by Euclidean distance in the digitised list (`<CapTrakElectrodeList>`) of the `.bvct`. k-nearest neighbours do not depend on the origin, orientation or unit of the coordinate frame, so the open frame/unit question of S3a-D2-reopen does not affect them;
  - test P's predictor-neighbour check and test N's 5th-percentile rule are evaluated in the assembly; positions for the subjects without a `.bvct` (sub-12, sub-23, sub-24) are decided there.
- **Synthetic test:** `revision/stage3/test_stage3_d4e4_compute_one.m` (spatially mixed synthetic sources; a swapped-label recording; an exactly interpolated channel).
- **Outputs:** per recording, the canonical `out.mat` in the batch folder. The CSVs named in S3a-D4e-4-test are written by the assembly.

## S3a-D5-0-amend2 · 2026-10-11 · linePeaks: guarded parabolic refinement (bug fix); D5-0 recomputed as d5_0_2

- **Decision:** Amirhossein, 2026-10-11.
- **How the bug was found.** In the D5-0 assembly `d5asm_1` (S3a-D5-0-asm), R3 reported impossible peak offsets: the maximum |peak − f₀| was 1426.7 Hz, although the grid spans only f₀ ± 3 Hz. 13878 of the 42000 kept-channel × f₀ rows had an offset > 0.55 Hz. A valid parabolic refinement can move the peak by at most half a grid step (0.05 Hz) from a bin within ± 0.5 Hz, so it cannot exceed 0.55 Hz.
- **Cause.** In `stage3_d5_0_linepeaks.m` (and in the local `linePeaks` of `stage3_d5_0_line_noise.m`), the peak bin is the maximum of the *excess* within ± 0.5 Hz. The refinement `delta = 0.5 (ym − yp) / den` uses the dB values of that bin and its neighbours. It was guarded only against `den == 0`. When the bin is not a local maximum of the dB values (e.g. at the edge of the ± 0.5 Hz window on a rising slope), `den` is ≥ 0 or near 0 and `delta` is unbounded.
- **Fix (standard guard).** The refinement is applied only if the parabola is concave (`den < 0`) and its vertex lies within half a grid step (`|delta| ≤ 0.5`); otherwise the grid peak is reported.
- **Affected:** the peak frequencies only, i.e. per-chunk `fpk` and the chunk-averaged `peak_freq_hz`, hence R3 and the drift descriptives (`freq_sd_det_hz`, `freq_range_det_hz`, `max_abs_offset_det_hz`).
- **Unaffected:** `excess_db` and the amplitude (they use the grid peak bin), hence R1, R2 and `amp_cv`.
- **Recompute.** The stored D5-0 outputs hold per-chunk excess, frequency and amplitude, and only the *chunk-averaged* spectrum (`avgP`). The per-chunk spectra needed to recompute per-chunk peaks are not stored, so D5-0 is recomputed as A/B batch `d5_0_2` (the same 84-job list and job function). It is followed by the assembly `d5asm_2` from `d5_0_2`, exported to `<outRoot>/stage3/d5_0_v2/`. The `d5asm_1` outputs in `<outRoot>/stage3/d5_0/` are kept unchanged.
- **Check when `d5_0_2` is done:** `res.exc`, `res.amp`, `res.avgP` and `nChunk` must equal those of `d5_0_1` for every recording, and R1/R2 must equal `d5asm_1`.
- **Not changed:** `stage3_d5_0_line_noise.m` (historical record of the 2026-10-04 run) and the burn-in outputs.
- **Tests (synthetic):** `test_stage3_d5_0_linepeaks.m` (the old function as reference); `test_stage3_d5_0_compute_one.m` and `test_stage3_d5_0_assemble.m` now exclude the peak frequency from the comparison with the unchanged script and check that it is bounded.

## S3a-D14-draw · 2026-10-11 · D14 test subjects: stratified seeded draw (rule fixed before the draw)

- **Decision:** Amirhossein, 2026-10-11, on Claude's proposal. D14 is defined in `revision_plan.md` (Stage 3a decision list) as difficult cases: "sub-25, an Fz-interpolated subject, a 'drift' subject 08/09/15; up to 3". The choice is made by a seeded draw within these categories, because the D5-0 R2 ranking had already been seen when the rule was set.
- **Source lists (fixed here, before the draw):**
  - **Fixed:** sub-25.
  - **Fz-interpolated in v1 (rest):** the subjects whose `interpolatedKeyChans` contains the token `Fz` in `<outRoot>/stage0/rest_markers_in_clean_sets.csv` (output of S0-2; SHA-256 `723035ec24cbca8a7383420f4629c6a2ea0f16a921326d4e31b6f527c650469f`), sub-25 excluded. These are 14 subjects (as in S0-2): sub-04, sub-05, sub-08, sub-10, sub-12, sub-13, sub-15, sub-19, sub-28, sub-29, sub-31, sub-32, sub-33, sub-41.
  - **Drift:** sub-08, sub-09, sub-15.
- **Procedure** (`revision/stage3/stage3_d14_draw.m`, committed with this entry before it runs; run once):
  1. `rng(1, 'twister')` (seed 1, set by Amirhossein);
  2. `pF = randperm(14)` over the Fz list in the order above; Fz subject = `list(pF(1))`;
  3. `pD = randperm(3)` over the drift list in the order above; drift subject = the first of `drift(pD)` that is not the Fz subject (sub-08 and sub-15 are in both lists).
  - The script checks the file hash and both lists, refuses to run if a result exists, and writes `<outRoot>/stage3/d14_draw/d14_draw_result.txt`.
- **Then the R2 replacement step (S3a-D5-0 R2):** the worst set is the 3 highest-ranked recordings by severity S (from `d5asm_1`; R2 uses `excess_db`, which S3a-D5-0-amend2 does not affect) whose subject is not a D14 subject.
- **(b) residual-test set (S3a-D5-opt):** the 3 D14 subjects × (rest, MSIT+), plus those 3 worst recordings. The script `revision/stage3/stage3_d5b_test_set.m` writes `<outRoot>/stage3/d5b/test_set.csv`.
- No EEG data are read.

## S3a-INF-1-amend2-appr · 2026-10-11 · S3a-INF-1-amend2 approved

- Amirhossein approved S3a-INF-1-amend2 (timeouts for job types other than D5-0) on 2026-10-11. The entry is unchanged (its hash is recorded in batches `d5asm_1` and `d4e4_1`).

## S3a-D4e-4-asm · 2026-10-11 · D4e-4 test: decision rules applied from the verified d4e4_1 outputs (A/B job)

- **Status:** implementation of the S3a-D4e-4-test rules. Requested by Amirhossein on 2026-10-11, with the instruction that no label is changed until he confirms. **The D4e-4 stop stays in force until then.**
- **Inputs:** the canonical `out.mat` of the 84 recordings of batch `d4e4_1` (84/84 verified), each hash-checked against its state file. For the predictor check, the subjects' `.bvct`, checked against the manifest.
- **Job function** `revision/stage3/stage3_d4e4_assemble.m`, export `stage3_d4e4_export.m`. Run as an A/B batch `d4e4asm_1` via `Invoke-Stage3JobTypeChain.ps1` (timing run, then batch; S3a-INF-1-amend2). Synthetic test: `test_stage3_d4e4_assemble.m`.
- **Gap in S3a-D4e-4-test, and how it is filled (flagged for Amirhossein).** The entry defines the reference as "s(U) for every unaffected label U (identical under both hypotheses)". The parenthesis holds only for unaffected labels none of whose k neighbours is affected: the score uses the neighbours' columns, which differ between the hypotheses. Two variants are therefore computed and reported:
  - **A (primary):** unaffected labels with no affected label among their k neighbours. For these, s_vhdr = s_tsv (asserted), as the entry states.
  - **B (sensitivity):** all unaffected labels, scored under each hypothesis separately, giving a percentile per hypothesis.
- **Further details** (the entry is silent on them):
  - 5th percentile = MATLAB `prctile(x, 5)` (default method).
  - H "meets the rule" in a recording if (i) and (ii) of the entry hold.
  - Per subject, H is supported if exactly H meets the rule in both rest and MSIT+, with the same pattern in both; otherwise ambiguous.
  - k = 6 is primary; k = 4 and 8 are sensitivity.
- **Test P predictor check:** for each near-perfectly predicted channel, the number of its 6 largest standardised weights whose labels are among the channel's 6 nearest labels (subject's `.bvct`, digitised list). For sub-12, sub-23 and sub-24 (no `.bvct`) the count is NaN: the position source for them is Amirhossein's decision, still pending. sub-13/41/42 are evaluated under both labellings.
- **Outputs** (`<outRoot>/stage3/d4e4_test/`; never overwritten):
  - `neighbour_scores.csv`, `rank_predictability_by_recording.csv`, `predictability_by_channel.csv` (as named in S3a-D4e-4-test);
  - `test_n_by_recording.csv`, `test_n_decisions.csv`, `near_perfect_predictors.csv`, `run_info.txt`.
- Outcome-blind: only the stored 1–10 Hz time-domain statistics are read.

## S3a-D14-draw-result · 2026-10-11 · D14 draw run once; R2 replacement step; (b) residual-test set

- **Draw** (`stage3_d14_draw.m` at commit `3cfdb46`, run once 2026-10-11 10:39; `<outRoot>/stage3/d14_draw/d14_draw_result.txt`):
  - `rng(1, 'twister')`; `randperm(14)` = [3 6 5 7 13 4 8 9 1 11 10 12 2 14] → Fz subject **sub-08**;
  - `randperm(3)` = [1 3 2] → order sub-08, sub-15, sub-09 → sub-08 is already chosen → drift subject **sub-15**.
  - **D14 test subjects: sub-25, sub-08, sub-15.**
- **R2 replacement step** (ranking of `d5asm_1`): rank 2 (sub-08 rest) belongs to a D14 subject and is skipped. **Worst set: sub-14 rest (rank 1), sub-22 rest (3), sub-06 rest (4).**
- **(b) residual-test set** (`<outRoot>/stage3/d5b/test_set.csv`, 9 recordings): sub-25, sub-08 and sub-15 (rest and MSIT+), plus sub-14 rest, sub-22 rest and sub-06 rest.

## S3a-INF-1-amend3 · 2026-10-11 · Per-replica timeout for timing runs of long job types

- **Status:** implementation choice under Amirhossein's session waiver of 2026-10-11 (stop only for decisions that are his). Flagged for his review.
- **Problem.** S3a-INF-1-amend2 times new job types with 3-replica timing runs under the fixed `AcceptanceTimeoutS` (30 min, hang detection). A synthetic benchmark of `cleanLineNoise` (S3a-D5-opt parameters, 2 threads) took 20.6 s per channel per 300 s of data. The (b) test recordings last 661–1365 s, so one recording takes about 1.8 h (rest) to 3.3 h (MSIT+) with 127 channels. Under the 30-min timeout, every timing replica would fail.
- **Change.** `Acceptance -TimingOnly` accepts `-ReplicaTimeoutS` (hang detection only; refused without `-TimingOnly`), stored in `batch.json`. `Invoke-Stage3JobTypeChain.ps1 -TimingTimeoutS` passes it on. For the (b) test: **43200 s (12 h)**, about 3.6 × the MSIT+ estimate.
- The batch timeouts still follow amend2 (3 × the timing median). `runner_config.psd1` is unchanged.

## S3a-D5b · 2026-10-11 · D5 option (b) residual test: implementation as an A/B job type

- **Requested by Amirhossein** (2026-10-11): implement the S3a-D5-opt residual test of (b) on the final test set (S3a-D14-draw-result), with R-b1 = 3 dB and R-b2 = 0.5 dB, as an A/B job type with a synthetic test first, and start it detached. This includes reading the `.eeg` files of the 9 test-set recordings from the verified D: copy.
- **Job function** `revision/stage3/stage3_d5b_compute_one.m`, one job per test-set recording (job-list type `d5b`, recording types `d5b_rest`/`d5b_msit`), compare kind `all`. Per 16-channel group:
  1. `pop_loadbv`, then the D4e block extents as events;
  2. high-pass 0.5 Hz at 1000 Hz (D4a), then `pop_resample` to 500 Hz (D4c order). The high-pass is included so that (b) sees the data as in the pipeline; its gain at ≥ 47 Hz is unity;
  3. **measure before**;
  4. `cleanLineNoise` (CleanLine 2.1) on each raw segment, with the S3a-D5-opt parameters (`lineFrequencies` [50 100 150 200], `p` 0.01, `fScanBandWidth` 2, `taperBandWidth` 2, `taperWindowSize` 4, `taperWindowStep` 1, `tau` 100, `pad` 2, `fPassBand` [0 250], `maximumIterations` 10);
  5. **measure after**.
- **Segment rule** (as committed): a segment shorter than one 4 s window is not processed and must not overlap a block (asserted; known case: the 0.192 s segment of sub-25 rest).
- **Measure:** exactly the D5-0 measure (10 s chunks inside the clipped blocks, detrend, Hann, DFT at f₀ ± 3 Hz, linear floor on the flanks, excess = maximum over ± 0.5 Hz; `stage3_d5_0_linepeaks` with the S3a-D5-0-amend2 guard, which does not affect excess).
- **Per recording, over kept channels (TP9/TP10 excluded) and every f₀:**
  - R-b1: chunk-averaged excess after (b) < 3 dB;
  - R-b2: |change in the dB of the mean chunk-averaged PSD over the flank bins| ≤ 0.5 dB;
  - also stored: per-chunk residual excess (median, maximum), excess before, and the flank levels.
- **(b) passes** only if every tested recording passes both R-b1 and R-b2 (S3a-D5-opt). The overall verdict is read from the 9 verified outputs after batch `d5b_1` ends, and the D5 decision is logged then.
- **Run:** queued after the D5-0 recompute (`Invoke-Stage3D5Queue.ps1`, serial). Timing runs on sub-25 rest and sub-25 MSIT+ (3 replicas each, 12-h per-replica timeout, S3a-INF-1-amend3), then `timeouts_d5b.json` and the A/B batch `d5b_1`. Expected total: about 2.5 days (A/B and timing replicas at roughly 1.8–3.3 h per run).
- **Synthetic test:** `revision/stage3/test_stage3_d5b_compute_one.m`.
- **Outcome-blind:** only the f₀ ± 3 Hz grid is computed. CleanLine's internal multitaper spectra and the cleaned data are neither saved nor inspected.

## S3a-D5b-amend1 · 2026-10-11 · (b) residual test split into short A/B units; amend3 withdrawn; queue stops before (b)

- **Decision:** Amirhossein, 2026-10-11. This laptop crashes under sustained multi-hour load (burn-in: heap corruption after 9–52 min, S3a-INF-1-amend1). Unchunked CleanLine jobs of 1.8–3.3 h would likely exhaust the 5 attempts per replica.
- **Units.** One test-set recording × one channel range, processed as one group by `stage3_d5b_compute_one` (`params.chans`): 6 channels per rest unit, 3 per MSIT+ unit. From the synthetic benchmark (S3a-INF-1-amend3) that is about 5 min each. The test set gives 261 units (9 recordings; 22 per rest recording, 43 per MSIT+ recording).
  - Each unit runs A/B and is verified (job-list type `d5bu`, recording types `d5bu_rest`/`d5bu_msit`).
  - Timing runs (S3a-INF-1-amend2) use normal replicas under the 30-min `AcceptanceTimeoutS`.
- **Merge** (`stage3_d5b_merge.m`, job-list type `d5bmerge`, an A/B job). From the verified units it rebuilds each recording's result:
  - the units must cover channels 1..N exactly once, with identical grid, segments, chunk positions and CleanLine parameters;
  - the rules are computed by the same function as the unsplit job (`stage3_d5b_rules.m`).
- **Equivalence test** (`test_stage3_d5b_chunked.m`, synthetic):
  - merged units must equal the unsplit job with the same group width exactly (`isequaln`);
  - the difference from the default 16-channel grouping is reported (pass ≤ 1e-6, because filters may round differently for different matrix widths);
  - a missing unit is refused.
- **S3a-INF-1-amend3 is withdrawn.** `-ReplicaTimeoutS` stays in the code (synthetic test T12) but is not used.
- **Queue** (`Invoke-Stage3D5Queue.ps1`): it now stops after `d5_0_2` → `d5asm_2` → export → `d5_0_1`/`d5_0_2` check. The unchunked (b) step is removed.
  - The running queue was stopped during a cool-down: killed 12:01:53, after `sub-03_msit` replica A ended at 12:00:32 (verified). The edited queue was restarted at 12:02.
  - The journal of `d5_0_2` shows `resume` at 12:02:09 and `sub-03_msit` replica B starting at 12:04:11, with A kept.
- **Driver:** `Invoke-Stage3D5bChunked.ps1 -Stage null` (S3a-D5b-null), then `-Stage real -Approved` (only after the R-b1 decision).
- **Cost (estimate):** per stage, 261 units × 2 replicas × ~5 min ≈ 44 h of computation, plus 522 cool-downs of 120 s ≈ 17 h. That is about 2.5 days for the null and 2.5 days for the real test. `CooldownS` is unchanged (any change is Amirhossein's decision).

## S3a-D5b-null · 2026-10-11 · R-b1 noise floor: null calibration by simulation; revised criterion proposed (decision pending)

- **Reason.** In the synthetic test of S3a-D5b, a noise-only recording (4 chunks) reached a maximum excess of 6.36 dB, and the line recording after (b) reached 4.60 dB. The committed R-b1 (maximum over all kept channels × f₀ < 3 dB) can therefore fail from the measure's own noise. The (b) test has 125 kept channels × 4 f₀ per recording and 9 recordings.
- **Null** (requested by Amirhossein; to run before any (b) output exists). Noise-only twins of the 9 test recordings (`stage3_d5b_null_make.m`):
  - the real `.vhdr`, `.vmrk` and `channels.tsv` are copied, so channel count, labels, duration, raw boundaries and the D4e blocks (the same block-table rows) are identical;
  - the `.eeg` is replaced by seeded white Gaussian noise of identical size (seed base 5000; the real `.eeg` bytes are not read);
  - the twins are cleaned and measured by the same chunked job (`d5bnullu_1`) and merged (`d5bnullm_1`);
  - `stage3_d5b_criterion.m` tabulates, per recording, the after-excess distribution over the 500 cells (maximum; 50th/90th/95th/99th percentiles; cells ≥ 3 dB).
- **Candidate criteria** (evaluated per recording; (b) passes only if every recording passes):
  - **C0** (committed): maximum < 3 dB.
  - **C1:** 95th percentile over cells < 3 dB.
  - **C2:** maximum ≤ the same recording's null maximum.
  - **C3:** 99th percentile ≤ the recording's null 99th percentile.
- **Claude's recommendation: C1, provided the null shows headroom.** It keeps the committed 3 dB convention and fails when more than 5 % of the cells keep a line residual ≥ 3 dB.
  - C1 is valid only if the null 95th percentile is clearly below 3 dB in every recording (proposed: ≤ 2 dB).
  - C2 and C3 compare against a single null realization: for perfectly cleaned data they fail with probability of about 0.5 per recording, so they are not recommended without many null realizations (cost × the number of realizations).
- **The decision is Amirhossein's.** It is made after the null table exists and before `-Stage real` runs (the driver refuses that stage without `-Approved`). The R-b2 criterion is unchanged.

## S3a-D4e-4-asm-amend1 · 2026-10-11 · D4e-4: references approved; .bvef positions for sub-12/23/24; all three subjects ambiguous; sub-28 to D6

- **Decisions (Amirhossein, 2026-10-11):** reference A (unaffected labels without affected neighbours) is primary and reference B is the sensitivity analysis. For sub-12, sub-23 and sub-24, positions come from the integer-rounded `.bvef` (S3a-D2-reopen). sub-28 goes to the D6 (bad-channel) review.
- **`.bvef` conversion** (`stage3_d4e4_assemble.m`, `readBvef`): BESA spherical convention, x = r sin θ cos φ, y = r sin θ sin φ, z = r cos θ, with the per-electrode radius. The sign variant (θ, φ) ≡ (−θ, φ + 180) maps to the same point. k-nearest neighbours do not depend on frame or unit. Each predictor-check row records its `position_source` (`bvct`/`bvef`). The assembly is to be re-run as `d4e4asm_2` and exported to `<outRoot>/stage3/d4e4_test_v2/` (the `d4e4asm_1` outputs are kept). Synthetic test: `test_stage3_d4e4_assemble.m` with a synthetic `.bvef`.
- **Outcome of `d4e4asm_1` (test N):** ambiguous for sub-13, sub-41 and sub-42 at k = 4, 6 and 8, under both references.
  - Under reference A, sub-42 has no reference labels: every unaffected label has an affected neighbour, so p5 is undefined.
- **What the committed rule prescribes** (S3a-D4e-4-test): if a result is ambiguous, "the affected channels are treated as unreliable for that subject (handling decided under D6/D11), and the stop stays until that decision". The affected channels are:
  - sub-13: FFT8h, FCC6h;
  - sub-41: FC5, FT9;
  - sub-42: the 35 labels at positions 93–127.
  - None of Fz, Cz or C4 is affected. **No label is changed until Amirhossein confirms.**
- **Test P, for the D6 review:** sub-28 (rest and MSIT+) has 10 deficient dimensions and 16 near-perfectly predicted channels. Their 6 largest predictors are not their spatial neighbours (0 of 6 for 15 channels, 1 of 6 for one), so this is not consistent with interpolation from neighbours. No recording was exported average-referenced.

## S3a-D5b-cooldown · 2026-10-12 · CooldownS = 30 s for all subsequent batches

- **Decision:** Amirhossein, 2026-10-12.
- **Change:** `CooldownS` in `revision/infra/runner_config.psd1` goes from 120 s to 30 s for every batch started after this entry; the first is `d4e4asm_2`. Earlier batches keep the configuration recorded in their fingerprints and summaries (runner config SHA-256).
- **Reason (Amirhossein):** the cool-down was introduced for thermal reasons (S3a-INF-1 §6). Temperature is ruled out as the cause of the crashes.
- **Monitoring kept:** the crash rate per job-hour stays reported in every batch summary (`Write-Stage3Summary.ps1`, S3a-INF-1-amend1).
- The cost estimate in S3a-D5b-amend1 assumed 120 s. It is not recomputed here.

## S3a-D5b-null-amend1 · 2026-10-12 · R-b1 null restricted to two twins (fewest chunks per task)

- **Decision:** Amirhossein, 2026-10-12. This amends S3a-D5b-null: the null uses two noise-only twins instead of nine.
- **Rule:** per task (rest, MSIT+), take the test-set recording with the fewest chunks: fewest chunks means the largest null fluctuation, i.e. the worst case. A tie is broken by the shorter duration; a remaining tie stops the run.
- **Wording clarified (Amirhossein, 2026-10-12, in chat).** The instruction said "the shortest rest and the shortest MSIT+ recording … (fewest chunks = largest null fluctuation = worst case)". For MSIT+, duration and chunk count disagree:
  - shortest MSIT+: sub-25 (1321.7 s, 96 chunks);
  - fewest chunks: sub-15 (1364.6 s, 93 chunks).
  - For rest they agree: sub-25 (660.7 s, 58 chunks).
  - Amirhossein chose the chunk count, hence sub-15 MSIT+. This was Claude's recommendation: it matches the stated rationale and is the more conservative choice for the validity condition of S3a-D5b-rb1.
- **Where these numbers come from:** they were read before this entry. Chunk counts are `n_chunks` in `<outRoot>/stage3/d5_0_v2/line_noise_by_channel.csv`. Durations come from the `.vhdr` and the `.eeg` file size of the verified D: copy; no `.eeg` bytes were read. The run recomputes them with `stage3_d5b_null_set.m` and writes `<outRoot>/stage3/d5b/null_set.csv`.
- **Expected twins:** sub-25 rest and sub-15 MSIT+, i.e. 22 + 43 = 65 units (S3a-D5b-amend1 unit sizes).
- **Implementation:**
  - `stage3_d5b_null_set.m` (new).
  - `Invoke-Stage3D5bChunked.ps1 -Stage null` builds the null set first. It then runs:
    1. the twins: `stage3_d5b_null_make` on the null set, with seeds 5001 and 5002 in null-set row order;
    2. the unit batch `d5bnullu_1` (job list built with `-TestSet null_set.csv`);
    3. the merge `d5bnullm_1`.
  - Synthetic test: `test_stage3_d5b_criterion.m`.
- **Not changed:** how the twins are built (S3a-D5b-null), the job function and the measure.

## S3a-D5b-rb1 · 2026-10-12 · R-b1 = C1, approved conditionally on the null

- **Decision:** Amirhossein, 2026-10-12. Made before any (b) output exists: neither `d5bnullu_1` nor `d5bu_1` has run.
- **R-b1 (replaces C0 of S3a-D5b).** Per recording, the 95th percentile of the post-cleaning excess over the 500 kept-channel × f₀ cells (125 × 4) must be < 3 dB.
  - The percentile is the one computed by `stage3_d5b_rules.m` (MATLAB `quantile(cells, 0.95)`).
  - The number of cells per recording is reported (`n_cells`).
- **Validity condition:** C1 is valid only if the null 95th percentile is ≤ 2 dB in **both** null twins (S3a-D5b-null-amend1).
  - If it holds, `-Stage real -Approved` starts automatically.
  - If it does not, the chain stops and writes the reason. R-b1 is then open again and returns to Amirhossein.
- **(b) passes** only if:
  - the null condition holds, **and**
  - every one of the 9 test recordings passes both C1 and R-b2. R-b2 is unchanged: |flank change| ≤ 0.5 dB in every kept channel and f₀.
- **Descriptives only (no decision):** per recording, the maximum excess and the number of cells > 3 dB.
- **Not used:** C0, C2 and C3. C2 and C3 would also need a null twin per recording, which S3a-D5b-null-amend1 no longer provides.
- **Implementation:**
  - `stage3_d5b_criterion.m` is rewritten; it had not run. It writes:
    - `null_criterion.csv`, with `null_q95_le_2db` and `null_c1_valid`;
    - `criterion_real_vs_null.csv`, with `C1_q95_lt3`, `rb2_pass`, `recording_pass`, `b_passes` and the descriptives.
  - Chain: `Invoke-Stage3D5bNullThenReal.ps1`, resumable with the same command.
    - Log: `<EegOutRoot>/stage3_runs/d5b_chain.log`. On a stop, the reason is also written to `<outRoot>/stage3/d5b/chain_stop_reason.txt`.
    - The chain re-checks the validity condition from `null_q95_db` and stops if that disagrees with `null_c1_valid`.

## S3a-D6-note-sub42 · 2026-10-12 · D6 note: sub-42, exclusion rather than interpolation

- **Note (Amirhossein, 2026-10-12), for the D6 review:** sub-42 has 35 affected channels, the labels at positions 93–127 (S3a-D4e-4-asm-amend1). That is about 28 % of its channels. At D6, consider excluding the subject rather than interpolating.
- This is not a decision; D6 decides.

## S3a-D4e-4-asm-v2-result · 2026-10-12 · d4e4asm_2 (with .bvef positions): sub-12/23/24 have nothing to check

- **Run:** `Invoke-Stage3JobTypeChain.ps1 -Type d4e4_asm -Name d4e4asm2 -TimingJobs d4e4_asm_d4e4_1 -SourceBatch d4e4_1 -BatchId d4e4asm_2`, 2026-10-12 02:39–02:46, with `CooldownS` = 30 s (S3a-D5b-cooldown). Status DONE. It was exported to `<outRoot>/stage3/d4e4_test_v2/` (canonical `out.mat` SHA-256 `661f5827…6586`, see `run_info.txt`). The `-TimingJobs` argument is mandatory; it is the same job id as in `d4e4asm_1`.
- **Predictor check for sub-12, sub-23 and sub-24:** `near_perfect_predictors.csv` has no rows for them. In `rank_predictability_by_recording.csv`, each of their 6 recordings has `n_deficient_lt_m60db` = 0. No channel of theirs is near-perfectly predicted, so the `.bvef` positions are never used on real data (they are exercised only by the synthetic test).
- **v1 vs v2:**
  - `neighbour_scores.csv`, `predictability_by_channel.csv`, `rank_predictability_by_recording.csv`, `test_n_by_recording.csv` and `test_n_decisions.csv` are byte-identical to `d4e4_test/`.
  - `near_perfect_predictors.csv` has the same 57 rows and differs only by the new `position_source` column, which is `bvct` in every row.
  - Test N stays ambiguous for sub-13, sub-41 and sub-42 (S3a-D4e-4-asm-amend1).

## S3a-D5b-result · 2026-10-13 · Option (b) REJECTED under the pre-registered rule; fallback (a) applies

- **Decision:** Amirhossein, 2026-10-13, applying S3a-D5b-rb1 as committed. No threshold is changed.
- **Chain:** `Invoke-Stage3D5bNullThenReal.ps1`, started 2026-10-12 02:55:08 and finished 2026-10-13 18:40:34 (`<EegOutRoot>/stage3_runs/d5b_chain.log`).
- **Null (validity condition met).** At 10:21:11 the chain logged that C1 is valid and started `-Stage real -Approved`.

  | twin | chunks | cells | q95 (dB) | max (dB) | cells > 3 dB |
  |---|---|---|---|---|---|
  | sub-15 MSIT+ | 93 | 500 | 0.520 | 0.927 | 0 |
  | sub-25 rest | 58 | 500 | 0.834 | 1.114 | 0 |

- **Real test:** 3 of 9 recordings pass C1 and 6 fail. sub-14 rest also fails R-b2. Hence `b_passes` = 0.

  | recording | role | chunks | q95 (dB) | C1 (< 3) | max \|flank change\| (dB) | R-b2 (≤ 0.5) | pass | max (dB) | cells > 3 dB |
  |---|---|---|---|---|---|---|---|---|---|
  | sub-06 rest | R2 worst | 60 | 3.427 | 0 | 0.165 | 1 | 0 | 6.900 | 40 |
  | sub-08 MSIT+ | D14 | 99 | 2.232 | 1 | 0.251 | 1 | 1 | 4.711 | 3 |
  | sub-08 rest | D14 | 60 | 3.239 | 0 | 0.224 | 1 | 0 | 4.182 | 41 |
  | sub-14 rest | R2 worst | 60 | 3.831 | 0 | 2.165 | 0 | 0 | 6.941 | 63 |
  | sub-15 MSIT+ | D14 | 93 | 3.918 | 0 | 0.042 | 1 | 0 | 7.849 | 43 |
  | sub-15 rest | D14 | 60 | 2.464 | 1 | 0.043 | 1 | 1 | 6.124 | 9 |
  | sub-22 rest | R2 worst | 59 | 3.337 | 0 | 0.342 | 1 | 0 | 4.232 | 44 |
  | sub-25 MSIT+ | D14 | 96 | 2.655 | 1 | 0.189 | 1 | 1 | 4.338 | 10 |
  | sub-25 rest | D14 | 58 | 3.922 | 0 | 0.187 | 1 | 0 | 6.637 | 67 |

  - Values are rounded to 3 decimals for display; the exact values are in the CSV.
  - Max and cells > 3 dB are descriptives only (S3a-D5b-rb1).
- **Consequence (S3a-D5-opt):** option (b) is rejected and fallback (a) applies. Before (a) is applied to all recordings, two checks run: S3a-D5a-R3 and S3a-D5a-test.
- **Files (SHA-256):**
  - `<outRoot>/stage3/d5b/test_set.csv` `cb07216a04d7620ce8174ad8f6c2eb088fbc14e59b0c28b2aaa44549cab9bcd2`
  - `<outRoot>/stage3/d5b/null_set.csv` `7c8f94c0dfe4792d5fc78b51413dfdfc4a73b9833b00f0c89af69d66b79236dd`
  - `<outRoot>/stage3/d5b/null_criterion.csv` `b8c044d54bff4bcf63aeceda84110a6bb98cfe041439323fa401954bcd0d1717`
  - `<outRoot>/stage3/d5b/criterion_real_vs_null.csv` `865bfd3a2a5d18600a6602e8e5e92b169050e5c2c0e72a19baac6efe59375f12`
  - merge `d5bnullm_1`, canonical `out.mat` `40520c7097b10349ae231392547adc57dae61112c1ff30effb3b8e41292dc270`
  - merge `d5bm_1`, canonical `out.mat` `9a01d098a963f03828c10ac8d185fedb81fb1bd0a501a1641dc840d96326ea3e`
- **Batches** (all DONE, every job verified):
  - `d5bnullu_1`: 65 units, 130 attempts, 0 crashes, 5.552 job-hours;
  - `d5bu_1`: 261 units, 535 attempts, 13 crashed, 26.057 job-hours, **0.499 crashes per job-hour**;
  - merges `d5bnullm_1` and `d5bm_1`: 2 attempts each, 0 crashes.

## S3a-D5a-R3 · 2026-10-13 · R3 re-examination for fallback (a): definition and decision rule (before computing)

- **Requested by Amirhossein (2026-10-13).** D5-0 R3 flagged "RE-EXAMINE notch width" (max |peak − f₀| = 0.550 Hz in `d5_0_v2`). That maximum includes chunks with excess ≥ 6 dB, where the peak estimate is dominated by noise.
- **Cell (definition by Amirhossein, 2026-10-13, in chat):** one 10 s chunk × kept channel × f₀ whose **own** chunk excess (`res.exc`) is ≥ 10 dB.
  - The cell's offset is |`res.fpk` − f₀|, the guarded per-chunk peak of S3a-D5-0-amend2.
  - Source: the canonical outputs of batch `d5_0_2` (84 recordings), each hash-checked against its state file. Kept channels exclude TP9/TP10, as in `stage3_d5_0_assemble`.
  - Rationale (Amirhossein): the notch must cover the instantaneous line frequency. Chunk-averaging hides drift; max-over-chunks includes weak (≥ 6 dB) chunks whose peak is noise-dominated.
- **Reported:**
  - per f₀, pooled: number of cells and of recordings, and the median, p95, p99 and maximum |offset|;
  - per recording × f₀: number of cells, median, p99 and maximum, so that a few recordings cannot dominate unnoticed;
  - **harmonic scaling (descriptive):** per recording × chunk, the median signed offset over the kept channels that qualify at both 50 Hz and k·50 Hz. For k = 2, 3, 4 the script gives the slope through the origin of offset(k·50) on offset(50), Pearson r, and the median ratio (where |offset(50)| ≥ 0.05 Hz). True mains drift predicts a slope of about k.
  - Percentiles use MATLAB `prctile` (default method).
- **Decision rule.** If the p99 of |offset| over the qualifying cells is ≤ 0.2 Hz at **every** f₀, the ±2 Hz notch of (a) is kept: within ±0.2 Hz, (a) attenuates by ≥ 33 dB (S3a-D5-opt, table A: −33.146 dB at 50 − 0.2 Hz, −33.041 dB at 100 − 0.2 Hz). Otherwise the work stops and is reported to Amirhossein.
- **Script:** `revision/stage3/stage3_d5a_r3_recheck.m`, writing to `<outRoot>/stage3/d5a_r3/` (`r3_pooled.csv`, `r3_by_recording.csv`, `r3_harmonic.csv`, `r3_decision.txt`; never overwritten). Synthetic test: `test_stage3_d5a_r3_recheck.m` (PASS). No EEG data is read.

## S3a-D5a-R3-result · 2026-10-13 · R3 re-examination: p99 > 0.2 Hz at 100 and 200 Hz → STOP, reported to Amirhossein

- **Run:** `stage3_d5a_r3_recheck.m` at commit `a9f2414`, on `d5_0_2` (84 recordings; batch.json SHA-256 `4f5a0a32…1831f`). Output: `<outRoot>/stage3/d5a_r3/`.
- **Pooled, per f₀** (cells = chunk × kept channel × f₀ with chunk excess ≥ 10 dB; |offset| in Hz):

  | f₀ | cells | recordings | median | p95 | p99 | max | p99 ≤ 0.2 |
  |---|---|---|---|---|---|---|---|
  | 50 | 744011 | 84 | 0.0136 | 0.0381 | 0.0593 | 0.5500 | 1 |
  | 100 | 347292 | 84 | 0.0283 | 0.2672 | 0.5000 | 0.5500 | 0 |
  | 150 | 704846 | 84 | 0.0359 | 0.1000 | 0.1585 | 0.5500 | 1 |
  | 200 | 221893 | 84 | 0.0601 | 0.4138 | 0.5164 | 0.5500 | 0 |

- **DECISION (rule of S3a-D5a-R3): STOP and report to Amirhossein.** The ±2 Hz notch is **not** confirmed. No further step that assumes it runs automatically.
- **Per recording** (`r3_by_recording.csv`):
  - Every recording has qualifying cells at every f₀ (minimum 4915 / 451 / 3634 / 456 cells at 50 / 100 / 150 / 200 Hz).
  - Recordings with p99 > 0.2 Hz: 7 at 50 Hz, 69 at 100 Hz, 27 at 150 Hz and 84 at 200 Hz.
  - Median per-recording p99: 0.050, 0.499, 0.122 and 0.519 Hz.
  - So the failure at 100 and 200 Hz is not driven by a few recordings.
- **Harmonic scaling** (descriptive, `r3_harmonic.csv`; per recording × chunk, median signed offset over channels qualifying at both f₀):

  | k | recording-chunks | slope through origin | Pearson r | median ratio (n) |
  |---|---|---|---|---|
  | 2 (100 Hz) | 6528 | 0.681 | 0.100 | 1.725 (36) |
  | 3 (150 Hz) | 6592 | 2.741 | 0.959 | 2.974 (15) |
  | 4 (200 Hz) | 6509 | 1.825 | 0.204 | 2.604 (37) |

  - At 150 Hz the offsets track 3 × the 50 Hz offset, as true mains drift predicts.
  - At 100 and 200 Hz they do not (r = 0.10 and 0.20).
  - The pooled p99 at 100 Hz is exactly 0.5000 Hz, i.e. a grid point at the edge of the ±0.5 Hz peak window (where the S3a-D5-0-amend2 guard reports the grid peak).
  - **Not interpreted here** (flagged): whether the even-harmonic offsets reflect real line-frequency excursions, a broad or split line, or peak picking at the window edge is open. It is Amirhossein's question.
- **Files (SHA-256):**
  - `r3_pooled.csv` `ccb58c1ca6087732fd49bfebe057a06a3db208b3f1a0204d323fe4db1d1f9943`
  - `r3_by_recording.csv` `87bd2410594978ae708c7527e1236cc5b7007365cde060f94d0bda49a422d033`
  - `r3_harmonic.csv` `205403527ed645774d9eb2ddd3eafd06ed4f6aee19db0baf6ea00e1a023161cc`
  - `r3_decision.txt` `704721abaff1bfe95a1ce5004d6c3e4121a968cb7b9ba7f795ca32dfba46d0f9`

## S3a-D5a-H · 2026-10-13 · Data cost of (a) under D4e from the pipeline code (definition, before computing)

- **Requested by Amirhossein (2026-10-13):** verify, from the actual pipeline code, how many stimuli H = 6.637 s loses. The figure of 2026-10-04 (35 stimuli; 32 blocks clipped; 16 block-first; 17 subjects) came from a hand-edited `filter_halflengths.csv` and is unverified (S3a-D5-opt).
- **Procedure:**
  1. `stage3_filter_halflengths(S, lineNoise)`: new optional argument. `'none'` is the default, and the output is unchanged for existing callers. `'a'` adds the four band-stop kernels of option (a), designed by `pop_eegfiltnew` at `S.fsOut` exactly as in S3a-D5-opt, one row each.
  2. `stage3_compute_H_d5a.m` writes `<outRoot>/stage3/d5a_d4e/filter_halflengths.csv` (refuses to overwrite).
  3. The committed survey `stage3_raw_boundaries_d4e.py` runs unchanged with `out_dir = <outRoot>/stage3/d5a_d4e`. It reads only `.vhdr`, `.vmrk` and `*_events.tsv` text files from the verified D: copy.
- **Expected H** = 3.333 + 4 × 0.826 = 6.637 s if the installed design matches S3a-D5-opt. Whatever the code returns is used and reported.
- **Reported:** H; blocks and blocks clipped; stimuli outside their clipped block (total, block-first, number of subjects); checks; and the minimum number of kept pre-stimulus trials per condition. The D4e outputs in `<outRoot>/stage3/` (H = 3.333 s) are not touched.
- **This is a verification, not a decision.** The S3a-D5a-R3 stop stands: (a) is not adopted, and the notch width is open.

## S3a-D5a-H-result · 2026-10-13 · H = 6.637 s from the code; 35 stimuli lost (verified)

- **Run:** commit `24f9843`. `stage3_compute_H_d5a.m` (MATLAB R2022b, installed EEGLAB/firfilt), then `python -I stage3_raw_boundaries_d4e.py D:\Revision_Raw\ds004621 <outRoot>/stage3/d5a_d4e`.
- **H from the code:** high-pass 3.300 s + anti-aliasing 0.033 s + 4 band-stop filters × 0.826 s (order 826 each, designed at 500 Hz) = **6.637 s** (6637 raw samples). This matches S3a-D5-opt.
- **Data cost** (`d4e_lost_stimuli.csv`, `d4e_block_clipping.csv` in `d5a_d4e/`), against the current D4e outputs without D5 (H = 3.333 s):

  | | H = 3.333 s (current) | H = 6.637 s (with (a)) |
  |---|---|---|
  | blocks (of 588) clipped | 13 | 32 |
  | stimuli outside their clipped block | 4 | **35** |
  | of which block-first | 1 | 16 |
  | of which first-in-mini-block | 1 | 18 |
  | subjects affected | 3 | 17 |

  - **The 2026-10-04 figure (35 stimuli; 16 block-first; 17 subjects; 32 blocks) is now verified from the code.**
  - No block has a STOP status (`unchanged` 556, `CLIPPED` 32). The survey reports the same 3 D3e-3 discards (sub-07, sub-24, sub-37 MSIT+) as checks.
  - Minimum kept pre-stimulus trials per condition (not block-first; over 42 subjects): F0 66, FS 79, 00 79, S0 68. First-in-mini-block: F0 17, FS 20, 00 22, S0 17.
- **Files (SHA-256):**
  - `filter_halflengths.csv` `1a925122f4161e44df894c6b60e71b8d1cea3c8f5f1d9febe18e76202ed6a541`
  - `d4e_block_clipping.csv` `6524101f72c8c4058abcacfbbdee337b2e70ec8b8f39b336e817e446d795eec4`
  - `d4e_lost_stimuli.csv` `f972e44754044d11cb2c67ee100111ccd48aa23ba0c0822e61d39c497a677034`
  - `d4e_trials_by_condition.csv` `eb4b126f6cd165fef2975335632b5238cfbb5cba6761e478903e8deece31bdf8`
  - `raw_boundaries.csv` `203f8391d87d5d2a34ba7330b79f087fd2f811e42fa5ea02f8c1d48591051e1b`

## S3a-D5a-test · 2026-10-13 · Residual test of fallback (a): definition and rule (implemented, NOT started: S3a-D5a-R3 stop)

- **Requested by Amirhossein (2026-10-13).** The residual test of (a) on the 9 test-set recordings (S3a-D14-draw-result), with the C1 definition of S3a-D5b-rb1 and the R-b2 definition of S3a-D5-opt, as an A/B job type in short units.
- **Status: not started.** S3a-D5a-R3 ended in STOP (p99 > 0.2 Hz at 100 and 200 Hz). This test applies the ±2 Hz notch, which R3 did not confirm. It starts only on Amirhossein's word: `Invoke-Stage3D5aTest.ps1`, batch `d5a_1`.
- **Job** (`stage3_d5a_compute_one.m`, job-list type `d5a`, recording types `d5a_rest`/`d5a_msit`, compare kind `all`):
  - The same pipeline steps and measure as the (b) job: `pop_loadbv`, D4e blocks, high-pass 0.5 Hz, `pop_resample` to 500 Hz, measure before, **(a)**, measure after.
  - (a) is the four `pop_eegfiltnew` band-stop filters f₀ ± 2 Hz, `revfilt` 1, in cascade at 500 Hz (S3a-D5-opt). firfilt filters each raw segment separately.
  - Rules come from `stage3_d5b_rules.m`, identical to (b).
- **Unit size.** One job per whole recording (16-channel groups inside the job), so 9 jobs. Reasons:
  - FIR filtering is fast. A D5-0 job (load, high-pass, resample and measure of a whole recording) took about 107 s on average in `d5_0_2`, cool-downs excluded. (a) adds four FIR passes at 500 Hz.
  - The timing runs measure the real duration: sub-15 MSIT+ and sub-14 rest, the longest test recording per task, 3 replicas each, under the 30-min `AcceptanceTimeoutS`. If a unit is too long, the chain stops at the timing step and nothing is half-done.
  - No merge step is needed.
- **Blocks (a choice made here, flagged).** The blocks come from `<outRoot>/stage3/d5a_d4e/d4e_block_clipping.csv`, i.e. H = 6.637 s with the notches (S3a-D5a-H), not from the current H = 3.333 s table.
  - Reason: with H = 3.333 s, chunks near a segment edge could contain notch edge effects (3.304 s) that the pipeline would clip under (a).
  - The (b) test used the H = 3.333 s blocks, so chunk positions differ slightly between (a) and (b) in clipped blocks.
- **R-b2 vs the notch transition band.** The flank band (1.5 ≤ |f − f₀| ≤ 3 Hz) overlaps the transition band of every (a) kernel (0 ≤ |f − f₀| ≤ 1.998 Hz; order 826, Hamming).
  - The job computes this from the kernels actually applied (`res.notch.flankInTransition`).
  - In the synthetic test the cascade gain over the flank bins is −1.151 to +0.018 dB.
  - **As instructed, R-b2 is then not evaluated; the test uses C1 only.** R-b2 values are still reported descriptively.
- **Per recording:** C1 = 95th percentile of the after-excess over the kept-channel × f₀ cells < 3 dB. `recording_pass` = C1, plus R-b2 only where the flank band is not in a transition band.
- **Decision rule:**
  - (a) passes on all 9 recordings → adopt (a) for all recordings.
  - Otherwise → stop and report to Amirhossein. No further automatic step.
- **Descriptive:** maximum excess, cells > 3 dB, q99, maximum |flank change|, flank gain range, and per recording the (b) q95 (from `d5bm_1`) and (a) − (b).
- **Caveat for interpretation (flagged, no rule changed).** The notch also attenuates the noise inside ±0.5 Hz, while the flank floor (1.5–3 Hz) is nearly untouched. So after (a) the excess of noise alone is strongly negative: in the synthetic noise-only recording, q95 after (a) = −13.64 dB (under (b) the noise baseline stays near 0 dB, S3a-D5b-null). C1 < 3 dB under (a) therefore tolerates a residual about 16 dB above the local noise. It is less strict than the same 3 dB under (b), and the (a) vs (b) q95 comparison is not like-for-like.
- **Outputs:** `<outRoot>/stage3/d5a/criterion_a.csv` and `criterion_a_decision.txt` (`stage3_d5a_criterion.m`, never overwritten). Driver log: `<EegOutRoot>/stage3_runs/d5a_test.log`.
- **Synthetic test:** `test_stage3_d5a_compute_one.m` (PASS). It checks lines removed (q95 < 3 dB), 4 kernels of order 826, gain ≤ −40 dB at every f₀, flank in transition, two runs identical, the criterion (C1 only, (a) − (b), decision text) and no overwrite.

## S3a-D5a-diag · 2026-10-13 · Diagnostics before choosing the notch width (descriptive, no decision)

- **Requested by Amirhossein (2026-10-13), after accepting the S3a-D5a-R3 stop.** His observation: 50 and 150 Hz behave like mains drift; 100 and 200 Hz do not, and their p99 sits at the ±0.5 Hz window edge. Even harmonics cannot drift independently of the fundamental, so the R3 measure may be mis-specified there. **No decision is taken from these diagnostics.** All frequencies involved lie outside 13–30 and 55–95 Hz.
- **(a) Line spectra** (`stage3_d5a_diag.m`, from the verified `d5_0_2` outputs, hash-checked; finest resolution available: chunk-averaged PSD `res.avgP` on the 0.1 Hz grid, f₀ ± 3 Hz, 10 s Hann windows, so the true resolution is the Hann mainlobe, not 0.1 Hz):
  - Per kept channel and f₀, the spectrum in dB relative to that channel's mean flank level (mean PSD over 1.5 ≤ |f − f₀| ≤ 3 Hz).
  - Per recording: the median over kept channels.
  - Across the 84 recordings, per bin: the mean (grand average) and the 10/25/50/75/90th percentiles (`prctile`). One figure per f₀.
  - Table per f₀, from the grand-average and median spectra:
    - main peak: grid bin and parabolic vertex;
    - −3 dB width: contiguous bins ≥ peak − 3 dB, linear interpolation at the crossings;
    - second peaks: any other local maximum ≥ 3 dB above the flank level and ≥ 3 dB prominent.
  - Per recording: the main-peak offset, the number of recordings with |peak offset| > 0.5 Hz, and those with a second peak.
- **(b) The (b) failure by f₀:** from the verified `d5bm_1` merge, per recording × f₀, the number of kept-channel cells with after-excess ≥ 3 dB (of 125).
- **(c) Notch width of (a), from the actual kernels:** `pop_eegfiltnew(locutoff f₀ − a, hicutoff f₀ + a, revfilt 1)` at 500 Hz, with a = 2, 3, 4, 5, 6 Hz.
  - Under the default design the transition width stays 2 Hz for 2 ≤ a ≤ 8 (`pop_eegfiltnew.m`: df = min(max(a/4, 2), a)). Its value is reported from each kernel's order.
  - So a = 2, 3, 4 are the nominal "±a Hz" settings (the current one is a = 2), and a = 4, 5, 6 give a stop band of half-width a − 2 = 2, 3, 4 Hz. Amirhossein's "stop-band half-width 2, 3, 4 Hz" is covered under either reading.
  - Per a and f₀: order, transition width, the cascade gain at f₀ + {0, 0.2, 0.5, 1, 1.5, 2, 3, 4} Hz, the half-widths with ≥ 33 dB and ≥ 20 dB attenuation and the −6 dB half-width (0.001 Hz grid), and the largest |gain| in 13–30 and 55–95 Hz (filter response only, no data).
  - H = high-pass + anti-aliasing + 4 notch half-lengths (`stage3_filter_halflengths(S, 'a', a)`). The stimulus loss comes from the unchanged D4e survey, run once per a into `<outRoot>/stage3/d5a_diag/notch_a<a>/`.
- **Outputs:** `<outRoot>/stage3/d5a_diag/` (never overwritten).

## S3a-D5a-diag-result · 2026-10-13 · Diagnostics: lines centred on f₀; 100/200 Hz weak; wider notch costs no H

- **Run:** commit `2aaa79e` (`stage3_d5a_diag.m` on `d5_0_2` and `d5bm_1`; then the D4e survey per a; then `stage3_d5a_diag_loss.m`). Output: `<outRoot>/stage3/d5a_diag/`. Descriptive; no decision.
- **(a) Line spectra** (`line_peaks.csv`; figures `spectrum_f0_<f0>.png`; dB re the mean flank level). Grand-average spectrum:

  | f₀ | peak offset (vertex, Hz) | peak (dB) | −3 dB width (Hz) | second peaks |
  |---|---|---|---|---|
  | 50 | −0.0004 | 19.41 | 0.109 | none |
  | 100 | −0.0004 | 5.70 | 0.246 | none |
  | 150 | −0.0012 | 16.04 | 0.153 | none |
  | 200 | −0.0040 | 2.53 | undefined (peak − 3 dB lies below the flank level) | none |

  - The median spectrum agrees: offsets ≤ 0.004 Hz and no second peaks.
  - **Per recording** (`line_peaks_by_recording_summary.csv`):
    - |peak offset| > 0.5 Hz in 0 / 24 / 0 / 30 recordings at 50 / 100 / 150 / 200 Hz;
    - −3 dB width undefined in 0 / 37 / 0 / 48 recordings;
    - a second peak in 0 / 1 / 1 / 0 recordings (sub-08 rest, −1.5 Hz at 100 Hz; sub-41 MSIT+, +1.5 Hz at 150 Hz).
  - The lines at 100 and 200 Hz are weak. Where a recording's line is near the flank level, its spectral maximum within ±3 Hz falls anywhere. (Fact stated; the link to R3 is Amirhossein's call.)
- **(b) Where (b) failed** (`d5b_fail_cells.csv`; kept cells with after-excess ≥ 3 dB, of 1125 per f₀ over 9 recordings): 30 at 50 Hz, 109 at 100 Hz, 84 at 150 Hz, 97 at 200 Hz (320 in all). Per recording:
  - sub-06 rest 4/15/11/10; sub-08 MSIT+ 3/0/0/0; sub-08 rest 1/16/2/22;
  - sub-14 rest 7/10/31/15; sub-15 MSIT+ 1/6/28/8; sub-15 rest 2/2/0/5;
  - sub-22 rest 5/32/1/6; sub-25 MSIT+ 2/5/0/3; sub-25 rest 5/23/11/28.
  - So the failure is spread over 100, 150 and 200 Hz, not only the even harmonics.
- **(c) Notch width** (`notch_profiles.csv`, `notch_profile_f0_100.png`, `notch_loss.csv`). Band edges f₀ ± a Hz, default design:
  - Every kernel has order 826 and transition width 1.998 Hz, so **H = 6.637 s for every a**. Every a also gives the same D4e cost: 32 blocks clipped, 35 stimuli lost (16 block-first, 18 first-in-mini-block), 17 subjects, no STOP.
  - Half-width with ≥ 33 dB attenuation (all f₀ within 0.006 Hz):

    | a (Hz) | ≥ 33 dB | ≥ 20 dB | −6 dB |
    |---|---|---|---|
    | 2 | 0.20 | 0.45 | 1.00 |
    | 3 | 1.19 | 1.45 | 2.00 |
    | 4 | 2.19 | 2.45 | 3.00 |
    | 5 | 3.19 | 3.45 | 4.00 |
    | 6 | 4.19 | 4.45 | 5.00 |

  - Largest |gain| of the cascade in 55–95 Hz: 0.015 / 0.015 / 0.007 / 0.027 / **6.04 dB** for a = 2…6. In 13–30 Hz it is ≤ 0.006 dB for every a.
  - **a = 6 is excluded by outcome-blindness / control-band integrity:** the 50 Hz notch's passband edge reaches 56 Hz.
- **Files (SHA-256):**
  - `line_peaks.csv` `f8b0d5780a1fd82fe19649a2259f3d19eb5e4eae5f1be93f30fb76d1ef8e3f19`
  - `line_peaks_by_recording.csv` `8aa657faca71aaf8cf821761bf4296430b6d3b2cdd30eb044ae3a52b8ed5b5d8`
  - `line_peaks_by_recording_summary.csv` `fd548cc91505cd2470e75667c99f98ff6f88ca5cdfdbe81aacd03c3e429e9fd8`
  - `d5b_fail_cells.csv` `e6fc9df49357050e25d57dd79b163d86b06f77d0c7cce96db22bee2ac170ec22`
  - `notch_profiles.csv` `0ad8d6aa3c6a960bf3710515002dac084002062cb66c146405c19bc3288b126f`
  - `notch_loss.csv` `7099037d659e97963dd21379d54aacd2f5957a8e44b7599f0b190cf3840de945`

## S3a-D5a-test-amend1 · 2026-10-13 · (a) test: H-specific blocks approved; criterion relative to an (a) null; start after the width choice

- **Decisions (Amirhossein, 2026-10-13), recorded before any (a) run:**
  - **Blocks** come from the H-specific D4e table, as proposed in S3a-D5a-test. For a = 2…5, H = 6.637 s (S3a-D5a-diag-result), so `<outRoot>/stage3/d5a_d4e/d4e_block_clipping.csv` applies to every admissible width.
  - **Criterion (replaces the absolute C1 for (a), which has not run).** A recording passes if real q95 − null q95 < 3 dB.
    - The null is computed by running (a), with the chosen width, on the two noise twins of S3a-D5b-null-amend1 (`<EegOutRoot>/d5b_null`: sub-25 rest, sub-15 MSIT+). This is cheap.
    - The reason: under (a) the absolute C1 is lenient, since the null excess is about −13.6 dB.
  - **R-b2 is not evaluated for (a):** the flank band lies inside the notch transition band.
  - **Do not start the (a) test until Amirhossein has chosen the notch width** after S3a-D5a-diag.
- **Operationalization (Claude; flagged for Amirhossein).** Each real recording is compared with the null twin of the **same task**: rest recordings with sub-25 rest, MSIT+ recordings with sub-15 MSIT+. There is one twin per task (S3a-D5b-null-amend1).
- **Implementation pending:** the width parameter of `stage3_d5a_compute_one`, the null batch on the twins, and the relative criterion in `stage3_d5a_criterion`. These will be committed together with the width decision, before any (a) run. `Invoke-Stage3D5aTest.ps1` must not be run until then.
