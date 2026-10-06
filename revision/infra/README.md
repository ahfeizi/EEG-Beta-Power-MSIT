# revision/infra: crash-tolerant A/B runner (S3a-INF-1)

Implements decision-log entries **S3a-INF-1** (`df80384`) and **S3a-INF-1-clar1**. Every heavy
Stage 3 MATLAB job runs as a fresh `MATLAB.exe -batch` process, twice (A, B), and is accepted only if
the two outputs are content-identical; otherwise a third replica (C) decides.

## Files

| File | Role |
|---|---|
| `Invoke-Stage3Batch.ps1` | Runner. Modes `Batch`, `Acceptance`, `BurnIn` (incl. `-Calibrate`), `Timeouts`. One command starts or resumes a batch (`-BatchId`). |
| `Stage3Runner.psm1` | Runner functions: HWiNFO log reader and gates, atomic JSON, journal, entry hash, event counts, MATLAB process control. |
| `runner_config.psd1` | All thresholds, paths and seeds. Its SHA-256 goes into every fingerprint and summary. |
| `stage3_job.m` | Worker: one replica of one job in one process (threads, seed, fingerprint, job function, partial → final rename, DONE marker). |
| `stage3_env_fingerprint.m` | Environment fingerprint and the §1 assertions (no pool, `Pool.AutoCreate` false, `option_parallel` 0, no `hlp_diskcache`). |
| `stage3_compare.m` | Content comparison of two outputs (kinds `d5_0`, `burnin`, `all`; `set` reserved). |
| `stage3_check_input.m` | SHA-256 check of a raw input file against `verified_manifest.tsv`. |
| `stage3_burnin.m` | Burn-in job function (D5-0 kernel block + 2000×2000 GEMM block per iteration). |
| `Test-Stage3Prechecks.ps1` | The five batch-start pre-checks of S3a-INF-1-clar1. |
| `Copy-Stage3VerifiedState.ps1` | Q9 carry-over of verified recordings into a new batch after a kernel-crash stop. |
| `Write-Stage3Summary.ps1` | `summary.csv` / `summary.txt` (§9), copied to `<OutRoot>\stage3\runs\`. |
| `Get-Stage3SystemEvents.ps1` | §7 event counts (WHEA, BugCheck 1001, Kernel-Power 41, Application Error 1000 for MATLAB.exe). |
| `New-Stage3JobList.ps1` | Writes a job list (type `d5_0`: one job per recording of the D4e block table). |
| `stage3_noop.m`, `stage3_loadcheck.m` | Helpers (pre-check fingerprint; Q9 load check). |
| `tests/` | Synthetic tests only: `Test-Stage3Runner.ps1`, `Start-FakeHwinfo.ps1`, `stage3_testjob.m`. |

The D5-0 job function is `revision/stage3/stage3_d5_0_compute_one.m`. Its equivalence with the
original script is tested on synthetic data by `revision/stage3/test_stage3_d5_0_compute_one.m`.

## Output locations

- Batch folder: `<EegOutRoot>\stage3_runs\<BatchId>\` (on D:). It holds:
  - `batch.json`, `journal.csv`, `state\<job>.json`;
  - `jobs\<job>\<replica>\attempt<k>\{spec.json, job.log, fingerprint.json, out.mat}`;
  - `compare\*.json`;
  - `acceptance.json` (Acceptance and BurnIn modes);
  - `summary.csv` and `summary.txt`.
- Summary copies: `<OutRoot>\stage3\runs\<BatchId>_summary.csv|txt` (and `<BatchId>_acceptance.json`).
- Timeouts: `<EegOutRoot>\stage3_runs\timeouts.json`, with a copy in `<OutRoot>\stage3\runs\`.

## Adding a job type

A job type is a MATLAB function plus parameters. The infrastructure does not change.

1. **Write the job function** `myjob(params, partialFile)`:
   - It must write exactly one MAT file, `partialFile`, with `save(partialFile, ...)`. The worker renames it to the final name only after the function returns. It must write nothing else outside its own attempt folder.
   - It must call `stage3_check_input(file, params.rawRoot, params.manifest)` for **every** raw file before reading it.
   - It must not draw random numbers without first setting `rng(<step seed>, 'twister')`. A per-step seed constant is added to `StepSeeds` in `runner_config.psd1` and logged in the decision log first.
   - It must not use `parfor` or a parallel pool.
   - `params` contains the job's own parameters, plus `rawRoot`, `manifest`, `blockTable`, `seedGlobal`, `replica` and `attempt`.
2. **Choose a compare kind** in `stage3_compare.m`:
   - use `'all'` (every variable), or
   - add a case that lists the fields to compare, as `'d5_0'` does.

   The comparison reports only equal / number differing / maximum absolute difference.
3. **Write a job list.** Each job is `{ id, func, params, recType, compareKind }`:
   - `recType` selects the timeout in `timeouts.json`. A new recording type needs its own acceptance timing first.
   - Add a `-Type` to `New-Stage3JobList.ps1`, or write the JSON directly.
4. **Log the job type's decision rule** in `docs/decision_log.md` before it runs on real data, then run `Invoke-Stage3Batch.ps1 -Mode Batch -JobList <list>`.

Deferred job types that are meant to use this route (S3a-INF-1-clar1 item 8): the D4e-4 label test
(test N: 6 recordings, test P: 84) and the D5-0 assembly (R1–R3 from the canonical outputs).

## Configuration items to set before real runs

- `HwinfoCsv`: the path of the HWiNFO CSV log (HWiNFO logging every 2 s, non-essential sensors off).
- `parallel.Settings` `Pool.AutoCreate` must be false (every job asserts it).
- `TestMode` must stay `$false`.
