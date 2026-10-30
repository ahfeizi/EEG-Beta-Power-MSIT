# Pre-Registration: Resting-State Beta-Peak Detection Criterion (Stage 4)

**Project:** EEG beta-power study, Nencki-Symfonia MSIT+ dataset (OpenNeuro ds004621 / GigaDB DOI 10.5524/100990)
**Author:** Amirhossein Feizi (ORCID 0000-0001-8929-0910); Supervisor: Prof. Ali Motie Nasrabadi (ORCID 0000-0002-3702-8547)
**Status:** DRAFT — to be committed, tagged, and deposited to Zenodo for DOI assignment *before* the peak-detection code below is executed on real data.
**Related code/data archive:** Zenodo DOI 10.5281/zenodo.22232799 (prior analysis artifact)
**Repo:** `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`, file `docs/zenodo_preregistration_stage4.md` (alongside `docs/decision_log.md`). Implementation files live under `revision/stage4/`.

---

## 1. Disclosure statement

This pre-registration is written with full knowledge of results from a prior analysis attempt ("v1") on this same dataset, which is already public (archived at the Zenodo DOI above). Specifically, v1 found:
- A resting-state beta-peak detection pass in which roughly half the sample (20–22 of 42 subjects, across five peak-detection methods) showed no stable beta peak.
- A task-based finding of a 63–73% pre-stimulus beta-power increase during the MSIT+ task, localized to channels **Fz, Cz, C4**.

The author explicitly affirms that the region-of-interest (ROI) and all decision criteria specified below were chosen independently of these v1 results — in particular, the ROI is **not** based on the Fz/Cz/C4 channels that were identified post hoc from the task-based effect in v1, since that selection was outcome-driven on this same dataset and reusing it here would be circular with respect to the present resting-state decision. The methodological rationale for each choice is given in Section 3.

## 2. Research question

Does each subject's resting-state EEG show statistical evidence of a discrete beta-band oscillatory peak (over and above the aperiodic/background spectrum), using a criterion whose detection threshold is calibrated in advance via simulation rather than chosen post hoc?

## 3. Methods (fixed in advance)

### 3.1 Input data
- N = 39 subjects (final Stage-3 sample; 3 excluded for channel-quality reasons — see project decision log).
- Resting-state recordings only, restricted to rest pseudo-epochs surviving Stage-3 quality control (D1–D6) and the rest-specific D12 artifact rule below (§3.1.1).

### 3.1.1 Rest pseudo-epochs and artifact rejection (D12 for rest)
- Rest data are segmented into 2 s, **non-overlapping** pseudo-epochs, starting from the beginning of each rest block. An incomplete final segment at the end of a block counts as "outside," not kept.
- A pseudo-epoch is rejected if its broadband (time-domain) peak-to-peak amplitude exceeds 150 µV on **Fz, Cz, or C4** — the same channels and threshold as the project's core D12 artifact rule, applied here for consistency.
- A subject is excluded from Stage 4 if fewer than 50% of rest pseudo-epochs remain (kept / (total − outside)).
- **Note:** Fz/Cz/C4 here are the general-purpose artifact-check channels only, unrelated to the Stage-4 analysis ROI (§3.3). The task-window-dependent deferral of D12 (recorded 2026-10-25) applies only to the *task* analysis window, which rest pseudo-epochs do not depend on; this rest-specific rule was decided and recorded independently on 2026-10-30.
- **Architecture:** this step (rebuild + D12) is implemented in MATLAB (`stage4_export_roi.m`), producing only the retained 7-channel ROI time series per subject (no spectra). All downstream spectral/fit steps (§3.2–3.8) are implemented in a shared Python module (`stage4_core.py`) used identically by the extraction-only, simulation, and peak-detection scripts, so all three run the exact same pipeline.

### 3.2 Spectral estimation
- Welch's method: Hann window, 2 s segments, 50% overlap, `detrend='constant'` (scipy default), averaging method `mean`, power spectral density units µV²/Hz.
- Welch windows are placed only within contiguous runs of retained (non-rejected) pseudo-epochs post-§3.1.1 — never spanning a gap left by a rejected pseudo-epoch or a block boundary. (A run of length 1 kept epoch yields a single 2 s window with no internal overlap — this is expected, not an error; see §3.8 for where this matters.)
- Per-channel PSDs are computed first, then averaged across the 7-channel ROI (§3.3) on **linear power** (before any log transform), producing one mean PSD per subject.
- Fit/analysis range: 2–40 Hz inclusive, at 0.5 Hz resolution → **n = 77** frequency bins.
- Rationale: matches the estimator used in v1, so any change in peak-detection outcome relative to v1 cannot be attributed to a change in spectral estimator.

### 3.3 Decision unit (ROI)
- The primary decision unit is the **mean PSD across a 7-channel region of interest**: C3, Cz, C4, FC1, FC2, CP1, CP2.
- This ROI was selected a priori from the established topography of resting mu/beta rhythms over sensorimotor cortex (Pfurtscheller & Lopes da Silva, 1999), independent of any result from the present dataset (see Section 1).
- Single-channel results (any channel, including Fz/Cz/C4) are reported as secondary/exploratory only, never as the primary peak/no-peak decision.

### 3.4 Aperiodic model and fit range
- Spectral parameterization using the **`fooof`** Python package (Donoghue et al., 2020), **version 1.1.1** — the current official stable release, installed pinned in a user-level Python 3.12 environment. (`specparam` 2.0 was considered but rejected: only release candidates exist, and a pre-release API is not appropriate for a frozen, citable pre-registered pipeline; `fooof`/1.1.1 also matches the name cited by this project's own v1 analysis.)
- Default model: **fixed** (no spectral knee).
- The **knee** model is used instead only if it improves the fit by **ΔBIC > 10** relative to the fixed model (Kass & Raftery, 1995, "decisive evidence" threshold).
- ΔBIC is computed on the **aperiodic-only** fit — specifically, `fooof`'s internal robust aperiodic-fit routine (`_robust_ap_fit`), which estimates the aperiodic curve before periodic (peak) components are added — so this model-selection step uses no information about 13–30 Hz peaks:
  `BIC = n·ln(RSS/n) + k·ln(n)`, with `n = 77` (§3.2); `RSS` = sum of squared residuals between log10(power) and the fitted aperiodic curve over those bins; `k` = 2 (fixed: offset, exponent) or 3 (knee: offset, knee, exponent).
- R² is `fooof`'s own definition (squared correlation between model and data).
- This rule is based solely on fit-quality statistics and is applied identically regardless of any beta-band outcome.

### 3.5 Peak criterion
`fooof` is run with `peak_width_limits=[1,8]`, `max_n_peaks=inf`, `peak_threshold=2`, `min_peak_height=0` (i.e., liberal candidate-peak detection; the calibrated height threshold, not `fooof`'s own default, is what filters peaks — applied post-fit on the detected peaks' height, PW, column).

A subject is scored as having a resting beta peak if the fitted model returns **at least one Gaussian** with:
- center frequency in [13, 30] Hz,
- bandwidth in [1, 8] Hz,
- peak height (PW) ≥ the calibrated threshold (Section 3.6).

If more than one Gaussian falls within [13, 30] Hz, the **tallest** (highest PW) is treated as the primary peak; all detected peaks in range are reported as secondary/sensitivity information.

As a sensitivity analysis only (not part of the primary criterion), an alpha-harmonic rule will also be reported: IAF = the center frequency of the **tallest (highest PW)** alpha-band (8–13 Hz) peak from the same fit, if one or more are present; a beta-range peak is flagged as a possible alpha harmonic if its center falls within 2×IAF ± 2 Hz. This operational definition is deliberately lightweight, as this check is explicitly exploratory.

#### 3.5.1 Poor-fit flag (secondary category)
If the full model's (fixed- or knee-, as selected) R² is **below 0.90**, the subject is reported as **indeterminate (poor fit)** rather than classified as "no peak." This is a separate, third category from peak/no-peak, reported alongside the primary classification.

#### 3.5.2 Threshold-grid sensitivity analysis (secondary)
In addition to the primary threshold (the 95th percentile of the null-simulation distribution, §3.6), the peak/no-peak classification is also reported using the 90th and 99th percentiles of the same null distribution, to show how classification counts change across a reasonable range of thresholds.

### 3.6 Threshold calibration (simulation)
The peak-height threshold in 3.5 is set by simulation, not chosen by inspecting real beta-band results.

**Signal generation:** each simulated signal is Gaussian white noise, filtered in the frequency domain by multiplying by √(target PSD), where target PSD = 10^(aperiodic curve + injected Gaussian, if any) — so injected height is in the same log-power (PW) units used by the peak criterion. Below 0.5 Hz, the generative spectrum is set to **zero** rather than following the aperiodic formula to f→0, matching the real data's 0.5 Hz high-pass filter edge and avoiding unrealistic low-frequency power leaking into the 2–40 Hz fit range via Hann-window spectral leakage.

Each simulated signal represents the **ROI-level decision unit directly** — one simulated spectrum per repetition, not seven simulated channels subsequently averaged. This is a deliberate, conservative simplification: it does not model the variance reduction that real data gets from averaging seven correlated channels, so the resulting threshold is expected to be, if anything, somewhat **higher (more conservative, lower power)** than one built from a fully channel-correlation-aware simulation. This is a known, documented limitation, consistent with this project's general preference for conservative statistical choices (e.g. the ΔBIC > 10 rule, exact Wilcoxon elsewhere).

**Aperiodic parameters:** drawn from the real data's **fixed-model** fit only — i.e., the `offset_fixed`/`exponent_fixed` pair from each of the 39 real subjects (§3.7), regardless of which model (fixed or knee) was actually selected for that subject's real data by the ΔBIC rule. The full analysis pipeline, including its own ΔBIC model-selection step, is then applied unchanged to each simulated signal — so a simulated signal may still be fit with a "knee" model if the pipeline selects it, which is itself a check that model misselection does not corrupt peak detection.

**Design (full factorial, per decision 2026-10-30):**
1. Null condition: no injected peak, for all 39 empirical (offset, exponent) pairs, 1000 repetitions each (39,000 null simulations).
2. Injected condition: a Gaussian peak with center frequency drawn uniformly CF ~ U[13, 30] Hz and bandwidth BW ~ U[1, 8] Hz (matching the ranges allowed by §3.5) at each of 10 height levels (log10 PW units: 0.05, 0.10, ..., 0.50), for all 39 empirical (offset, exponent) pairs, 1000 repetitions each (390,000 injected simulations).
3. Each simulated signal is matched in length/Fs to the real post-D12 rest data and passed through the identical pipeline as the real-data analysis: Welch estimation (§3.2) → fooof fit + ΔBIC model selection (§3.4) → peak criterion (§3.5). The poor-fit flag (§3.5.1) is **not** applied at this stage — all 39,000 null simulations are included in the threshold calculation regardless of their fit quality.

**Threshold:** pooling all 39,000 null simulations, compute the maximum detected PW among any Gaussian in [13, 30] Hz (0 if none detected) for each. The primary threshold is the **95th percentile** of this pooled null distribution (NumPy's default `linear` interpolation method; a continuous percentile, not restricted to the 10 injected-height grid values). The 90th and 99th percentiles are also recorded for the sensitivity analysis (§3.5.2).

**Detection-power curve:** using the primary (95th-percentile) threshold, report the proportion of injected simulations correctly classified as "peak" at each of the 10 height levels — a simulation counts as a correct detection whenever **any** qualifying Gaussian is found in [13, 30] Hz, regardless of whether its center frequency matches the injected CF — with Clopper–Pearson (exact) confidence intervals at each level, and a logistic curve (fit by binomial maximum-likelihood on individual simulation outcomes, height as the sole predictor; the null condition is not included in this fit) for interpolation between levels.

### 3.7 Leakage-prevention procedure
- A dedicated "extraction-only" script (`stage4_extraction_only.py`) computes, from the real resting-state data, **only**:
  - bookkeeping fields needed to match simulated signals to real data, none of which carry outcome information: `subject`, `fs`, `n_pseudoepochs_total`, `n_pseudoepochs_kept`, `n_outside`, `excluded_D12` (flag), and the lengths of contiguous kept-epoch runs;
  - fooof fit-quality statistics (R², BIC, computed as in §3.4) for **both** fixed and knee models;
  - aperiodic parameters for **both** models: `offset_fixed`, `exponent_fixed`, `offset_knee`, `knee_knee`, `exponent_knee` (all stored regardless of which model is selected, per §3.6's simulation requirements);
  - `model_chosen` (fixed/knee, per the ΔBIC rule);
  - noise-floor power: the standard deviation of the aperiodic-fit residual (log10(power) minus the fitted aperiodic curve, from the selected model) computed separately over frequency bins in 2–12 Hz (`noise_2_12Hz`) and 31–40 Hz (`noise_31_40Hz`). **Caveat:** `noise_2_12Hz` overlaps the alpha band, so it partly reflects alpha-rhythm power rather than a pure noise floor; this is a known limitation, not a reason to change the definition.
- This script calls only the aperiodic-only fit and model-selection functions of the shared module (`stage4_core.py`) — never the full (periodic) fit function. No output in the 13–30 Hz range, and no peak count, height, or frequency, is computed or stored.
- The peak-detection code (`stage4_peak_detection.py`) is committed and tagged at a fixed commit hash **before** this pre-registration is deposited to Zenodo and a DOI is obtained, and additionally enforces this programmatically: it refuses to run on real data unless invoked with the registered Zenodo DOI as an argument, and that DOI must already be present in `docs/decision_log.md`.
- No spectra or peak counts/heights from the real resting-state data are viewed by the author before the DOI is registered.

### 3.8 Split-half reliability (secondary analysis)
For each subject, the retained (post-D12) rest pseudo-epochs are split into two halves by odd/even **sequential index among the retained (kept) epochs** (not by raw epoch index in the original recording), so each half is balanced regardless of which specific epochs were rejected. Because halving breaks epoch contiguity, each half's Welch estimate is built from one non-overlapping 2 s window per kept epoch (no intra-epoch overlap is possible, since no two epochs from the same half are adjacent to each other) — this is the expected, correct consequence of the split, not an error.

The full pipeline (§3.2–3.5) is run independently on each half, using the primary (95th-percentile) threshold for both halves.

Reported: (a) the peak/no-peak classification agreement rate between halves, computed only among subjects who are **not** flagged poor-fit (§3.5.1) in either half (poor-fit counts in either half are reported separately); (b) the intraclass correlation of peak height (PW) between halves — **ICC(2,1), two-way random-effects, absolute agreement, single measures (Koo & Li, 2016)** — computed among subjects classified as having a peak in both halves.

## 4. Deviation policy
Any deviation from the above procedure (e.g., change of ROI, threshold rule, or model-selection rule after seeing real-data beta-band results) will be reported in the manuscript as a post hoc, exploratory departure from this pre-registration, clearly labeled as such, and will not replace the pre-registered primary analysis.

## 5. Code and data availability
- Analysis code: [repository + commit hash to be filled in at tagging] (repo `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`, files under `revision/stage4/`)
- `fooof` package version: **1.1.1** (pinned; installed in Python 3.12)
- Preprocessing provenance: Stage-3 decision log, commit range `d7176e8..30ed2ea`
- Raw data: OpenNeuro ds004621 / GigaDB DOI 10.5524/100990
- This record: Zenodo DOI [to be assigned on deposit]

---
*Drafted 2026-10-27; specification details (ΔBIC formula, noise definitions, rest D12 rule) resolved 2026-10-30; package fixed to `fooof==1.1.1` 2026-10-30; implementation details (D1–D15), poor-fit flag, threshold-grid sensitivity, and split-half/ICC added 2026-10-30; remaining ambiguities (single-signal simulation unit, sub-0.5Hz zeroing, ICC type, split-half mechanics, multi-peak IAF, CI/logistic/percentile methods) resolved 2026-10-30 during script-writing review. To be finalized, tagged, and deposited prior to any execution of the peak-detection code on real resting-state data.*
