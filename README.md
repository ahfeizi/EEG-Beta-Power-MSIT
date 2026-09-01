# Pre-Stimulus Beta Power During Task Anticipation — Analysis Code

Analysis code accompanying the manuscript (title under revision) on pre-stimulus beta
power increases during task anticipation, using the Nencki-Symfonia EEG dataset.

This repository contains the EEG preprocessing, feature-extraction, statistical, and
figure-generation code used in the manuscript. It does **not** contain raw EEG data.

## Dataset

All analyses use the publicly available **Nencki-Symfonia** EEG-ERP dataset:

- Dzianok, P., Antonova, E., Wojciechowski, J., Dreszer, J., & Kublik, E. (2022).
  *Nencki-Symfonia EEG/ERP dataset*. GigaScience.
- OpenNeuro accession: **ds004621** — https://openneuro.org/datasets/ds004621
- 128-channel resting-state and MSIT+ (conflict/task) EEG recordings from 42 healthy adults.

To reproduce the analyses, download ds004621 from OpenNeuro and set the dataset path
in each script (see **Setup** below).

## Repository structure

```
preprocessing/        Resting-state EEG preprocessing pipeline (EEGLAB: triage -> pilot -> full)
msit_task/             MSIT+ task epoching, baseline/pre-stimulus beta power, control-band power
feature_extraction/    Individual beta frequency (IBF) / beta-power feature extraction —
                        the five peak-detection methods reported in Table 1 (see below)
statistics/             Whole-scalp channel statistics, EMG-contamination test,
                        MSIT 4-condition comparison. All Wilcoxon signed-rank tests use
                        'method','exact' (see Methods in the manuscript).
figures/                Scripts that regenerate all manuscript figures (spectra, scalp maps,
                        paired rest-vs-task beta power, heatmaps)
exploratory/            Early/diagnostic scripts kept for methodological transparency:
                        subject-inclusion diagnostics, early peak-detection prototypes, and
                        superseded pilot-scale (5-subject) versions of the feature-extraction
                        scripts. Not part of the final reported pipeline.
derivatives/            Small aggregated output tables (CSV) used to regenerate figures/stats
                        without re-running the full EEGLAB pipeline. No raw/per-sample EEG data.
```

## Table 1 (beta peak detection methods) -> script mapping

| Method (Table 1)              | *n* lacking peak | Script                                       | Output CSV |
|--------------------------------|:---:|-----------------------------------------------|------------|
| Heuristic detrending           | 23 (54.8%) | `feature_extraction/Extract_beta_detrend_SGF_full42.m` | `beta_features_full42_detrend_sgf.csv` |
| Alpha-masked reanalysis        | 22 (52.4%) | `feature_extraction/extract_beta_alphamasked_full42.m` | `beta_features_full42_alphamasked.csv` |
| FOOOF/specparam (fixed)        | 24 (57.1%) | `feature_extraction/extract_IBF_full42.m` (run with `settings.aperiodic_mode = 'fixed'`) | `beta_features_full42_fixed.csv` |
| FOOOF/specparam (knee)         | 20 (47.6%) | `feature_extraction/extract_IBF_full42.m` (run with `settings.aperiodic_mode = 'knee'`)  | `beta_features_full42_knee.csv` |
| Savitzky-Golay (raw spectrum)  | 37 (88.1%) | `feature_extraction/extract_IBF_SGF.m`                  | `beta_features_full42_sgf.csv` |

**Note on `extract_IBF_full42.m`:** this single script produces both the FOOOF-fixed and
FOOOF-knee results depending on the `settings.aperiodic_mode` toggle near the top of the
file — run it twice (once per mode); the output filename is set automatically to match.

## Pipeline order (final, reported pipeline)

1. `preprocessing/preprocess_rest_eeglab_staged_Pilot.m` — resting-state preprocessing
   (filtering, ASR, ICA/ICLabel, epoching). Run with `RUN_MODE = 'triage'`, then `'pilot'`,
   then `'full'`.
2. `msit_task/msit_beta_erd_by_condition.m` — MSIT+ preprocessing + pre-stimulus
   (baseline) vs. post-stimulus beta power and control-band (55–95 Hz) power, by condition.
3. `feature_extraction/` — the five beta-peak-detection methods in Table 1 (see mapping above).
4. `feature_extraction/control_band_55_95_power_RS.m` — resting-state control-band power.
5. `statistics/beta_channel_stats_emg_test.m` — whole-scalp channel statistics + EMG
   contamination test (beta vs. control-band power correlation).
6. `figures/paired_figure_rest_task_beta_power.m` — rest vs. task pre-stimulus beta power
   figure (paired, Wilcoxon signed-rank, exact method).

## Requirements

- MATLAB (R2022b used for development)
- [EEGLAB](https://sccn.ucsd.edu/eeglab/) with plugins: `bva-io`, `clean_rawdata` (ASR),
  `ICLabel`, `firfilt`, `dipfit`; `CleanLine` and `Picard` optional (scripts fall back to
  a band-stop notch filter / `runica` if not installed)
- Signal Processing Toolbox (`pwelch`, `sgolayfilt`, `findpeaks`), Statistics and Machine
  Learning Toolbox (`signrank`)
- [FOOOF](https://fooof-tools.github.io/fooof/) MATLAB wrapper (`fooof_mat`, calling the
  Python `fooof` package via MATLAB's `pyenv` interface — Python 3.10 was used for
  development) for `feature_extraction/extract_IBF_full42.m`

## Setup

Each script has a `bidsRoot` / `derivRoot` (or `cfg.bidsRoot` / `cfg.derivRoot`) variable
near the top, marked `<-- EDIT`. Set these to:

- `bidsRoot` — local path to the downloaded ds004621 dataset
- `derivRoot` — local path where intermediate/derivative outputs should be written

### FOOOF / Python setup (required for `extract_IBF_full42.m` only)

`feature_extraction/extract_IBF_full42.m` (methods 3 and 4 in Table 1) calls a MATLAB
function `fooof()`, which is not built into MATLAB or EEGLAB — it comes from the
**fooof_mat** wrapper, which itself calls the Python `fooof` / specparam package via
MATLAB's `pyenv` interface. All other scripts in this repository are plain MATLAB/EEGLAB
and do **not** need this setup.

1. **Install Python 3.10** somewhere on your machine (a dedicated virtual environment is
   recommended, separate from MATLAB's own environment). This is the version used for
   development; MATLAB R2022b's `pyenv` interface requires a compatible Python version —
   check [MathWorks' supported-versions table](https://www.mathworks.com/support/requirements/python-compatibility.html)
   if you're on a different MATLAB release.
2. **Install the `fooof` package** into that Python environment:
   ```
   pip install fooof
   ```
3. **Point MATLAB at that Python install**, once per MATLAB session, *before* running the
   script:
   ```matlab
   pyenv('Version', '/full/path/to/python3.10')   % e.g. '/usr/bin/python3.10' or a venv path
   ```
4. **Download the fooof_mat wrapper** from
   [github.com/fooof-tools/fooof_mat](https://github.com/fooof-tools/fooof_mat) and add its
   folder to your MATLAB path (`addpath` or the Set Path dialog). This is what provides the
   `fooof(...)` function the script calls.
5. **Sanity-check the setup** on a small dummy signal before running the full 42-subject
   loop, e.g.:
   ```matlab
   f = (1:0.5:40)'; psd = 10.^(2 - 1.2*log10(f)) + 0.1*rand(size(f));
   fr = fooof(f, psd, [3 40], struct('aperiodic_mode','fixed','verbose',false), false);
   disp(fr.r_squared)   % should run without error and print a value close to 1
   ```
   If step 5 errors out, the issue is almost always step 3 (pyenv not pointed at a Python
   that has `fooof` installed) or step 4 (fooof_mat not on the MATLAB path).

## Statistical note

All two-sided Wilcoxon signed-rank tests (rest vs. task comparisons, whole-scalp
channel-level tests, MSIT 4-condition pairwise comparisons) are computed with
`signrank(...,'method','exact')`, matching what is reported in the manuscript's Methods
section. With n = 42 paired observations, MATLAB's `signrank` defaults to the
large-sample normal approximation unless `'method','exact'` is specified explicitly,
which yields different (less extreme) p-values — this is set explicitly throughout.

## Citing

If you use this code, please cite the manuscript (citation to be added upon publication)
and the original dataset (Dzianok et al., 2022).

## License

MIT License — see `LICENSE`.
