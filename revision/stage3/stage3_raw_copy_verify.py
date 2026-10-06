"""Stage 3 / decision S3a-D1-amend (Q3 of 2026-10-06): one-time copy of the raw files Stage 3 needs,
from the read-only source drive to the working drive, verified against the OpenNeuro snapshot.

Three modes, each run separately (nothing runs implicitly):

  manifest  Query the OpenNeuro GraphQL metadata of snapshot <tag> (as in S0-1) and freeze the
            reference for every file in scope into <out>/reference_manifest_<tag>.tsv.
            No raw file is opened.
  copy      Stream each file in the manifest from <src> to <dst>. The source is opened read-only
            and read ONCE: the same bytes are hashed and written. A file is accepted only if its
            size and hash equal the reference; it is then fsync'ed and renamed from *.partial to its
            final name. Anything else is deleted and logged. No retry inside a run.
  verify    Re-read every copied file from <dst> (never from <src>), recompute the hashes, compare
            with the reference and with the copy-time hash. Writes the per-file report and, only if
            every file matches, <out>/verified_manifest.tsv, which the Stage 3 jobs check their
            input against. Run it as a separate process, ideally after a reboot, so the files are
            read from the disk and not from the Windows file cache filled by `copy`.

Reference (same rule as S0-1, stage0_openneuro_version_check.py):
  annexed files      the snapshot id is a git-annex SHA256E key -> SHA-256 of the content
  non-annexed files  the snapshot id is a git blob SHA-1 = sha1(b"blob <size>\\0" + content)
Both hashes are computed for every file; SHA-256 is also recorded for non-annexed files.

Scope (fixed here; S3a-D1-amend):
  sub-01..sub-42/eeg/*task-rest* and *task-msit*      (the 420 files of S0-1)
  sourcedata/sub-01..sub-42/coords/*                  (CapTrak .bvct / .bvef, S3a-D2-reopen)
  top-level files of the dataset                      (dataset_description.json, sidecars, ...)
The file list comes from the snapshot metadata, not from listing the source folder, so files that
exist locally but not in the snapshot are never copied (they are only reported, by name).

Safety: the source is only ever opened with mode "rb"; no command is run inside it; <dst> must be on
a different drive than <src>. Note: with NTFS last-access updates enabled on this machine
(`fsutil behavior query disablelastaccess` = 2), Windows itself may update the last-access time
stamp of a source file when it is read; this script cannot prevent that without write access.

Usage:
  python stage3_raw_copy_verify.py manifest <out_dir> [tag]
  python stage3_raw_copy_verify.py copy     <src_root> <dst_root> <out_dir> [tag]
  python stage3_raw_copy_verify.py verify   <dst_root> <out_dir> [tag]
"""
import datetime
import hashlib
import json
import os
import platform
import shutil
import sys
import time
import urllib.error
import urllib.request

URL = "https://openneuro.org/crn/graphql"
QUERY = """query($t:String,$tag:String!){ snapshot(datasetId:"ds004621", tag:$tag){
            files(tree:$t){ id filename size directory annexed } } }"""
SUBJECTS = [f"sub-{i:02d}" for i in range(1, 43)]
CHUNK = 8 << 20                    # 8 MiB read size
MARGIN = 15 << 30                  # S3a-D1 disk-space margin: 15 GiB must remain on <dst> after the copy
COLS = ["relpath", "size", "annexed", "ref_kind", "ref_hash"]


def now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


RAW_RESPONSES = []                # every GraphQL response of a manifest run, saved verbatim


def list_tree(tag, tree=None):
    """List one directory level of a snapshot (tree=None -> dataset root). Same call as S0-1.
    The raw response bytes are kept, with the request and a time stamp, in RAW_RESPONSES."""
    body = json.dumps({"query": QUERY, "variables": {"t": tree, "tag": tag}}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    for attempt in range(5):
        try:
            raw = urllib.request.urlopen(req, timeout=90).read()
            RAW_RESPONSES.append({"time": datetime.datetime.now().isoformat(timespec="seconds"),
                                  "url": URL, "request": body.decode(), "response": raw.decode("utf-8")})
            return json.loads(raw)["data"]["snapshot"]["files"]
        except urllib.error.URLError:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))


def ref_of(f):
    """(kind, hash) of a snapshot file entry, exactly as S0-1 interprets the id."""
    if f["annexed"]:
        return "sha256", f["id"].split("--")[1].split(".")[0]
    return "gitblob_sha1", f["id"]


def hash_stream(fin, size, fout=None):
    """Read fin to the end once; return (bytes read, sha256, git blob sha1); optionally write fout."""
    h256 = hashlib.sha256()
    h1 = hashlib.sha1(b"blob %d\0" % size)
    n = 0
    for chunk in iter(lambda: fin.read(CHUNK), b""):
        h256.update(chunk)
        h1.update(chunk)
        n += len(chunk)
        if fout is not None:
            fout.write(chunk)
    return n, h256.hexdigest(), h1.hexdigest()


def status_of(row, n, s256, s1):
    if n != int(row["size"]):
        return f"SIZE_DIFFERS read={n} reference={row['size']}"
    got = s256 if row["ref_kind"] == "sha256" else s1
    return "MATCH" if got == row["ref_hash"] else "HASH_DIFFERS"


def read_tsv(path):
    with open(path, encoding="utf-8") as fh:
        head = fh.readline().rstrip("\n").split("\t")
        return [dict(zip(head, ln.rstrip("\n").split("\t"))) for ln in fh if ln.strip()]


def append_tsv(path, cols, row):
    new = not os.path.exists(path)
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        if new:
            fh.write("\t".join(cols) + "\n")
        fh.write("\t".join(str(row[c]) for c in cols) + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def write_atomic(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)


# ---------------------------------------------------------------------------------------------
def mode_manifest(out_dir, tag):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"reference_manifest_{tag}.tsv")
    if os.path.exists(path):
        sys.exit(f"{path} exists; a frozen manifest is never overwritten")
    rows = []
    top = list_tree(tag)
    byname = {f["filename"]: f for f in top}
    for f in top:                                              # top-level files
        if not f["directory"]:
            rows.append((f["filename"], f))
    for s in SUBJECTS:                                         # rest + MSIT+ files (S0-1 scope)
        eeg = {f["filename"]: f for f in list_tree(tag, byname[s]["id"])}["eeg"]
        for f in list_tree(tag, eeg["id"]):
            if not f["directory"] and ("task-rest" in f["filename"] or "task-msit" in f["filename"]):
                rows.append((f"{s}/eeg/{f['filename']}", f))
    if "sourcedata" not in byname:
        sys.exit("snapshot has no sourcedata/ folder: the coords scope must be decided again")
    src = {f["filename"]: f for f in list_tree(tag, byname["sourcedata"]["id"])}
    for s in SUBJECTS:                                         # CapTrak coordinates
        if s not in src:
            continue
        sub = {f["filename"]: f for f in list_tree(tag, src[s]["id"])}
        if "coords" in sub:
            for f in list_tree(tag, sub["coords"]["id"]):
                if not f["directory"]:
                    rows.append((f"sourcedata/{s}/coords/{f['filename']}", f))
    lines = ["\t".join(COLS)]
    for rel, f in rows:
        kind, h = ref_of(f)
        lines.append("\t".join([rel, str(int(f["size"])), str(int(bool(f["annexed"]))), kind, h]))
    write_atomic(path, "\n".join(lines) + "\n")
    with open(path, "rb") as fh:
        digest = hashlib.sha256(fh.read()).hexdigest()
    # the raw API responses, verbatim and time-stamped, next to the frozen manifest (Q3, 2026-10-06)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    raw_path = os.path.join(out_dir, f"reference_raw_responses_{tag}_{stamp}.jsonl")
    write_atomic(raw_path, "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in RAW_RESPONSES))
    with open(raw_path, "rb") as fh:
        raw_digest = hashlib.sha256(fh.read()).hexdigest()
    write_atomic(path + ".sha256", f"{digest}  {os.path.basename(path)}\n"
                                   f"{raw_digest}  {os.path.basename(raw_path)}\n")
    print(f"raw responses: {len(RAW_RESPONSES)} -> {raw_path} (SHA-256 {raw_digest})")
    n_eeg = sum(1 for r, _ in rows if "/eeg/" in r)
    n_coords = sum(1 for r, _ in rows if r.startswith("sourcedata/"))
    total = sum(int(f["size"]) for _, f in rows)
    msg = (f"manifest {tag} written {now()}: {len(rows)} files ({n_eeg} rest/MSIT+, {n_coords} coords, "
           f"{len(rows) - n_eeg - n_coords} top-level), {total} bytes; SHA-256 of manifest {digest}")
    print(msg)
    print("saved ->", path)
    if n_eeg != 420:
        print(f"WARNING: expected 420 rest/MSIT+ files as in S0-1, found {n_eeg}")


def mode_copy(src, dst, out_dir, tag):
    src, dst = os.path.abspath(src), os.path.abspath(dst)
    if os.path.splitdrive(src)[0].lower() == os.path.splitdrive(dst)[0].lower():
        sys.exit("source and destination must be on different drives")   # also excludes dst inside src
    rows = read_tsv(os.path.join(out_dir, f"reference_manifest_{tag}.tsv"))
    log = os.path.join(out_dir, "copy_log.tsv")
    done = {r["relpath"] for r in read_tsv(log) if r["status"] == "MATCH"} if os.path.exists(log) else set()
    todo = [r for r in rows if r["relpath"] not in done]
    need = sum(int(r["size"]) for r in todo)
    os.makedirs(dst, exist_ok=True)
    free = shutil.disk_usage(dst).free
    print(f"{now()} copy: {len(rows)} in manifest, {len(done)} already done, {len(todo)} to copy, "
          f"{need} bytes; free on destination {free} bytes")
    if free - need < MARGIN:
        sys.exit(f"STOP: less than {MARGIN} bytes would remain on the destination after the copy")
    cols = ["time", "relpath", "size", "bytes_read", "sha256", "gitblob_sha1", "status"]
    for i, r in enumerate(todo, 1):
        rel = r["relpath"]
        s_path = os.path.join(src, *rel.split("/"))
        d_path = os.path.join(dst, *rel.split("/"))
        part = d_path + ".partial"
        os.makedirs(os.path.dirname(d_path), exist_ok=True)
        if os.path.exists(d_path):                             # final name without a MATCH log row
            os.remove(d_path)                                  # -> left by an interrupted run; redo
        n, s256, s1 = -1, "", ""
        try:
            with open(s_path, "rb") as fin, open(part, "wb") as fout:
                n, s256, s1 = hash_stream(fin, int(r["size"]), fout)
                fout.flush()
                os.fsync(fout.fileno())
            st = status_of(r, n, s256, s1)
        except OSError as e:
            st = f"READ_OR_WRITE_ERROR {type(e).__name__}: {e}".replace("\t", " ")
        if st == "MATCH":
            os.replace(part, d_path)
        elif os.path.exists(part):
            os.remove(part)
        append_tsv(log, cols, {"time": now(), "relpath": rel, "size": r["size"], "bytes_read": n,
                               "sha256": s256, "gitblob_sha1": s1, "status": st})
        print(f"[{i}/{len(todo)}] {rel}: {st}")
    rows_log = read_tsv(log)
    last = {}
    for x in rows_log:
        last[x["relpath"]] = x["status"]
    bad = [k for k in (r["relpath"] for r in rows) if last.get(k) != "MATCH"]
    print(f"{now()} copy finished: {len(rows) - len(bad)} MATCH, {len(bad)} not copied")
    for k in bad:
        print("  NOT COPIED:", k, last.get(k, "never attempted"))


def mode_verify(dst, out_dir, tag):
    dst = os.path.abspath(dst)
    rows = read_tsv(os.path.join(out_dir, f"reference_manifest_{tag}.tsv"))
    log = os.path.join(out_dir, "copy_log.tsv")
    copy256 = {x["relpath"]: x["sha256"] for x in read_tsv(log) if x["status"] == "MATCH"}
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    rep = os.path.join(out_dir, f"verification_{stamp}.tsv")
    cols = ["relpath", "size", "bytes_read", "sha256", "status_vs_reference", "status_vs_copy"]
    ok, lines = 0, []
    for r in rows:
        rel = r["relpath"]
        d_path = os.path.join(dst, *rel.split("/"))
        try:
            with open(d_path, "rb") as fin:
                n, s256, s1 = hash_stream(fin, int(r["size"]))
            st_ref = status_of(r, n, s256, s1)
            st_copy = "MATCH" if copy256.get(rel) == s256 else ("NO_COPY_RECORD" if rel not in copy256 else "HASH_DIFFERS")
        except OSError as e:
            n, s256 = -1, ""
            st_ref = st_copy = f"READ_ERROR {type(e).__name__}"
        ok += st_ref == "MATCH" and st_copy == "MATCH"
        append_tsv(rep, cols, {"relpath": rel, "size": r["size"], "bytes_read": n, "sha256": s256,
                               "status_vs_reference": st_ref, "status_vs_copy": st_copy})
        lines.append(f"{rel}\t{r['size']}\t{s256}")
    extra, known = [], {r["relpath"] for r in rows}
    for root, _, files in os.walk(dst):                        # files on <dst> not in the manifest
        for fn in files:
            rel = os.path.relpath(os.path.join(root, fn), dst).replace(os.sep, "/")
            if rel not in known:
                extra.append(rel)
    print(f"{now()} verify ({platform.node()}, Python {platform.python_version()}): "
          f"{ok}/{len(rows)} files MATCH both the reference and the copy-time hash; "
          f"{len(extra)} unexpected files on the destination")
    for e in extra:
        print("  UNEXPECTED:", e)
    print("report ->", rep)
    if ok == len(rows) and not extra:
        path = os.path.join(out_dir, "verified_manifest.tsv")
        write_atomic(path, "relpath\tsize\tsha256\n" + "\n".join(lines) + "\n")
        print("all files verified -> ", path)
    else:
        print("NOT VERIFIED: verified_manifest.tsv is not written")


if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "manifest" and len(a) in (2, 3):
        mode_manifest(a[1], a[2] if len(a) > 2 else "1.0.3")
    elif a[0] == "copy" and len(a) in (4, 5):
        mode_copy(a[1], a[2], a[3], a[4] if len(a) > 4 else "1.0.3")
    elif a[0] == "verify" and len(a) in (3, 4):
        mode_verify(a[1], a[2], a[3] if len(a) > 3 else "1.0.3")
    else:
        sys.exit(__doc__)
