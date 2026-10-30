# Pre-Registration: Resting-State Beta-Peak Detection Criterion (Stage 4)

**Project:** EEG beta-power study, Nencki-Symfonia MSIT+ dataset (OpenNeuro ds004621 / GigaDB DOI 10.5524/100990)
**Author:** Amirhossein Feizi (ORCID 0000-0001-8929-0910); Supervisor: Prof. Ali Motie Nasrabadi (ORCID 0000-0002-3702-8547)
**Status:** FROZEN CODE, DRAFT TEXT — code is committed and tagged (`S4-prereg-frozen`, commit `4207162872790ca6c49d52610b820a489875d2a4`); real-data export and extraction-only have both been run on all 39 subjects (0 excluded by D12); threshold simulation is about to start. This text is still to be deposited to Zenodo for DOI assignment *before* `stage4_peak_detection.py` is executed on real data.
**Related code/data archive:** Zenodo DOI 10.5281/zenodo.22232799 (prior analysis artifact)
**Repo:** `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`, file `docs/zenodo_preregistration_stage4.md` (alongside `docs/decision_log.md`). Implementation files live under `revision/stage4/`.

---

## 1. Disclosure statement

This pre-registration is written with full knowledge of results from a prior analysis attempt ("v1") on this same dataset, which is already public (archived at the Zenodo DOI above). Specifically, v1 found:
- A resting-state beta-peak detection pass in which roughly half the sample (20–22 of 42 subjects, across five peak-detection methods) showed no stable beta peak.
- A task-based finding of a 63–73% pre-stimulus beta-power increase during the MSIT+ task, localized to channels **Fz, Cz, C4**.

The author explicitly affirms that the region-of-interest (ROI) and all decision criteria specified below were chosen independently of these v1 results — in particular, the ROI is **not** based on the Fz/Cz/C4 channels that were identified post hoc from the task-based effect in v1, since that selection was outcome-driven on this same dataset and reusing it here would be circular with respect to the present resting-state decision. The methodological rationale for each choice is given in Section 3.

**Additional disclosure (added 2026-10-30, before any beta-band information was seen):** two methods decisions below — the boundary-event handling in §3.1.1 and the switch to a fixed-only aperiodic model in §3.4 — were made after inspecting real-data statistics that carry no 13–30 Hz information (pseudo-epoch counts and latencies for the first; aperiodic fit-quality and parameter statistics for the second). Both are disclosed in detail in their respective sections and in the project decision log, precisely because methods decisions informed by any look at the real data, however outcome-blind, should be transparent rather than silently folded into an "originally planned" protocol.

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
- **Boundary-event handling:** every rest bundle carries two `boundary` events at the very start of the recording (latency 0.5 and 1.0 samples), artefacts of the Stage-3 cropping step that separate no actual data. In the shared Stage-3 trial-counting helper these would otherwise cause pseudo-epoch 1 to be miscounted as "outside" in every subject; `stage4_export_roi.m` removes boundary events with `latency ≤ 1` from its own working copy before calling that helper (the helper itself is unchanged). Found and fixed 2026-10-30 (decision log `S4-boundary-fix`), before any spectral or 13–30 Hz quantity had been computed.
- **Real-data export results (all 39 subjects, post-fix):** `fracKept` mean 0.9925 (min 0.9333, sub-07; max 1.0000); 87 pseudo-epochs rejected by D12 across 16 subjects; 9 "outside" pseudo-epochs, all incomplete tail segments in subjects with <300 s of data; **0 subjects excluded** (none fell below the 50%-kept threshold).

### 3.2 Spectral estimation
- Welch's method: Hann window, 2 s segments, 50% overlap, `detrend='constant'` (scipy default), averaging method `mean`, power spectral density units µV²/Hz.
- Welch windows are placed only within contiguous runs of retained (non-rejected) pseudo-epochs post-§3.1.1 — never spanning a gap left by a rejected pseudo-epoch or a block boundary. (A run of length 1 kept epoch yields a single 2 s window with no internal overlap — this is expected, not an error; see §3.8 for where this matters.)
- Per-channel PSDs are computed first, then averaged across the 7-channel ROI (§3.3) on **linear power** (before any log transform), producing one mean PSD per subject.
- Fit/analysis range: 2–40 Hz inclusive, at 0.5 Hz resolution → **n = 77** frequency bins.
- Rationale: matches the estimator used in v1, so any change in peak-detection outcome relative to v1 cannot be attributed to a change in spectral estimator.

### 3.3 Decision unit (ROI)
- The primary decision unit is the **mean PSD across a 7-channel region of interest**: C3, Cz, C4, FC1, FC2, CP1, CP2.
- This ROI was selected a priori from the established topography of resting mu/beta rhythms over sensorimotor cortex (Pfurtscheller & Lopes da Silva, 1999), independent of any result from the present dataset (see Section 1).
- Single-channel results (any channel, including Fz/Cz/C4) are reported as secondary/exploratory only, never as the primary peak/no-peak decision. **This is not implemented in the frozen `S4-prereg-frozen` pipeline** (the ROI-only export does not currently include Fz). If added later, it is a separate, clearly-labeled exploratory addition, and it must be gated by the same Zenodo-DOI rule as the primary analysis (§3.7), since it carries the same category of 13–30 Hz information.

### 3.4 Aperiodic model and fit range
- Spectral parameterization using the **`fooof`** Python package (Donoghue et al., 2020), **version 1.1.1** — the current official stable release, installed pinned in a user-level Python 3.12 environment. (`specparam` 2.0 was considered but rejected: only release candidates exist, and a pre-release API is not appropriate for a frozen, citable pre-registered pipeline; `fooof`/1.1.1 also matches the name cited by this project's own v1 analysis.)
- **Aperiodic mode: fixed only.** No knee model, and no model-selection step, is used anywhere in the pipeline.
- **Why (resolved 2026-10-30, after inspecting aperiodic-only fit statistics but before any 13–30 Hz quantity was computed):** an earlier version of this protocol selected between fixed and knee models via ΔBIC on the aperiodic-only fit (computed exactly as described for §3.4 below in the decision log). On real data, this selected the knee model for 38/39 subjects (ΔBIC range 4.17–142.41, mean 56.02), but with knee parameters that were frequently non-physiological: knee values up to 6.8×10¹¹, aperiodic exponents from 0.0001 to 8.09, a divergent fit in one subject (knee = −1, exponent ≈ 0), and — most importantly — a derived knee frequency falling *inside* the 13–30 Hz beta band itself for 8 of the 39 subjects. A synthetic check (pure power-law aperiodic plus a simple alpha peak, no knee, no beta, generated by the frozen simulation module) did **not** reproduce this ΔBIC pattern, so the mechanism behind the real-data knee preference is not fully understood; what is established is that the fitted knee model is frequently not a credible aperiodic background in this fit range, and that the real-data model-selection behavior did not match the simulation's generative model (which was fixed-only), undermining the validity of a simulation-calibrated threshold under the original ΔBIC design. Rather than add further ad hoc plausibility constraints on knee parameters post hoc, the aperiodic model was fixed to **fixed-only** throughout the pipeline — automatically consistent with the simulation generator, which was already fixed-only.
- **Fit-failure handling:** if the aperiodic-only fit fails on real data, the script stops and reports it (not silently handled). In simulation, a fixed-model aperiodic-fit failure is labeled `fit_failed`, counted (not discarded) and treated as a non-detection (max PW = 0) in the null/injected pools; the count/rate of `fit_failed` repetitions is reported alongside the threshold and power-curve results for transparency. Standard deviations in §3.7 use the sample convention (`ddof=1`).
- R² is `fooof`'s own definition (squared correlation between model and data). On real data, the aperiodic-only fixed-model fit (identical regardless of this change, since fixed-model fitting itself did not change) had R² mean 0.8090, range 0.6256–0.9654 across the 39 subjects — this excludes the alpha peak by construction (aperiodic-only), so a moderate R² here is expected rather than a sign of a bad fit.

### 3.5 Peak criterion
`fooof` is run with `peak_width_limits=[1,8]`, `max_n_peaks=inf`, `peak_threshold=2`, `min_peak_height=0` (i.e., liberal candidate-peak detection; the calibrated height threshold, not `fooof`'s own default, is what filters peaks — applied post-fit on the detected peaks' height, PW, column), using the fixed aperiodic model throughout (§3.4).

A subject is scored as having a resting beta peak if the fitted model returns **at least one Gaussian** with:
- center frequency in [13, 30] Hz,
- bandwidth in [1, 8] Hz,
- peak height (PW) ≥ the calibrated threshold (Section 3.6).

If more than one Gaussian falls within [13, 30] Hz, the **tallest** (highest PW) is treated as the primary peak; all detected peaks in range are reported as secondary/sensitivity information.

As a sensitivity analysis only (not part of the primary criterion), an alpha-harmonic rule will also be reported: IAF = the center frequency of the **tallest (highest PW)** alpha-band (8–13 Hz) peak from the same fit, if one or more are present; a beta-range peak is flagged as a possible alpha harmonic if its center falls within 2×IAF ± 2 Hz. This operational definition is deliberately lightweight, as this check is explicitly exploratory.

**Full-fit failure:** if `fooof` fails to return a full (periodic) model at all, the subject is classified `poor_fit` (indeterminate, §3.5.1) on real data, since no R² is available to evaluate; in simulation, the same repetition is handled like a fixed-model fit failure (§3.4) — labeled `fit_failed`, counted, treated as a non-detection.

#### 3.5.1 Poor-fit flag (secondary category)
If the full model's R² is **below 0.90**, the subject is reported as **indeterminate (poor fit)** rather than classified as "no peak." This is a separate, third category from peak/no-peak, reported alongside the primary classification. (Given the fixed-only model decision in §3.4, this flag may trigger more often than it would under a per-subject best-fitting model; this is treated as an honest consequence of §3.4's choice, not a reason to revisit it.)

#### 3.5.2 Threshold-grid sensitivity analysis (secondary)
In addition to the primary threshold (the 95th percentile of the null-simulation distribution, §3.6), the peak/no-peak classification is also reported using the 90th and 99th percentiles of the same null distribution, to show how classification counts change across a reasonable range of thresholds.

### 3.6 Threshold calibration (simulation)
The peak-height threshold in 3.5 is set by simulation, not chosen by inspecting real beta-band results.

**Signal generation:** each simulated signal is Gaussian white noise, filtered in the frequency domain by multiplying by √(target PSD), where target PSD = 10^(aperiodic curve + injected Gaussian, if any) — so injected height is in the same log-power (PW) units used by the peak criterion. Below 0.5 Hz, the generative spectrum is set to **zero** rather than following the aperiodic formula to f→0, matching the real data's 0.5 Hz high-pass filter edge and avoiding unrealistic low-frequency power leaking into the 2–40 Hz fit range via Hann-window spectral leakage. The generative aperiodic model is fixed-only (§3.4), matching the fitting model used throughout.

Each simulated signal represents the **ROI-level decision unit directly** — one simulated spectrum per repetition, not seven simulated channels subsequently averaged. This is a deliberate, conservative simplification: it does not model the variance reduction that real data gets from averaging seven correlated channels, so the resulting threshold is expected to be, if anything, somewhat **higher (more conservative, lower power)** than one built from a fully channel-correlation-aware simulation. This is a known, documented limitation, consistent with this project's general preference for conservative statistical choices (e.g. exact Wilcoxon elsewhere).

**Aperiodic parameters:** drawn from the real data's fixed-model fit — i.e., the `offset_fixed`/`exponent_fixed` pair from each real subject not excluded by D12 (§3.1.1); since D12 excludes 0 of the 39 subjects, the simulation runs with all 39 empirical pairs.

**Design (full factorial, per decision 2026-10-30):**
1. Null condition: no injected peak, for all 39 empirical (offset, exponent) pairs, 1000 repetitions each.
2. Injected condition: a Gaussian peak with center frequency drawn uniformly CF ~ U[13, 30] Hz and bandwidth BW ~ U[1, 8] Hz (matching the ranges allowed by §3.5) at each of 10 height levels (log10 PW units: 0.05, 0.10, ..., 0.50), for all 39 empirical (offset, exponent) pairs, 1000 repetitions each.
3. Each simulated signal is matched in length/Fs to the real post-D12 rest data (using that subject's actual run-length structure) and passed through the identical pipeline as the real-data analysis: Welch estimation (§3.2) → fooof fixed-model fit (§3.4) → peak criterion (§3.5). The poor-fit flag (§3.5.1) is **not** applied at this stage — all null simulations are included in the threshold calculation regardless of their fit quality; fit failures are handled per §3.4/§3.5.

**Threshold:** pooling all null simulations, compute the maximum detected PW among any Gaussian in [13, 30] Hz (0 if none detected, including `fit_failed` cases) for each. The primary threshold is the **95th percentile** of this pooled null distribution (NumPy's default `linear` interpolation method; a continuous percentile, not restricted to the 10 injected-height grid values). The 90th and 99th percentiles are also recorded for the sensitivity analysis (§3.5.2).

**Detection-power curve:** using the primary (95th-percentile) threshold, report the proportion of injected simulations correctly classified as "peak" at each of the 10 height levels — a simulation counts as a correct detection whenever **any** qualifying Gaussian is found in [13, 30] Hz, regardless of whether its center frequency matches the injected CF — with **Clopper–Pearson (exact) confidence intervals at the 95% confidence level** at each level, and a logistic curve (fit by binomial maximum-likelihood on individual simulation outcomes, height as the sole predictor; the null condition is not included in this fit) for interpolation between levels. The `fit_failed` count/rate is reported separately for the null and injected pools, overall and per height level.

### 3.7 Leakage-prevention procedure
- A dedicated "extraction-only" script (`stage4_extraction_only.py`) computes, from the real resting-state data, **only**:
  - bookkeeping fields needed to match simulated signals to real data, none of which carry outcome information: `subject`, `fs`, `n_pseudoepochs_total`, `n_pseudoepochs_kept`, `n_outside`, `excluded_D12` (flag), and the lengths of contiguous kept-epoch runs;
  - fooof fixed-model fit-quality statistics (`R2_fixed`, `BIC_fixed`, computed as in §3.4);
  - fixed-model aperiodic parameters: `offset_fixed`, `exponent_fixed`;
  - noise-floor power: the standard deviation (`ddof=1`) of the aperiodic-fit residual (log10(power) minus the fitted aperiodic curve) computed separately over frequency bins in 2–12 Hz (`noise_2_12Hz`) and 31–40 Hz (`noise_31_40Hz`). **Caveat:** `noise_2_12Hz` overlaps the alpha band, so it partly reflects alpha-rhythm power rather than a pure noise floor; this is a known limitation, not a reason to change the definition.
  - (An earlier version of this script also stored knee-model statistics and a `model_chosen` field, when the pipeline still used ΔBIC-based model selection; these were removed when the aperiodic model was fixed to fixed-only, §3.4. The superseded knee-era output file is kept only as provenance for that decision, labeled accordingly in the decision log, and is not used downstream.)
- This script calls only the aperiodic-only fit function of the shared module (`stage4_core.py`) — never the full (periodic) fit function. No output in the 13–30 Hz range, and no peak count, height, or frequency, is computed or stored.
- The peak-detection code (`stage4_peak_detection.py`) is committed and tagged (`S4-prereg-frozen`, commit `4207162872790ca6c49d52610b820a489875d2a4`) **before** this pre-registration text is deposited to Zenodo and a DOI is obtained, and additionally enforces this programmatically: it refuses to run on real data unless invoked with the registered Zenodo DOI as an argument, that DOI must match the `10.5281/zenodo.<number>` format, it must **not** equal the v1 archive's DOI (`10.5281/zenodo.22232799`), and it must already be present in `docs/decision_log.md`.
- No spectra or peak counts/heights from the real resting-state data are viewed by the author before the DOI is registered.

### 3.8 Split-half reliability (secondary analysis)
For each subject, the retained (post-D12) rest pseudo-epochs are split into two halves by odd/even **sequential index among the retained (kept) epochs** (not by raw epoch index in the original recording), so each half is balanced regardless of which specific epochs were rejected. Because halving breaks epoch contiguity, each half's Welch estimate is built from one non-overlapping 2 s window per kept epoch (no intra-epoch overlap is possible, since no two epochs from the same half are adjacent to each other) — this is the expected, correct consequence of the split, not an error.

The full pipeline (§3.2–3.5) is run independently on each half, using the primary (95th-percentile) threshold for both halves.

Reported: (a) the peak/no-peak classification agreement rate between halves, computed only among subjects who are **not** flagged poor-fit (§3.5.1) in either half (poor-fit counts in either half are reported separately); (b) the intraclass correlation of peak height (PW) between halves — **ICC(2,1), two-way random-effects, absolute agreement, single measures (Koo & Li, 2016)** — computed among subjects classified as having a peak in both halves. (The ICC(2,1) implementation was verified against the published Shrout & Fleiss (1979) worked example, reproducing their reference value of 0.29.)

## 4. Deviation policy
Any deviation from the above procedure (e.g., change of ROI, threshold rule, or model-selection rule after seeing real-data beta-band results) will be reported in the manuscript as a post hoc, exploratory departure from this pre-registration, clearly labeled as such, and will not replace the pre-registered primary analysis. (This is distinct from the boundary-event fix and the fixed-only aperiodic-model decision, §3.1.1/§3.4, both made before any beta-band information was seen and both disclosed above.)

## 5. Code and data availability
- **Analysis code:** repo `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`, files under `revision/stage4/` (`stage4_export_roi.m`, `stage4_core.py`, `stage4_extraction_only.py`, `stage4_simulate_threshold.py`, `stage4_peak_detection.py`). Frozen at tag **`S4-prereg-frozen`**, commit **`4207162872790ca6c49d52610b820a489875d2a4`** (short: `4207162`), 2026-10-30. This commit has not been pushed to the remote as of this writing. The tag has moved twice on 2026-10-30, each time before anything had been deposited to Zenodo and before the tag was ever pushed: first `be6f091`→`bcbac0c` (boundary-event fix, §3.1.1), then `bcbac0c`→`4207162` (fixed-only aperiodic model, §3.4).
- **Note on ordering:** a text-only edit to this document necessarily lands in a commit *after* the `S4-prereg-frozen` tag — the tag stays fixed on the code commit above and the frozen code is never altered by text updates. The two tag moves above were code changes made in direct response to findings on real (but outcome-blind) data, not routine text edits; both are fully documented in §3.1.1, §3.4, and the decision log.
- `fooof` package version: **1.1.1** (pinned; installed in Python 3.12)
- Preprocessing provenance: Stage-3 decision log, commit range `d7176e8..30ed2ea`
- Raw data: OpenNeuro ds004621 / GigaDB DOI 10.5524/100990
- This record: Zenodo DOI [to be assigned on deposit]

---
*Drafted 2026-10-27; specification details (ΔBIC formula, noise definitions, rest D12 rule) resolved 2026-10-30; package fixed to `fooof==1.1.1` 2026-10-30; implementation details (D1–D15), poor-fit flag, threshold-grid sensitivity, and split-half/ICC added 2026-10-30; further ambiguities resolved 2026-10-30 across several rounds of script-writing review; single-channel secondary analysis deferred (§3.3); code frozen 2026-10-30. Same day, on real (outcome-blind) data: boundary-event bug found and fixed (§3.1.1); aperiodic model switched from ΔBIC-selected fixed/knee to fixed-only after non-physiological knee fits were found in 38/39 subjects (§3.4). All 39 subjects exported and extracted with 0 excluded by D12. To be deposited to Zenodo prior to any execution of `stage4_peak_detection.py` on real resting-state data.*
