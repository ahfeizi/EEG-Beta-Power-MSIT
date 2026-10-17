"""D6 report (S3a-D6-report): decision lists only, no spectra or power.

Reads <outRoot>/stage3/d6/d6_summary.csv (stage3_d6_summary.m over batch d6_1; one row per subject) and writes
<outRoot>/stage3/d6/d6_report.csv (refuses to overwrite), one row per subject:
  n_pair, n_dependent      known-bad channels removed before RANSAC (S3a-D6 items 5, 6; disjoint from RANSAC)
  n_flat_or_ransac         channels removed by pop_clean_rawdata (flatline + RANSAC; the stored D6 output does not
                           separate the two criteria), union over rest and MSIT+ = n_bad - n_pair - n_dependent
  n_ransac_rest, n_ransac_msit   the same per condition
  n_bad, pct_bad, excluded (> 15 %), key_bad (Fz/Cz/C4 among the removed channels)
Prints the totals, the excluded subjects, the key-channel check and the analysable sample size.

Usage: python -I stage3_d6_report.py <outRoot>
"""
import csv
import os
import sys

out_root = sys.argv[1]
src = os.path.join(out_root, "stage3", "d6", "d6_summary.csv")
dst = os.path.join(out_root, "stage3", "d6", "d6_report.csv")
if os.path.exists(dst):
    sys.exit(f"refusing to overwrite {dst}")
KEY = ("Fz", "Cz", "C4")
rows = []
with open(src, newline="", encoding="utf-8") as fh:
    for r in csv.DictReader(fh):
        removed = r["removed_channels"].split()
        n_bad, n_pair, n_dep = int(r["n_bad"]), int(r["n_pair"]), int(r["n_dependent"])
        assert len(removed) == n_bad, r["subject"]
        rows.append({
            "subject": r["subject"], "n_channels": int(r["n_channels"]), "n_pair": n_pair, "n_dependent": n_dep,
            "n_flat_or_ransac": n_bad - n_pair - n_dep, "n_ransac_rest": int(r["n_ransac_rest"]),
            "n_ransac_msit": int(r["n_ransac_msit"]), "n_bad": n_bad,
            "pct_bad": round(100 * n_bad / int(r["n_channels"]), 1), "excluded": int(r["excluded"]),
            "key_bad": ";".join(k for k in KEY if k in removed), "removed_channels": r["removed_channels"],
            "positions_source": r["positions_source"]})
rows.sort(key=lambda x: x["subject"])
with open(dst, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
nb = sorted(x["n_bad"] for x in rows)
med = nb[len(nb) // 2] if len(nb) % 2 else (nb[len(nb) // 2 - 1] + nb[len(nb) // 2]) / 2
print(f"subjects {len(rows)}; n_bad min {nb[0]} median {med} max {nb[-1]}; zero bad: {sum(v == 0 for v in nb)}")
for k in ("n_pair", "n_dependent", "n_flat_or_ransac"):
    print(f"{k}: total {sum(x[k] for x in rows)} in {sum(x[k] > 0 for x in rows)} subjects")
exc = [x["subject"] for x in rows if x["excluded"]]
print("excluded (> 15 %):", ", ".join(exc) if exc else "none")
key = [(x["subject"], x["key_bad"]) for x in rows if x["key_bad"]]
print("Fz/Cz/C4 bad:", "; ".join(f"{s}: {k}" for s, k in key) if key else "none")
print(f"analysable sample: {len(rows) - len(exc)} of 42 (sub-42 excluded under S3a-D6)")
for x in rows:
    print(f"{x['subject']} pair {x['n_pair']} dep {x['n_dependent']} flat/RANSAC {x['n_flat_or_ransac']} "
          f"(rest {x['n_ransac_rest']}, msit {x['n_ransac_msit']}) union {x['n_bad']} = {x['pct_bad']} % "
          f"excl {x['excluded']} key {x['key_bad'] or '-'}")
