
# Decision Log — Stage 3 Close, Stage 4 Decisions & Stage 5

Date: 2026-10-26 (Stage 3 close) / 2026-10-27 (Stage 4 decided) / 2026-10-30–31 (spec details + package resolved; code frozen; boundary-event bug fixed; fixed-only aperiodic model adopted; threshold calibration redesigned twice; extraction and simulation run on real/simulated data; Zenodo DOI registered; real-data peak-detection run completed) / 2026-11-01 (Stage 5 begun: architecture, SOA premise corrected, task boundary fix, task ROI export, outcome-blind task extraction and diagnostics — §10)
Commits: `d7176e8..30ed2ea` (pushed, Stage 3); pre-registration text: `47d8b8c`, `1d0b05c`, `36ab9e5`, `890ae1b`, `884d457`, `03f40b1` (not yet pushed); code: `be6f091` (superseded) → `bcbac0c` (superseded) → `4207162` (superseded) → `2923dc2` → `f73dcda` → `4e48a03` → `0d53db6` → `bd96a95c175ddcb04af225a2716b56a52e9f8087` tagged `S4-prereg-frozen` (annotated tag; Stage-4 code, not yet pushed to remote as of this writing — local branch `revision-v2` is ahead of `origin/revision-v2`; tag moved via `git tag -f` five times on 2026-10-30/31 — see §5, §6, §7). Zenodo deposit published 2026-10-31: DOI **10.5281/zenodo.23843194** (see §8). DOI logged in repo at commit `9c53d5f85bf0e171207b7eae396890cc2f5d2548` (one commit after the frozen tag, text-only per §5's own note); real-data peak-detection run at that same commit (working tree clean) — see §9.
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

## 2. Stage 4 Decisions (`S4-decided`) — FINAL, DOI registered (§8), results obtained (§9)

Decided 2026-10-27, talked through item by item (Amir chose/confirmed each).

| Topic | Final decision |
|---|---|
| Spectral estimator & pseudo-epochs | Welch, 2s Hann window, 50% overlap (matches v1, for direct comparability). Decision unit = mean PSD over a 7-channel ROI: **C3, Cz, C4, FC1, FC2, CP1, CP2** (central/sensorimotor strip). ROI chosen a priori from independent literature on resting beta/mu topography (Pfurtscheller & Lopes da Silva, 1999), explicitly NOT from the v1 task-based Fz/Cz/C4 finding (that selection was outcome-driven on this same dataset and would have been circular). Single-channel results reported as secondary only. |
| Aperiodic model & frequency range | **Superseded 2026-10-30 — see §6.** (Originally: fit range 2–40 Hz, fixed default, knee selected if ΔBIC > 10. Replaced with fixed-only throughout, for the reasons in §6.) |
| Peak criterion | At least one Gaussian with center in [13, 30] Hz, width in [1, 8] Hz, height ≥ calibrated threshold. **Threshold is now per-subject, see §7** (originally planned as one pooled threshold — superseded). If multiple Gaussians fall in range, the tallest (highest power) is the primary peak; others reported as secondary/sensitivity. Alpha-harmonic rule (2×IAF) kept as a sensitivity analysis only. |
| Simulation for threshold calibration | **Superseded 2026-10-30/31 — see §7.** (Originally: one pooled threshold = 95th percentile of the null distribution pooled across all 39 subjects' empirical (offset, exponent) pairs. Replaced with per-subject calibration, including a per-subject spectral-roughness parameter and a per-subject threshold, for the reasons in §7.) |
| Leakage prevention | A separate "extraction-only" script computes, from real data, only: fit-quality stats, aperiodic parameters, and noise-floor power from 2–12 Hz and 31–40 Hz residuals (column set updated per §6 — fixed-model only). No 13–30 Hz output or peak count/height is computed or stored. Peak-detection code on real data is committed and frozen (tagged `S4-prereg-frozen`) before the Zenodo DOI is obtained, and additionally refuses to run without a `--doi` argument matching a DOI already logged here (and not equal to the v1 archive DOI). **Executed 2026-10-31 — see §9.** |
| Zenodo pre-registration | Order: finalize protocol text + code → commit with tag → upload to Zenodo (code + pre-registration text) → obtain DOI → run Stage-4 analysis on real data → log DOI in this decision log. **Completed in full — see §8 (DOI) and §9 (results).** Pre-registration text explicitly discloses that v1 results on this same dataset were already known to the author, and that the ROI/criteria here were chosen independently of those results (not from the data-driven Fz/Cz/C4 selection). |

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
- **Commits/tag:** `0d53db6` (`stage4_peak_detection.py` reads half-length thresholds in split-half; `stage4_simulate_half_threshold.py` added); `bd96a95c175ddcb04af225a2716b56a52e9f8087` (`stage4_compare_half_full_thresholds.py`, the documentation/comparison script, moved from scratchpad into `revision/stage4/` per the repo's traceability convention). Tag `S4-prereg-frozen` moved to `bd96a95c175ddcb04af225a2716b56a52e9f8087` — current frozen code commit (verify with `git rev-parse S4-prereg-frozen^{commit}`, since this is an **annotated** tag — bare `git rev-parse S4-prereg-frozen` returns the tag object's own hash, not the commit hash).
- **Data-leakage check:** only simulated null data (aperiodic + roughness, no beta) was used; no 13–30 Hz quantity, real or simulated, entered this decision.

**Status as of this entry:** code frozen at `bd96a95`; `docs/zenodo_preregistration_stage4.md` §3.5, §3.5.2, §3.6, §3.8 still need to be rewritten to describe this redesign (pending as of this point in the log); `__pycache__/` to be added to `.gitignore`. Nothing had yet been deposited to Zenodo at this point. No real 13–30 Hz quantity has been computed or viewed at any point in §7. (Both items resolved 2026-10-31 — see §8.)

## 8. Zenodo DOI Registered (`S4-doi-registered`, 2026-10-31)

- **Pre-registration text rewrite:** `docs/zenodo_preregistration_stage4.md` §1 (further disclosure), §3.5.2, §3.6, §3.8 rewritten to fully describe the §7 threshold-calibration redesign (per-subject roughness, per-subject threshold, half-length threshold) — confirmed complete prior to deposit.
- **`.gitignore`:** `revision/stage4/__pycache__/` confirmed added (was missing; added and committed on the local machine, 2026-10-31).
- **Frozen-code archive:** built via `git archive --format=zip ... S4-prereg-frozen -- revision/stage4` from the annotated tag (dereferences to commit `bd96a95c175ddcb04af225a2716b56a52e9f8087`); verified identical to that commit's `revision/stage4` tree via `git diff bd96a95c175ddcb04af225a2716b56a52e9f8087 S4-prereg-frozen -- revision/stage4` (empty diff).
- **Zenodo deposit:** published 2026-10-31 by Amirhossein, manually via the Zenodo web UI. Two files: `stage4_frozen_code.zip` (the above archive) and `zenodo_preregistration_stage4.md` (the rewritten pre-registration text). Title "Resting-State Beta-Peak Detection Criterion - Stage 4 Pre-Registration and Frozen Analysis Code (Nencki-Symfonia MSIT+ EEG)"; author Feizi, Amirhossein (ORCID 0000-0001-8929-0910); upload type Software; version string `S4-prereg-frozen (commit bd96a95c)`.
- **DOI:** **10.5281/zenodo.23843194** (https://doi.org/10.5281/zenodo.23843194). Verified: matches the required `10.5281/zenodo.<number>` format; not equal to the v1 archive DOI (`10.5281/zenodo.22232799`); record content (title/author/files/version) confirmed by fetching the Zenodo record page before logging here.
- **This satisfied the `stage4_peak_detection.py` DOI gate (§3.7/§4):** once logged in `docs/decision_log.md` in the actual repo (commit `9c53d5f85bf0e171207b7eae396890cc2f5d2548`), the script's `--doi 10.5281/zenodo.23843194` argument passed all three checks (format, ≠ v1 DOI, present in decision log) — confirmed by the successful run in §9.

## 9. Stage 4 — Real-Data Peak-Detection Results (`S4-results`, 2026-10-31)

**First point in the project where any 13–30 Hz quantity has been computed or viewed.** Run after §8's DOI was both registered and synced into the actual repo's `docs/decision_log.md` (commit `9c53d5f85bf0e171207b7eae396890cc2f5d2548`, local branch `revision-v2`, working tree clean, `revision/stage4/` content unchanged from `bd96a95` per §8's own diff check).

- **Command:** `stage4_peak_detection.py --doi 10.5281/zenodo.23843194 --roi-dir D:\Revision_EEG\stage4\roi --thresholds ...\sim_rough\thresholds_per_subject.json --half-thresholds ...\sim_rough\thresholds_per_subject_half.json --out-dir ...\Revision_Output\stage4\peak_detection`. DOI gate passed (all three checks). `fooof` 1.1.1 deprecation warning only (cosmetic, package fully functional per pre-registration §3.4).
- **Data integrity:** all 39 subjects `fit_ok=1` (no real-data fit failures anywhere); `excluded_D12=0` for all 39 (matches §5); `n_pseudoepochs_kept` per subject consistent with §5's export results.

**Primary classification (p95 threshold, the pre-registered primary criterion):**

| Class | n | % |
|---|---|---|
| peak | 24 | 61.5% |
| no_peak | 14 | 35.9% |
| poor_fit | 1 (sub-34, R²=0.8035 < 0.90, §3.5.1) | 2.6% |

**Contrast with v1:** v1's uncalibrated argmax approach found 20–22/42 (~48–52%) with no stable beta peak. Here, under the pre-registered, simulation-calibrated criterion, only 14/39 (35.9%) show no peak — i.e. a **majority (61.5%) show a stable beta peak**, the opposite qualitative impression from v1. This is exactly the comparison §1 of the pre-registration anticipated reporting.

**Threshold-grid sensitivity (§3.5.2, secondary):**

| Threshold | peak | no_peak | poor_fit |
|---|---|---|---|
| p90 | 26 | 12 | 1 |
| p95 (primary) | 24 | 14 | 1 |
| p99 | 21 | 17 | 1 |

Classification shifts by only 2–3 subjects across the threshold grid — the primary result is not a knife-edge artifact of the exact p95 choice.

**Split-half reliability (§3.8):** `n_poor_fit_either`=1 (sub-34, poor-fit in both halves, excluded per protocol) → `n_evaluable`=38. **Agreement rate 37/38 = 97.4%** — only **sub-08** disagrees between halves (h1=peak, h2=no_peak). Among the 20 subjects classified peak in **both** halves, **ICC(2,1) of peak height (PW) = 0.919** — "excellent" reliability per Koo & Li (2016). The 8 subjects with an odd kept-epoch count (sub-05, 08, 13, 17, 22, 26, 35, 38) split into unequal half-lengths exactly as predicted in §7c.

- **Secondary observation (not a protocol violation):** three subjects (**sub-05, sub-21, sub-31**) are classified "peak" on the full data but "no_peak" in **both** halves. This is consistent with §3.8's definition of agreement (between the two halves, not between primary and halves) and with the half-length threshold being calibrated higher than the full-length threshold (§7c) — expected to occasionally pull a full-data peak below both half thresholds even when the halves agree with each other.

**Alpha-harmonic sensitivity flag (§3.5, D14 — exploratory only, not part of the primary criterion):** of the 24 primary (p95) peaks, **19/24 (79%)** have center frequency within 2×IAF ± 2 Hz of that subject's own alpha peak, i.e. flagged as possible alpha harmonics rather than independent beta oscillations (non-harmonic primary peaks: sub-03, 23, 24, 30, 40). This was pre-specified as a sensitivity/exploratory output (§3.5), so reporting it is not a deviation — but the fraction is large enough that it should be discussed explicitly alongside the 61.5% headline figure in the manuscript, rather than left as a footnote; it bears directly on whether "beta peak" and "independent beta oscillation" can be equated in this dataset. No methods decision has been revisited because of this — per the §4 deviation policy, that determination is left for manuscript-writing discussion, not for retroactively altering the frozen criterion.

- **Output files** (`Revision_Output\stage4\peak_detection\`): `run_meta.json` (full thresholds/half-thresholds/git state), `peaks_primary.csv` (per-subject primary result + p90/p95/p99 classification), `peaks_all_in_range.csv` (every detected Gaussian in [13,30] Hz, with alpha-harmonic and threshold-grid flags), `sensitivity_counts.csv`, `split_half.csv` (per-half detail), `split_half_summary.json` (agreement rate, ICC).
- **Not yet done:** no methods decision has been revisited based on this result. Any future change to ROI/threshold/model after this point must be disclosed per §4 as a post hoc, exploratory departure — the primary analysis above stands as the pre-registered result regardless.

## 10. Stage 5 — Task-Based Exploratory Analysis (`S5-*`, 2026-11-01)

Stage 5 is **exploratory** throughout: it extends the already-registered Stage-4 framework to the MSIT+
task period and does not re-litigate an independent confirmatory claim. No second Zenodo deposit or DOI
gate is required (Amirhossein's call, 2026-11-01), but the same discipline as Stage 4 applies in full:
outcome-blind extraction first, freeze-then-run before any real 13–30 Hz task quantity is viewed, a
data-leakage check at every decision, and every decision logged here at the §1–§9 level of detail.

### 10a. Two-track architecture (`S5-architecture`)

**Decision (Amirhossein, 2026-11-01):** Stage 5 splits into two tracks with genuinely different
requirements, because the task is trial-structured while Stage 4's peak criterion needs long segments:

| | Track A | Track B |
|---|---|---|
| Question | does band-average beta power differ across the 4 MSIT+ conditions? | is a discrete beta peak present during the task period overall (condition-collapsed)? |
| Unit | one segment per trial, locked to the condition marker | 2 s non-overlapping pseudo-epochs from the start of each task block (not trial-locked) |
| Needs fine frequency resolution | no (band average only) | yes (Stage-4 peak criterion) |
| Second Zenodo deposit | no | no |

- **ROI for both tracks: the same 7 Stage-4 channels** (C3, Cz, C4, FC1, FC2, CP1, CP2), **not** the
  Fz/Cz/C4 of v1's `msit_beta_power_by_condition.m` / `msit_beta_erd_by_condition.m`. That v1 selection
  was made from v1's own task result on this same dataset — exactly the circularity Stage 4's a-priori,
  literature-based ROI (§2) was designed to avoid. Keeping the independent ROI also keeps rest and task
  on the same decision unit.
- **D12 unchanged** (Fz/Cz/C4, 150 µV peak-to-peak, subject excluded below 50 % kept): a project-wide
  artifact rule, independent of the analysis ROI (§3, `S4-D12-rest` note).
- **Rejected: a full per-condition discrete-peak criterion** (a per-condition parallel to Stage 4). Under
  the trial structure it would require redesigning the whole Welch-window/frequency-resolution approach
  from scratch, with a real risk of several iteration rounds like §7's three. Deferred as a possible
  future extension, explicitly not part of the current manuscript revision.
- **Data-leakage check:** this is an architecture decision taken before any task spectrum was computed;
  no 13–30 Hz quantity, real or simulated, was involved.

### 10b. SOA survey — a corrected premise and the Track-A segment length (`S5-soa`)

**Found while pinning down the Track-A segment length over all 39 subjects instead of the single
sub-01 sample the architecture had been drafted from (`revision/stage5/stage5_soa_survey.py`).**

- **Symptom / corrected premise:** the architecture above was drafted on the understanding that the
  stimulus-onset asynchrony (SOA) between consecutive MSIT+ condition markers is **870–1070 ms**, from a
  sample of sub-01 — which is why a 2 s Welch window was described as not fitting inside a single trial.
  The full survey of all 39 subjects gives, over the 15,024 within-block SOAs of 15,492 analysed trials:
  **min 1733 ms**, p01 1733, p05 1734, median 2034, mean 2339, p95 4467, max 5433 ms. The minimum is
  **exactly 1733 ms in every one of the 39 subjects** — a hard floor of the design, not a per-subject
  property.
- **Cause of the discrepancy:** the earlier figure was in **samples at 500 Hz**, not milliseconds
  (870 samples = 1740 ms, 1070 samples = 2140 ms — consistent with this survey's floor of 1733 ms and
  median of 2034 ms). A factor-of-2 unit error. No decision had yet depended on the number, and the
  survey was run precisely because the brief asked for the minimum to be recomputed over the full
  dataset before fixing the segment length.
- **Consequence for the architecture:** Track B is **unaffected** (it is not trial-locked: it segments
  continuous task blocks, so the SOA never constrained it). Track A is **less constrained** than assumed:
  any segment up to ~1.1 s is unconditionally safe, where ~0.6–0.7 s had been expected.
- **Decision (Claude, 2026-11-01): the Track-A segment is `[0, +1000) ms` from the condition marker**
  (500 samples at 500 Hz).
  - Rationale: (i) **zero** of the 15,492 within-block trials have a 1000 ms forward window that reaches
    the next condition marker or leaves its clipped task block — the same holds at every duration up to
    1100 ms; the first clipping appears at 1200 ms (1 trial) and the first overlap at 1800 ms (1,349
    trials). (ii) It covers the stimulus→response interval for about 95 % of trials (response time, from
    `events.tsv`, median 602 ms, p95 934 ms), i.e. the interval in which movement-related beta
    desynchronization is expected (Pfurtscheller & Lopes da Silva, 1999). (iii) It is a round number
    fixed before any task beta quantity was computed, with a 733 ms margin to the SOA floor.
  - **Rejected: ~600–700 ms** (the brief's starting suggestion): its only justification was the mistaken
    870 ms minimum, and at 600 ms the window would end before the response in roughly half the trials
    (RT median 602 ms), measuring mostly pre-response anticipation rather than the movement-related
    window the track is named for.
  - **Rejected: ~1500 ms** ("the longest that still fits, with a margin"): it straddles the post-movement
    beta rebound (ERS, typically beginning a few hundred ms after movement; RT p95 934 ms + rebound onset
    lands inside such a window), mixing a desynchronization and a resynchronization period in one
    average, which would dilute any condition difference in an uncontrolled way.
  - **Rejected: a response-locked window:** a different design (and the usable-trial count would then
    depend on the response itself); out of scope for this track.
- **Open item requiring Amirhossein's sign-off (flagged 2026-11-01, not decided here):** Track A as
  approved in 10a measures **absolute band power in a post-onset window**. It is therefore neither (i)
  the baseline-normalized ERD of v1's `msit_beta_erd_by_condition.m` (baseline −0.2–0 s, post 0.2–0.6 s),
  nor (ii) the **pre-stimulus** window that `revision_plan.md` steps 1–2 and audit items B/C are about.
  The corrected SOA floor of 1733 ms means a pre-stimulus window (e.g. −500–0 ms) now fits comfortably
  inside every trial alongside the post-onset window, which was not thought possible when 10a was
  approved. Whether Track A should be extended to carry a pre-stimulus window (and the mini-block
  first-vs-later split of `revision_plan.md` step 2) is a scope decision for the manuscript, not a
  technical call, so it is left open here. Track B does not depend on it.
- **Outputs** (`Revision_Output\stage5\`): `stage5_soa_per_subject.csv`, `stage5_soa_candidates.csv`,
  `stage5_soa_summary.json`.
- **Data-leakage check:** the survey reads only `*_task-msit_events.tsv` (small text files, freely
  readable per the project's raw-data rule) and the Stage-3 block-clipping table. No EEG sample is read,
  no spectrum is computed, and no 13–30 Hz quantity exists anywhere in this step.

### 10c. Boundary-event fix and task ROI export (`S5-export-task`)

**The §5 flag ("the leading-boundary pattern has not yet been checked in the MSIT/task bundles") is now
resolved: the pattern is present there too.**

- **Symptom:** every one of the 39 `P2.msit` bundles carries two `boundary` events at latency 0.5 and
  1.0 at the very start of the recording — identical to `P2.rest` (§5), and an artefact of the same
  Stage-3 cropping. Confirmed by reading `P2.msit.event` latencies directly. Because the first task
  block's `task_b1_start` is at latency 1, pseudo-epoch 1 of block 1 would be reported "outside" by
  `stage3_d12_trials` in every subject without a fix.
- **Decision:** apply the **same fix as §5, in the same way** — in the new Stage-5 export script only,
  on the helper's input copy, removing `boundary` events with `latency <= 1`. `stage3_d12_trials` and
  its assert are untouched, as is the frozen `revision/stage4/stage4_export_roi.m`.
  - Rejected (as in §5): loosening the assert, which would silently drop one pseudo-epoch per subject
    for no real discontinuity; and fixing the shared Stage-3 helper, which is tested, committed code
    used elsewhere.
- **New script:** `revision/stage5/stage5_export_roi_task.m`, a Stage-5 copy of
  `stage4_export_roi.m` with `cond='msit'`, `task_bK_start/_end` block markers, output
  `<eegOutRoot>/stage5/roi/<sub>_msit_roi.mat` and the extra bookkeeping fields `cond`, `nBlocks`,
  `runBlock`. Everything else — ROI, 2 s non-overlapping pseudo-epochs from each block start, the
  incomplete block tail counted as "outside", D12 channels/threshold, the 50 % rule, the contiguous
  kept-epoch run export — is unchanged, so rest and task PSDs are produced by the identical shared
  Python pipeline.
  - The frozen Stage-4 script is **copied, not parameterised**: `revision/stage4/` is deposited on Zenodo
    (DOI 10.5281/zenodo.23843194) and must stay byte-identical to the frozen tag.
- **Verification on sub-01** (as in §5): 12 task blocks, 526 pseudo-epochs, 513 kept, **12 "outside" —
  exactly one per block, i.e. only the incomplete block tails**, so pseudo-epoch 1 is no longer outside
  and the fix works; 1 epoch rejected by D12; `fracKept` 0.99805; not excluded; 12 contiguous runs
  (44;44;42;40;44;45;45;41;39;40;45;44).
- **Data-leakage check:** the export script computes no spectral quantity of any kind (it is the same
  outcome-blind code as §5); only event latencies, epoch counts and time-domain peak-to-peak amplitudes
  (the D12 artifact rule) are used.

**Real-data export results (`stage5_export_roi_task.m`, all 39 subjects, post-fix):**

| | Value |
|---|---|
| `<sub>_msit_roi.mat` files | 39/39, all read without error by `load_roi` (483 MB total) |
| Task blocks per subject | 12 for 36 subjects; 9 (sub-21), 13 (sub-29), 14 (sub-23) |
| Pseudo-epochs, total / kept | 20,170 / 19,449 |
| `nKept` per subject | min 388 (sub-21), median 502, max 545 (sub-29) |
| `fracKept` | mean 0.9873, min 0.9173 (sub-34), max 1.0000 |
| Pseudo-epochs rejected by D12 | 253 total, across 25 subjects; highest sub-34 (42), sub-06 (40), sub-07 (40), sub-14 (38) |
| Pseudo-epochs "outside" | 468 total; **`n_outside == n_blocks` in every one of the 39 subjects** — i.e. exactly the one incomplete tail of each block, and pseudo-epoch 1 was never outside: the boundary fix is verified on the whole sample, not just sub-01 |
| Contiguous kept-epoch runs | min 9, median 13, max 45 per subject |
| Subjects excluded by D12 (<50 % kept) | **0** |

All 39 proceed to extraction. Compared with rest (§5: `fracKept` mean 0.9925, 87 epochs rejected across
16 subjects), the task has somewhat more D12 rejection (253 across 25 subjects) — expected, since the
task involves button presses and sustained posture, and D12's channels are Fz/Cz/C4.
Consolidated manifest: `Revision_Output\stage5\manifest_roi_task_all39.tsv` (the per-subject manifests
written by each run sit next to the `.mat` files, as in Stage 4).

### 10d. Track B calibration plan and pre-specified decision rules (`S5-trackB-plan`)

**Written before the task extraction was run, i.e. before any task spectral quantity existed** (CLAUDE.md
rule 8: the decision rule of an analysis is recorded before the analysis). Nothing in this subsection was
informed by a task PSD, fit statistic or 13–30 Hz value.

**Calibration path — the frozen Stage-4 code is reused verbatim.** Inspecting the five Stage-4 scripts
showed that only `stage4_peak_detection.py` hard-codes anything rest-specific (the `sub-*_rest_roi.mat`
glob and the DOI gate). `stage4_core.py`, `stage4_calibrate_rough_sigma.py`,
`stage4_simulate_threshold.py`, `stage4_per_subject_thresholds.py`, `stage4_simulate_half_threshold.py`
and `diag_noise_floor_null.py` are all parameterised by `--extraction` / `--rough-sigma` / `--sim-dir` /
`--out-dir`, and `stage4_core.load_roi` reads only variable names that the task export also writes. They
are therefore run **unchanged** on the task tables, into new output directories.
- Rationale: the statistically critical path (generator, Welch, fooof fit, percentiles, ICC) stays
  byte-identical to the implementation deposited on Zenodo. Only three thin Stage-5 files are new:
  `stage5_export_roi_task.m`, `stage5_extraction_only_task.py` (the rest-specific glob) and
  `stage5_peak_detection_task.py` (the glob plus the freeze gate below).
- Rejected: parameterising the Stage-4 scripts with a `--pattern`/`--seed` flag — `revision/stage4/` must
  stay byte-identical to tag `S4-prereg-frozen` / the Zenodo deposit.
- **Known, accepted consequence of reusing the scripts unchanged:** their seed constants (`SEED =
  20261030` / `20261102` / `20261103`) are module-level, so the task runs draw from the same seed streams
  as the rest runs. Because `simulate_runs` draws the roughness factors first and their count depends only
  on `fs`, subject *i*'s roughness pattern is shared between its rest and task nulls (the white noise is
  not: the run lengths differ). This makes each subject's rest and task thresholds paired rather than
  independent. It does **not** affect the validity of either threshold — each is still the 95th percentile
  of its own correctly-specified null — and for a rest-vs-task comparison pairing is if anything
  favourable. Documented rather than fixed, because fixing it would mean editing frozen code.

**Freeze gate (the Stage-5 substitute for Stage 4's DOI gate).** Stage 5 needs no second deposit, so
`stage5_peak_detection_task.py` refuses to run unless (1) `--frozen-tag` names an existing git tag,
(2) that tag's commit is HEAD, (3) `revision/stage5` and `revision/stage4` have no uncommitted changes,
and (4) the tag name already appears in this decision log. The planned tag is **`S5-task-peak-frozen`**
(named here so the gate can find it). This makes "freeze, document, then run" mechanical rather than a
matter of good intentions.

**Pre-specified decisions, settled now so that no branch is chosen after seeing a result:**
1. **Aperiodic model: fixed-only, unconditionally.** The brief asked whether ΔBIC still prefers the knee
   model for task data. §6's decision was *not* "knee loses on this dataset" — it was that a knee model
   whose derived knee frequency lands inside the 13–30 Hz band of interest is not a credible description
   of background for this analysis **regardless of cause**, and the knee branch was removed from the
   pipeline entirely. That reasoning transfers to the task unchanged, so there is no model selection to
   re-run and no branch to take. For **disclosure only**, a clearly-labelled Stage-5 diagnostic
   (`stage5_diag_knee_task.py`) fits a knee model to the task ROI spectra outside the pipeline and reports
   ΔBIC and the derived knee frequency per subject. Its numbers are **used in no decision** (the same
   status as `BIC_fixed` in §3) and it cannot affect the pipeline, which has no knee code path.
2. **Roughness σ_i: recalibrated from task data, unconditionally.** Task σ_i comes from
   `stage4_calibrate_rough_sigma.py` on the task extraction, matched to each subject's own task
   `noise_31_40Hz`. Rest's σ_i are **not** reused. `diag_noise_floor_null.py` is run on the task
   extraction as well, but only to *document* the size of the real-vs-simulated roughness mismatch for
   task (§7a reported median 2.92× for rest); it does not gate the calibration. Pre-specifying
   unconditional recalibration avoids a post hoc "the mismatch looked small enough" judgement.
3. **Threshold: per-subject p95, primary; pooled threshold reported for comparison only.** §7b's
   single-outlier dominance is expected to recur; whether it does is reported, not re-litigated.
   p90/p99 are the threshold-grid sensitivity, as in §3.5.2.
4. **Split-half: the subject's own half-length p95** (§7c), unconditionally, from
   `stage4_simulate_half_threshold.py` on the task extraction.
5. **Rest-vs-task sensitivity rule (written before either power curve exists).** Task subjects have more
   pseudo-epochs than rest subjects (sub-01: 513 kept vs ~300 at rest), so the task null is estimated
   from more Welch windows, its p95 is lower, and task detection is *more* sensitive — which would
   inflate task peak prevalence relative to rest for purely methodological reasons. **Rule:** compare the
   two pooled detection-power curves (proportion detected per injected PW level, each signal against its
   own subject's p95). *If* the task and rest curves differ by more than **0.05** at any injected level,
   the rest-vs-task prevalence comparison is reported **only** alongside a length-matched secondary
   analysis (each subject's task kept-epoch sequence truncated in time order, preserving run structure, to
   that subject's rest `n_kept`, with thresholds recalibrated at those run lengths). *If* every level
   differs by ≤ 0.05, the prevalence comparison is reported directly and the matched analysis is not run.
6. **Primary Track B result and what it would mean.** The primary output is the per-subject task
   classification (peak / no_peak / poor_fit at p95) and the paired rest × task 2 × 2 table over subjects
   evaluable in both, with **McNemar's exact (binomial) test** on the discordant pairs.
   - Task prevalence reliably **above** rest (McNemar p < .05, and the sensitivity rule above satisfied)
     → a discrete beta peak is more often detectable during the task than at rest; the absence of a
     resting peak in a large minority is then partly a state/arousal matter, not only a trait one.
   - **No reliable difference** → no evidence that the task reveals a beta peak where rest does not; this
     supports the manuscript's framing that the missing resting beta peak is not an artifact of the
     resting condition itself.
   - Task prevalence reliably **below** rest → reported as such, and the ERD-type power changes of
     Track A become the natural explanation (band power moving without a discrete peak).
   - In every case the **alpha-harmonic flag rate among task peaks** is reported next to the headline
     figure, as §9 required for rest (19/24 = 79 % there). A task peak rate that is also dominated by
     2 × IAF ± 2 Hz centres does not support "independent beta oscillation" any more than rest's did.
7. **Reliability rule.** If split-half agreement is below 80 % or ICC(2,1) of peak PW below 0.75 (Koo &
   Li, 2016: "poor" to "moderate"), the task peak measure is reported as unreliable and the prevalence
   comparison in 6 is reported as exploratory only, whatever its p-value. (Rest achieved 97.4 % and
   0.919, §9.)

- **Data-leakage check:** every rule above was written from event timings, epoch counts, the Stage-4 rest
  results already in §9, and the structure of the frozen code. No task spectrum, fit statistic or 13–30 Hz
  quantity existed at the time of writing.

### 10e. Task extraction-only and the aperiodic/noise picture (`S5-extract-task`)

**Run before any peak code touched task data; every quantity below is aperiodic-only.** Output:
`Revision_Output\stage5\stage5_extraction_task.csv` + `_meta.json` (39 rows, 0 excluded, no NaNs,
exit code 0).

**Task vs rest, aperiodic-only (rest figures from `stage4_extraction_fixedonly.csv`, §6):**

| Quantity | Task (msit) | Rest |
|---|---|---|
| `R2_fixed` (aperiodic-only fit) | mean 0.8162 (0.6506–0.9657) | mean 0.8090 (0.6256–0.9654) |
| `offset_fixed` | mean 0.8255 (−0.2826–1.4200) | mean 0.7287 (−0.2191–1.3803) |
| `exponent_fixed` | mean 1.2920 (0.3007–1.6318) | mean 1.2718 (0.3466–1.5698) |
| `noise_2_12Hz` | mean 0.2966 (0.0955–0.6037) | mean 0.3006 (0.0628–0.6633) |
| `noise_31_40Hz` | median 0.0404, mean 0.0526 (0.0076–0.1645) | median 0.0549, mean 0.0652 (0.0122–0.2011) |
| `n_pseudoepochs_kept` | min 388, median 502, max 545 | min ~291, ~300 typical (§5) |

- The broadband offset is higher during the task and the spectral slope is essentially unchanged — the
  expected direction for a condition with movement and sustained engagement.
- **The task/rest ratio of kept epochs is 1.30–1.84 (median 1.68) and exceeds 1 in all 39 subjects.**
  Task PSDs are therefore estimated from ~1.7× more Welch windows, which is visible directly in the
  smoother residual (`noise_31_40Hz` median 0.0404 vs 0.0549). This is exactly the asymmetry §10d rule 5
  was written for, so that rule is now live and will be evaluated once both power curves exist.

**Knee-model disclosure (`stage5_diag_knee_task.py`, used in no decision, §10d rule 1):**
39/39 knee fits converged. ΔBIC (fixed − knee) median **68.31**, range −2.67 to 173.73; **37 of 39**
subjects would have selected the knee model under the superseded ΔBIC > 10 rule. The derived knee
frequency (`knee^(1/exponent)`) has median **10.18 Hz** (range 1.66–25.17) and lands **inside the
13–30 Hz band of interest in 13 subjects**. The rest pattern of §6 (38/39 selected, mean ΔBIC 56.02,
8 subjects in-band) therefore recurs in the task, if anything more strongly. This is disclosure of the
task behaviour, not a re-opened decision: the pipeline has no knee code path, and §6's reasoning (a knee
whose frequency falls inside the band of primary interest is not a credible background description) holds
a fortiori here. Output: `stage5_diag_knee_task.csv` + `_meta.json`.

**Roughness mismatch (`diag_noise_floor_null.py`, run unchanged on the task extraction):** with the frozen
σ = 0 generator, real task `noise_31_40Hz` is a median of **3.02×** the matched simulated null's residual
SD (range 0.62–12.62) and exceeds the maximum of that subject's own 10 matched simulations in **33/39**
subjects; `noise_2_12Hz` median ratio 21.01 (expected — the generator injects no alpha). §7a's rest
figures were 2.92× and 31/39. The pattern recurs essentially unchanged, so the §10d rule-2 decision
(recalibrate σ_i from the task's own `noise_31_40Hz`, do not reuse rest's) proceeds as pre-specified.
Output: `stage5_diag_noise_floor_null_task.csv`.

- **Data-leakage check:** extraction computed only the fixed aperiodic-only fit and the two noise floors
  (the shared `stage4_core` functions the Stage-4 leakage rule permits before the freeze); the knee
  diagnostic computed only aperiodic-only fits in both modes, the same class of quantity §6 inspected for
  rest; the roughness diagnostic used simulated nulls plus real `noise_31_40Hz`. No full (periodic) fit,
  no peak, no band power and no 13–30 Hz quantity, real or simulated, has been computed or viewed at any
  point in Stage 5 so far.

### 10f. Task roughness calibration σ_i (`S5-rough-sigma-task`)

`stage4_calibrate_rough_sigma.py` run **unchanged** on `stage5_extraction_task.csv`, matching each
subject's σ_i to that subject's own real task `noise_31_40Hz` (the §10d rule-2 decision, pre-specified
and unconditional). Output: `Revision_Output\stage5\rough_sigma_task_per_subject.csv` (+ `_points.csv`).

| | Task (msit) | Rest (§7a) |
|---|---|---|
| σ_i median | **0.15** | 0.21 |
| σ_i range | 0.00 (sub-40) – 0.70 (sub-01) | 0.00 – 0.86 (sub-01) |
| `floor=1` (real below the σ=0 simulated median) | **1** (sub-40) | 5 (sub-06, 16, 22, 23, 40) |
| `extended=1` (needed the grid above 0.50) | **1** (sub-01, σ=0.70) | 6 (sub-01, 27, 19, 31, 39, 13) |
| `ceiling=1` (unresolved at σ=1.00) | **0** | 0 |
| Fit quality \|simulated median − real\| | median 0.00047, max 0.00562 | median ≈0.0004–0.0010, max 0.0010 |

- Task σ_i are systematically a little lower than rest's, which is the expected consequence of the task's
  ~1.68× greater epoch count: more Welch windows make the task PSD estimate smoother, so less injected
  roughness is needed to match it. Only one subject hits the floor for task (five did for rest), i.e. the
  generator now reaches nearly every subject's real roughness from below rather than from above.
- The **subject ordering is stable across conditions** (Pearson r(σ_rest, σ_task) = **0.827**; sub-01 is
  the roughest in both, sub-40 at the floor in both), which supports §7a's premise that spectral
  roughness is largely a property of the subject rather than of the recording condition. Caveat: because
  the seed constants are shared between the rest and task runs (§10d), the simulated medians entering the
  two calibrations are drawn from correlated streams, so this correlation is an upper bound on the purely
  physiological agreement. The calibration **targets** are, however, independent real measurements.
- §7a's documented limitation carries over unchanged: σ_i is matched to a single noisy per-subject
  estimate of `noise_31_40Hz`, matches only the size (SD) and not the frequency-correlation structure of
  real deviations, and is assumed uniform across 2–40 Hz (unverifiable without looking at 13–30 Hz).
- **Data-leakage check:** only real aperiodic-only `noise_31_40Hz` values and simulated-null aperiodic
  statistics were used. No 13–30 Hz quantity, real or simulated, entered the calibration.

**Next in the chain (running):** `stage4_simulate_threshold.py` on the task extraction + task σ_i, into
`Revision_Output\stage5\sim_task\` — the full factorial 39 pairs × (1 null + 10 injected levels) × 1000
reps = 429,000 simulations, resumable via `parts_r1000/`. The equivalent rest run took ≈7.4 h on this
machine (2026-10-31, 10:42→18:05, 8 workers); measured task throughput is ≈0.50 cells/min with 8 workers,
i.e. ≈14 h in total. It is launched with no environment changes (no thread-count overrides), exactly as
the rest run was, so the two are numerically comparable.

*Run provenance (operational, no scientific content):* the run was started 2026-11-01 10:29, stopped at
**22 of 429 cells** complete (11:15, at a checkpoint boundary — no partially written part file existed)
and relaunched detached at 11:15:58 so that it no longer depends on any editor/app session. The relaunch
resumed from exactly those 22 completed cells (`22 of 429 cells already done`), recomputing nothing. The
only difference in the relaunch command is `python -u` (unbuffered stdout, so the log updates live); it
changes no computation. Log: `Revision_Output\stage5\sim_task_run.log`; the exact command is also kept as
`Revision_Output\stage5\sim_task_run.cmd` for manual restarts. Checkpoint integrity was verified
empirically against the real `write_csv`/resume code before the restart: a part file is written to
`<part>.csv.tmp` and moved into place with `os.replace` (atomic on NTFS), the resume test is the
existence of `<part>.csv`, so a stale `.tmp` is never counted as progress and is truncated on recompute;
the assembly-time row-count assertions are a second net. No change was needed.

### 10g. Track A gets a pre-stimulus baseline; ERD% becomes the primary metric (`S5-trackA-erd`)

**Resolves the open item flagged in §10b. Decision (Amirhossein, 2026-11-01).** Written before any real
value was computed in the new window; the only numbers below come from event timings and from one
integrity check of event latencies.

**Architecture.** Track A carries **two** windows per trial, both relative to the condition-marker onset *t*:

| Window | Interval | Length | Role |
|---|---|---|---|
| baseline | `[t − 500, t)` ms | 500 ms (250 samples at 500 Hz) | pre-stimulus reference |
| active | `[t, t + 1000)` ms | 1000 ms (500 samples) | post-onset, fixed in §10b |

- **Primary metric: classic ERD% = (baseline_power − active_power) / baseline_power × 100**, per trial,
  then averaged per subject × condition. Positive = desynchronization.
- **Secondary/diagnostic:** the absolute post-onset band power of §10b, and the absolute baseline power,
  reported alongside so it is visible which side of the ratio moves.
- Same 7-channel Stage-4 ROI, same 13–30 Hz band average on linear power, same ROI averaging on linear
  power, same D12 rule as everywhere else in the project.

**Welch settings — identical segments in both windows (decision, Claude 2026-11-01).** ERD% is a *ratio*
of two band-average powers. If the two PSDs were computed with different taper lengths, their spectral
smoothing kernels would differ, so alpha leakage into 13–30 Hz would differ between numerator and
denominator and the ratio would be biased even with no true beta change. The segment is therefore the
same in both windows: **Hann, 250 samples (500 ms), 50 % overlap, `detrend='constant'`, density, mean
averaging** — one segment in the baseline, three in the active window (0–250, 125–375, 250–500).
- This happens to match the v1 pattern `winLen = min(nSamp, round(0.5*fs))`, but now for a stated reason
  rather than by inheritance.
- Rejected: a 1 s segment in the active window and 0.5 s in the baseline (unmatched leakage kernels —
  precisely the bias the ratio cannot tolerate).
- Rejected: shortening the active window to 500 ms so the segments match trivially — it would discard
  half the post-onset data and end before the response in about half the trials (RT median 602 ms, §10b).
- **Documented limitation:** a 500 ms Hann taper has its first spectral null 4 Hz from centre, so 10 Hz
  alpha still leaks toward ~14 Hz. Being identical on both sides, it cancels to first order in the ratio
  but does not vanish: it dilutes ERD% toward zero where alpha dominates. This is the same mechanism as
  audit item C, and far milder than v1's 200 ms window (first null 10 Hz away, i.e. leakage across the
  whole low-beta range).
- **Verified on synthetic data, not asserted** (the standing Stage-5 PSD note asks for exactly this):
  the 250-sample baseline is **1** Welch segment and the 500-sample active window **3**, confirmed both
  by scipy's own segment formula and by an explicit manual segment average reproducing scipy's output to
  a maximum relative difference of 3 × 10⁻¹⁵. `nfft = nperseg`, so **resolution and bin spacing are both
  2 Hz and coincide** — unlike v1, where a 0.2 s window (5 Hz resolution) was reported on a zero-padded
  1.95 Hz grid (`nfft = 256`), the distinction the project's PSD note flags for the Methods text. On this
  grid the 13–30 Hz band is carried by **9 bins: 14, 16, …, 30 Hz**, identically in both windows (so the
  ratio is unaffected; stated because it also defines the absolute secondary measures).

**D12 for Track A.** A trial is usable only if **both** its windows pass D12 (peak-to-peak ≤ 150 µV on
Fz/Cz/C4 within that window) — ERD% needs both sides, so a trial failing on either side is rejected
whole. The existing "outside" convention is inherited unchanged: a window crossing a `boundary` event or
the data edge is *outside*, not kept, and the 50 % rule uses kept/(total − outside). The §5/§10c leading-
boundary fix is applied on the helper's input copy, as in the pseudo-epoch path.

**Empirical window verification (`revision/stage5/stage5_window_overlap_check.py`, all 39 subjects,
15,492 in-block trials, 15,024 consecutive pairs).** Arithmetic alone says the windows cannot collide
(SOA floor 1733 ms − 1500 ms of window = 233 ms of slack); this was checked trial by trial instead of
assumed, as the post-onset window was.

| Hard check | Count |
|---|---|
| baseline of trial *k+1* overlapping the active window of trial *k* | **0** |
| baseline of trial *k+1* overlapping the baseline of trial *k* | **0** |
| active window extending past its block's end | **0** |
| baseline and active of the same trial overlapping | **0** |
| baseline starting before its block's first sample | **5** (see below) |

Clear space between one trial's active end and the next trial's baseline start: min **233 ms**, p01 233,
median 534, max 3933 — the floor is exactly the predicted value, reached in every subject.

**The 5 exceptions, and why they need no new rule.** One trial each in sub-02, sub-13, sub-17, sub-37 and
sub-40 has its baseline window starting 12–425 ms before its block's first sample. All five are the first
retained stimulus of a block that **D4e clipped** for filter-edge padding (`status=CLIPPED`): sub-02/13/37/40
block 1 with `clip_start_reason='recording_start'` (pushed to 6.638 s ≈ H), sub-17 block 4 with
`clip_start_reason='raw_boundary'`. The existing convention already excludes them: verified by reading
`P2.msit.event` directly for the two distinct cases — sub-02's block 1 starts at latency 1, so the window
would begin at latency −249 (`a < 1` → outside), and sub-17's block 4 starts at latency 124155 with one
`boundary` event inside the window (→ outside). Loss: **5 of 15,492 trials (0.032 %)**, by the same
mechanism that excluded Stage 4's incomplete block tails. No new rule, no code change.

**Where the baseline actually sits — a real limitation, quantified rather than assumed.** The baseline is
not a resting reference: it falls in the *previous* trial's post-response period, which is where
post-movement beta rebound (ERS) occurs. Measured lag from the previous response to the baseline start:

| Trial class | n | median lag | min | max |
|---|---|---|---|---|
| first in mini-block | 3,921 | **2940 ms** | 1164 | 4524 |
| later in mini-block | 10,936 | **864 ms** | −344 | 1522 |

(The previous response physically falls inside the baseline window in 26 of 14,857 trials, 0.175 %.)
First-in-mini-block trials follow the `S 11` end-of-mini-block marker and so have long SOAs and a clean
baseline; later trials have a baseline sitting ~0.9 s after the previous response, i.e. plausibly on the
rebound. Baseline power — and therefore ERD% magnitude — is thus **not comparable between the two trial
classes**, and they are reported separately rather than pooled.
- **The condition comparison is protected**, though: the first-in-mini-block fraction is essentially
  identical across the four conditions (group means F0 0.2640, FS 0.2622, 00 0.2642, S0 0.2630; median
  within-subject spread across conditions 0.034, max 0.066, from `d4e_trials_by_condition.csv`), so this
  asymmetry cannot by itself produce a condition difference.

**Pre-specified analysis plan (CLAUDE.md rule 8; no value in either window computed yet).**
- Unit of analysis: mean ERD% per subject × condition over usable trials; 39 subjects.
- Primary: **Friedman test** across the four conditions with **Kendall's W** as effect size —
  distribution-free, so no assumption check and therefore no data-dependent branch, and consistent with
  the project's non-parametric tradition (v1 used Wilcoxon and Page's L).
- Post hoc: **Wilcoxon signed-rank on all six pairs, Holm-corrected**, with **rank-biserial r** per pair
  (the effect size `revision_plan.md` step 3 asks for).
- Reported in parallel on the absolute post-onset power and the absolute baseline power, and separately
  for first-in-mini-block and later trials.
- Interpretation: a significant omnibus with a pairwise pattern separating interference conditions from
  the control condition is evidence of conflict-related beta modulation in this ROI; a null is quantified
  with BF₀₁ and TOST (`revision_plan.md` step 2) and read in light of the mini-block design — from the
  second trial of a mini-block on the upcoming condition was partly predictable, so a null is *not* a
  design-expected null for first-in-mini-block trials, while it is less surprising for later ones. If the
  two subsets disagree, both are reported and the first-in-mini-block subset carries the cleaner test.
- **Not pre-specified, and deliberately not guessed:** an *ordered* trend test (Page's L, audit item A)
  needs the interference semantics of the four labels. The dataset's own `task-msit_events.json` defines
  only the mapping (`S 5`=F0, `S 6`=FS, `S 7`=00, `S 8`=S0; `S 11`="End of a mini-block", `S 10`="Start of
  a break", `S 12`="Beginning of the run") and **not** what F, S and 0 stand for. The natural reading
  (0 = source absent, so 00 = control, F0/S0 = one source, FS = both) must be confirmed against Dzianok
  et al. 2022 before any ordered hypothesis is stated. Until then only the omnibus and the pairwise
  contrasts are pre-specified.
- **Timing:** Track A computation waits for the §10f threshold simulation to finish — it needs 39 MATLAB
  rebuilds and would contend with the 8-worker simulation for the same 8 cores.

**Amendment, same day, before any real value was computed (`S5-trackA-erd-amend1`).** The paragraph above
first specified ERD% as "per trial, then averaged per subject × condition". That is **not** the classic
definition and is the worse estimator here, so the primary estimator is changed:
- **Primary: `erd_pct` = (mean baseline power − mean active power) / mean baseline power × 100**, with the
  band powers averaged over the trials of a subject × condition cell **first** — the classic ERD
  definition (Pfurtscheller & Lopes da Silva, 1999), which is what the ERD literature this analysis sits
  in actually computes.
- **Secondary/diagnostic: `erd_pct_trialwise`**, the mean over trials of the per-trial ratio (plus its
  median). Kept and reported, since it is what the first wording specified.
- Reason for the change: a per-trial ratio divides a 1-segment baseline estimate by a 3-segment active
  estimate, so it has heavy tails, and by Jensen's inequality the mean of ratios is biased upward
  relative to the ratio of means. Averaging the powers first removes that bias and is the published
  definition. Nothing is hidden: both estimators are computed and written to the same table.
- This is an estimator choice, not a result-dependent one: it was made while writing the code, before any
  value existed in either window.

**Implementation (written, linted and smoke-tested; not yet run on real data).**
- `revision/stage5/stage5_export_trials_task.m` — rebuild, per-trial two-window D12, ROI export.
  Event types were read out of a real bundle rather than assumed: the condition markers are `'S  5'`,
  `'S  6'`, `'S  7'`, `'S  8'` (**two** spaces), and **`'S 11'` survives the Stage-3 cropping inside
  blocks while `'S 10'`/`'S 12'` do not**, because the latter two lie between blocks. The first-in-mini-
  block flag therefore uses "first trial of a block, or an `'S 11'` since the previous trial", which is
  what the vanished markers would have given; the Python step refuses to continue unless the resulting
  total matches the independent `events.tsv`-based count (3,921, §10g above). Metadata is written for
  every in-block trial, including rejected ones, so the bookkeeping is complete. `checkcode`: clean.
- `revision/stage5/stage5_erd_by_condition.py` — the two PSDs, both ERD% estimators, the Welch
  verification above, and the first-in-mini-block cross-check.
- `revision/stage5/stage5_erd_stats.py` — the Friedman/Kendall-W omnibus and the Holm-corrected pairwise
  Wilcoxon with Kerby (2014) rank-biserial, using the same r_rb definition as
  `legacy_v1/statistics/effect_size_rankbiserial.m` so the effect sizes are comparable with the ones
  already in the manuscript. Smoke-tested on synthetic cells with a known injected condition effect: it
  recovered the effect in ERD% (χ² = 88.54, W = 0.757) and correctly found none in the baseline power
  (p = 0.378) where none was injected.

- **Data-leakage check:** the window verification reads only `*_task-msit_events.tsv` and the Stage-3
  block table; the 5-trial diagnosis read only `P2.msit.event` latencies and block-table columns; the
  mini-block balance came from `d4e_trials_by_condition.csv` (trial counts); the event-type check read
  only `P2.msit.event` types and latencies; the Welch and statistics checks used synthetic data only.
  No EEG sample was read into any spectral estimate, and no 13–30 Hz quantity, real or simulated, exists
  for Track A at this point.

### 10h. Task thresholds, and the §10d rule-5 sensitivity rule fires (`S5-threshold-task`)

**Simulated data only.** Every 13–30 Hz quantity in this subsection comes from simulated null and
injected signals, exactly as in §7 for rest. No real task 13–30 Hz quantity has been computed or viewed
at any point in Stage 5.

**Main simulation, complete.** `stage4_simulate_threshold.py` (frozen, unchanged) on the task extraction
and task σ_i finished 2026-11-01 21:47:47, 10 h 32 m for the 407 cells remaining after the detached
relaunch (§10f), i.e. 0.64 cells/min on 8 workers. Integrity: **429/429** part files, every one exactly
1001 lines, no stale `.tmp`; `sim_null.csv` 39,000 rows and `sim_injected.csv` 390,000 rows, both exactly
as expected; `test_run: false`. Fit failures: **1 of 39,000** nulls (2.6 × 10⁻⁵) and **0 of 390,000**
injected — comparable to rest (§7b: 0/39,000 and 2/390,000).

**Per-subject thresholds (the primary criterion, §10d rule 3):**

| | Task (msit) | Rest (§7b) |
|---|---|---|
| p95, min | **0.0491** (sub-40) | 0.0619 (sub-22) |
| p95, median | **0.1563** | 0.2174 |
| p95, max | **0.7122** (sub-01) | 0.8710 (sub-01) |
| pooled p95 (comparison only) | **0.3669** | 0.4545 |

Task thresholds are lower than the same subject's rest threshold in **28 of 39** subjects, and the two
orderings agree closely (r = 0.843) — the expected consequence of the task's ~1.68× greater epoch count
(§10e) on top of a largely subject-specific roughness (§10f).

**§7b's single-outlier dominance recurs, as §10d rule 3 anticipated.** Under the pooled task p95, of the
1,950 null simulations at or above it, **sub-01 alone contributes 901 (46 %)**, with sub-27 (404, 21 %),
sub-19 (248, 13 %) and sub-31 (230, 12 %) making up most of the rest — four subjects for 92 %. And
**28 of 39 subjects' own nulls never reach the pooled threshold at all.** Rest's figures were 874/1950
(45 %) from sub-01 and 28/39. The pattern is reported as recurring, not re-litigated: the per-subject
threshold remains the primary criterion.

**Detection-power curve** (all 390,000 injected signals, each against its own subject's p95): PW=0 (null)
0.0500 by construction; 0.05: 0.2652; 0.10: 0.5222; 0.15: 0.6616; 0.20: 0.7656; 0.25: 0.8389; 0.30:
0.8966; 0.35: 0.9305; 0.40: 0.9531; 0.45: 0.9695; 0.50: 0.9778. Logistic (converged): b0 = −1.1645,
b1 = 11.0073 (rest: −1.2287, 9.0652 — the task curve is steeper).

**§10d rule 5: TRIGGERED.**

| injected PW | task power | rest power | difference | > 0.05? |
|---|---|---|---|---|
| 0.05 | 0.2652 | 0.2236 | +0.0415 | |
| 0.10 | 0.5222 | 0.4454 | **+0.0768** | yes |
| 0.15 | 0.6616 | 0.5822 | **+0.0795** | yes |
| 0.20 | 0.7656 | 0.6784 | **+0.0873** | yes |
| 0.25 | 0.8389 | 0.7588 | **+0.0801** | yes |
| 0.30 | 0.8966 | 0.8192 | **+0.0774** | yes |
| 0.35 | 0.9305 | 0.8683 | **+0.0622** | yes |
| 0.40–0.50 | 0.9531–0.9778 | 0.9053–0.9526 | +0.0478 to +0.0251 | |

Maximum absolute difference **0.0873**, exceeding the pre-specified 0.05 at six of the ten injected
levels. The rule therefore fires exactly as written: **the rest-vs-task peak-prevalence comparison may be
reported only alongside a length-matched secondary analysis.** Task detection is genuinely more sensitive
than rest detection, by up to 8.7 percentage points, purely because the task gives more pseudo-epochs —
so a raw comparison of task prevalence against rest's 24/39 (§9) would have attributed part of a
methodological artefact to physiology. This is why the rule was written before either curve existed.

**What the matched analysis requires, and its scope.** §10d rule 5 specifies the matched design as: each
subject's task kept-epoch sequence truncated in time order, preserving its contiguous-run structure, to
that subject's rest `n_kept`, **with thresholds recalibrated at those run lengths**. It specifies
thresholds, not a second full power curve. The matched calibration therefore needs the **null** cells
only (1 per subject rather than 11), which is ~1/11 of the compute of the run above. It will be produced
by a thin Stage-5 driver that calls the frozen `stage4_simulate_threshold.run_cell` with the null
condition on a matched extraction table (same `offset_fixed`, `exponent_fixed` and σ_i per subject, only
`run_lengths_epochs` truncated), so the generator, estimator and percentile code stay the frozen ones.
- Decision (Claude, 2026-11-02): produce the matched thresholds from null cells only, rather than
  re-running the full factorial. Rejected: a second full 10 h factorial run — the injected grid would
  only re-demonstrate a sensitivity match that the matched epoch counts already enforce by construction,
  and §10d asked for thresholds. If a matched power curve turns out to be wanted for the manuscript, it
  can be added later as a clearly-labelled addition.

**Matched design, built and validated on run lengths alone (outcome-blind; `stage5_matched_length.py`).**
The truncation was unit-tested (whole runs kept whole until the target, the last run cut to the remainder,
`truncate_runs` producing exactly those sample counts) and then applied to the real tables:

| | Matched task | Rest | Task, full |
|---|---|---|---|
| kept epochs per subject | **276–300** (= each subject's rest `n_kept` by construction) | 276–300 | 388–545 |
| Welch windows per subject | **537–593** | 542–598 | 767–1076 |
| contiguous runs | 7–23 | few (2 blocks) | 9–45 |

Matching on epochs matches the **window** count to within **3.51 % (median 1.00 %)** — demonstrated, not
assumed. The small residual exists because the truncated task subset is cut from 12-ish short blocks and
so contains more runs than rest's 2 blocks, and each run loses one window to the 50 % overlap
(`2k − 1` windows for a run of *k* epochs). Its **direction is conservative**: the matched task has fewer
Welch windows than rest in **38 of 39** subjects (median −6 of ~560). So if the matched analysis still
shows more task peaks than rest, that cannot be attributed to greater sensitivity — the matched task is
if anything marginally *less* sensitive. The matched subset uses a median 40.6 % fewer epochs than the
full task.
- `stage5_peak_detection_task.py` was extended, **before the freeze**, with the optional matched pass
  (`--matched-thresholds` + `--rest-extraction`), importing `truncate_runs` from the same module that
  built the matched thresholds, so the thresholds and the classification cannot drift apart. All real
  task 13–30 Hz computation therefore still happens in exactly one gated script.

**Half-length thresholds (§10d rule 4), complete.** `stage4_simulate_half_threshold.py` (frozen,
unchanged) was run on the task extraction and task σ_i, detached (PID 27296, 8 workers, orphaned — not a
descendant of any editor session), log `Revision_Output\stage5\sim_task_half_run.log`. It ran
2026-11-02 00:33:43 → 02:08:50 (1 h 35 m) for **39 subjects / 54 (subject, half-size) cells**, the cell
count exceeding 39 because a subject with an odd kept-epoch count has two halves of different lengths and
each length is calibrated separately. Integrity, checked and not assumed: 54 of 54 part files present,
every one exactly 1001 lines (header + 1000 null repetitions), **no stale `.tmp` file**,
`sim_null_half.csv` 54,000 rows, and **0 fit failures of 54,000**.
- Half lengths 194–273 epochs. Task half p95 min 0.0927, median 0.1893, max 0.8020 (`sub-01` again the
  extreme, as in the full-length run — the outlier dominance recorded above recurs at half length).
- Sanity check the simulation was *not* asked to confirm but which it does: the half-length p95 exceeds
  the same subject's full-length p95 in **every** subject, ratio min 1.080, median 1.213, max 1.919. A
  shorter record gives a noisier Welch spectrum and so a higher null max-PW; a ratio below 1 anywhere
  would have indicated a length bookkeeping error. §10d rule 4 was adopted unconditionally for exactly
  this reason, before any of these numbers existed.

**Length-matched null run, launched 2026-11-02 02:10:54.** `stage5_matched_length.py` detached
(**PID 15512**, 8 workers; its only live ancestor is an orphaned `nohup.exe`, so no live chain reaches the
editor session, and the containing job object carries no `KILL_ON_JOB_CLOSE` — established in §10f), log
`Revision_Output\stage5\sim_task_matched_run.log`, launcher recorded in `sim_task_matched_run.cmd`,
outputs under `Revision_Output\stage5\sim_task_matched\`. Pre-flight, from run lengths only:
`39 subjects matched; epochs 276-300` and `Welch windows: matched 537-593, rest 542-598; relative
difference max 3.51 %, median 1.00 %` — reproducing the table above from the live inputs. 39 null cells,
1000 repetitions each; the full-length run needed ~13 min per 8-cell wave at ~470 epochs, so ~45–65 min is
expected at 276–300.
- Fix made before the freeze (`stage5_matched_length.py`): the script wrote
  `stage5_extraction_task_matched.csv` *before* the simulation and then refused to start if that file
  existed, so a crash mid-run would have blocked the resume its own docstring promises. It now rebuilds
  the matched table into a `.recheck` file, continues only if the two are byte-identical, and otherwise
  refuses with an explicit message — because a changed input table would silently invalidate the cells
  already sitting in `parts_matched_r1000/`. The "never overwrite" discipline is kept: nothing is
  rewritten, the rebuild is compared and deleted.

**Length-matched thresholds, complete.** The run of 02:10:54 → 03:04:22 (53 min) finished all 39 null
cells. Integrity, checked and not assumed: 39 of 39 part files, every one exactly 1001 lines, **no stale
`.tmp` file**, `sim_null_matched.csv` 39,000 rows, **0 fit failures of 39,000**. Matched p95 min 0.0644,
median 0.1631, max 0.7034 (`sub-01` the extreme again, at 0.7034).
- Matched against the **full-length task**: ratio median 1.038, above 1 in 34 of 39 subjects — slightly
  higher, which is the direction a shorter record must give. It is smaller than the half-length ratio
  (median 1.213), and the matched subset (276–300 epochs) is longer than the halves (194–273), so the
  three calibrations order correctly by length. Nothing here was tuned to make that happen.
- Matched against **rest**: ratio median 0.828, above 1 in only 13 of 39 subjects. The matched task
  threshold is *lower* than the same subject's rest threshold, even though the Welch window counts agree
  to within 3.51 %. That single number is what prompted the correction below.

**Correction to the decision recorded above, and a new pre-specified rule (`S5-matched-power`).** The
rejection of a matched power curve argued that the injected grid "would only re-demonstrate a sensitivity
match that the matched epoch counts already enforce by construction". **That rationale is wrong.** The
frozen simulator injects peaks at **absolute** PW heights (0.05 … 0.50, pre-registration §3.6), not at
heights scaled by σ_i, so detection power at a given level depends on the subject's spectral roughness as
much as on the record length. Task spectra are systematically smoother than rest spectra — task σ_i median
0.1500 against rest 0.2100, task lower in 26 of 39 subjects, paired median difference −0.0500, median
ratio 0.80 over the 34 subjects with rest σ_i > 0 (σ_i values from §7a and §10f; roughness statistics, not
13–30 Hz peak quantities). Matching the window count therefore equates **data quantity but not
sensitivity**, the 8.7 pp gap in the curves above mixes length and roughness, and the matched design
removes only the first of the two.
- Decision (Claude, 2026-11-02): run the frozen `stage4_simulate_threshold.py`, **unchanged**, on the
  matched extraction and the task σ_i, out-dir `Revision_Output\stage5\sim_task_matched_full`, producing
  the matched nulls plus all ten injected levels — a matched power curve directly comparable with the rest
  and task-full curves because it is the same script, the same seed and the same levels. No new code is
  written for it.
- Free consistency check it brings: its 39 null cells must come out byte-identical to the ones already in
  `sim_task_matched\parts_matched_r1000\` (same seeding by `(pair index, condition)`, same run lengths),
  which independently verifies `stage5_matched_length.py`'s truncation against the frozen path.
- Cost ~10 h (39 null + 390 injected cells). It does **not** block the freeze or the first real look:
  `stage5_peak_detection_task.py` classifies against `thresholds_per_subject_matched.json`, which already
  exists and is final. The curve decides only whether the rest-vs-task prevalence *comparison* may be
  reported, not what the classification is.
- **Decision rule, written before the run (CLAUDE.md rule 8).** Compare the matched-task power curve with
  the rest curve at each of the ten injected levels, the same metric as the comparison above.
  - **≤ 0.05 at every level** → the matched comparison is sensitivity-equated. The matched rest-vs-task
    prevalence comparison, with McNemar exact (§10d rule 6), becomes the primary rest-vs-task statement,
    and the full-length task prevalence is reported as the within-task descriptive figure.
  - **> 0.05 at any level** → the matched comparison is **not** sensitivity-equated either. Then no
    rest-vs-task prevalence difference is reported as a physiological result at all. Each condition's
    prevalence is reported descriptively against its own calibrated threshold, with the measured power gap
    and the σ_i difference stated as the reason the two cannot be compared. No sensitivity-adjusted
    prevalence will be estimated, modelled or interpolated to fill that gap.
  - Either way the **within-task** Stage-5 results are unaffected — task peak prevalence, split-half
    reliability (rule 7) and the alpha-harmonic rate each use only the task's own thresholds.

- **Data-leakage check:** all of the above comes from simulated signals plus the real aperiodic/noise
  statistics already logged in §10e–10f. No real task 13–30 Hz quantity exists yet; the first will be
  produced by `stage5_peak_detection_task.py`, behind the freeze gate, once the half-length and matched
  thresholds are in place.

### 10i. Track B real-data results — the first task 13–30 Hz quantities (`S5-task-results`, 2026-11-02)

**Gate satisfied before the run.** `stage5_peak_detection_task.py` refused to start until the annotated tag
`S5-task-peak-frozen` existed, dereferenced to **`bfc4365edb7b3fc692dceefe6fd0275d2617d6d7`**, equalled
HEAD, left `revision/stage4` and `revision/stage5` with no uncommitted change, and already appeared in this
log. All four conditions held; the commit is recorded in `peak_detection_taskun_meta.json` together with
every per-subject threshold actually used. Three threshold sets were in place beforehand, all calibrated on
simulated signals only: full-length, half-length (§10d rule 4) and length-matched (rule 5).

**Primary result (per-subject p95, fixed-only, 39 subjects, 0 excluded by D12).**

| | peak | no_peak | poor_fit | prevalence (evaluable) |
|---|---|---|---|---|
| **Task, full length** | **28** | 10 | 1 | **28/38 = 73.7 %**, 95 % CI [56.9, 86.6] |
| Task, length-matched | 28 | 10 | 1 | 28/38 = 73.7 %, 95 % CI [56.9, 86.6] |
| Rest (§9) | 24 | 14 | 1 | 24/38 = 63.2 %, 95 % CI [46.0, 78.2] |

- The single poor fit is **`sub-34`** (R² = 0.6786), the same subject that was poor_fit at rest in §9.
- Threshold grid, full length: p90 28, p95 28, p99 26 — the classification is not sitting on the
  threshold choice. Matched: p90 29, p95 28, p99 27.
- Task `n_kept` median 502 epochs (388–545); full-model R² median 0.9928, minimum 0.6786. Beta peaks in
  range per subject: 0 in 1 subject, 1 in 18, 2 in 14, 3 in 5, 4 in 1.
- Primary peaks (n = 28): CF median **18.66 Hz** (13.32–25.60), PW median 0.376 (0.169–0.617). Rest's
  primary CF median was 20.17 Hz.

**Length-matched secondary pass (§10d rule 5).** Identical counts to the full-length pass, with
**37/39 agreement** and two discordant subjects, both marginal:
- `sub-26` full-length no_peak (primary 18.95 Hz, PW 0.2097 against threshold 0.2761) → matched peak
  (primary **13.07 Hz**, PW 0.3667 against 0.2778). The matched primary sits on the lower edge of the
  13–30 Hz band, so this is an edge case, not a different physiological reading.
- `sub-37` full-length peak (PW 0.2928 against 0.2698) → matched no_peak (PW 0.2640 against 0.2702); both
  within 0.03 of the threshold.
That the prevalence is unchanged after discarding a median 40.6 % of the task epochs is the strongest
single piece of evidence that the task peak prevalence is not a data-quantity artefact.

**Reliability (§10d rule 7).** Split-half on odd/even kept epochs against each subject's own half-length
p95: **37 of 38 evaluable subjects agree, 97.4 %**; **ICC(2,1) on PW = 0.938** over the 26 subjects with a
peak in both halves. Rule 7's unreliability condition (agreement < 80 % or ICC < 0.75) is **not** met, so
the task peak measure is reported as reliable. Rest was 97.4 % and ICC 0.919 (§9) — the two are
indistinguishable on reliability.

**Rest vs task (§10d rule 6), paired over the 38 subjects evaluable in both.**

| | both | rest only | task only | neither | McNemar exact |
|---|---|---|---|---|---|
| Task full length | 22 | 2 | 6 | 8 | **p = 0.2891** |
| Task length-matched | 22 | 2 | 6 | 8 | **p = 0.2891** |

**There is no significant rest-vs-task difference in beta-peak prevalence, at either task length.** The
10.5-point prevalence gap (73.7 % vs 63.2 %) rests on 8 discordant subjects and does not survive a paired
test.
- Relation to the still-running `S5-matched-power` curve: its verdict governs whether a rest-vs-task
  *difference* may be reported as physiological, and there is no significant difference to report either
  way. The **direction** of the known bias is also informative: the measured sensitivity advantage favours
  the task, so removing it could only lower the task count and move the table further toward equality. The
  null therefore cannot be an artefact of the task being *less* sensitive. Whatever the curve returns, the
  reported statement stays "no significant difference", with the sensitivity gap stated alongside it.

**Alpha-harmonic diagnostic (§10d rule 6, exploratory).** The same 2 × IAF ± 2 Hz coincidence rule flags
**12 of 28 task primary peaks, 42.9 %**, 95 % CI [24.5, 62.8] — against **19 of 24, 79.2 %** at rest (§9).
The flag is a coincidence rule and attributes nothing, so this is a diagnostic and not a result. It is
nevertheless the one number here that bears directly on the manuscript's central claim: the task beta
peaks are far less often explainable as alpha harmonics than the resting peaks were, which is what a
genuine task-related beta rhythm would look like and what an alpha-harmonic artefact would not.

- **Data-leakage check.** These are the first real task 13–30 Hz quantities in the project. Every one was
  produced after the code was committed (`bfc4365`), tagged and documented, by the gated script, against
  thresholds calibrated from simulated signals alone. No rule above was written, relaxed or chosen after
  seeing them, and the rules that remain open (`S5-matched-power`, Track A in §10g) were fixed in writing
  before this run. Nothing downstream may now be selected by looking at these numbers: in particular the
  ROI, the window, the aperiodic model and the ERD estimator for Track A are already fixed in §10a and
  §10g and will not be revisited in the light of §10i.

### 10j. The matched power curve, and the `S5-matched-power` verdict (2026-11-02)

**Run and integrity.** The frozen `stage4_simulate_threshold.py`, unchanged, on the matched extraction and
task σ_i: 2026-11-02 03:17:15 → 12:26:39 (9 h 09 m), PID 26576, detached. All **429 of 429** cells present,
every part file exactly 1001 lines, **no stale `.tmp` file**, `sim_null.csv` 39,000 rows,
`sim_injected.csv` 390,000 rows, and **0 fit failures in both** (null 0/39,000, injected 0/390,000).
`stage4_per_subject_thresholds.py` (frozen) then produced the per-subject curve, which is the metric the
primary classification uses.

**Both consistency checks passed.**
- The 39 null cells of this independent run are **byte-identical** to the 39 already in
  `sim_task_matched\parts_matched_r1000\`, cell for cell. `stage5_matched_length.py`'s truncation is
  therefore verified against the frozen implementation, not merely unit-tested against itself.
- The per-subject thresholds recomputed here are **identical at p90, p95 and p99 for all 39 subjects** to
  the ones that classified the real data in §10i. The §10i classification is reproducible from this run.
- The null row of all three curves is exactly **0.0500**, i.e. each subject's own p95 delivers the intended
  5 % false-positive rate in rest, full-length task and matched task alike.

**Detection power at each injected level (per-subject p95).**

| PW | rest | task, full | task, matched | full − rest | matched − rest |
|---|---|---|---|---|---|
| 0 (null) | 0.0500 | 0.0500 | 0.0500 | +0.0000 | +0.0000 |
| 0.05 | 0.2236 | 0.2652 | 0.2210 | +0.0415 | −0.0026 |
| 0.10 | 0.4454 | 0.5222 | 0.5004 | +0.0768 | **+0.0550** |
| 0.15 | 0.5822 | 0.6616 | 0.6531 | +0.0795 | **+0.0709** |
| 0.20 | 0.6784 | 0.7656 | 0.7585 | **+0.0873** | **+0.0802** |
| 0.25 | 0.7588 | 0.8389 | 0.8403 | +0.0801 | **+0.0815** |
| 0.30 | 0.8192 | 0.8966 | 0.8958 | +0.0774 | **+0.0766** |
| 0.35 | 0.8683 | 0.9305 | 0.9314 | +0.0622 | **+0.0631** |
| 0.40 | 0.9053 | 0.9531 | 0.9549 | +0.0478 | +0.0496 |
| 0.45 | 0.9323 | 0.9695 | 0.9684 | +0.0372 | +0.0361 |
| 0.50 | 0.9526 | 0.9778 | 0.9789 | +0.0251 | +0.0262 |

**Verdict: the rule's second branch. Max |matched − rest| = 0.0815 (at PW 0.25), above 0.05 at six of the
ten levels — the matched comparison is NOT sensitivity-equated.**

**Length matching removed almost none of the gap: 0.0873 → 0.0815.** That is the substantive finding of
this run, and it confirms the §10h correction empirically. With the run lengths matched, the gap can only
come from the per-subject parameters the simulator takes from each condition — `offset_fixed`,
`exponent_fixed` and σ_i — and those can be separated: the **exponents are effectively identical** (paired
median difference +0.0155, task lower in 19 of 39 subjects, i.e. no systematic direction), the **offsets**
differ by a vertical shift (+0.0941) which does not move a PW measured relative to the fitted aperiodic
component, and **σ_i**, the one parameter that directly sets spurious beta-peak amplitude, is systematically
lower in the task (median 0.1500 against 0.2100, lower in 26 of 39). By elimination among the simulator's
own inputs, the sensitivity difference is a **spectral-roughness** effect, not a data-quantity effect, so
§10d rule 5's remedy — designed for a data-quantity artefact — cannot repair it, and **no length-based
matching can**. Had the matched curve not been run, the matched pass in §10i would have been presented as a
sensitivity-controlled comparison when it is nothing of the kind. The earlier rationale for skipping it was
wrong in exactly the way that mattered.

**Consequences, exactly as pre-specified in §10h before this run.**
1. **No rest-vs-task prevalence difference is reported as a physiological result.** Each condition's
   prevalence is reported descriptively against its own calibrated threshold: task 28/38 = 73.7 %
   [56.9, 86.6], rest 24/38 = 63.2 % [46.0, 78.2] (§9's headline figure is 24/39 = 61.5 %).
2. The paired table and McNemar exact p = 0.2891 (§10i) may be reported **only descriptively**, each time
   with the statement that detection sensitivity is not equated — up to 8.15 percentage points higher in
   the task at matched length, 8.73 at full length — and that the gap is a roughness effect that length
   matching does not remove.
3. **No sensitivity-adjusted prevalence** is estimated, modelled or interpolated. The rule forbade it
   before the numbers existed and it stays forbidden now.
4. The bias runs **in favour of the task**, so the non-significant table cannot be an artefact of the task
   being less sensitive; equally, the nominal 10.5-point task excess cannot be claimed as physiological,
   because a bias of up to ~8 points points the same way. Both halves of that sentence must appear
   together wherever this is reported.

**A caveat the pre-specified rule does not cover, recorded rather than resolved.** The alpha-harmonic rate
comparison in §10i (task 42.9 % against rest 79.2 %) is conditional on a peak being detected, and a
sensitivity difference changes *which* peaks enter the denominator — the task admits marginal peaks that
rest would miss. So that comparison is not sensitivity-controlled either. No rule for it was written in
advance, and none will be invented now: it is reported as a within-condition descriptive figure with the
comparison explicitly flagged as uncontrolled. Quantifying it properly would need a peak-height-matched
analysis, which is listed as a possible addition, not run and not relied on.

**What this does not touch.** The project's primary negative result is a rest-only statement — by the
pre-registered simulation-calibrated method, 14 of 38 evaluable subjects have no resting beta peak (§9),
alongside the legacy five-method agreement on the earlier 42-subject sample — and no part of it depends on
the task comparison. The within-task Stage-5 results (prevalence, split-half 97.4 % / ICC 0.938,
threshold-grid stability) are likewise unaffected, since each uses the task's own calibration throughout.
Track A (§10g) compares conditions *within* the task against a within-task baseline and shares neither the
rest calibration nor this confound.

- Observation that no decision rests on, recorded for completeness and explicitly post hoc: the gap is
  smallest at the extremes of the grid, and the observed task primary peaks have PW median 0.376, where the
  gap is ≈0.05–0.06. This was computed after the real data were seen, it selects a level by reference to
  them, and so it is **not** used to soften conclusion 2 or anywhere else.
- **Data-leakage check:** every number in this entry comes from simulated signals. The two real-data
  quantities quoted (the §10i prevalences, the σ_i medians) were already logged in §10f and §10i. The
  verdict applied here is the rule written in §10h at 03:05, before the simulation was launched at 03:08
  and before any real task 13–30 Hz quantity existed.

### 10k. F/S/0 semantics confirmed, and an ordered-trend test for Track A (`S5-conflict-order`, 2026-11-02)

Next-steps item 15, closed. The dataset's own `task-msit_events.json` gives only the marker mapping
(`S  5` = F0, `S  6` = FS, `S  7` = 00, `S  8` = S0, plus `S 10` start of a break, `S 11` end of a
mini-block, `S 12` beginning of the run) and never says what F, S and 0 denote, so nothing was guessed. The
definitions come from the dataset paper, Dzianok et al., *GigaScience* 11:giac015 (2022),
doi 10.1093/gigascience/giac015, Methods and its Table 3:

> "The extended MSIT contains 4 conditions: 00 (no interference, non-conflict), S0 (Simon effect), F0
> (Flanker effect)" and "FS (double-conflict, Simon and Flanker effects combined)."

So **0 = that interference absent, S = Simon interference, F = Flanker interference**, and the four
conditions carry **0, 1, 1 and 2** sources of conflict. The paper's stimulus sets corroborate it directly:
00 uses (100, 020, 003), where the deviant digit's value equals its position (no Simon) among 0 distractors
(no Flanker); S0 uses (010, 001, 200, 002, 300, 030), value ≠ position; F0 uses (122, 133, 121, 323, 113,
223), digit distractors with value = position.

**Three design facts from the same source, each confirming something this project had measured
independently** — recorded because agreement between an external description and our own extraction is the
only check available on the marker semantics:
- Stimulus 900 ms, ISI 800–1,300 ms in 100 ms steps → a within-mini-block SOA of 1,700–2,200 ms. §10b
  measured a minimum SOA of **1,733 ms in every one of the 39 subjects**, inside that interval. The
  corrected premise in §10b is therefore right, and the original 870–1,070 ms figure was indeed samples.
- "Three or 4 stimuli of the same condition were presented consecutively", inter-mini-block interval
  2.5–4.4 s, and a 10 s rest every 30–40 stimuli. This is exactly the mini-block structure §10d and §10g
  describe, and it explains §10g's asymmetry directly: a first-in-mini-block baseline falls in a 2.5–4.4 s
  gap (measured median 2,940 ms after the previous response), a later one in an ISI (measured 864 ms).
- Trials per condition, paper against our own count over the 39 retained subjects' `events.tsv`:

| | 00 | S0 | F0 | FS | total |
|---|---|---|---|---|---|
| Paper (n = 42) | 102 (SD 7) | 105 (SD 7) | 94 (SD 9) | 98 (SD 9) | 399 (SD 6) |
| **Ours (n = 39)** | **101.6 (SD 7.8)** | **104.8 (SD 9.1)** | **94.2 (SD 9.8)** | **97.5 (SD 9.9)** | 398.1 (SD 18.3) |

  The means agree to the paper's rounding on all four conditions, which **confirms the marker mapping
  independently**. Our SDs are larger because the 39 retained subjects include the clipped final blocks
  recorded in §10c, which the paper's sample-level figures do not.

**Decision (Claude, 2026-11-02): add Page's L to the Track A plan, on three ordered levels, not four.**
The design licenses only a **partial** order — 00 (no conflict) < {F0, S0} (one conflict each) < FS (two)
— because nothing in the paper or in the task ranks Flanker interference against Simon interference. The
test therefore runs on the within-subject mean of F0 and S0 as a single middle level:
**00 < mean(F0, S0) < FS**, with the hypothesis that ERD% increases with the number of conflict sources.
`scipy.stats.page_trend_test` is used, exact where it can be and asymptotic otherwise, and the method it
chose is reported per row.
- Rejected: Page's L over all four conditions in a fixed order such as 00 < S0 < F0 < FS. It would need an
  ordering of Flanker against Simon that no source supports, and a significant L could then be produced by
  the arbitrary half of the ordering. Also rejected: dropping the trend test, which was §10g's position
  only while the semantics were unconfirmed; a monotone conflict hypothesis is the natural form of the
  question MSIT+ was built to ask, and leaving it to the six pairwise tests wastes the ordering.
- The Friedman omnibus and the six Holm-corrected Wilcoxon pairs stay exactly as §10g pre-specified them.
  Page's L is an **addition**, reported alongside and not instead, and it is run for every metric and every
  mini-block class, as the rest of the plan already is.
- **Decision rule, written before Track A runs.** On the primary metric (ERD%), a significant Page's L
  (p < .05) together with a significant Friedman supports a graded conflict effect; a significant Friedman
  with a non-significant L means the conditions differ without a monotone conflict ordering, and the text
  must say so rather than describing the effect as graded; a non-significant Friedman ends the conflict
  analysis regardless of L. The first-in-mini-block and later-trial classes are read separately throughout,
  since §10g established their baselines are not comparable in magnitude.

- **Data-leakage check:** nothing here touches real EEG. The condition semantics come from a published
  paper, the trial counts from `events.tsv` marker labels (no 13–30 Hz quantity), and the SOA and
  mini-block figures were already logged in §10b and §10g. Track A has not been run: this rule is in place
  before any real ERD% value exists.

### 10l. Track A real-data results — ERD% across the four MSIT+ conditions (`S5-trackA-results`, 2026-11-08)

**Step 1, trial export.** `stage5_export_trials_task()` under `matlab -batch`, detached (PID 10216),
2026-11-08 15:57 → 16:05 (8 min), log `Revision_Output\stage5\trackA_export_run.log`, launcher recorded
in `trackA_export_run.cmd`. 39 of 39 subjects exported, manifest `manifest_trials_20261108T160444.tsv`.
**0 subjects excluded** by the per-condition 50 % rule.
- 15,492 in-block trials, **15,335 usable (98.99 %)**, 5 outside, 82 baseline-window D12 rejections, 119
  active-window rejections, 49 trials failing **both** windows. The naive sum
  `usable + outside + rej_base + rej_act` therefore exceeds the trial count in 12 subjects — that is the
  double-counted overlap, not a bookkeeping error. The identity that does hold,
  `n_trials = usable + |outside ∪ rej_base ∪ rej_act|`, is exact in all 39 subjects.
- Integrity, checked per subject from the stored per-trial metadata rather than assumed — **12 checks × 39
  subjects, 468 of 468 pass**: metadata row count equals the manifest's trial count; `sum(usable)` equals
  the manifest and `base.shape[2]` and `act.shape[2]`; `base` is 7×250×n and `act` 7×500×n in `single`;
  usable and the rejected-or-outside union are exact complements; every manifest count reproduces from the
  flags; and the export index is a permutation of 1…n_usable, non-zero exactly on usable trials.
- Two independent cross-checks against `events.tsv`, computed by different code on different days:
  **15,492 in-block trials** and **4,428 first-in-mini-block trials** both match
  `stage5_window_overlap_summary.json` exactly.

**Bug found and fixed before any ERD% value was computed.** `stage5_erd_by_condition.py`'s `psd_band`
documented and unpacked its input as `(n_channels, n_trials, n_samples)`, but the exporter writes
`(n_channels, n_samples, n_trials)`. The first real run therefore stopped at
`AssertionError: unexpected window length 405` — 405 being sub-01's trial count read as a window length.
The earlier smoke test had passed because it fed synthetic arrays in the function's own documented layout,
which no file ever has. Fixed by making `psd_band` take the exporter's layout and `np.moveaxis` internally,
then verified by recomputing one trial's band power by hand — per-channel Welch, ROI mean on linear power,
band mean — agreeing to a relative 1.4e-16. The window-length assert is what caught it, so it stays.
No ERD% value had been produced before the fix.

**Step 2, ERD% computation.** `stage5_erd_by_condition.py` on all 39 subjects. The script's own two gates
passed: the Welch verification reproduces scipy by explicit manual segmentation to 2.8e-15 for the 250
sample window (1 segment) and 2.4e-15 for the 500 sample window (3 segments), 2.0 Hz bins; and the hard
refusal on the mini-block count found **4,428 == 4,428** against `events.tsv`. Outputs: 15,492 per-trial
rows with a power value on exactly the 15,335 usable trials, and 468 subject × condition × class cells
(39 × 4 × 3) with **no missing ERD%**. Trials per cell: median 99.5 (all), 28.0 (first), 71.0 (later).

**Step 3, the pre-specified statistics.** Medians of the primary metric, ERD% (positive = desynchronization
from the baseline to the post-onset window):

| class | 00 | S0 | F0 | FS | Friedman χ² | p | Kendall W | Page's L | p |
|---|---|---|---|---|---|---|---|---|---|
| all | 23.65 | 30.10 | 35.97 | 38.13 | 56.169 | 3.87e−12 | **0.480** | 525 | 5.45e−11 |
| **first** | 19.61 | 28.13 | 26.71 | 31.99 | 15.831 | 0.00123 | **0.135** | 499 | 2.24e−4 |
| later | 24.86 | 31.28 | 39.15 | 41.26 | 52.692 | 2.13e−11 | **0.450** | 526 | 2.56e−11 |

**The §10k decision rule is satisfied in all three classes: a significant Friedman together with a
significant Page's L supports a graded conflict effect on post-onset beta ERD%.** All six Holm-corrected
pairs are significant in `all` and `later`; in `first`, three are — F0 vs 00 (p = .031, r_rb = +0.482),
FS vs 00 (p = .00024, +0.713) and 00 vs S0 (p = .0059, −0.579), i.e. every pair involving the non-conflict
condition. ERD% is positive in 449 of the 468 cells, so beta desynchronizes after stimulus onset in every
condition and the effect is a difference in how much.

**Secondary metrics behave as a real effect requires.** Absolute post-onset power mirrors ERD% with the
expected sign (FS lowest: median 0.157 against 00's 0.178 in `all`; FS vs 00 r_rb = −0.995), and the
trial-wise diagnostic estimator agrees in every class at uniformly smaller magnitude, as the §10g amendment
predicted (all: 9.03 to 23.61 against the trial-averaged 23.65 to 38.13).

**The baseline is not flat, and that decides which number is the headline.** `baseline_power_mean` differs
across conditions in `later` (χ² = 16.077, p = .0011, W = 0.137, Page's L p = 7.6e−4) but **not in `first`**
(χ² = 4.385, **p = 0.223**, W = 0.037, L p = 0.129).
- Within a mini-block the preceding trial is the **same condition**, so a later trial's baseline sits in
  that condition's own post-response interval, a median 864 ms after the previous response (§10g).
  **Carry-over from the preceding same-condition trial is at least as parsimonious as anticipation**, and
  this design cannot separate the two. Since ERD% divides by that baseline, the `later` and pooled ERD%
  are partly contaminated by it.
- The `first` class is the clean estimate: the condition is unpredictable there, its baseline sits a median
  2,940 ms after the previous response, and it does **not** differ across conditions — yet the graded ERD%
  effect survives. So the conflict effect is in the **post-onset response**, not inherited from a
  pre-stimulus difference.
- Therefore **W = 0.135 (first-in-mini-block) is the effect size to report as the conflict effect**, not
  0.450 or 0.480. Honest counterweight, recorded rather than resolved: `first` cells hold a median 28
  trials against `later`'s 71, so noisier cell means attenuate Kendall's W, and this analysis cannot say
  how much of the drop from 0.450 to 0.135 is a smaller true effect and how much is attenuation.

**Two things this does NOT establish, stated before any text is drafted.**
1. The window is **post-onset `[0, +1000)` ms**. This says nothing about the v1 manuscript's *pre-stimulus*
   conflict claim and neither revives nor refutes it. Any sentence built on §10l must name the window.
2. The ordering F0 > S0 (Flanker interference producing more ERD% than Simon) is significant in `all` and
   `later` but **not in `first`**, where that pair does not survive Holm, so it rests on the two classes the
   baseline contaminates and **will not be claimed**. §10k's three-level collapse, which never ranks F0
   against S0, remains the only ordering asserted.

- **Data-leakage check.** Every analytic choice was fixed and committed before these numbers existed: the
  ROI and windows in §10a/§10b, the ERD estimator and the mini-block split in §10g with its amendment, and
  Page's L with its decision rule in §10k (commits `eb559b0`, `b58ddf8`, 2026-11-02, six days before this
  run). The only code change made during the run was the axis bug above, a layout fix with no degrees of
  freedom: it could not be tuned toward a result, and the run that produced these numbers is the first that
  reached an ERD% value at all. Track A shares no threshold, calibration or classification with Track B, so
  the §10i–§10j sensitivity confound does not reach it.

### 10m. The within-task control window, the equivalence bound and the BF₀₁ rule (`S5-control-window`, `S5-tost-bound`, 2026-11-08)

Three decisions, all taken before the analyses they govern run, after the §10l results and the
reconciliation pass (`stage5_reconciliation.md`, root commit `ddb1f41`) identified what was still missing:
`revision_plan.md` Stage 5 (audit #5, #6) needs a within-task control window, and Stage 6 (audit #1, #13)
needs BF₀₁ and TOST before the pre-stimulus conflict null may be called a null.

**Amirhossein's decisions (2026-11-08), recorded as given.**
1. The control window is a **late ITI** window, **not** a post-response window. His reason: the
   post-response interval is the beta-rebound (ERS) period that §10g already identified as the
   contaminator of the later-trial baselines, so using it as a "control" would measure a different
   physiological state instead of the neutral within-task level that has to be compared with rest.
2. Its length and position are to be established **empirically over all 39 subjects**, as the
   pre-stimulus window was, not assumed. He noted specifically that with a 1,733 ms SOA floor a 500 ms
   window placed immediately before the existing baseline would probably collide with the previous
   trial's active window.
3. The v1 ±10 % bound is **discarded** — not because the number is wrong but because it was unmotivated,
   and its asymmetry in linear terms is a symptom of that. The replacement must be symmetric on a
   ratio/log scale (bioequivalence style) or a standardised SESOI, and its justification must be logged
   before TOST runs.

---

**The empirical survey (`stage5_iti_window_survey.py`, read-only, events.tsv and the block table only).**
For a trial at onset *t* whose previous in-block trial is at *p*, the free interval between the previous
**active** window and this trial's **baseline** window is `[p + 1000, t − 500)`, of length
`(t − p) − 1500`. Over 15,024 consecutive in-block trial pairs:

| gap length (ms) | n | min | median | p95 | max |
|---|---|---|---|---|---|
| first-in-mini-block pairs | 3,960 | **1,966** | 2,566 | 3,517 | 3,933 |
| later-in-mini-block pairs | 11,064 | **233** | 533 | 734 | 767 |

Amirhossein's prediction is confirmed and sharpened: in a typical within-mini-block ITI there is no room
at all — a 500 ms window fits in only 5,559 of 11,064 later pairs, and the project's per-condition 50 %
rule then **fails in 37 of 39 subjects** (minimum retained fraction 0.322, median 0.439). The long
intervals are all at the mini-block boundaries, which the dataset paper gives as 2.5–4.4 s (§10k).

Placement was then measured rather than argued, for a 500 ms window in the first-in-mini-block gaps
(median clearances, ms):

| placement | n fitting | from prev. active | from prev. response | to upcoming onset | prev. response inside |
|---|---|---|---|---|---|
| early (against the previous active window) | 3,960 | 0 | 410 | 2,566 | 99 |
| **centred** | **3,960** | **1,033** | **1,424** | **1,533** | **2** |
| late (against the baseline) | 3,960 | 2,066 | 2,440 | 500 | 0 |

**Decision (`S5-control-window`): the control window is 500 ms, centred in the inter-mini-block interval,
on first-in-mini-block trials only.** Measured properties of exactly that window over all 39 subjects: it
fits in **3,960 of 3,960** such pairs; **0** fall outside their clipped task block; clearance from the
previous active window min **733** / median 1,033 / max 1,716 ms; clearance from the previous response
p05 **1,047** / median 1,424 ms over the 3,921 pairs with a recorded previous response; clearance to the
upcoming onset min **1,233** / median 1,533 ms; and the previous response falls inside the window in
**2 of 3,960** trials, which will be dropped. Every subject retains **100 %** of each condition's
first-in-mini-block trials, so the 50 % rule is not even approached.
- Rejected, **late** placement: it sits only 500 ms before the onset and immediately adjacent to the
  baseline, so it is effectively a second pre-stimulus window and cannot distinguish a pre-stimulus
  specific elevation from a general within-task level — which is the question audit #5 asks.
- Rejected, **early** placement: zero clearance from the previous active window and the previous response
  inside 99 windows.
- Rejected, **later-in-mini-block trials**: the 50 % rule fails in 37 of 39 subjects, as above.
- Rejected, **a shorter window (250–400 ms)** to keep all trials: it would break the identical-estimator
  requirement that is the entire point of audit #5. 500 ms is the baseline's own length, giving 250
  samples at 500 Hz, one Welch segment and 2.0 Hz bins, the settings §10l already verified.
- Rejected, **the 10 s in-task breaks**, which would be the ideal neutral window: D3e splits task blocks
  at S 10 / S 12 and at gaps > 10 s, so the breaks lie outside the cropped blocks and are not in the data.
- Loose end closed: the figure **3,921** that appeared in earlier working notes is this — the number of
  first-in-mini-block pairs with a measurable previous response — not a trial count. The
  first-in-mini-block trial count is 4,428 (§10l).

**Consequence for the export.** The current trial files hold only `[−500, 0)` and `[0, +1000)`, so this
window needs a new MATLAB export pass. It must be an **added** output under a new filename, never an
overwrite (project rule 4).

---

**Decision (`S5-tost-bound`): the equivalence bound is the ratio interval [0.900, 1.111] = [0.9, 1/0.9],
i.e. |mean log₁₀ ratio| < 0.0457575, applied on the within-subject difference of log₁₀ band power.**
Justification, in the order it carries weight:
1. It is **symmetric on the scale the test is performed on**. That is precisely audit #10's complaint: the
   v1 bound was symmetric in log₁₀ but described as ±10 %, which in linear terms is +10 % / −9.1 %.
2. It is the **principled correction of the magnitude this project already proposed**, so the goalposts do
   not move after the data are seen.
3. It is **2.5× stricter** than the regulatory bioequivalence interval [0.80, 1.25] for which this
   log-ratio TOST machinery was designed, so passing it is a strong statement rather than a formality.
4. It is fixed **before any control-band or conflict log-ratio value exists**.
5. One scale and one bound serve both bands and both kinds of comparison, which is what audit #11 asks for.

**The guard that keeps the bound from driving the conclusion.** The **primary report is the bound-free
90 % CI** of the mean log₁₀ ratio (the interval matching the 5 % one-sided TOST), from which equivalence at
any bound can be read. When TOST fails at the pre-specified bound, the **attained bound** —
max(|CI_low|, |CI_high|), the smallest symmetric bound that would pass — is reported in its place, and the
claim is weakened to "no evidence of a difference; equivalence established only within ±X %".
- Rejected: a **data-derived SESOI** (Cohen's d ≈ 0.2 times the between-subject SD of the same quantity).
  The SD of the very quantity under test would then set its own bound, so a noisier measure would earn a
  more lenient bound — the opposite of what an equivalence claim should require. The standardised effect
  `dz` is reported alongside for context instead.
- Also rejected: adopting [0.80, 1.25] unchanged. It was calibrated for drug exposure, not band power, and
  is wide enough that passing it would say little.

---

**Decision rule for BF₀₁ (`stage5_equivalence.py`), written before its first run.** JZS default Bayes
factor for the paired t-test — Cauchy(0, *r*) on the standardised effect, Jeffreys prior on the variance
(Rouder, Speckman, Sun, Morey & Iverson, 2009, *Psychon Bull Rev* 16:225–237) — with **r = 0.707
primary** and r = 0.5, 1.0 as a robustness check. BF₀₁ = 1 / BF₁₀.
- Primary comparison: **FS vs 00** (the maximum conflict contrast, and the contrast the manuscript already
  planned) on **`baseline_power_mean`**, pre-stimulus 13–30 Hz power, in the **first-in-mini-block** class.
  All six pairs and all three classes are reported.
- **Positive control, pre-specified:** the same machinery is run on `active_power_mean`, where §10l found a
  large condition effect, so BF₁₀ there must come out large. A null-looking result on that metric would
  indict the implementation rather than the data, and the run is to be stopped if it appears.
- Interpretation (Jeffreys, as tabulated by Lee & Wagenmakers): BF₀₁ ≥ 10 strong evidence for the null,
  3 ≤ BF₀₁ < 10 moderate, **1/3 < BF₀₁ < 3 inconclusive and must be reported as inconclusive**,
  BF₀₁ ≤ 1/3 evidence against the null.
- **Conjunction required before the manuscript may call the pre-stimulus conflict result a null:**
  BF₀₁ ≥ 3 on the primary comparison **and** TOST equivalence at the pre-specified bound. If only one
  holds, the text reports exactly what held and what did not, with the attained bound; §10l's
  p = 0.223 on its own stays "a failure to reject".
- Implementation verified before the first run, no real data involved: two mathematically distinct
  routes — quadrature over the mixing variable *g*, and quadrature over the effect size against a
  noncentral-t likelihood — agree to a relative **3.06e−11** over 54 (t, n, r) grid points, a Monte Carlo
  over the inverse-gamma prior agrees to ~1e−3 at 400,000 draws, and BF₁₀(t = 0, n = 39) = 0.173, i.e.
  BF₀₁ = 5.79, the expected moderate evidence for the null at this sample size. **Stated limitation:** no
  third-party Bayes-factor implementation is installed here, so this verifies the implementation of the
  cited formula, not the formula.

- **Data-leakage check:** nothing in this entry was chosen in the light of a result it governs. The window
  survey reads only event timings and block boundaries — no EEG sample, no spectral quantity — and the
  window was selected on clearance geometry alone. The bound is fixed in advance and the primary report is
  bound-free. The BF verification uses synthetic *t* values only. No control-band power, no log ratio and
  no Bayes factor on real data existed when this entry was written.

### 10n. BF₀₁ and TOST on the pre-stimulus conflict result — the conjunction FAILS (`S5-equivalence-results`, 2026-11-08)

Run of `stage5_equivalence.py` on the §10l cell table, under the rules committed in §10m (`2b2f06d`)
before the script was first run. The implementation check reported in the output: the two quadrature
routes agree to **3.06e−11** over 54 (t, n, r) grid points.

**The pre-specified positive control passes first.** On `active_power_mean`, where §10l found a large
condition effect, FS vs 00 gives BF₁₀ = **5.71e+07** in the later class and 1.23e+07 pooled (and 4.88 in
the first class, p = .0082). The machinery detects the effect it must detect, so a null-looking result on
the pre-stimulus metric is about the data, not the code.

**Primary comparison: `baseline_power_mean`, FS vs 00, first-in-mini-block class, n = 39.**

| quantity | value |
|---|---|
| ratio (10^mean log₁₀) | 1.0886 |
| **90 % CI, the bound-free primary report** | **[0.9790, 1.2104]** |
| attained bound | **±21.0 %** |
| **BF₀₁ (r = 0.707)** | **2.509** (r = 0.5: 1.942; r = 1.0: 3.358) |
| p_TOST at [0.900, 1.111] | **0.3733** — not equivalent |
| two-sided p | 0.1853 |
| dz | +0.216 |

**Verdict under the §10m conjunction rule: it FAILS on both arms.** BF₀₁ = 2.51 falls in the
1/3 – 3 band, which §10m defines as **inconclusive**, and the prior sensitivity (1.94 to 3.36 across
r = 0.5 – 1.0) straddles the threshold, which confirms rather than weakens that reading. TOST does not
establish equivalence at the pre-specified bound; equivalence holds only within **±21 %**.

**So the manuscript may NOT call the pre-stimulus conflict result a null.** §10l's p = 0.223 stays "a
failure to reject". What may be said is exactly this: the omnibus does not reject, the maximum conflict
contrast is inconclusive by Bayes factor, and equivalence is established only within ±21 % — i.e. **the
study cannot resolve a difference of the size it observed**.

**And the direction is consistent across classes, which argues against absence.** The FS/00 pre-stimulus
ratio is 1.0886 (first), 1.0841 (later) and 1.1030 (pooled). The first-class non-significance therefore
looks like insufficient resolution in the class with the fewest trials per cell (median 28 against 71),
not like a different physiological state. **This corrects the reading in
`stage5_reconciliation.md` §1.2**, which called it "a clean null" on the strength of the Friedman p alone;
that document is amended in the same commit.

**All six pairs, first-in-mini-block class** (eq = TOST equivalent at [0.900, 1.111]):

| pair | ratio | 90 % CI | attained | BF₀₁ | p_TOST | eq |
|---|---|---|---|---|---|---|
| F0 vs FS | 0.9605 | [0.8717, 1.0584] | ±14.7 % | 4.608 | 0.1327 | 0 |
| F0 vs 00 | 1.0456 | [0.9994, 1.0939] | ±9.4 % | 1.646 | 0.0146 | 1 |
| F0 vs S0 | 0.9620 | [0.9032, 1.0246] | ±10.7 % | **3.523** | 0.0414 | **1** |
| **FS vs 00** | **1.0886** | **[0.9790, 1.2104]** | **±21.0 %** | **2.509** | **0.3733** | **0** |
| FS vs S0 | 1.0016 | [0.9468, 1.0595] | ±5.9 % | **5.788** | 0.0017 | **1** |
| 00 vs S0 | 0.9201 | [0.8561, 0.9889] | ±16.8 % | 1.054 | 0.3046 | 0 |

Two pairs pass **both** arms and are the only equivalence claims this analysis supports: **FS vs S0**
(BF₀₁ = 5.79, equivalent within ±5.9 %) and **F0 vs S0** (BF₀₁ = 3.52, within ±10.7 %). One passes TOST
with an inconclusive BF (F0 vs 00), one passes BF with a failing TOST (F0 vs FS), and two pass neither —
including the primary contrast. Each must be reported as it came out, not pooled into a verdict.

---

**The parametric and distribution-free TOST disagree, and the cause is one trial.** On the primary pair
the t-based TOST fails (p = 0.3733) while the two-one-sided-Wilcoxon robustness check passes
(p = 0.0022). That is not a reason to prefer either: §10m made the t-based test the pre-specified one and
the Wilcoxon version a check, so the disagreement is reported and diagnosed.
- The log₁₀ ratios have **mean +0.0369 but median +0.0038** (ratio 1.0886 against 1.0088), SD 0.1706,
  IQR [−0.0246, +0.0524], **skew +4.78, excess kurtosis +24.77**. The median sits 10.4 % of the way from
  zero to the mean.
- One subject accounts for it: **`sub-06`, log₁₀ ratio +1.0025, i.e. an FS/00 pre-stimulus power ratio of
  10.06**. The next most extreme are +0.1825 (`sub-07`) and −0.1476 (`sub-14`).
- Tracing it to the trial level: **89.4 % of `sub-06`'s FS cell mean comes from a single trial**, whose
  baseline power is 27.66 against that cell's median of 0.126 — a factor of 220 — while its 00 cell is
  unremarkable (largest-trial share 0.066, mean 0.1184, median 0.1200). The 10× ratio is that one trial.
- **D12 did not catch it.** The rule is a 150 µV time-domain peak-to-peak test on Fz/Cz/C4, which does not
  bound a large beta-band burst in the ROI channels.
- Scope, measured over all 156 first-class cells: the largest trial contributes a median of **0.088** of a
  cell mean (uniform expectation at n ≈ 27 is 0.037), p90 0.145, p99 0.498, max 0.894. **Four cells exceed
  0.25**: `sub-06` FS (0.894), `sub-06` S0 (0.704), `sub-17` F0 (0.330), `sub-17` FS (0.325). So the
  problem is rare but decisive where it occurs.
- Reassurance that bounds the damage: §10l's statistics are **rank-based** (Friedman, Wilcoxon, Page's L),
  so such a cell can move a result by at most one rank; the unbounded sensitivity is specific to the
  parametric TOST and to any mean-based summary.

**Nothing was excluded.** No subject and no trial was dropped. Removing `sub-06` after seeing that it
reverses the TOST verdict would be exactly the data-dependent choice this project's discipline exists to
prevent, and the trial-averaged estimator is what §10g pre-specified. This is recorded as a **decision for
Amirhossein** (next-steps item 19): whether to add a trial-level robustness rule — a per-cell median, a
trimmed mean, or an outlier-trial criterion applied **uniformly to every cell** — as a clearly labelled
**sensitivity analysis reported alongside** the pre-specified primary, never replacing it. If it is added,
the text must say that it was adopted after the outlier was found.

**The §10m control window is exported, and it reproduces the survey on real data.**
`stage5_export_control_task.m` under `matlab -batch`, detached, 2026-11-08 17:57 (sub-01, the verification
run) and 18:0x → 20:52 (the other 38), log `Revision_Output\stage5	rackA_control_run.log`, output
`<eegOutRoot>\stage5\control\`. The §10l trial export was not touched: the control windows go to their
own directory under their own filenames (rule 4). Because the verification run had already written
`sub-01`, and the script never overwrites, the remaining 38 subjects were passed explicitly rather than
deleting anything in `Revision_EEG`; the result is **two manifests whose union is the 39 subjects**, which
is why both are kept.
- 39 of 39 subjects, **0 excluded** by the per-condition 50 % rule. **3,960 eligible** windows, **3,943
  usable (99.6 %)**, 0 outside, 15 D12 rejections, 2 trials rejected for a response inside the window.
- Integrity, checked per subject from the stored per-trial metadata: **8 checks × 39 subjects, 312 of 312
  pass** — counts agree with the manifest and with `ctrl.shape[2]`, `ctrl` is 7×250×n `single`, usable is
  the exact complement of outside-or-rejected-or-response-inside, the export index is a permutation of
  1…n_usable, and **every** window clears both the previous active window and the upcoming onset.
- **The independent confirmation that matters.** The survey ran in Python on the 1000 Hz `events.tsv`
  grid; the export ran in MATLAB on the 500 Hz pipeline grid through the rebuilt bundles. Every figure
  agrees to the 1–2 ms the grid note predicted:

| | survey (1000 Hz) | export (500 Hz) |
|---|---|---|
| eligible windows | 3,960 | **3,960** |
| outside their block | 0 | **0** |
| previous response inside | 2 | **2** |
| clearance from prev. active, min / median / max | 733 / 1,033 / 1,716 | **732 / 1,032 / 1,716** |
| clearance from prev. response, n / p05 / median | 3,921 / 1,047 / 1,424 | **3,921 / 1,046 / 1,425** |
| clearance to next onset, min / median / max | 1,233 / 1,533 / 2,217 | **1,234 / 1,534 / 2,218** |

  Nothing was tuned to make these match: the window definition was fixed in §10m before the MATLAB script
  existed.
- Still to come on this window (next-steps item 18): the 13–30 Hz and 55–95 Hz band powers, resting beta
  re-estimated at the same 500 ms segment length, and the matched-estimator rest-vs-task comparison. **No
  band power has been computed on these files yet.**

- **Data-leakage check:** every rule applied here — the bound, the primary comparison, the BF thresholds,
  the conjunction, the positive control — was committed in §10m before this script first ran, and the
  verdict is reported as it came out, against the reading the reconciliation pass had hoped for. The
  outlier diagnosis is a post-hoc diagnostic, labelled as one, and it changes no reported number: the
  primary verdict above stands on the pre-specified test.

### 10o. Two decision rules, written before the analyses they govern (`S5-robust-estimator`, `S5-matched-rest-task`, 2026-11-08)

Amirhossein instructed both analyses on 2026-11-08 after §10n. Neither has been run; no band power on the
control windows and no robust-estimator value exists at the time this entry is written.

---

#### 10o-1. The trial-level robustness sensitivity analysis (next-steps item 19)

**Full disclosure, first.** This analysis was **added after** §10n found that one trial supplies 89.4 % of
`sub-06`'s FS cell mean and that removing it would reverse the parametric TOST verdict. It was **not**
pre-specified. Every number it produces is therefore a **labelled sensitivity analysis**, reported beside
the pre-specified mean-based result of §10l and §10n, never in place of it. The manuscript must say that it
was adopted after the outlier was found.

**Decision: the cell MEDIAN is the sensitivity estimator, with the 20 % trimmed mean reported alongside.**
Amirhossein left the choice between the two to a documented preference. The median comes first because:
1. **It has no tuning constant.** A trim fraction is a new free parameter that would be chosen after
   seeing the outlier, which is exactly the degree of freedom this exercise is meant to remove.
2. **It speaks in the units the manuscript already uses.** §9 through §10l report medians throughout, so
   the sensitivity analysis needs no new vocabulary.
3. **Its breakdown point is the highest available** (50 %), and with a median of 28 trials per cell in the
   first-in-mini-block class and one trial at 220× the cell median, that matters; a 20 % trimmed mean
   breaks down at 20 %.
The 20 % trimmed mean is reported with it because it is far more efficient — it uses the central 60 % of
the ordered values rather than one — so agreement between the two shows the conclusion does not rest on an
inefficient estimator.

**Applied uniformly.** Both estimators replace the trial average in **every** cell of §10l and §10n — all
39 subjects × 4 conditions × 3 mini-block classes, both windows — not only the cells whose verdict they
change. The full §10l statistics (Friedman, Kendall's W, the six Holm-corrected Wilcoxon pairs with
rank-biserial r, Page's L on the §10k levels) and the full §10n machinery (BF₀₁ and TOST at the §10m
bound) are rerun on them, by importing the same functions from `stage5_erd_stats.py` and
`stage5_equivalence.py` so no definition can drift.

**A limitation that must travel with the result, not be buried.** The median and the trimmed mean of trial
power are **not** estimates of the mean of trial power: they change the **estimand**, not just the
estimator, and the classic ERD definition §10g adopted (Pfurtscheller & Lopes da Silva, 1999) averages
power across trials. So agreement between the estimators supports the robustness of the **conclusion**, not
of the number, and the pre-specified mean-based values stay the reported ones.

**Decision rule, written before the run.**
- The mean-based cells are recomputed from the per-trial table first and must reproduce
  `stage5_erd_per_subject_condition.csv` exactly; the run stops if they do not.
- If the robust estimators **agree** with the pre-specified result on every verdict that §10l and §10n
  report (the Friedman and Page's L significance per class, the §10m conjunction on the primary pair),
  the text says the conclusions are robust to the trial-level outliers and keeps the pre-specified numbers.
- If they **disagree** anywhere, the disagreement is reported in full at that point, with both numbers and
  with the statement that the robust version was adopted after the outlier was found. No verdict is
  replaced by the robust one, and no subject or trial is excluded in any version.

---

#### 10o-2. The matched-estimator rest-vs-task comparison (next-steps item 18)

This is `revision_plan.md` Stage 5, audit items #5 and #6, CLAUDE.md step 1, and the control-band half of
audit #10. It is the item that unblocks the title.

**One estimator everywhere, which is the whole point.** Every window on both sides is 500 ms = 250 samples
at 500 Hz, through one Welch call with `nperseg = 250`, `noverlap = 125`, `nfft = 250`, Hann,
`detrend='constant'`, `scaling='density'` — exactly one Hann-tapered periodogram with 2.0 Hz bins per
window, the settings §10l already verified against a manual segmentation to 2.8e−15. Audit #5's objection
was that rest used 2 s windows and the task 200 ms; after this there is no difference left to object to.

**Where the rest segments come from.** The Stage-4 rest ROI exports hold exactly the **kept** 2 s
pseudo-epochs as contiguous runs (verified: `sub-01` has runs of 150 + 150 epochs for `nKept` = 300). Each
kept 2 s epoch is subdivided into **four non-overlapping 500 ms segments**, so Stage-4's D12 decisions are
inherited unchanged and **no new artifact rule is introduced on the rest side**. At `n_kept` 276–300
(§10h) that gives 1,104–1,200 rest segments per subject.

**The three comparisons, per band, on the within-subject difference of log₁₀ power:**
- **A: task pre-stimulus vs rest.** The manuscript's +63–73 % claim, recomputed honestly.
- **B: within-task control window vs rest.** The §10m window.
- **C: task pre-stimulus vs the control window.** Whether any elevation is specific to the pre-stimulus
  moment or is the general within-task level.

**Bands:** 13–30 Hz (the beta claim) and 55–95 Hz (audit #10's EMG control). Both lie clear of the 50 and
100 Hz line-noise removal (D5) and inside the band the pipeline preserves (D4: no low-pass).

**Statistics.** Exact Wilcoxon signed-rank on the log₁₀ ratio with matched-pairs rank-biserial r (the
project's standing choice), **Holm-corrected across the three comparisons within each band**; the
geometric-mean percent change 10^mean − 1 with its 90 % CI; and the §10m equivalence machinery — the
bound-free 90 % CI, TOST at [0.900, 1.111], BF₀₁ with r = 0.707 primary. The three comparisons are not
multiplicity-corrected **against each other across bands**, because each band answers a different
pre-registered question; every p-value is reported either way. Audit #11 is satisfied by construction:
one scale, one framework, both bands.

**Decision rule, written before the run.**
1. **A significant in 13–30 Hz, task above rest** → the pre-stimulus elevation survives a matched
   estimator. Report the ratio and the geometric-mean % change, replacing the +63–73 % figure, and state
   that the v1 number came from a mismatched estimator.
2. **A not significant in 13–30 Hz** → the reported elevation does not survive, the engagement /
   anticipation reading loses its empirical basis, and the manuscript says so plainly.
3. **Specificity, only if A is significant.** If **C is also significant in the same direction**, the
   elevation is pre-stimulus specific. If **C is not significant** (or B ≈ A), it is a general within-task
   level, and by CLAUDE.md step 1's own rule **the word "anticipation" leaves the title**.
4. **Control band 55–95 Hz.** The §10m conjunction governs: BF₀₁ ≥ 3 **and** TOST equivalence are both
   required before the manuscript may claim the control band shows no parallel increase. If the
   conjunction fails, the text reads "no evidence of a parallel increase; equivalence established only
   within ±X %" with the attained bound, which is audit #10's own recommended wording, and the words
   "dissociate" and "rule out directly" do not return.
5. If a 55–95 Hz increase is itself significant and comparable to the 13–30 Hz one, the EMG explanation is
   **supported**, not excluded, and that is reported as such.
6. Every comparison is additionally reported with the §10o-1 robust estimators, labelled as the sensitivity
   analysis it is.

- **Data-leakage check:** both rules above are fixed before either analysis runs. The robust estimators are
  disclosed as post-outlier additions. The rest-vs-task rule names, in advance, what each outcome means for
  the title and for the control-band wording, so no result can choose its own interpretation. No band
  power has yet been computed on the control windows and no rest 500 ms segment has been estimated.

### 10p. Results of the two §10o analyses — the robust sensitivity, and the matched rest-vs-task comparison (2026-11-08)

Both run under the rules committed in §10o (`b264abf`) before either script was first executed.

---

#### 10p-1. Trial-level robustness (§10o-1, `stage5_robust_sensitivity.py`)

Hard check first: the mean-based cells rebuilt from the per-trial table reproduce the committed
`stage5_erd_per_subject_condition.csv` over **1,404 values to a relative 1.67e−14**, so the three
estimators differ by nothing except the trial aggregation.

**ERD%, the Track A primary metric — every verdict holds, and the robust estimators are slightly
stronger.**

| class | mean (pre-specified) | median (sens.) | trim20 (sens.) |
|---|---|---|---|
| all | p 3.9e−12, W 0.480, L p 5.4e−11 | p 8.0e−13, W 0.507, L p 1.1e−12 | p 4.7e−13, W 0.517, L p 2.1e−13 |
| **first** | p 0.00123, **W 0.135**, L p 2.2e−4 | p 1.8e−4, **W 0.170**, L p 2.2e−4 | p 2.3e−4, **W 0.166**, L p 9.3e−5 |
| later | p 2.1e−11, W 0.450, L p 2.6e−11 | p 1.0e−11, W 0.464, L p 2.5e−12 | p 2.3e−13, W 0.529, L p 1.1e−12 |

So §10l's graded conflict effect is **not** an artefact of the trial-averaged estimator; if anything the
pre-specified estimator understates it (W 0.135 against 0.170 in the clean class).

**Pre-stimulus power omnibus — also unchanged in every class:** the first-in-mini-block class stays
non-significant under all three (p 0.223 / 0.214 / 0.134) and the later and pooled classes stay
significant. No verdict moves.

**But the §10n primary equivalence comparison DOES move, and this is the finding of 10p-1.**

| estimator | ratio | 90 % CI | attained bound | BF₀₁ | p_TOST | equivalent |
|---|---|---|---|---|---|---|
| **mean (pre-specified)** | 1.0886 | [0.9790, 1.2104] | **±21.0 %** | **2.509** | 0.3733 | **no** |
| median (sensitivity) | 1.0017 | [0.9628, 1.0420] | **±4.2 %** | **5.780** | 0.0000 | **yes** |
| trim20 (sensitivity) | 1.0058 | [0.9699, 1.0431] | ±4.3 % | 5.599 | 0.0000 | yes |

Under the robust estimators the §10m conjunction **passes** — BF₀₁ ≈ 5.8 with equivalence inside ±4.2 % —
while under the pre-specified mean it **fails**. §10o-1 pre-specified what to do with exactly this
disagreement, so:
- **The pre-specified verdict stands as the reported one.** §10n is unchanged: the pre-stimulus conflict
  result may not be called a null on the pre-registered analysis.
- **The manuscript must report both**, with the disclosure that the estimator which supports the null was
  adopted **after** the `sub-06` outlier was found, and that it changes the estimand (§10o-1).
- The honest one-sentence form: *whether the pre-stimulus conflict null can be asserted depends on a
  single trial in one subject* — which is itself the most informative thing this analysis produced, and
  which no amount of further testing on these data can resolve.
- Nothing was excluded, in any version.

---

#### 10p-2. The matched-estimator rest-vs-task comparison (§10o-2, `stage5_rest_vs_task_matched.py`)

One 500 ms Welch estimator on both sides (2.0 Hz bins), rest segments being the Stage-4 kept 2 s epochs
subdivided × 4. Windows per subject: rest 1,104–1,200 (median 1,196), task pre-stimulus 305–426
(median 396), control 78–112 (median 102). Holm across the three comparisons within each band.

**13–30 Hz, pre-specified mean aggregation:**

| comparison | ratio | geometric % change | 90 % CI | p_Holm | r_rb |
|---|---|---|---|---|---|
| **A** task pre-stimulus vs rest | 1.4002 | **+40.0 %** | [+30.3, +50.5] | 2.8e−09 | +0.954 |
| **B** control window vs rest | 1.2891 | **+28.9 %** | [+19.7, +38.9] | 8.1e−07 | +0.844 |
| **C** task pre-stimulus vs control | 1.0862 | **+8.6 %** | [+4.3, +13.2] | 0.00155 | +0.567 |

**Rule 1 is satisfied: the pre-stimulus elevation survives a matched estimator — but it is +40 %, not
+63–73 %.** The v1 figure was inflated by roughly 23–33 percentage points, which is audit #5's predicted
leakage, now measured: v1 estimated rest with 2 s windows (0.5 Hz bins) and the task pre-stimulus window
with one 200 ms window (5 Hz true resolution on 1.95 Hz zero-padded bins). **+40.0 % [30.3, 50.5] replaces
+63–73 % as the reported figure.**

**Rule 3, and the number that matters most here.** C is significant, so by the letter of §10o-2 the
elevation is "pre-stimulus specific" and the word "anticipation" is not automatically struck. But the
decomposition is additive in log units, A = B + C exactly, and it says the opposite of what a binary
verdict suggests:

| aggregation | general within-task share (B/A) | pre-stimulus-specific share (C/A) |
|---|---|---|
| mean (pre-specified) | **75.4 %** | **24.6 %** |
| median (sensitivity) | 84.5 % | 15.5 % |
| trim20 (sensitivity) | 84.2 % | 15.8 % |

**Three quarters of the rest-to-task beta increase is already present in a late-ITI window that is a
median 1,032 ms after the previous active window, 1,425 ms after the previous response and 1,534 ms before
the next stimulus.** Only about a quarter — a sixth under robust aggregation — is specific to the
pre-stimulus moment. The pre-specified rule was binary and is honoured as written; the decomposition is
reported as the substantive result, and any sentence that reads the +40 % as anticipation is wrong by a
factor of four.

**55–95 Hz, the EMG control band — and §10o-2 rule 5 fires.**

| comparison | ratio | geometric % change | 90 % CI | p_Holm | BF₀₁ | p_TOST |
|---|---|---|---|---|---|---|
| A control band, task pre-stimulus vs rest | 1.3676 | **+36.8 %** | [+17.5, +59.2] | 0.00267 | 0.040 | 0.9867 |
| B control band, control window vs rest | 1.2077 | +20.8 % | [+4.9, +39.1] | 0.0322 | 0.614 | 0.8369 |
| C control band, pre-stimulus vs control | 1.1324 | +13.2 % | [+5.6, +21.4] | 0.00383 | 0.124 | 0.6759 |

**The control band rises by +36.8 %, against beta's +40.0 % — 93 % of the beta effect in log units.**
§10o-2 rule 5, written before this ran, says exactly what that means: *"If a 55–95 Hz increase is itself
significant and comparable to the 13–30 Hz one, the EMG explanation is supported, not excluded, and that
is reported as such."* It is significant and it is comparable. **The EMG account of the rest-to-task beta
increase is now positively supported, not merely unexcluded.**
- No equivalence is available anywhere in the control band: TOST p 0.68–0.99 and BF₀₁ 0.04–0.61 on A, B
  and C. The §10m conjunction fails on every one.
- So audit #10's recommended replacement wording — "no evidence of a parallel increase; equivalence not
  established" — is **itself no longer accurate**: there **is** evidence of a parallel increase. The
  words "dissociate", "argue against", "support a genuine neurophysiological origin" and "rule out
  directly" cannot appear in any form.
- Under the robust aggregators the control band rises **+15.8 % (median) / +18.2 % (trim20)**, i.e.
  **49–54 %** of the beta effect in log units rather than 93 %, while beta itself barely moves
  (+35.3 % / +36.4 %). So the control-band mean is the quantity inflated by extreme windows, which is what
  broadband muscle artefact looks like. Both readings must be reported: on the pre-registered analysis the
  two bands rise together; on the robust one beta rises about twice as much as the control band. **Neither
  reading supports a dissociation.**

**What this does not touch.** Both bands and all three comparisons are task-vs-rest *power* contrasts; they
are independent of §10j's peak-*prevalence* sensitivity confound, which concerns discrete peak detection
and not band-average power.

- **Data-leakage check:** every rule applied — the estimator, the rest segmentation, the three
  comparisons, the Holm scheme, the bound, and what each outcome means for the title and the control-band
  wording — was committed in §10o before either script ran. Both verdicts went against the manuscript's
  existing claims and are reported as they came out. The only code change during the run was adding a
  missing `os.makedirs` after a write failed, and making `psd_band` take the band as an argument with its
  default unchanged (checked: the default call is bit-identical to the explicit 13–30 Hz call).

## File locations (as of 2026-11-02)
- Decision log: `github/eeg-beta-project/docs/decision_log.md` (repo `ahfeizi/EEG-Beta-Power-MSIT`, branch `revision-v2`).
- Pre-registration: `github/eeg-beta-project/docs/zenodo_preregistration_stage4.md` (same repo/branch).
- Implementation: `github/eeg-beta-project/revision/stage4/` — `stage4_export_roi.m`, `stage4_core.py`, `stage4_extraction_only.py`, `stage4_simulate_threshold.py`, `stage4_calibrate_rough_sigma.py`, `stage4_simulate_half_threshold.py`, `stage4_peak_detection.py`, `stage4_compare_half_full_thresholds.py`, plus the diagnostic scripts `diag_noise_floor_null.py` and `diag_calibrate_rough_sigma.py` (superseded design, provenance only).
- Local repo root: `C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\github\eeg-beta-project`. Stage-3 bundles live under `D:\Revision_EEG\stage3_part2\`; Stage-4 ROI exports live under `D:\Revision_EEG\stage4\roi\`; other Stage-4 outputs live under `C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output\stage4\...`.
- Official Stage-4 extraction-only output: `Revision_Output\stage4\stage4_extraction_fixedonly.csv` + `_meta.json`.
- Official Stage-4 threshold outputs (post-§7): `Revision_Output\stage4\sim_rough\thresholds_per_subject.json`, `thresholds_per_subject_half.json`, `rough_sigma_per_subject.csv`, plus `sim_null.csv`/`sim_injected.csv`/`sim_null_half.csv`. Superseded/provenance-only: `sim\` (no roughness), `sim_rough\thresholds.json` (pooled threshold with roughness).
- Zenodo deposit: DOI `10.5281/zenodo.23843194`, https://zenodo.org/records/23843194 — contains `stage4_frozen_code.zip` (= `revision/stage4/` at `bd96a95`) and `zenodo_preregistration_stage4.md`.
- **Official Stage-4 peak-detection output (§9):** `Revision_Output\stage4\peak_detection\` — `run_meta.json`, `peaks_primary.csv`, `peaks_all_in_range.csv`, `sensitivity_counts.csv`, `split_half.csv`, `split_half_summary.json`.

**Stage 5 (§10):**
- Implementation: `github/eeg-beta-project/revision/stage5/` — `stage5_soa_survey.py`,
  `stage5_export_roi_task.m`, `stage5_extraction_only_task.py`, `stage5_diag_knee_task.py`,
  `stage5_peak_detection_task.py`, `stage5_window_overlap_check.py`, `stage5_matched_length.py`, and the
  Track-A chain `stage5_export_trials_task.m`, `stage5_erd_by_condition.py`, `stage5_erd_stats.py`. The calibration path reuses
  `revision/stage4/stage4_core.py`, `stage4_calibrate_rough_sigma.py`, `stage4_simulate_threshold.py`,
  `stage4_per_subject_thresholds.py`, `stage4_simulate_half_threshold.py` and `diag_noise_floor_null.py`
  **unchanged** (§10d).
- Task ROI exports (Track B): `D:\Revision_EEG\stage5\roi\<sub>_msit_roi.mat` (39 files, 483 MB) +
  per-run manifests.
- Task trial exports (Track A): `D:\Revision_EEG\stage5\trials\<sub>_msit_trials.mat` + per-run
  `manifest_trials_<timestamp>.tsv` (not yet produced).
- Stage-5 outputs: `Revision_Output\stage5\` — `stage5_soa_per_subject.csv`,
  `stage5_soa_candidates.csv`, `stage5_soa_summary.json`, `manifest_roi_task_all39.tsv`,
  `stage5_extraction_task.csv` (+ `_meta.json`), `stage5_diag_knee_task.csv` (+ `_meta.json`),
  `stage5_diag_noise_floor_null_task.csv`, `rough_sigma_task_per_subject.csv` (+ `_points.csv`),
  `stage5_window_overlap_per_subject.csv`, `stage5_window_overlap_summary.json` (§10g),
  `erd\` (Track A: `stage5_erd_per_trial.csv`, `stage5_erd_per_subject_condition.csv`,
  `stage5_erd_meta.json`, `stage5_erd_stats_omnibus.csv`, `stage5_erd_stats_pairwise.csv`,
  `stage5_erd_stats_meta.json`),
  `sim_task\` (threshold simulation: `sim_null.csv`, `sim_injected.csv`, `thresholds.json` (pooled),
  `thresholds_per_subject.json`, `power_curve_per_subject.csv`, `detection_per_subject.csv`,
  `fpr_per_subject.csv`, `logistic_per_subject.json`, resumable in `parts_r1000\`),
  `sim_task_run.log`, `sim_task_half_run.log`,
  `sim_task_matched\` (length-matched nulls: `stage5_extraction_task_matched.csv`,
  `sim_null_matched.csv`, `thresholds_per_subject_matched.json`, resumable in `parts_matched_r1000\`),
  `sim_task_run.cmd` / `.pid` (detached-run bookkeeping, §10f).

## Next steps
1. ~~Rewrite `docs/zenodo_preregistration_stage4.md` §3.5, §3.5.2, §3.6, §3.8 to describe the §7 redesign.~~ Done.
2. ~~Add `revision/stage4/__pycache__/` to `.gitignore`.~~ Done (2026-10-31, local commit).
3. ~~Deposit the pre-registration text + frozen code (`bd96a95`) to Zenodo, obtain DOI.~~ Done — DOI `10.5281/zenodo.23843194` (§8).
4. ~~Log the DOI here.~~ Done (§8).
5. ~~Sync decision log + pre-registration doc (with DOI) into the actual repo.~~ Done — commit `9c53d5f85bf0e171207b7eae396890cc2f5d2548`.
6. ~~Run `stage4_peak_detection.py --doi 10.5281/zenodo.23843194` on real ROI data.~~ Done — results in §9.
7. ~~Sync this §9 entry into the actual repo's `docs/decision_log.md`~~ — **stale**, struck 2026-11-08: since §9 every edit has been made directly in this repo file, so there is nothing left to sync.
8. ~~Begin Stage 5 (task-based exploratory analysis): resolve the open boundary-event flag in MSIT/task bundles (§5, still unchecked as of this entry), define the task analysis window, and apply D12 for task.~~ Done — §10a–10e (boundary flag resolved and fixed; Track-A window fixed at 1000 ms; task D12 applied, 0 subjects excluded).
9. For manuscript writing: the 79% alpha-harmonic rate among primary peaks (§9) needs explicit discussion alongside the 61.5% headline peak-detection rate — flagged here so it isn't lost before drafting results/discussion text.
17. ~~Run `stage5_equivalence.py` and apply the §10m conjunction rule~~ — **done** 2026-11-08 (§10n): the conjunction **FAILS** (BF₀₁ = 2.51, inconclusive; TOST p = 0.373, equivalence only within ±21 %), so the pre-stimulus conflict result may not be called a null.
18. ~~Add the §10m control window and run the matched-estimator comparison~~ — **done** 2026-11-08 (§10p-2): +40.0 % beta elevation, of which 75 % is a general within-task level; the 55–95 Hz control band rises +36.8 %, so the EMG account is supported, not excluded. Originally: add the §10m control window to the Track A export under a new filename (never an overwrite), then compute the control band 55–95 Hz from the existing trial files, re-estimate resting beta at the same 500 ms segment length, and run the matched-estimator rest-vs-task comparison (`revision_plan.md` Stage 5; audit #5, #6; CLAUDE.md step 1). This is what unblocks the title.
19. ~~Decision for Amirhossein (§10n): a uniform trial-level robustness rule~~ — **answered and done** 2026-11-08 (§10o-1, §10p-1): median and 20 % trimmed mean, applied uniformly; every §10l verdict holds, but the §10n equivalence verdict flips, so both are reported. Originally: whether to add a uniform trial-level robustness rule (per-cell median, trimmed mean, or an outlier-trial criterion) as a labelled sensitivity analysis beside the pre-specified trial-averaged estimator. One trial supplies 89 % of one cell mean and reverses the parametric TOST verdict; 4 of 156 first-class cells have a largest-trial share above 0.25.
20. Decide the title and the framing (audit #17, CLAUDE.md step 5), now unblocked: §10p-2 replaced the +63–73 % figure with +40.0 %, showed three quarters of it is not pre-stimulus specific, and turned the control band from an unexcluded confound into a supported one.
21. Estimate and then carry out the manuscript rewrite (`revision_plan.md` Stage 7). The scope estimate is in `stage5_reconciliation.md`.

**Stage 5, open (as of 2026-11-01):**
10. ~~Calibrate the task thresholds~~ — **done**: σ_i (§10f), full-length (§10h), half-length (§10h, 54/54 cells), matched-length (§10h, 39/39 cells), every run with 0 fit failures. All three threshold sets needed by `stage5_peak_detection_task.py` now exist.
11. ~~Commit and tag `S5-task-peak-frozen`, then run `stage5_peak_detection_task.py`~~ — **done** 2026-11-02: tag at `bfc4365`, results in §10i (28 peak / 10 no_peak / 1 poor_fit; matched pass identical; split-half 97.4 %, ICC 0.938; rest-vs-task McNemar exact p = 0.2891).
12. ~~Evaluate §10d rule 5~~ — **evaluated and TRIGGERED** (§10h: max difference 0.0873, above 0.05 at six of ten levels). The length-matched secondary analysis is therefore required before any rest-vs-task prevalence comparison is reported.
13. ~~**Awaiting Amirhossein's sign-off (§10b):** whether Track A carries a pre-stimulus window ... in addition to the approved post-onset window.~~ Answered 2026-11-01: yes — baseline `[−500, 0)` ms added, ERD% is the primary metric, absolute post-onset power secondary (§10g). Windows verified empirically over all 39 subjects.
14. ~~Build and run Track A~~ — **done** 2026-11-08 (§10l): 39/39 exported, 15,335 of 15,492 trials usable, 0 subjects excluded; a graded conflict effect on post-onset ERD% with the §10k rule satisfied in all three mini-block classes. One axis bug in `stage5_erd_by_condition.py` found and fixed before any ERD% value existed. The headline effect size is the first-in-mini-block W = 0.135.
15. ~~Confirm the F/S/0 interference semantics of the four MSIT+ labels against Dzianok et al. 2022~~ — **done** 2026-11-02 (§10k): 0 = no interference, S = Simon, F = Flanker, FS = both. Page's L added to the Track A plan on the three ordered levels 00 < mean(F0, S0) < FS, with its decision rule written before the run.
16. ~~Compare the matched-task power curve with the rest curve and apply the `S5-matched-power` decision rule~~ — **done** 2026-11-02 (§10j): max |matched − rest| = 0.0815, above 0.05 at six of ten levels, so the second branch applies. No rest-vs-task prevalence difference is reported as a physiological result; length matching removed almost none of the gap (0.0873 → 0.0815), which identifies it as a spectral-roughness effect.
