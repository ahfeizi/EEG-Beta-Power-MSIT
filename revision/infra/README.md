# revision/infra: crash-tolerant A/B runner (S3a-INF-1)

Implements decision-log entries **S3a-INF-1** (`df80384`), **S3a-INF-1-clar1**, **S3a-INF-1-amend1** and **S3a-INF-1-amend2** (timeouts for job types other than D5-0). Every heavy
Stage 3 MATLAB job runs as a fresh `MATLAB.exe -batch` process, twice (A, B), and is accepted only if
the two outputs are content-identical; otherwise a third replica (C) decides. Since S3a-INF-1-amend1, MATLAB
crashes are expected (up to 5 attempts per replica), there is no thermal monitoring, and a kernel crash is
handled by resuming with the same command (verified outputs are re-hashed, everything else is reset).

## Files

| File | Role |
|---|---|
| `Invoke-Stage3Chain.ps1` | The amend1 chain: acceptance sub-06 MSIT+ × 11 → rest × 3 (timing) → `Timeouts` → D5-0 job list → D5-0 batch. Rerun the same command to resume. Log: `<EegOutRoot>\stage3_runs\chain.log`. |
| `Invoke-Stage3JobTypeChain.ps1` | The amend2 chain for another job type: timing run(s) (`Acceptance -TimingOnly`, 3 replicas) → `JobTimeouts` → Batch with `-JobTimeouts`. Rerun the same command to resume. Log: `<EegOutRoot>\stage3_runs\chain_<Name>.log`. |
| `Invoke-Stage3Batch.ps1` | Runner. Modes `Batch` (optional `-JobTimeouts`), `Acceptance`, `BurnIn` (incl. `-Calibrate`), `Timeouts`, `JobTimeouts`. One command starts or resumes a batch (`-BatchId`). |
| `Export-Stage3D50Assembly.ps1` | Writes the D5-0 CSVs and `run_info.txt` (S3a-D5-0-asm) from the verified output of a D5-0 assembly batch; never overwrites. |
| `Stage3Runner.psm1` | Runner functions: atomic (flushed) JSON, journal, entry hash, event counts, MATLAB process control. |
| `runner_config.psd1` | All thresholds, paths and seeds. Its SHA-256 goes into every fingerprint and summary. |
| `stage3_job.m` | Worker: one replica of one job in one process (threads, seed, fingerprint, job function, partial → final rename, DONE marker). |
| `stage3_env_fingerprint.m` | Environment fingerprint and the §1 assertions (no pool, `Pool.AutoCreate` false, `option_parallel` 0, no `hlp_diskcache`). |
| `stage3_compare.m` | Content comparison of two outputs (kinds `d5_0`, `burnin`, `all`; `set` reserved). |
| `stage3_check_input.m` | SHA-256 check of a raw input file against `verified_manifest.tsv`. |
| `stage3_burnin.m` | Burn-in job function (D5-0 kernel block + 2000×2000 GEMM block per iteration). |
| `Test-Stage3Prechecks.ps1` | The five batch-start pre-checks of S3a-INF-1-clar1 (without the burn-in, amend1). |
| `Copy-Stage3VerifiedState.ps1` | Q9 carry-over of verified recordings into a new batch (optional since amend1: a kernel crash no longer stops a batch). |
| `Write-Stage3Summary.ps1` | `summary.csv` / `summary.txt` (§9), copied to `<OutRoot>\stage3\runs\`. |
| `Get-Stage3SystemEvents.ps1` | §7 event counts (WHEA, BugCheck 1001, Kernel-Power 41, Application Error 1000 for MATLAB.exe). |
| `New-Stage3JobList.ps1` | Writes a job list: `d5_0` and `d4e4` (one job per recording of the D4e block table), `d5_0_asm` (the single D5-0 assembly job). |
| `stage3_noop.m`, `stage3_loadcheck.m` | Helpers (pre-check fingerprint; Q9 load check). |
| `tests/` | Synthetic tests only: `Test-Stage3Runner.ps1`, `stage3_testjob.m`. |

Job functions (in `revision/stage3/`) and their synthetic tests:
- D5-0: `stage3_d5_0_compute_one.m`; equivalence with the original script: `test_stage3_d5_0_compute_one.m`.
- D5-0 assembly (S3a-D5-0-asm): `stage3_d5_0_assemble.m`, export `stage3_d5_0_export.m`; equivalence with the script's assembly: `test_stage3_d5_0_assemble.m`.
- D4e-4 label test (S3a-D4e-4-test-approval): `stage3_d4e4_compute_one.m`; `test_stage3_d4e4_compute_one.m`.

## Output locations

- Batch folder: `<EegOutRoot>\stage3_runs\<BatchId>\` (on D:). It holds:
  - `batch.json`, `journal.csv`, `state\<job>.json`;
  - `jobs\<job>\<replica>\attempt<k>\{spec.json, job.log, fingerprint.json, out.mat}`;
  - `compare\*.json`;
  - `acceptance.json` (Acceptance and BurnIn modes);
  - `summary.csv` and `summary.txt`.
- Summary copies: `<OutRoot>\stage3\runs\<BatchId>_summary.csv|txt` (and `<BatchId>_acceptance.json`).
- Timeouts: `<EegOutRoot>\stage3_runs\timeouts.json`, with a copy in `<OutRoot>\stage3\runs\`; job-type timeouts (amend2): `timeouts_<Name>.json` next to it, also copied.

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
   - `recType` selects the timeout in `timeouts.json`. A new recording type needs its own timing run first: `Invoke-Stage3JobTypeChain.ps1` does the timing run, writes `timeouts_<Name>.json` (`JobTimeouts` mode) and runs the batch with `-JobTimeouts` (S3a-INF-1-amend2).
   - Add a `-Type` to `New-Stage3JobList.ps1`, or write the JSON directly.
4. **Log the job type's decision rule** in `docs/decision_log.md` before it runs on real data, then run `Invoke-Stage3Batch.ps1 -Mode Batch -JobList <list>`.

The two job types deferred by S3a-INF-1-clar1 item 8 use this route since 2026-10-10: the D5-0 assembly
(`-Type d5_0_asm`, batch `d5asm_1`) and the D4e-4 label test (`-Type d4e4`, batch `d4e4_1`).

## Configuration items to set before real runs

- `parallel.Settings` `Pool.AutoCreate` must be false (every job asserts it).
- `TestMode` must stay `$false`.
