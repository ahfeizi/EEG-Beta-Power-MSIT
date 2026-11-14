"""Review round 1, Phase 1: helpers shared by the r1_* scripts (decision log §11).

The Stage-4 pipeline is imported unchanged from revision/stage4 (byte-identical to the Zenodo deposit,
DOI 10.5281/zenodo.23843194): generator, Welch, fooof fit and peak criterion are never re-implemented here.
"""
import csv
import hashlib
import json
import os
import sys

import numpy as np
from scipy.stats import binomtest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(REPO, 'revision', 'stage4'))

import stage4_core as core               # noqa: E402  (unchanged frozen code)
import stage4_simulate_threshold as sim  # noqa: E402  (read_pairs: per-subject offset, exponent, sigma, runs)

DECISION_LOG = os.path.join(REPO, 'docs', 'decision_log.md')
CI_LEVEL = 0.95


def sha256(path):
    with open(path, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def provenance(script_path, inputs):
    """Hashes that tie a run to the rule and code on disk at run time (§11 preamble)."""
    return dict(script=os.path.basename(script_path), script_sha256=sha256(script_path),
                r1_common_sha256=sha256(os.path.abspath(__file__)),
                stage4_core_sha256=sha256(core.__file__),
                decision_log_sha256=sha256(DECISION_LOG),
                inputs={k: dict(path=v, sha256=sha256(v)) for k, v in inputs.items()},
                fooof_version=core.FOOOF_VERSION, numpy_version=np.__version__)


def cp_ci(k, n):
    """Clopper-Pearson (exact) 95 % CI, as in §4 Q6."""
    if n == 0:
        return float('nan'), float('nan')
    ci = binomtest(int(k), int(n)).proportion_ci(confidence_level=CI_LEVEL, method='exact')
    return float(ci.low), float(ci.high)


def peaks_to_str(peaks):
    """All beta-range Gaussians (core.beta_peaks order, tallest first) as 'cf:pw:bw;...'."""
    bp = core.beta_peaks(peaks)
    return ';'.join(f'{cf:.4f}:{pw:.5f}:{bw:.4f}' for cf, pw, bw in bp)


def str_to_peaks(s):
    if not s:
        return np.empty((0, 3))
    return np.array([[float(v) for v in p.split(':')] for p in s.split(';')])


def write_csv(path, rows, fields=None):
    """Write via a temporary file, so a part file exists only when complete (resumable runs)."""
    tmp = path + '.tmp'
    fields = fields or list(rows[0])
    with open(tmp, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    os.replace(tmp, path)


def read_csv(path):
    with open(path, newline='') as fh:
        return list(csv.DictReader(fh))


def refuse_existing(paths):
    for p in paths:
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')


def read_thresholds(path):
    with open(path) as fh:
        d = json.load(fh)
    assert d.get('test_run') is False, f'{path}: not the calibration run'
    return {s: v['p95'] for s, v in d['thresholds'].items()}


def read_classes(peaks_primary_csv):
    return {r['subject']: r['class_p95'] for r in read_csv(peaks_primary_csv)}
