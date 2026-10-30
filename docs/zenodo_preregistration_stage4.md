# Pre-Registration: Resting-State Beta-Peak Detection Criterion (Stage 4)

**Project:** EEG beta-power study, Nencki-Symfonia MSIT+ dataset (OpenNeuro ds004621 / GigaDB DOI 10.5524/100990)
**Author:** Amirhossein Feizi (ORCID 0000-0001-8929-0910); Supervisor: Prof. Ali Motie Nasrabadi (ORCID 0000-0002-3702-8547)
**Status:** DRAFT — to be committed, tagged, and deposited to Zenodo for DOI assignment *before* the peak-detection code below is executed on real data.
**Related code/data archive:** Zenodo DOI 10.5281/zenodo.22232799 (prior analysis artifact)

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
- Rest data are segmented into 2 s, **non-overlapping** pseudo-epochs.
- A pseudo-epoch is rejected if its broadband (time-domain) peak-to-peak amplitude exceeds 150 µV on **Fz, Cz, or C4** — the same channels and threshold as the project's core D12 artifact rule, applied here for consistency.
- A subject is excluded from Stage 4 if fewer than 50% of rest pseudo-epochs remain.
- A pseudo-epoch crossing a block boundary or the data edge counts as "outside," not kept; the 50% rule uses kept/(epochs − outside).
- **Note:** Fz/Cz/C4 here are the general-purpose artifact-check channels only, unrelated to the Stage-4 analysis ROI (§3.3). The task-window-dependent deferral of D12 (recorded 2026-10-25) applies only to the *task* analysis window, which rest pseudo-epochs do not depend on; this rest-specific rule was decided and recorded independently on 2026-10-30.
- After this rejection step, the surviving (non-rejected) continuous rest data are used for spectral estimation (§3.2) — a separate segmentation from the one used here for artifact rejection.

### 3.2 Spectral estimation
- Welch's method, Hann window, 2-second segments, 50% overlap, applied within the surviving rest data (post-§3.1.1).
- Rationale: matches the estimator used in v1 exactly, so that any change in peak-detection outcome relative to v1 cannot be attributed to a change in spectral estimator. The 2 s window gives 0.5 Hz frequency resolution, sufficient to resolve the aperiodic-model fit and beta-band peak shape without over-smoothing.

### 3.3 Decision unit (ROI)
- The primary decision unit is the **mean PSD across a 7-channel region of interest**: C3, Cz, C4, FC1, FC2, CP1, CP2.
- This ROI was selected a priori from the established topography of resting mu/beta rhythms over sensorimotor cortex (Pfurtscheller & Lopes da Silva, 1999), independent of any result from the present dataset (see Section 1).
- Single-channel results (any channel, including Fz/Cz/C4) are reported as secondary/exploratory only, never as the primary peak/no-peak decision.

### 3.4 Aperiodic model and fit range
- Spectral parameterization fit over 2–40 Hz, using the official Python package **`specparam`** (current name for what was previously released as `fooof`), pinned to a specific stable release version (version number to be recorded in Section 5 once installed).
- Default model: **fixed** (no spectral knee).
- The **knee** model is used instead only if it improves the fit by **ΔBIC > 10** relative to the fixed model (Kass & Raftery, 1995, "decisive evidence" threshold).
- ΔBIC is computed on the **aperiodic-only** fit (before periodic/peak components are added), so this model-selection step uses no information about 13–30 Hz peaks:
  `BIC = n·ln(RSS/n) + k·ln(n)`, where `n` = number of frequency bins in 2–40 Hz (~76 at 0.5 Hz resolution); `RSS` = sum of squared residuals between log10(power) and the fitted aperiodic curve over those bins; `k` = 2 (fixed: offset, exponent) or 3 (knee: offset, knee, exponent).
- This rule is based solely on fit-quality statistics and is applied identically regardless of any beta-band outcome.

### 3.5 Peak criterion
A subject is scored as having a resting beta peak if the fitted model returns **at least one Gaussian** with:
- center frequency in [13, 30] Hz,
- bandwidth in [1, 8] Hz,
- peak height ≥ the calibrated threshold (Section 3.6).

If more than one Gaussian falls within [13, 30] Hz, the **tallest** (highest power) is treated as the primary peak; all detected peaks in range are reported as secondary/sensitivity information.

As a sensitivity analysis only (not part of the primary criterion), an alpha-harmonic rule (peak near 2×IAF) will also be reported.

### 3.6 Threshold calibration (simulation)
The peak-height threshold in 3.5 is set by simulation, not chosen by inspecting real beta-band results:

1. Simulate time-domain signals matched to the real post-D12 rest-data length and sampling rate.
2. Aperiodic offset and exponent for each simulated signal are drawn from the **empirical distribution** of these two parameters, as estimated from real data by the extraction-only procedure in Section 3.7 (fit-quality/aperiodic parameters only — no beta-band or peak information is used).
3. Half of simulated signals contain no injected beta oscillation (negative ground truth); half contain an injected Gaussian peak in [13, 30] Hz at one of 8–10 height levels spanning from near-undetectable to clearly detectable.
4. 1000 repetitions are run per height level × aperiodic-parameter draw.
5. Each simulated signal is passed through the identical pipeline as the real-data analysis: Welch estimation (§3.2) → specparam fit (§3.4) → peak criterion (§3.5).
6. The primary threshold is the lowest injected height at which the false-positive rate (peak detected in a true-negative simulated signal) remains below 5%.
7. A full detection-power curve (proportion detected vs. injected height) is reported with Clopper–Pearson or Wilson confidence intervals at each level, with a logistic curve fit for interpolation between levels.

### 3.7 Leakage-prevention procedure
- A dedicated "extraction-only" script computes, from the real resting-state data, **only**:
  - specparam fit-quality statistics (R², BIC for both fixed and knee models, computed as in §3.4);
  - aperiodic parameters (offset, exponent) from the model selected by the ΔBIC rule;
  - noise-floor power: the standard deviation of the aperiodic-fit residual (log10(power) minus the fitted aperiodic curve) computed separately over frequency bins in 2–12 Hz (`noise_2_12Hz`) and 31–40 Hz (`noise_31_40Hz`).
- No output in the 13–30 Hz range, and no peak count, height, or frequency, is computed or stored by this script.
- The peak-detection code to be run on real data (implementing §3.1.1–3.5) is committed and tagged at a fixed commit hash **before** this pre-registration is deposited to Zenodo and a DOI is obtained. It is not executed on real resting-state data until after the DOI is logged in the project decision log.
- No spectra or peak counts/heights from the real resting-state data are viewed by the author before the DOI is registered.

## 4. Deviation policy
Any deviation from the above procedure (e.g., change of ROI, threshold rule, or model-selection rule after seeing real-data beta-band results) will be reported in the manuscript as a post hoc, exploratory departure from this pre-registration, clearly labeled as such, and will not replace the pre-registered primary analysis.

## 5. Code and data availability
- Analysis code: [repository + commit hash to be filled in at tagging]
- `specparam` package version: [to be filled in at install]
- Preprocessing provenance: Stage-3 decision log, commit range `d7176e8..30ed2ea`
- Raw data: OpenNeuro ds004621 / GigaDB DOI 10.5524/100990
- This record: Zenodo DOI [to be assigned on deposit]

---
*Drafted 2026-10-27; specification details (ΔBIC formula, noise definitions, rest D12 rule, specparam package choice) resolved and added 2026-10-30. To be finalized, tagged, and deposited prior to any execution of the peak-detection code on real resting-state data.*
