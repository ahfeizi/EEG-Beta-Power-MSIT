"""Stage 3: preprocessing QC summary for the 39-subject run (decision log next-steps item 23).

    python stage3_p2_qc_summary39.py <part2_dir> <stage3_out_dir> <out_dir>

Why this exists. The Methods paragraph on preprocessing needs the as-run parameters and the
per-participant counts of interpolated channels and removed components, including the muscle-component
count CLAUDE.md step 4 asks for as secondary evidence. The only existing file with those fields is
`Rest_Output/full_qc_summary.csv`, which is the **v1 pipeline on 42 subjects** and must not be quoted for
these results. `stage3_p2_qc_report.m` produces most of this but reads a batch `state/*.json` directory
and omits the interpolated-channel count, so this script reads the verified part-2 bundles directly and
writes a table under a **different name**, so the two pipelines' outputs can never be confused:

    stage3_p2_qc_summary39.csv      one row per subject
    stage3_p2_qc_summary39.json     the constant settings, the filter table, and the pooled summary

Everything it reports is read from the bundles and from `stage3_params.m`; nothing is recomputed from EEG
and no parameter is restated by hand. The settings struct is asserted to be identical across all 39
subjects, so the Methods text can state single values. Each bundle's SHA-256 is checked against the
part-2 manifests before it is read.

Read-only apart from its two outputs; never overwrites.
"""
import csv
import glob
import hashlib
import json
import os
import re
import sys

import numpy as np
from scipy.io import loadmat

N_SUBJECTS = 39
SETTING_FIELDS = ('icatype', 'icaHighpassHz', 'asrCutoff', 'asrMaxMemMB', 'iclabelThreshold',
                  'rankTolRel', 'seedGlobal')
# ICLabel class order as stored in the bundle; asserted against P2.classes
CLASSES = ('Brain', 'Muscle', 'Eye', 'Heart', 'Line Noise', 'Channel Noise', 'Other')
PRIMARY_LIST = 'beta_withoutOther'      # the version the analyses use (version 'beta', Other retained)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(16 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def read_manifests(part2):
    """{basename: sha256} from every manifest in the part-2 directory."""
    out = {}
    for m in glob.glob(os.path.join(part2, 'manifest*.tsv')):
        with open(m, newline='', encoding='latin1') as fh:
            for r in csv.DictReader(fh, delimiter='\t'):
                out[os.path.basename(r['file'])] = r['sha256'].strip().lower()
    return out


def params_from_matlab(stage3_dir):
    """The approved Stage-3 parameters, parsed out of stage3_params.m rather than retyped."""
    src = open(os.path.join(stage3_dir, 'stage3_params.m'), encoding='latin1').read()

    def num(name):
        m = re.search(r'S\.%s\s*=\s*([0-9.]+)' % name, src)
        return float(m.group(1)) if m else None

    def vec(name):
        m = re.search(r'S\.%s\s*=\s*\[([0-9 .]+)\]' % name, src)
        return [float(x) for x in m.group(1).split()] if m else None

    d6 = {}
    m = re.search(r"S\.d6\s*=\s*struct\((.*?)\);", src, re.S)
    if m:
        for k, v in re.findall(r"'(\w+)'\s*,\s*([0-9.eE-]+|'[^']*')", m.group(1)):
            d6[k] = v.strip("'")
    return dict(fs_raw_hz=num('fsRaw'), fs_out_hz=num('fsOut'), highpass_edge_hz=num('hpEdge'),
                line_freqs_hz=vec('lineFreqs'), notch_halfwidth_hz=num('notchA'), d6=d6)


def filter_table(stage3_out):
    p = os.path.join(stage3_out, 'filter_halflengths.csv')
    if not os.path.exists(p):
        p = os.path.join(stage3_out, 'd4e_d5a3', 'filter_halflengths.csv')
    with open(p, newline='') as fh:
        return list(csv.DictReader(fh))


def main():
    part2 = sys.argv[1] if len(sys.argv) > 1 else r'D:\Revision_EEG\stage3_part2'
    stage3_out = sys.argv[2] if len(sys.argv) > 2 else None
    out_dir = sys.argv[3] if len(sys.argv) > 3 else None
    here = os.path.dirname(os.path.abspath(__file__))
    out_csv = os.path.join(out_dir, 'stage3_p2_qc_summary39.csv')
    out_json = os.path.join(out_dir, 'stage3_p2_qc_summary39.json')
    for p in (out_csv, out_json):
        if os.path.exists(p):
            raise SystemExit(f'output exists, not overwritten: {p}')

    man = read_manifests(part2)
    files = sorted(glob.glob(os.path.join(part2, 'sub-*_s3p2.mat')))
    assert len(files) == N_SUBJECTS, f'{len(files)} part-2 bundles, {N_SUBJECTS} expected'

    rows, settings, unhashed = [], None, []
    for f in files:
        base = os.path.basename(f)
        if base in man:
            got = sha256(f)
            assert got == man[base], f'{base}: SHA-256 mismatch ({got} vs manifest {man[base]})'
        else:
            unhashed.append(base)
        P2 = loadmat(f, squeeze_me=True, struct_as_record=False)['P2']
        q, s = P2.qc, P2.settings
        assert tuple(str(c) for c in np.ravel(P2.classes)) == CLASSES, f'{base}: ICLabel class order'
        cur = {k: (str(getattr(s, k)) if isinstance(getattr(s, k), str) else float(getattr(s, k)))
               for k in SETTING_FIELDS}
        if settings is None:
            settings = cur
        else:
            assert cur == settings, f'{base}: settings differ from the other subjects: {cur}'
        per_class = [int(x) for x in np.ravel(q.nPerClass_p08)]
        top_class = [int(x) for x in np.ravel(q.nTopClass)]
        rc = [str(x) for x in np.ravel(q.removedChannels)] if np.ravel(q.removedChannels).size else []
        lists = {k: int(np.ravel(getattr(P2.lists, k)).size) for k in P2.lists._fieldnames}
        row = dict(subject=str(P2.subject), n_good_channels=int(q.nGood), rank=int(q.rank),
                   pca=int(q.pca), n_ic=int(q.nIC),
                   n_interpolated_channels=len(rc), interpolated_channels=';'.join(rc),
                   asr_modified_fraction=float(q.asrModifiedFraction),
                   n_removed_primary=lists[PRIMARY_LIST],
                   **{f'n_removed_{k}': v for k, v in lists.items()},
                   **{'p08_' + c.lower().replace(' ', '_'): n for c, n in zip(CLASSES, per_class)},
                   **{'top_' + c.lower().replace(' ', '_'): n for c, n in zip(CLASSES, top_class)})
        rows.append(row)

    with open(out_csv, 'w', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    def stats(key):
        v = sorted(float(r[key]) for r in rows)
        return dict(n=len(v), min=v[0], median=float(np.median(v)), max=v[-1],
                    mean=round(float(np.mean(v)), 4), sd=round(float(np.std(v, ddof=1)), 4))

    summary = dict(
        script='stage3_p2_qc_summary39.py', n_subjects=len(rows),
        note='the 39-subject Stage-3 pipeline; NOT Rest_Output/full_qc_summary.csv, which is the v1 '
             'pipeline on 42 subjects and must not be quoted for these results',
        settings_constant_across_subjects=settings,
        params=params_from_matlab(here), filters_before_cropping=filter_table(stage3_out),
        iclabel_classes=list(CLASSES), primary_removal_list=PRIMARY_LIST,
        bundles_without_a_manifest_entry=unhashed,
        per_subject=dict((k, stats(k)) for k in
                         ('n_good_channels', 'n_ic', 'n_interpolated_channels',
                          'asr_modified_fraction', 'n_removed_primary', 'p08_muscle', 'p08_brain',
                          'p08_eye', 'p08_channel_noise', 'p08_other')))
    with open(out_json, 'w') as fh:
        json.dump(summary, fh, indent=2)

    print(f'{len(rows)} subjects; settings identical across all of them:')
    for k, v in settings.items():
        print(f'  {k:20s} {v}')
    print('\nper-subject counts (min / median / max, mean (SD)):')
    for k in ('n_good_channels', 'n_interpolated_channels', 'n_ic', 'n_removed_primary', 'p08_muscle',
              'asr_modified_fraction'):
        s = summary['per_subject'][k]
        print(f"  {k:26s} {s['min']:>8g} / {s['median']:>8g} / {s['max']:>8g}   "
              f"mean {s['mean']} (SD {s['sd']})")
    if unhashed:
        print('\nbundles with no manifest entry (not hash-verified):', unhashed)
    print(f'\nwrote: {os.path.basename(out_csv)}, {os.path.basename(out_json)}')


if __name__ == '__main__':
    main()
