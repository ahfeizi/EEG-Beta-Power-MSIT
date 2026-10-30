"""Stage 4 shared pipeline (docs/zenodo_preregistration_stage4.md, §3.2-3.6 and §3.8).

Used identically by stage4_extraction_only.py, stage4_simulate_threshold.py and stage4_peak_detection.py,
so real and simulated data pass through the same code.

Leakage rule (§3.7): the extraction-only script may call only load_roi, welch_runs, aperiodic_only,
select_model and noise_floor. full_fit, run_pipeline and the peak functions (periodic fit, peaks) are for
the simulation and, after the Zenodo DOI is logged, the peak-detection script.
"""
import warnings

import numpy as np
from scipy.io import loadmat
from scipy.signal import welch

with warnings.catch_warnings():
    warnings.simplefilter('ignore', DeprecationWarning)   # fooof 1.1 announces its successor on import
    import fooof
    from fooof import FOOOF
    from fooof.core.errors import FitError
    from fooof.core.funcs import gaussian_function
    from fooof.sim.gen import gen_aperiodic

FOOOF_VERSION = '1.1.1'                                   # §3.4, §5
assert fooof.__version__ == FOOOF_VERSION, f'fooof {fooof.__version__} found, {FOOOF_VERSION} required'

ROI = ('C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2')      # §3.3
EPOCH_S = 2.0                                             # §3.1.1 pseudo-epoch = §3.2 Welch segment
FIT_RANGE = (2.0, 40.0)                                   # §3.2, §3.4, inclusive
N_BINS = 77                                               # §3.2
DBIC_KNEE = 10.0                                          # §3.4: knee only if BIC_fixed - BIC_knee > 10
K_PARAMS = {'fixed': 2, 'knee': 3}                        # §3.4
FOOOF_SETTINGS = dict(peak_width_limits=[1, 8], max_n_peaks=np.inf, peak_threshold=2, min_peak_height=0)  # §3.5
BETA = (13.0, 30.0)                                       # §3.5, inclusive
BW_RANGE = (1.0, 8.0)                                     # §3.5, inclusive
ALPHA = (8.0, 13.0)                                       # §3.5 alpha-harmonic sensitivity, inclusive
HARMONIC_TOL = 2.0                                        # §3.5: |CF - 2 x IAF| <= 2 Hz
R2_POOR = 0.90                                            # §3.5.1
NOISE_BANDS = {'noise_2_12Hz': (2.0, 12.0), 'noise_31_40Hz': (31.0, 40.0)}   # §3.7, inclusive
NOISE_DDOF = 1                                            # §3.7 noise SD with n - 1 (decided 2026-10-30)
HP_EDGE = 0.5                                             # §3.6: generative spectrum zero below 0.5 Hz


def load_roi(path):
    """Read one <sub>_rest_roi.mat written by stage4_export_roi.m (-v7) and check its structure."""
    m = loadmat(path, squeeze_me=False)
    rec = dict(
        subject=str(m['subject'].ravel()[0]),
        fs=float(m['fs'].item()),
        roi_labels=tuple(str(np.ravel(x)[0]) for x in m['roiLabels'].ravel()),
        runs=[np.asarray(r, dtype=np.float64) for r in m['runs'].ravel()],   # each (7, n), uV, time order
        run_len_epochs=[int(v) for v in np.ravel(m['runLenEpochs'])],
        n_pseudoepochs_total=int(m['nPseudoTotal'].item()),
        n_pseudoepochs_kept=int(m['nKept'].item()),
        n_outside=int(m['nOutside'].item()),
        excluded_D12=bool(m['excludedD12'].item()),
    )
    assert rec['roi_labels'] == ROI, f"{rec['subject']}: ROI labels {rec['roi_labels']}"
    epoch = int(round(EPOCH_S * rec['fs']))
    assert [r.shape for r in rec['runs']] == [(len(ROI), k * epoch) for k in rec['run_len_epochs']]
    assert sum(rec['run_len_epochs']) == (0 if rec['excluded_D12'] else rec['n_pseudoepochs_kept'])
    return rec


def welch_runs(runs, fs):
    """§3.2: Welch (Hann, 2 s, 50 % overlap, detrend 'constant', average 'mean', density) within each run;
    per-channel PSDs pooled over all windows of all runs (equal weight per window), then averaged over the
    channels on linear power. runs: list of (n_channels, n_samples) arrays in uV.
    Returns freqs (Hz) and psd (uV^2/Hz) over 0 .. fs/2."""
    nper = int(round(EPOCH_S * fs))
    assert abs(nper - EPOCH_S * fs) < 1e-9 and nper % 2 == 0
    nover = nper // 2
    acc, n_win = None, 0
    for x in runs:
        x = np.atleast_2d(np.asarray(x, dtype=np.float64))
        assert x.shape[1] >= nper, 'run shorter than one Welch window'
        w = (x.shape[1] - nover) // (nper - nover)        # number of windows scipy places in this run
        f, p = welch(x, fs=fs, window='hann', nperseg=nper, noverlap=nover, detrend='constant',
                     scaling='density', average='mean', axis=-1)
        acc = p * w if acc is None else acc + p * w       # undo the per-run mean -> sum over windows
        n_win += w
    return f, (acc / n_win).mean(axis=0)


def _fooof(mode):
    return FOOOF(aperiodic_mode=mode, verbose=False, **FOOOF_SETTINGS)


def aperiodic_only(freqs, psd, mode):
    """§3.4: fooof's robust aperiodic fit (_robust_ap_fit), i.e. the aperiodic curve before any peak is
    fitted, over 2-40 Hz. Returns the parameters, the curve and log10 power on the 77 fit bins, RSS,
    BIC = n ln(RSS/n) + k ln(n) and R^2 (fooof's definition: squared correlation of log10 power and curve).
    ok is False if the fit fails or the curve is not finite (e.g. knee < -f^exponent)."""
    fm = _fooof(mode)
    fm.add_data(freqs, psd, list(FIT_RANGE))              # trims to 2-40 Hz inclusive, log10 power
    n = fm.freqs.size
    assert n == N_BINS, f'{n} bins in {FIT_RANGE}, {N_BINS} expected'
    out = dict(mode=mode, ok=False, freqs=fm.freqs, logpow=fm.power_spectrum,
               params=np.full(K_PARAMS[mode], np.nan), curve=np.full(n, np.nan),
               rss=np.nan, bic=np.nan, r2=np.nan)
    try:
        params = fm._robust_ap_fit(fm.freqs, fm.power_spectrum)
    except FitError:
        return out
    out['params'] = params
    curve = gen_aperiodic(fm.freqs, params, mode)
    if not np.all(np.isfinite(curve)):
        return out
    rss = float(np.sum((fm.power_spectrum - curve) ** 2))
    k = K_PARAMS[mode]
    out.update(ok=True, curve=curve, rss=rss, bic=float(n * np.log(rss / n) + k * np.log(n)),
               r2=float(np.corrcoef(fm.power_spectrum, curve)[0, 1] ** 2))
    return out


def select_model(ap_fixed, ap_knee):
    """§3.4: 'knee' only if its aperiodic-only fit succeeded and BIC_fixed - BIC_knee > 10; else 'fixed'."""
    assert ap_fixed['ok'], 'fixed aperiodic-only fit failed'
    if ap_knee['ok'] and ap_fixed['bic'] - ap_knee['bic'] > DBIC_KNEE:
        return 'knee'
    return 'fixed'


def noise_floor(ap):
    """§3.7: SD of the aperiodic-only residual (log10 power - curve, selected model) in 2-12 and 31-40 Hz."""
    resid = ap['logpow'] - ap['curve']
    return {name: float(np.std(resid[(ap['freqs'] >= lo) & (ap['freqs'] <= hi)], ddof=NOISE_DDOF))
            for name, (lo, hi) in NOISE_BANDS.items()}


def full_fit(freqs, psd, mode):
    """§3.5: full fooof fit (aperiodic + peaks, settings FOOOF_SETTINGS) with the selected aperiodic mode.
    Returns fit_ok, the full model's R^2 and peaks (n x 3: CF, PW, BW = fooof's peak_params_)."""
    fm = _fooof(mode)
    fm.fit(freqs, psd, list(FIT_RANGE))                   # fooof catches its own FitError -> no model
    if not fm.has_model:
        return dict(fit_ok=False, r2=np.nan, peaks=np.empty((0, 3)))
    return dict(fit_ok=True, r2=float(fm.r_squared_), peaks=np.reshape(fm.peak_params_, (-1, 3)))


def run_pipeline(freqs, psd, simulated=False):
    """§3.4-3.5: both aperiodic-only fits -> ΔBIC model choice -> full fit with the chosen mode.
    Failures (decided 2026-10-30): a failed knee fit leaves 'fixed' (select_model). A failed fixed
    aperiodic-only fit stops on real data; on simulated data it returns fit_failed = True with no peaks
    (counted as a non-detection, max PW = 0). A failed full fit gives fit_ok = False: 'poor_fit' on real
    data (classify), fit_failed = True with no peaks on simulated data."""
    ap_fixed = aperiodic_only(freqs, psd, 'fixed')
    ap_knee = aperiodic_only(freqs, psd, 'knee')
    if not ap_fixed['ok']:
        if not simulated:
            raise RuntimeError('fixed aperiodic-only fit failed on real data: stop and report')
        return dict(fit_ok=False, fit_failed=True, r2=np.nan, peaks=np.empty((0, 3)), model_chosen='',
                    ap_fixed=ap_fixed, ap_knee=ap_knee)
    mode = select_model(ap_fixed, ap_knee)
    res = full_fit(freqs, psd, mode)
    res.update(fit_failed=not res['fit_ok'], model_chosen=mode, ap_fixed=ap_fixed, ap_knee=ap_knee)
    return res


def beta_peaks(peaks):
    """§3.5: Gaussians with CF in [13, 30] Hz and BW in [1, 8] Hz, tallest (highest PW) first."""
    cf, bw = peaks[:, 0], peaks[:, 2]
    p = peaks[(cf >= BETA[0]) & (cf <= BETA[1]) & (bw >= BW_RANGE[0]) & (bw <= BW_RANGE[1])]
    return p[np.argsort(-p[:, 1], kind='stable')]


def max_beta_pw(peaks):
    """§3.6: maximum PW among the beta-range Gaussians, 0 if there is none."""
    bp = beta_peaks(peaks)
    return float(bp[0, 1]) if len(bp) else 0.0


def classify(res, thr, apply_poor_fit=True):
    """§3.5 / §3.5.1: 'poor_fit' if the full model failed or its R^2 < 0.90 (only if apply_poor_fit);
    else 'peak' if a beta-range Gaussian has PW >= thr, else 'no_peak'."""
    if apply_poor_fit and not (res['fit_ok'] and res['r2'] >= R2_POOR):
        return 'poor_fit'
    return 'peak' if max_beta_pw(res['peaks']) >= thr else 'no_peak'


def alpha_harmonic(peaks):
    """§3.5 sensitivity: IAF = CF of the tallest Gaussian with CF in [8, 13] Hz (NaN if none); returns IAF
    and, for each beta-range peak (beta_peaks order), whether |CF - 2 x IAF| <= 2 Hz."""
    bp = beta_peaks(peaks)
    cf = peaks[:, 0]
    a = peaks[(cf >= ALPHA[0]) & (cf <= ALPHA[1])]
    if not len(a):
        return np.nan, np.zeros(len(bp), dtype=bool)
    iaf = float(a[np.argmax(a[:, 1]), 0])
    return iaf, np.abs(bp[:, 0] - 2 * iaf) <= HARMONIC_TOL


def simulate_runs(rng, run_lengths, fs, offset, exponent, cf=None, bw=None, pw=None):
    """§3.6: one simulated signal per run length (samples): Gaussian white noise filtered in the frequency
    domain by sqrt(target PSD), target PSD = 10^(offset - log10(f^exponent) [+ PW Gaussian]) in uV^2/Hz,
    zero below 0.5 Hz (DC included). The Gaussian follows fooof's convention BW = 2 SD, so pw is in PW
    units. Returns a list of (1, n) arrays: the same structure as the real runs (single-signal unit)."""
    out = []
    for n in run_lengths:
        f = np.fft.rfftfreq(n, d=1.0 / fs)
        m = f >= HP_EDGE
        logp = gen_aperiodic(f[m], [offset, exponent], 'fixed')
        if pw is not None:
            logp = logp + gaussian_function(f[m], cf, pw, bw / 2.0)
        target = np.zeros_like(f)
        target[m] = 10.0 ** logp
        # unit-variance white noise has one-sided density 2/fs, so a gain of sqrt(target * fs / 2) gives target
        x = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * np.sqrt(target * fs / 2.0), n=n)
        out.append(x[None, :])
    return out


def split_half_runs(runs, fs):
    """§3.8: cut the runs (time order) into their kept 2 s epochs; odd sequential index among the kept
    epochs (1st, 3rd, ...) -> half 1, even -> half 2. Each epoch becomes its own run, so each half gets one
    non-overlapping Welch window per epoch."""
    L = int(round(EPOCH_S * fs))
    epochs = [r[:, i:i + L] for r in runs for i in range(0, r.shape[1], L)]
    return epochs[0::2], epochs[1::2]
