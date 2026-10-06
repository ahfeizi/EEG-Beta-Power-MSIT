# HISTORICAL: D5-0 run of 2026-10-04 (do not run, do not edit)

These files document what was executed on 2026-10-04 for the D5-0 line-noise diagnostic
(decision log: S3a-D5-0, S3a-D5-0-exc, S3a-D5-0-crash, S3a-D5-0-hist). They were moved here
unchanged on 2026-10-06 from Claude Code session scratchpads under `%TEMP%` (same-volume moves,
no content change). They are kept for provenance only. Paths inside them are the ones that were
used at the time.

The D5-0 outputs they relate to (`<outRoot>/stage3/d5_0/per_recording/*.mat`, 78 files) are **not
used** for any decision (S3a-D5-0-crash). D5-0 is recomputed under S3a-INF-1.

| File | What it is | Origin |
|---|---|---|
| `run_d5_0.ps1` | The driver: one fresh `matlab -batch` per recording, at most 2 tries, then the assembly call. Ran 14:26–16:52 local. | scratchpad of session `1680c193…` |
| `stage3_d5_0_line_noise_pre_exc_reconstructed.m` | **Reconstruction** of `stage3_d5_0_line_noise.m` as it stood before the S3a-D5-0-exc edit, i.e. the version the driver most likely ran. See below. | rebuilt 2026-10-06 from the session transcript |
| `d50_probe.m` | Crash-bisection probe (modes load … full). Results were discarded. | scratchpad of session `1680c193…` |
| `check_d50_cache.m`, `check_d50_cache.log` | Post-crash structural check of the 78 cached files (loads, variables, shapes, finiteness, labels). | scratchpad of session `83244725…` |
| `d50_cache_sha256_2026-10-04.txt` | SHA-256 of the 78 cached `.mat` files, recorded 2026-10-04 19:44. | scratchpad of session `83244725…` |
| `d5_notch_design.m`, `d5_notch_design_output_2026-10-04.txt` | Synthetic-only design of the default `pop_eegfiltnew` band-stop kernels at 500 Hz (D5 option (a)); the output was captured from the session transcript (it was never saved to a file at the time). | scratchpad / transcript of session `1680c193…` |

## The pre-`-exc` script version

The exact bytes of `stage3_d5_0_line_noise.m` that the driver executed were **not recorded at run
time** (no hash, no commit). The current file in `revision/stage3/` contains the S3a-D5-0-exc edit,
saved 16:55:45 local, after the driver ended.

`stage3_d5_0_line_noise_pre_exc_reconstructed.m` was rebuilt from the tool calls in the session
transcript: one `Write` (10:32:09 UTC), two `Edit`s (10:32:40 and 10:32:41 UTC), which give this file.
The `-exc` patch (13:25:44 UTC = 16:55:44 local) was then re-applied to it from the same transcript.
The result is **byte-identical** to the current `revision/stage3/stage3_d5_0_line_noise.m`
(SHA-256 `1ae3f629…87c0`).

- What this shows: the logged edits fully account for the current file.
- What it cannot show: that nothing else (for example the MATLAB editor) changed the file on disk
  between 14:02 and 16:55 local. The reconstruction is therefore the most likely executed version,
  not a verified one.
- SHA-256 of the reconstruction: `9ea3b34f39b563ae1e1021b8b7764e3a26eddea20447048fc76e61606bd742ca`.
