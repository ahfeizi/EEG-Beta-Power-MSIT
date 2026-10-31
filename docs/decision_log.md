
# Decision Log — Stage 3 Close & Stage 4 Decisions

Date: 2026-10-26 (Stage 3 close) / 2026-10-27 (Stage 4 decided) / 2026-10-30–31 (spec details + package resolved; code frozen; boundary-event bug fixed; fixed-only aperiodic model adopted; threshold calibration redesigned twice; extraction and simulation run on real/simulated data)
Commits: `d7176e8..30ed2ea` (pushed, Stage 3); pre-registration text: `47d8b8c`, `1d0b05c`, `36ab9e5`, `890ae1b`, `884d457`, `03f40b1` (not yet pushed; §3.6/§3.8 text still pending as of this entry); code: `be6f091` (superseded) → `bcbac0c` (superseded) → `4207162` (superseded) → `2923dc2` → `f73dcda` → `4e48a03` → `0d53db6` → `bd96a95c175ddcb04af225a2716b56a52e9f8087` tagged `S4-prereg-frozen` (Stage-4 code, not yet pushed; tag moved via `git tag -f` five times on 2026-10-30/31 — see §5, §6, §7)
Repo: `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`. Decision log lives at `docs/decision_log.md` in that repo (not a `decision_log/` folder). The pre-registration file is saved alongside it at `docs/zenodo_preregistration_stage4.md`. Implementation files are at `revision/stage4/`.

## 1. Stage 3 Close (`S3a-close`)

**Final sample: N = 39.**

Three subjects excluded:
- **sub-42:** 35 channels with unresolved labeling.
- **sub-28:** 15.2% bad channels.
- **sub-32:** 21.6% bad channels.

Batches:
- Part 1: `s3p1_1`, `s3p1_2`
- D6: `d6_1`
- Part 2: `p2_d14`, `p2_1`, `p2_2`
- The 5 logged failed runs in `p2_1` are the sub-10 non-zero exits fixed in `S3a-P2-fix1`.

File locations: 39 saved S1 bundles in `D:\Revision_EEG\stage3_part2\`, with per-batch manifests alongside: `manifest_p2_d14.tsv`, `manifest_p2_1.tsv`, `manifest_p2_2.tsv`.
- Rebuild: main version via `stage3_p2_rebuild(...,'beta',false)`; EMG-check version via `'emg'`.

Labels carried forward to later stages:
- Interpolated Fz/Cz/C4 channels: sub-12, 19, 22, 23, 41.
- Channel pairs: sub-13, sub-41.
- Rest blocks: sub-25.
- Marker exception (unspecified detail carried forward as a flag).

Prior D12 history (for context, see `S3a-P2` §7, `S3a-P2-impl`, `S3a-D12-defer`, commits `6f536eb`/`4705e9c`/`d7d3664`):
- D12 core rule: a trial/pseudo-epoch is rejected if broadband time-domain peak-to-peak amplitude exceeds 150 µV on Fz, Cz, or C4; a subject is excluded if fewer than 50% of trials/pseudo-epochs remain in a condition; counts reported.
- `S3a-D12-defer` (2026-10-25) deferred applying D12 until Stage 5, because D12 needs the **task** analysis window, which was not yet fixed. It required the window and the rest pseudo-epoch definition to be recorded before Stage-5 output.
- `S4-options` (draft, 2026-10-26) proposed D12 for rest using 2s non-overlapping pseudo-epochs — but this predates the Stage-4/Stage-5 sequencing resolution below.

## 2. Stage 4 Decisions (`S4-decided`) — FINAL, pending Zenodo DOI registration before execution

Decided 2026-10-27, talked through item by item (Amir chose/confirmed each).

| Topic | Final decision |
|---|---|
| Spectral estimator & pseudo-epochs | Welch, 2s Hann window, 50% overlap (matches v1, for direct comparability). Decision unit = mean PSD over a 7-channel ROI: **C3, Cz, C4, FC1, FC2, CP1, CP2** (central/sensorimotor strip). ROI chosen a priori from independent literature on resting beta/mu topography (Pfurtscheller & Lopes da Silva, 1999), explicitly NOT from the v1 task-based Fz/Cz/C4 finding (that selection was outcome-driven on this same dataset and would have been circular). Single-channel results reported as secondary only. |
| Aperiodic model & frequency range | **Superseded 2026-10-30 — see §6.** (Originally: fit range 2–40 Hz, fixed default, knee selected if ΔBIC > 10. Replaced with fixed-only throughout, for the reasons in §6.) |
| Peak criterion | At least one Gaussian with center in [13, 30] Hz, width in [1, 8] Hz, height ≥ calibrated threshold. **Threshold is now per-subject, see §7** (originally planned as one pooled threshold — superseded). If multiple Gaussians fall in range, the tallest (highest power) is the primary peak; others reported as secondary/sensitivity. Alpha-harmonic rule (2×IAF) kept as a sensitivity analysis only. |
| Simulation for threshold calibration | **Superseded 2026-10-30/31 — see §7.** (Originally: one pooled threshold = 95th percentile of the null distribution pooled across all 39 subjects' empirical (offset, exponent) pairs. Replaced with per-subject calibration, including a per-subject spectral-roughness parameter and a per-subject threshold, for the reasons in §7.) |
| Leakage prevention | A separate "extraction-only" script computes, from real data, only: fit-quality stats, aperiodic parameters, and noise-floor power from 2–12 Hz and 31–40 Hz residuals (column set updated per §6 — fixed-model only). No 13–30 Hz output or peak count/height is computed or stored. Peak-detection code on real data is committed and frozen (tagged `S4-prereg-frozen`) before the Zenodo DOI is obtained, and additionally refuses to run without a `--doi` argument matching a DOI already logged here (and not equal to the v1 archive DOI). |
| Zenodo pre-registration | Order: finalize protocol text + code → commit with tag → upload to Zenodo (code + pre-registration text) → obtain DOI → run Stage-4 analysis on real data → log DOI in this decision log. Pre-registration text must explicitly disclose that v1 results on this same dataset were already known to the author, and that the ROI/criteria here were chosen independently of those results (not from the data-driven Fz/Cz/C4 selection). |

**Lessons from v1 (motivating these choices):**
- argmax always returns a frequency; with no real peak, it lands at the band edge. In v1, 20–22 of 42 subjects had no stable beta peak.
- Peak presence depends on threshold choice → need both a calibrated threshold and an analysis across a grid of thresholds.
- Peak stability should be demonstrated via split-half analysis, not assumed.

## 3. Stage 4 — Resolved Specification Details (`S4-spec-resolved`, 2026-10-30)

- **ΔBIC formula (superseded, see §6):** was computed on the **aperiodic-only** fit (before periodic/peak fitting is added), kept for provenance since it was used to discover the problem resolved in §6:
  `BIC = n·ln(RSS/n) + k·ln(n)`, `n = 77` (2–40 Hz inclusive at 0.5 Hz resolution), `RSS` = sum of squared residuals between log10(power) and the fitted aperiodic curve, `k` = 2 (fixed) or 3 (knee). The fixed-model BIC is still reported (`BIC_fixed`, unused in any decision); the knee branch no longer exists in the frozen pipeline.
- **Noise-floor definition:** standard deviation (`ddof=1`) of the aperiodic-fit residual (log10(power) minus the fitted aperiodic curve, fixed model per §6), computed separately over frequency bins in 2–12 Hz (`noise_2_12Hz`) and 31–40 Hz (`noise_31_40Hz`). Known caveat: `noise_2_12Hz` overlaps the alpha band. **`noise_31_40Hz` is the quantity that later motivated §7.**
- **D12 for rest (`S4-D12-rest`) — resolves the Stage-4/Stage-5 sequencing discrepancy:**
  - `S3a-D12-defer`'s deferral was specifically about the **task** analysis window (undefined at the time). Rest pseudo-epochs have no such task-locked window dependency, so this deferral does not block deciding D12 for rest now.
  - **Decision (Amirhossein, 2026-10-30):** approved.
  - Rule: rest pseudo-epochs are 2 s, non-overlapping, from the start of each block. A pseudo-epoch is rejected if broadband time-domain peak-to-peak amplitude exceeds 150 µV on Fz, Cz, or C4 within that 2 s window (same channels/threshold as the core D12 rule, for consistency). A subject is excluded from Stage 4 if fewer than 50% of rest pseudo-epochs remain.
  - Implementation choice (flagged, matching `S3a-P2-impl` precedent): a pseudo-epoch crossing a block boundary or the data edge counts as "outside," not kept; the 50% rule uses kept/(epochs − outside).
  - **Note:** Fz/Cz/C4 here are the general-purpose D12 artifact-check channels (unchanged from the original rule) — a different, unrelated set from the Stage-4 ROI (C3, Cz, C4, FC1, FC2, CP1, CP2) used for the beta-peak decision itself.
  - After D12 rejection, Welch PSD estimation is computed only within contiguous runs of retained pseudo-epochs; the D12 pseudo-epochs and the Welch estimation windows are two separate segmentations for two separate purposes.
- **Python package for spectral parameterization (resolved 2026-10-30):** `specparam` has no stable release — only release candidates exist on PyPI. Decision: use **`fooof==1.1.1`** instead (Donoghue et al. 2020), pinned in a user-level Python 3.12 environment.

## 4. Stage 4 — Implementation Decisions & Code Freeze (`S4-impl-resolved`, 2026-10-30)

Resolved across several rounds of script-writing review, after the local session wrote `revision/stage4/stage4_export_roi.m`, `stage4_core.py`, `stage4_extraction_only.py`, `stage4_simulate_threshold.py`, `stage4_peak_detection.py`:

- **Architecture (D1–D3):** MATLAB rebuild+D12 produces ROI time series only (no spectra); shared Python module (`stage4_core.py`) implements Welch/fooof identically for all three downstream scripts; pseudo-epochs split from block start, incomplete tail = outside; Welch windows only within contiguous kept-epoch runs.
- **Aperiodic-only fit (D4–D5):** `fooof`'s internal `_robust_ap_fit`, before periodic components; R² is `fooof`'s own definition.
- **fooof peak settings (D6):** `peak_width_limits=[1,8]`, `max_n_peaks=inf`, `peak_threshold=2`, `min_peak_height=0`; calibrated threshold applied post-fit on the PW column.
- **Threshold definition (D7, revised from the original draft, superseded again by §7):** was the continuous 95th percentile of the pooled null-simulation max-detected-height distribution; now per-subject (§7). 90th/99th percentiles also recorded per subject (§3.5.2 sensitivity).
- **Signal generation (D8):** filtered white noise, target PSD = 10^(aperiodic + Gaussian); generative spectrum zeroed below 0.5 Hz to match the real high-pass filter. **Extended in §7** with a per-subject multiplicative roughness factor.
- **Injected peak shape (D9):** CF ~ U[13,30] Hz, BW ~ U[1,8] Hz, drawn per repetition (not fixed values) — for threshold generalizability.
- **Height-level grid (D10):** 10 levels, log10 PW units 0.05–0.50, step 0.05.
- **Simulation scale (D11):** full factorial — every retained empirical (offset, exponent) pair × null/10 levels × 1000 reps (not random subject sampling).
- **Extraction-only output columns (D12, superseded, see §6):** originally included knee-model columns and `model_chosen`; now 13 columns, fixed-model only (§6).
- **Knee in simulation (D13, moot, see §6):** the simulation generator was always fixed-only; this decision described how a (since-removed) knee branch in the fitting pipeline would be exercised. No longer applicable — there is no knee branch anywhere in the frozen pipeline.
- **Alpha-harmonic rule (D14):** kept fully exploratory; lightweight operational definition (IAF = tallest alpha-band peak 8–13 Hz; harmonic flag = beta peak center within 2×IAF ± 2 Hz).
- **Welch details (D15):** `detrend='constant'`, averaging `mean`, units µV²/Hz, ROI-averaged on linear power, inclusive 2–40 Hz range (**n = 77** bins, corrected from the earlier ~76 estimate). scipy's default periodic (DFT-even) Hann window retained (the conventional choice for spectral analysis; the symmetric/periodic difference from MATLAB's `hann()` is immaterial here, since the whole Stage-4 pipeline is implemented in Python, not ported from v1's MATLAB code bit-for-bit).
- **Simulation unit (Q1):** each simulated signal represents the ROI-level decision unit directly (one signal per repetition), not seven simulated channels averaged — a documented conservative simplification (does not model real channel correlation; expected to raise the threshold, i.e. lower power, rather than lower it).
- **Sub-0.5Hz handling (Q2):** generative spectrum zeroed below 0.5 Hz (ties to D8).
- **ICC type (Q3):** ICC(2,1), two-way random effects, absolute agreement, single measures (Koo & Li, 2016); implementation verified against the Shrout & Fleiss (1979) worked example (reproduced their reference value 0.29).
- **Split-half mechanics (Q4):** odd/even by sequential index among *retained* (kept) epochs; agreement rate excludes subjects poor-fit in either half (counted separately); **now the half's own half-length threshold (§7), not the primary full-length threshold**; confirmed that each half's Welch estimate reduces to one non-overlapping window per kept epoch (expected consequence of breaking epoch contiguity, not an error).
- **Multi-peak IAF (Q5):** tallest (highest PW) alpha peak, if more than one present.
- **CI method (Q6):** Clopper–Pearson (exact), 95% confidence level.
- **Minor method confirmations (Q7):** logistic = binomial MLE on individual outcomes (height as sole predictor, null excluded); percentile = NumPy `linear`; poor-fit flag not applied during simulation (all null sims counted); "correct detection" = any qualifying peak in range, regardless of CF match to the injected target.
- **D12-excluded-subject handling in simulation:** runs with only the retained (non-D12-excluded) empirical pairs (0 excluded in practice, §5, so all 39 used).
- **Fit-failure handling:** real data + fixed-model aperiodic-fit failure → script stops, reports to Amir. Simulated data + any fit failure → labeled `fit_failed`, counted (not discarded), treated as non-detection (max PW = 0); rate reported in simulation output for transparency. Real data + full-fit failure → `poor_fit` category (no R² available). Noise-floor SD uses `ddof=1`.
- **CI level for the detection-power curve:** 95% (`CI_LEVEL=0.95`).
- **Single-channel secondary analysis (§3.3):** deferred — not implemented in the frozen pipeline (ROI-only export lacks Fz). If added later, must be gated by the same `--doi` mechanism as the primary analysis.
- **DOI gate (`stage4_peak_detection.py`):** refuses to run on real data unless given `--doi` matching `10.5281/zenodo.<number>`, not equal to the v1 archive DOI (`10.5281/zenodo.22232799`), and already present in `docs/decision_log.md`. Also refuses if `thresholds.json` is a test run (`test_run=true`) or lacks that key.

**Code freeze history (see §5, §6, §7 for subsequent fixes):** all five Stage-4 scripts (767 lines total) originally committed in one commit and tagged **`S4-prereg-frozen`** at commit `be6f091d6de82473221d0439f915959513cb9152` (short `be6f091`), 2026-10-30, not pushed.

## 5. Stage 4 — Boundary-Event Bug Fix (`S4-boundary-fix`, 2026-10-30)

**Found while running `stage4_export_roi.m` on real data, before extraction/simulation/peak-detection touched anything.**

- **Symptom:** the export script's own assert stopped on sub-01 with "outside epochs" for pseudo-epoch 1.
- **Cause:** every one of the 39 S1 rest bundles carries two `boundary` events at the very start of the recording, latency 0.5 and 1.0 — artefacts of the Stage-3 cropping that separate no data (nothing precedes them). The tested, already-committed Stage-3 helper `stage3_d12_trials` counts any boundary falling in `(a−0.5, b+0.5)` as "crosses a boundary," so pseudo-epoch 1 (a=1) was flagged outside even though no real discontinuity occurs there.
- **Decision:** fix **only** in `stage4_export_roi.m` (not in `stage3_d12_trials`, which is tested/committed Stage-3 code reused elsewhere) — on the helper's input copy only, remove `boundary` events with `latency <= 1` (safe: in EEGLAB the first real sample has latency 1; a boundary separating two real samples has latency ≥ 1.5, so this only strips boundaries with nothing before them). The helper itself and its assert are unchanged.
  - Rejected keeping the code as-is and loosening the assert: that would silently drop pseudo-epoch 1 in all 39 subjects for no real discontinuity, exactly the systematic, unmotivated exclusion §3.1.1 is meant to prevent.
  - Rejected fixing the shared Stage-3 helper: unnecessary regression risk to tested, committed code used elsewhere (incl. later at Stage 5).
- **Verification:** boundary pattern (0.5, 1.0 at start; one after each block end; nothing else) confirmed identical across all 39 subjects by reading `P2.rest.event` latencies directly (rebuild doesn't alter events). Fix tested on sub-01 (now `outside=0` for epoch 1, assert passes); result confirmed consistent once all 39 were exported (results table below).
- **Commit/tag:** fix committed as `bcbac0ce1cdf36c96e39a89f14d8b0da14c0548a`. Since nothing had yet been deposited to Zenodo and the tag was never pushed, the tag `S4-prereg-frozen` was **moved** (`git tag -f`) from `be6f091` to `bcbac0c` rather than creating a second "frozen" tag.
- **Data-leakage check:** throughout diagnosis and fix, only event latencies and epoch counts were inspected — no spectrum or 13–30 Hz quantity was computed at any point.
- **Flag for Stage 5 (still open, intentionally deferred):** the same leading-boundary pattern (latency 0.5, 1.0) is present in every rest bundle; it has not yet been checked in the MSIT/task bundles. If present there too, any task-window/trial definition in Stage 5 whose window could cover sample 1 needs the same handling as here (or an equivalent fix in whatever Stage-5 code calls `stage3_d12_trials`). To be checked and resolved when Stage-5 analysis windows are defined.

**Real-data export results (`stage4_export_roi.m`, all 39 subjects, post-fix):**

| | Value |
|---|---|
| `<sub>_rest_roi.mat` files | 39/39, all read without error by `load_roi` |
| `fracKept` | mean 0.9925, min 0.9333 (sub-07), max 1.0000 |
| Pseudo-epochs rejected by D12 | 87 total, across 16 subjects; highest in sub-07 (20), sub-18 (16), sub-25 (13) |
| Pseudo-epochs "outside" | 9 total, all incomplete tail segments in subjects with <300s of data (sub-08, 13, 21, 22, 25 [×2], 35, 37, 38) — expected §3.1.1 behavior; epoch 1 was never outside in any subject |
| Subjects excluded by D12 (<50% kept) | **0** |
| `nPseudoTotal` <300 | sub-21 (299), sub-22 (298), sub-25 (291) — shorter blocks; sub-25 is the previously-logged D3c case |

No subject is excluded by D12 for rest. All 39 proceed to extraction.

## 6. Stage 4 — Fixed-Only Aperiodic Model (`S4-fixed-only`, 2026-10-30)

**Found while running `stage4_extraction_only.py` on real ROI data (aperiodic-only statistics; no 13–30 Hz quantity computed at any point in this investigation).**

- **Symptom:** under the original ΔBIC rule (§2, §3), the knee model was selected for **38 of 39 subjects** (ΔBIC range 4.17–142.41, mean 56.02; only sub-19 kept fixed, ΔBIC=4.17). The fitted knee parameters were frequently non-physiological: `knee` up to 6.8×10¹¹, `exponent_knee` from 0.0001 to 8.09, a divergent fit in sub-34 (`knee`=−1, `exponent`≈0) and an extreme (though not divergent) fit in sub-31 (`knee`=6.8×10¹¹, `exponent`=8.09). Converting the fitted (knee, exponent) pair to a knee frequency (`knee^(1/exponent)`) placed it **inside the 13–30 Hz beta band itself** for 8 subjects (sub-01: 21.6 Hz; sub-11: 20.7 Hz; sub-31: 29.1 Hz; sub-02, 10, 13, 20, 33: 15–16 Hz) and in the alpha band (~8–13 Hz) for most others.
- **Diagnostic step taken before any decision:** a purely synthetic check (pure power-law aperiodic, offset 1.0/exponent 1.27, no knee, no beta, plus a simple alpha peak at CF=10, BW=2.5, PW swept 0/0.3/0.6/1.0, 20 reps/level, using the frozen simulation generator) did **not** reproduce the real-data pattern: median ΔBIC stayed below or only marginally above 0 (range −14.10 to 7.41 across all tested alpha heights), and knee was never selected (0/20 at every level). This rules out "a simple alpha peak alone, via this generator, explains the real-data knee preference" as the mechanism, but does not identify the true mechanism (candidates considered but not tested further: a genuine low-frequency aperiodic bend, a broader/multi-component alpha, high-frequency noise-floor shape — **the last of these turned out to be the right track; see §7**).
- **Decision (Amirhossein, 2026-10-30):** do not pursue further diagnostic testing (rejected options: constraining knee parameters to a physiologically plausible range post hoc; re-deriving the simulation generator to produce knee-shaped signals matching real data). Instead, **remove the knee model and the ΔBIC model-selection step entirely; the aperiodic model is fixed-only throughout the pipeline** (fitting and simulation generator alike).
  - Rationale: (a) a knee model whose derived frequency lands inside the band of primary interest (13–30 Hz) is not a credible description of "background" for this analysis regardless of its cause; (b) fixing the model removes the mismatch between the real-data model-selection behavior (almost always knee) and the simulation generator (always fixed), which had been silently invalidating the planned threshold calibration; (c) adding plausibility constraints on knee parameters instead would introduce new, more arbitrary thresholds with weaker defensibility than simply not using the knee model. (An earlier draft of this rationale also cited "standard practice" for this fit range as a reason; that claim was unverified and was removed from the pre-registration text on 2026-10-30, commit `03f40b1` — the decision itself did not depend on it.)
  - This decision was made after seeing real-data **aperiodic** fit statistics (never seen: any 13–30 Hz quantity, peak count, or peak height). Disclosed in the pre-registration text (§1 additional disclosure, §3.4) as a methods decision informed by an outcome-blind look at real data.
- **Code changes (all in `revision/stage4/`):**
  - `stage4_core.py`: `APERIODIC_MODE = 'fixed'` constant (replaces `DBIC_KNEE`); `K_PARAMS = 2` fixed; `select_model` removed entirely; `mode` argument removed from `_fooof`/`aperiodic_only`/`full_fit` (so any remaining caller expecting a knee branch fails loudly rather than silently). `BIC_fixed` still computed and reported but used in no decision.
  - `stage4_extraction_only.py`: output reduced to 13 columns — `subject, fs, n_pseudoepochs_total, n_pseudoepochs_kept, n_outside, excluded_D12, run_lengths_epochs, R2_fixed, BIC_fixed, offset_fixed, exponent_fixed, noise_2_12Hz, noise_31_40Hz`. `_meta.json` key `dbic_knee` replaced by `aperiodic_mode`.
  - `stage4_simulate_threshold.py`: `model_chosen` column removed.
  - `stage4_peak_detection.py`: `model_chosen` removed from the primary output table; `model_h1`/`model_h2` removed from split-half output.
  - Verified: no remaining reference to a knee code path anywhere in `revision/stage4/` (only explanatory comments noting its removal).
- **Tests (synthetic data only):** simulation `--test-reps 2` ran without error, no `model_chosen` column. Peak detection recovered an injected CF=20/PW=0.3 peak as [19.95, 0.29, 3.97]; split-half ran without error.
- **Real-data re-extraction:** re-run on the same 39 ROI files, output `stage4_extraction_fixedonly.csv` (new filename; old `stage4_extraction.csv` not overwritten). 39 rows, 0 excluded, no NaNs, exit code 0. `R2_fixed`/`BIC_fixed`/`offset_fixed`/`exponent_fixed` identical to the prior run (the fixed-model fit itself never changed — only which model was compared against it). Noise columns changed as expected, since they are now computed against the fixed-model residual instead of whichever model ΔBIC had picked: `noise_2_12Hz` mean 0.3006 (range 0.0628–0.6633; was 0.2225 under the old selection), `noise_31_40Hz` mean 0.0652 (range 0.0122–0.2011; was 0.0478).
- **Commit/tag:** fix committed as `4207162872790ca6c49d52610b820a489875d2a4`. Tag `S4-prereg-frozen` moved (`git tag -f`) from `bcbac0c` to `4207162`.
- **Superseded file (provenance only):** `Revision_Output\stage4\stage4_extraction.csv` (and its `_meta.json`) — the knee-era extraction output that the numbers in this section are drawn from. Not used in any downstream step.
- **Data-leakage check:** every statistic inspected during this investigation is an aperiodic-only quantity. No 13–30 Hz quantity was computed or viewed at any point.

## 7. Stage 4 — Threshold Calibration Redesign (`S4-threshold-redesign`, 2026-10-30/31)

Three linked revisions, in order, all made using only aperiodic/noise statistics and simulated-data results — never any real 13–30 Hz quantity.

### 7a. Per-subject spectral roughness (`S4-rough-sigma`)

**Found while comparing simulated-null aperiodic-residual noise to real `noise_31_40Hz`/`noise_2_12Hz` (`diag_noise_floor_null.py`, commit `d491057`), before any threshold existed.**

- **Symptom:** real `noise_31_40Hz` (a band with no alpha) was, per subject, a median of **2.92×** (range 0.67×–11.90×) the matched simulated null's residual SD; the real value exceeded the maximum of that subject's own 10 matched simulations in 31/39 subjects. `noise_2_12Hz`'s larger gap (median ratio 15.71×) was expected and already documented (simulation injects no alpha); the 31–40 Hz gap was not expected and meant the simulated null spectra were systematically smoother than real spectra even outside the alpha band.
- **Decision (Amirhossein, 2026-10-30):** add a per-subject multiplicative spectral-roughness factor to the generator rather than (i) shipping with the mismatch documented only as a limitation — rejected, because it leaves the primary threshold calibrated on unrealistically smooth nulls, inflating the true false-positive rate in an unknown, unquantified direction — or (ii) constraining/reshaping the aperiodic model further — rejected as an escalating, less transparent patch.
- **Design:** for each signal, draw one lognormal multiplicative factor (mean 1, i.e. `μ = −σ²/2` in natural log) per 0.5 Hz Welch-resolution bin (not per fine FFT bin — shown by a quick check to average away under Welch and need unrealistically large σ to show any effect), log-interpolated between bin centers (to avoid a bin-edge step artefact, Q1 option "c"), applied over all f ≥ 0.5 Hz (Q2), identically across all runs of one signal.
- **Calibration target:** initially the global median `noise_31_40Hz` (0.0549 — corrected from an earlier mistaken use of the mean, 0.0652); then, after this calibration is itself discussed (§7b below), **per subject**, each σ_i matched to that subject's own real `noise_31_40Hz` (not the global median) — because the project's standing principle has been to use each subject's own empirical values wherever possible (offset/exponent were already per-subject), and the cost of doing so here was modest (same order of compute as before).
  - Method: coarse grid (0, 0.05, …, 0.50 or, for 6 subjects whose target exceeded the σ=0.50 value, extended to 1.00), 50 reps/point, then refined with step 0.01 around the crossing; σ_i = the grid point minimizing |simulated median − real target|.
  - **Floor (5 subjects: sub-06, 16, 22, 23, 40):** real `noise_31_40Hz` (0.0122–0.0148) below even the σ=0 simulated median (~0.0168–0.0180) — σ_i = 0, flagged `floor=1`; the simulated null stays somewhat rougher than reality for these subjects, which is the safe direction (conservative, not FPR-inflating).
  - **Extended (6 subjects: sub-01 σ=0.86, sub-27 σ=0.54, sub-19 σ=0.53, sub-31 σ=0.52, sub-39 σ=0.51, sub-13 σ=0.50):** real value exceeded the σ=0.50 simulated median; grid extended to 1.00. **Ceiling (σ_i unresolved even at 1.00): 0 subjects** — no subject required manual intervention.
  - Fit quality: median absolute error ≈0.0004–0.0010 across all 39 (worst case sub-33: 0.1161 sim vs 0.1151 real).
  - **Known limitation (documented, not fixed):** σ_i is calibrated to each subject's own `noise_31_40Hz`, which is itself a single noisy per-subject estimate — part of σ_i therefore reflects sampling error in that one estimate, not only true subject-level roughness. The roughness factor also only matches the *size* (SD) of real deviations, not their *shape*/frequency-correlation structure, and is assumed uniform across the whole 2–40 Hz range (unverifiable without looking at 13–30 Hz).
- **Commits/tag:** `2923dc2` (per-subject σ generator + `stage4_calibrate_rough_sigma.py`); `f73dcda` (the earlier, abandoned global-σ=0.21 diagnostic script, kept as provenance). Tag `S4-prereg-frozen` moved to `f73dcda`.
- **Data-leakage check:** only `noise_31_40Hz` (aperiodic-only, real) and simulated-null aperiodic statistics were used. No 13–30 Hz quantity, real or simulated, was involved in calibrating σ_i.

### 7b. Per-subject threshold replaces the pooled threshold (`S4-per-subject-threshold`)

**Found after running the full ~429,000-simulation threshold calibration with per-subject σ_i (`sim_rough/`), before any real 13–30 Hz quantity was computed.**

- **Symptom:** the pooled threshold (95th percentile of all 39,000 null simulations together) came out at **0.4545** (vs. 0.0633 without roughness) — almost entirely driven by the single roughest subject, sub-01 (σ_i=0.86): of the 1,950 null simulations exceeding this threshold (5% of 39,000 by construction), **874 (≈45%) came from sub-01 alone**. Checking each subject's false-positive rate under this one pooled threshold: 28/39 subjects had FPR=0 (their own null almost never reaches 0.4545) and **8/39 had FPR>5%** (up to 87.4% for sub-01 itself) — i.e. the pooled threshold was simultaneously far too conservative for most subjects (power near 0 up to PW=0.30) and still not conservative enough for the roughest few.
- **Decision (Amirhossein, 2026-10-31):** replace the single pooled threshold with **one threshold per subject**, each the 95th percentile of that subject's own 1,000 null simulations (same for p90/p99, §3.5.2). Rejected: (i) keeping the pooled threshold with this documented as a limitation — the resulting power curve (power <20% up to PW=0.30) would mechanically bias the paper's primary finding toward "most subjects have no stable beta peak," which is not a result a reviewer should accept from a miscalibrated detection criterion; (ii) reverting to the single global σ=0.21 (§7a's abandoned alternative) — this does not fix the underlying issue, since it still does not match sub-01's real roughness (0.2011) and would simply relocate, not remove, the mismatch; (iii) excluding or down-weighting rough subjects by an ad hoc σ cutoff — introduces a new, more arbitrary and less defensible threshold than per-subject calibration itself.
- **Result (per-subject thresholds, from own null, N=1000 each):** p95 min 0.0619 (sub-22), median 0.2174, max 0.8710 (sub-01). Each subject's own-threshold FPR is, by construction, exactly 0.0500 (an internal consistency check, not an independent estimate — an independent re-estimate would need a fresh null with a different seed).
- **Detection-power curve** (pooling all 390,000 injected simulations, each classified against its own subject's p95): PW=0 (null): 0.0500 (CP 95% CI 0.0479–0.0522); 0.05: 0.2236; 0.10: 0.4454; 0.15: 0.5822; 0.20: 0.6784; 0.25: 0.7588; 0.30: 0.8192; 0.35: 0.8683; 0.40: 0.9053; 0.45: 0.9323; 0.50: 0.9526 (CI 0.9505–0.9547). Logistic (BFGS, converged): b0=−1.2287, b1=9.0652. `fit_failed`: null 0/39,000; injected 2/390,000.
- **Commit/tag:** `4e48a03`. Tag `S4-prereg-frozen` moved to `4e48a03`. `stage4_peak_detection.py` now reads a per-subject threshold file (`thresholds_per_subject.json`) and refuses to run if any retained subject is missing a threshold.
- **Superseded, kept as provenance:** `sim_rough/thresholds.json` (the pooled threshold, 0.4545) and all of `sim\` (the pre-roughness pooled run, 0.0633).
- **Data-leakage check:** only simulated null/injected data and real-data aperiodic/noise statistics were used throughout.

### 7c. Half-length threshold for split-half (`S4-half-threshold`)

**Raised as a concern alongside 7b, confirmed by a dedicated simulation before any code change (`stage4_simulate_half_threshold.py`).**

- **Concern:** the per-subject threshold (7b) is calibrated on null signals matching each subject's *full* kept-epoch count. The split-half analysis (§3.8) halves that count, which increases genuine PSD-estimation variance (fewer Welch windows) independently of σ_i — using the full-length threshold on half-length data would likely push every subject's half-analysis FPR above 5%, worst for the smoothest subjects (smallest threshold, so the added variance is relatively largest).
- **Verification:** for each subject (and, where `n_kept` is odd, both resulting half-sizes — 8 subjects: sub-05, 08, 13, 17, 22, 26, 35, 38 — 47 "cells" in total, not 39), generated 1,000 null simulations at the half's actual epoch count, same σ_i, seed `SeedSequence(20261103, spawn_key=(pair, n_epochs))`, resumable via `parts_half/`. Result: the half-length p95 exceeded the full-length p95 in **all 47/47 cells** (ratio min 1.094, median 1.203, mean 1.342, max 2.009 for sub-01; absolute difference min 0.0340, median 0.0478, max 0.1689). Spearman ρ(σ_i, ratio) = **−0.929**: smoother subjects (σ_i near 0) are hit relatively hardest (threshold roughly doubles, e.g. sub-16/22 ≈0.06→≈0.12), confirming the concern was general, not specific to one subject. `fit_failed` in this run: 0/47,000.
- **Decision (Amirhossein, 2026-10-31):** use a dedicated half-length, per-subject threshold (`thresholds_per_subject_half.json`) for split-half classification, not the full-length threshold — fixed properly rather than only documented, since the fix reused existing σ_i (no re-calibration) and cost well under an hour.
- **Commits/tag:** `0d53db6` (`stage4_peak_detection.py` reads half-length thresholds in split-half; `stage4_simulate_half_threshold.py` added); `bd96a95c175ddcb04af225a2716b56a52e9f8087` (`stage4_compare_half_full_thresholds.py`, the documentation/comparison script, moved from scratchpad into `revision/stage4/` per the repo's traceability convention). Tag `S4-prereg-frozen` moved to `bd96a95c175ddcb04af225a2716b56a52e9f8087` — **current tag position**.
- **Data-leakage check:** only simulated null data (aperiodic + roughness, no beta) was used; no 13–30 Hz quantity, real or simulated, entered this decision.

**Status as of this entry:** code frozen at `bd96a95`; `docs/zenodo_preregistration_stage4.md` §3.5, §3.5.2, §3.6, §3.8 have now been rewritten to describe this redesign (done — see that file); `__pycache__/` added to `.gitignore` (confirm/apply per the sync instructions accompanying this file). Nothing has been deposited to Zenodo yet. No real 13–30 Hz quantity has been computed or viewed at any point in §7.

## File locations (as of 2026-10-31)
- Decision log: `github/eeg-beta-project/docs/decision_log.md` (repo `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`).
- Pre-registration: `github/eeg-beta-project/docs/zenodo_preregistration_stage4.md` (same repo/branch).
- Implementation: `github/eeg-beta-project/revision/stage4/` — `stage4_export_roi.m`, `stage4_core.py`, `stage4_extraction_only.py`, `stage4_simulate_threshold.py`, `stage4_calibrate_rough_sigma.py`, `stage4_simulate_half_threshold.py`, `stage4_peak_detection.py`, `stage4_compare_half_full_thresholds.py`, plus the diagnostic scripts `diag_noise_floor_null.py` and `diag_calibrate_rough_sigma.py` (superseded design, provenance only).
- Local repo root: `C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\github\eeg-beta-project`. Stage-3 bundles and Stage-4 outputs live under `D:\Revision_EEG\...` / `C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output\stage4\...`.
- Official Stage-4 extraction-only output: `Revision_Output\stage4\stage4_extraction_fixedonly.csv` + `_meta.json`.
- Official Stage-4 threshold outputs (post-§7): `Revision_Output\stage4\sim_rough\thresholds_per_subject.json`, `thresholds_per_subject_half.json`, `rough_sigma_per_subject.csv`, plus `sim_null.csv`/`sim_injected.csv`/`sim_null_half.csv`. Superseded/provenance-only: `sim\` (no roughness), `sim_rough\thresholds.json` (pooled threshold with roughness).

## Next steps
1. ~~Rewrite `docs/zenodo_preregistration_stage4.md` §3.5, §3.5.2, §3.6, §3.8 to describe the §7 redesign.~~ Done.
2. Add `revision/stage4/__pycache__/` to `.gitignore` — confirm/apply via the sync instructions delivered with this file.
3. Deposit the pre-registration text + frozen code (`bd96a95`) to Zenodo, obtain DOI.
4. Log the DOI here.
5. Only after the DOI is logged: run `stage4_peak_detection.py` (with `--doi`) on real ROI data — Amir runs this step himself.
