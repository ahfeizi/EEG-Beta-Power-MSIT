"""Stage 5: Bayes factors and equivalence tests on the pre-stimulus conflict null (sec 10m).

    python stage5_equivalence.py --cells <outRoot>/stage5/erd/stage5_erd_per_subject_condition.csv \
        --out-dir <outRoot>/stage5/equivalence

Why. sec 10l found that pre-stimulus beta power does not differ across the four MSIT+ conditions in the
first-in-mini-block class (Friedman p = 0.223), the class where the upcoming condition is unpredictable and
the test is therefore fair. A non-significant Friedman is a failure to reject, not evidence of absence, so
`revision_plan.md` Stage 6 and audit item #1 require BF01 and TOST alongside the split before the
manuscript may call it a null. This script supplies both. Its decision rule is in sec 10m, written and
committed before it was first run.

Scale. Every test is on the within-subject difference of log10 band power, i.e. log10 of the ratio between
two conditions. Power is strictly positive and multiplicative, the ratio is the quantity the manuscript
interprets, and a bound symmetric on this scale is symmetric in the ratio - which the v1 +-10 % bound was
not (audit #10 notes it meant +10 % / -9.1 %). One scale and one bound serve both bands and both kinds of
comparison, which is what audit #11 asks for.

Metrics (both strictly positive, so the log ratio is always defined):
  baseline_power_mean   PRIMARY: pre-stimulus 13-30 Hz power, the quantity the conflict claim is about
  active_power_mean     POSITIVE CONTROL: sec 10l found a large condition effect here, so BF10 must come
                        out large; a null-looking result on this metric would indict the implementation

Mini-block classes, each analysed separately (sec 10g, sec 10l): `first` is primary - the condition is
unpredictable and the baseline sits a median 2,940 ms after the previous response; `later` and `all` are
reported for contrast only, because their baselines are contaminated by the preceding same-condition trial.

Bayes factor. JZS / Jeffreys-Zellner-Siow default Bayes factor for the paired t-test, as in Rouder,
Speckman, Sun, Morey & Iverson (2009), Psychon Bull Rev 16:225-237: a Cauchy(0, r) prior on the
standardised effect and a Jeffreys prior on the variance, integrated over the inverse-gamma(1/2, 1/2)
mixing variable g. The default scale r = 0.707 is primary, with r = 0.5 and r = 1.0 reported as a
robustness check. BF01 = 1 / BF10.

No third-party Bayes-factor implementation is installed in this environment, so the implementation is
verified against ITSELF by three mathematically distinct routes, and that is stated plainly rather than
called an independent check of the formula:
  (a) quadrature over the mixing variable g (the Rouder et al. expression),
  (b) quadrature over the effect size delta against a noncentral-t likelihood - a different
      parameterisation of the same model, using scipy.stats.nct,
  (c) Monte Carlo over draws of g from its inverse-gamma prior.
`verify_bf()` runs (a) vs (b) on a grid of (t, n, r) and refuses to continue unless they agree to a
relative 1e-6; (c) is reported in the metadata.

Equivalence. TOST (Schuirmann, 1987) as two one-sided paired t-tests on the log10 ratio against the bound
recorded in sec 10m, plus:
  - the 90 % CI of the mean log10 ratio, which is the PRIMARY report because it is bound-free: equivalence
    at any bound can be read off it, so the choice of bound cannot drive the conclusion;
  - the attained bound, max(|CI_low|, |CI_high|), the smallest symmetric bound at which TOST would pass at
    alpha = .05 - the honest answer when TOST fails at the pre-specified bound;
  - a two-one-sided-Wilcoxon version as a distribution-free robustness check, since the project prefers
    exact Wilcoxon elsewhere;
  - everything also expressed back in ratio units (10**x), since that is how the manuscript reads.

Never overwrites. No EEG file is read: the only input is the committed cell table from sec 10l.
"""
import argparse
import csv
import itertools
import json
import os

import numpy as np
from scipy import integrate
from scipy.stats import nct, t as tdist, wilcoxon

COND_ORDER = ('F0', 'FS', '00', 'S0')
CLASSES = ('first', 'later', 'all')          # 'first' is primary (sec 10l)
PRIMARY_CLASS = 'first'
METRICS = ('baseline_power_mean', 'active_power_mean')
PRIMARY_METRIC = 'baseline_power_mean'
PRIMARY_PAIR = ('FS', '00')                  # maximum conflict contrast; the audit's planned contrast
R_SCALES = (0.707, 0.5, 1.0)                 # Cauchy prior scales; 0.707 primary (Rouder et al. 2009)
R_PRIMARY = 0.707
RATIO_BOUND = 1.0 / 0.9                      # sec 10m: equivalence bound, symmetric in the ratio
LOG_BOUND = float(np.log10(RATIO_BOUND))     # 0.0457575...
ALPHA = 0.05


def jzs_bf10_g(t, n, r=R_PRIMARY):
    """JZS BF10 for a paired/one-sample t, by quadrature over the mixing variable g."""
    nu = n - 1.0

    def num(g):
        w = 1.0 + n * g * r * r
        return (w ** -0.5) * (1.0 + t * t / (w * nu)) ** (-(nu + 1) / 2) * \
            (2 * np.pi) ** -0.5 * g ** -1.5 * np.exp(-1.0 / (2 * g))

    val, _ = integrate.quad(num, 0, np.inf, limit=400)
    den = (1.0 + t * t / nu) ** (-(nu + 1) / 2)
    return float(val / den)


def jzs_bf10_delta(t, n, r=R_PRIMARY):
    """The same BF10 by quadrature over the effect size delta against a noncentral-t likelihood:
    BF10 = int f_nct(t; nu, delta*sqrt(n)) Cauchy(delta; 0, r) d delta / f_t(t; nu, 0)."""
    nu = n - 1.0

    def num(d):
        return nct.pdf(t, nu, d * np.sqrt(n)) / (np.pi * r * (1.0 + (d / r) ** 2))

    val, _ = integrate.quad(num, -np.inf, np.inf, limit=400)
    return float(val / nct.pdf(t, nu, 0.0))


def jzs_bf10_mc(t, n, r=R_PRIMARY, reps=400000, seed=20261108):
    """Monte Carlo over g ~ InvGamma(1/2, 1/2); reported, never used in a decision."""
    rng = np.random.default_rng(seed)
    g = 1.0 / rng.gamma(0.5, 1.0 / 0.5, size=reps)
    nu = n - 1.0
    w = 1.0 + n * g * r * r
    lik = (w ** -0.5) * (1.0 + t * t / (w * nu)) ** (-(nu + 1) / 2)
    den = (1.0 + t * t / nu) ** (-(nu + 1) / 2)
    return float(lik.mean() / den)


def verify_bf():
    """Refuse to run unless the two quadrature routes agree to a relative 1e-6 on a grid."""
    out, worst = [], 0.0
    for n in (10, 39, 120):
        for t in (0.0, 0.5, 1.5, 2.5, 4.0, -2.0):
            for r in R_SCALES:
                a, b = jzs_bf10_g(t, n, r), jzs_bf10_delta(t, n, r)
                rel = abs(a - b) / max(abs(a), abs(b), 1e-300)
                worst = max(worst, rel)
                out.append(dict(t=t, n=n, r=r, bf10_g=a, bf10_delta=b, rel_diff=rel))
    assert worst < 1e-6, f'the two BF routes disagree by {worst:.3e}'
    mc = [dict(t=t, n=39, r=R_PRIMARY, bf10_g=jzs_bf10_g(t, 39), bf10_mc=jzs_bf10_mc(t, 39))
          for t in (0.5, 2.5)]
    return dict(max_rel_diff_quadrature=worst, n_grid_points=len(out), monte_carlo_spotcheck=mc,
                note='both routes implement the same cited model; this verifies the implementation, '
                     'not the formula, and no third-party implementation was available to compare with')


def tost(d):
    """TOST on the paired log10 ratios d against LOG_BOUND, plus the bound-free 90 % CI."""
    n = d.size
    m, sd = float(d.mean()), float(d.std(ddof=1))
    se = sd / np.sqrt(n)
    nu = n - 1
    t_stat = m / se
    p_two = 2 * tdist.sf(abs(t_stat), nu)
    t_lo = (m + LOG_BOUND) / se                     # H0: mean <= -bound
    t_hi = (m - LOG_BOUND) / se                     # H0: mean >= +bound
    p_lo = float(tdist.sf(t_lo, nu))
    p_hi = float(tdist.cdf(t_hi, nu))
    p_tost = max(p_lo, p_hi)
    half = float(tdist.ppf(1 - ALPHA, nu)) * se     # 90 % CI matches the 5 % one-sided TOST
    ci = (m - half, m + half)
    try:
        w_lo = float(wilcoxon(d + LOG_BOUND, alternative='greater', method='exact').pvalue)
        w_hi = float(wilcoxon(d - LOG_BOUND, alternative='less', method='exact').pvalue)
        w_method = 'exact'
    except Exception:
        w_lo = float(wilcoxon(d + LOG_BOUND, alternative='greater', method='approx').pvalue)
        w_hi = float(wilcoxon(d - LOG_BOUND, alternative='less', method='approx').pvalue)
        w_method = 'approx'
    return dict(n=n, mean_log10_ratio=m, sd_log10_ratio=sd, t=float(t_stat), p_two_sided=float(p_two),
                dz=float(m / sd) if sd > 0 else float('nan'),
                p_tost_lower=p_lo, p_tost_upper=p_hi, p_tost=float(p_tost),
                equivalent=int(p_tost < ALPHA),
                ci90_low=ci[0], ci90_high=ci[1],
                attained_bound_log10=float(max(abs(ci[0]), abs(ci[1]))),
                attained_bound_ratio=float(10 ** max(abs(ci[0]), abs(ci[1]))),
                ratio=float(10 ** m), ratio_ci90_low=float(10 ** ci[0]), ratio_ci90_high=float(10 ** ci[1]),
                p_tost_wilcoxon=float(max(w_lo, w_hi)), equivalent_wilcoxon=int(max(w_lo, w_hi) < ALPHA),
                wilcoxon_method=w_method)


def read_cells(path):
    with open(path, newline='') as fh:
        rows = list(csv.DictReader(fh))
    out = {}
    for metric in METRICS:
        for cls in CLASSES:
            d = {}
            for r in rows:
                if r['miniblock_class'] != cls or r['condition'] not in COND_ORDER:
                    continue
                v = r.get(metric, '')
                if v in ('', 'NaN'):
                    continue
                d.setdefault(r['subject'], {})[r['condition']] = float(v)
            subs = sorted(s for s, dd in d.items()
                          if len(dd) == len(COND_ORDER) and all(x > 0 for x in dd.values()))
            out[(metric, cls)] = (subs, {c: np.array([d[s][c] for s in subs]) for c in COND_ORDER})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--cells', required=True)
    ap.add_argument('--out-dir', required=True)
    args = ap.parse_args()
    names = {k: os.path.join(args.out_dir, k) for k in
             ('stage5_equivalence_pairs.csv', 'stage5_equivalence_meta.json')}
    for p in names.values():
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')

    ver = verify_bf()
    cells = read_cells(args.cells)
    os.makedirs(args.out_dir, exist_ok=True)

    rows = []
    for metric in METRICS:
        for cls in CLASSES:
            subs, by_cond = cells[(metric, cls)]
            if len(subs) < 3:
                continue
            for a, b in itertools.combinations(COND_ORDER, 2):
                d = np.log10(by_cond[a]) - np.log10(by_cond[b])
                row = dict(metric=metric, miniblock_class=cls, pair=f'{a}_vs_{b}',
                           primary=int(metric == PRIMARY_METRIC and cls == PRIMARY_CLASS
                                       and (a, b) == PRIMARY_PAIR),
                           bound_ratio=RATIO_BOUND, bound_log10=LOG_BOUND)
                row.update(tost(d))
                bf10 = jzs_bf10_g(row['t'], row['n'], R_PRIMARY)
                row.update(bf10=bf10, bf01=1.0 / bf10)
                for r in R_SCALES:
                    if r == R_PRIMARY:
                        continue
                    v = jzs_bf10_g(row['t'], row['n'], r)
                    row[f'bf01_r{r}'] = 1.0 / v
                rows.append(row)

    with open(names['stage5_equivalence_pairs.csv'], 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), restval='')
        w.writeheader()
        w.writerows(rows)
    with open(names['stage5_equivalence_meta.json'], 'w') as fh:
        json.dump(dict(script='stage5_equivalence.py', plan='docs/decision_log.md sec 10m',
                       cells_file=args.cells, scale='within-subject difference of log10 band power',
                       metrics=METRICS, primary_metric=PRIMARY_METRIC, classes=CLASSES,
                       primary_class=PRIMARY_CLASS, primary_pair='_vs_'.join(PRIMARY_PAIR),
                       bound_ratio=RATIO_BOUND, bound_log10=LOG_BOUND, alpha=ALPHA,
                       bf_model='JZS default Bayes factor, Cauchy(0, r) on the standardised effect '
                                '(Rouder et al. 2009)', r_scales=list(R_SCALES), r_primary=R_PRIMARY,
                       bf_verification=ver,
                       primary_report='the bound-free 90 % CI of the mean log10 ratio; TOST at the '
                                      'pre-specified bound is derived from it'), fh, indent=2)

    print(f"BF implementation check: two quadrature routes agree to "
          f"{ver['max_rel_diff_quadrature']:.2e} over {ver['n_grid_points']} grid points\n")
    hdr = (f"{'metric':20s} {'class':6s} {'pair':12s} {'n':>3s} {'ratio':>7s} "
           f"{'90% CI':>17s} {'BF01':>9s} {'p_TOST':>8s} {'eq':>3s}")
    print(hdr)
    for r in rows:
        star = '  <- PRIMARY' if r['primary'] else ''
        print(f"{r['metric']:20s} {r['miniblock_class']:6s} {r['pair']:12s} {r['n']:3d} "
              f"{r['ratio']:7.4f} "
              f"[{r['ratio_ci90_low']:.4f},{r['ratio_ci90_high']:.4f}] "
              f"{r['bf01']:9.3f} {r['p_tost']:8.4f} {r['equivalent']:3d}{star}")
    print(f"\nwrote: {', '.join(os.path.basename(p) for p in names.values())}")


if __name__ == '__main__':
    main()
