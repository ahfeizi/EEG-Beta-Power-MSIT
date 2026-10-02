"""Stage 0 / decision S0-1: identify which OpenNeuro snapshot of ds004621 the local raw copy matches.

Read-only. Compares every *task-rest* and *task-msit* file of all 42 subjects with the
OpenNeuro GraphQL metadata of one snapshot:
  - annexed files: the snapshot file id is a git-annex SHA256E key -> compare SHA-256 + size
  - non-annexed files: the id is a git blob SHA-1 -> recomputed here in Python (no git command
    is run inside the raw-data folder)

Usage:
  python stage0_openneuro_version_check.py <tag> [big|small] [raw_root] [out_dir]
    <tag>     snapshot tag, e.g. 1.0.3
    big       also hash the large .eeg binaries (otherwise size-only for .eeg)
    raw_root  local ds004621 copy (= bidsRoot in config_local.m)
    out_dir   output folder (= <outRoot>/stage0)
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

# Paths: pass them on the command line (see Usage). The defaults mirror get_paths.m
# (repository-relative: raw_data/ds004621 and outputs/stage0).
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RAW = os.path.join(REPO, "raw_data", "ds004621")
OUT = os.path.join(REPO, "outputs", "stage0")
URL = "https://openneuro.org/crn/graphql"
QUERY = """query($t:String,$tag:String!){ snapshot(datasetId:"ds004621", tag:$tag){
            files(tree:$t){ id filename size directory annexed } } }"""


def list_tree(tag, tree=None):
    """List one directory level of a snapshot (tree=None -> dataset root)."""
    body = json.dumps({"query": QUERY, "variables": {"t": tree, "tag": tag}}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    for attempt in range(5):  # the API occasionally drops the TLS connection; retry a few times
        try:
            return json.load(urllib.request.urlopen(req, timeout=90))["data"]["snapshot"]["files"]
        except urllib.error.URLError:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))


def git_blob_sha1(path):
    """git's object id for a file: sha1(b'blob <size>\\0' + content)."""
    data = open(path, "rb").read()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    tag = sys.argv[1]
    hash_big = len(sys.argv) > 2 and sys.argv[2] == "big"
    raw = sys.argv[3] if len(sys.argv) > 3 else RAW
    out_dir = sys.argv[4] if len(sys.argv) > 4 else OUT

    top = {f["filename"]: f for f in list_tree(tag)}
    lines, n_checked, n_mismatch = [], 0, 0
    for s in [f"sub-{i:02d}" for i in range(1, 43)]:
        eeg_dir = {f["filename"]: f for f in list_tree(tag, top[s]["id"])}["eeg"]
        for f in list_tree(tag, eeg_dir["id"]):
            name = f["filename"]
            if "task-rest" not in name and "task-msit" not in name:
                continue
            path = os.path.join(raw, s, "eeg", name)
            if not os.path.exists(path):
                status = "MISSING_LOCALLY"
            elif os.path.getsize(path) != int(f["size"]):
                status = f"SIZE_DIFFERS local={os.path.getsize(path)} snapshot={f['size']}"
            elif f["annexed"] and name.endswith(".eeg") and not hash_big:
                status = "SIZE_MATCH_ONLY"
            elif f["annexed"]:
                status = "MATCH" if f["id"].split("--")[1].split(".")[0] == sha256(path) else "HASH_DIFFERS"
            else:
                status = "MATCH" if f["id"] == git_blob_sha1(path) else "HASH_DIFFERS"
            n_checked += 1
            n_mismatch += status not in ("MATCH", "SIZE_MATCH_ONLY")
            lines.append(f"{s}\t{name}\t{status}")

    header = (f"snapshot {tag}; files checked: {n_checked}; mismatches: {n_mismatch}; "
              f".eeg binaries {'hashed (SHA-256)' if hash_big else 'size-only'}")
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, f"openneuro_version_check_{tag}{'_big' if hash_big else ''}.txt")
    with open(out_file, "w", encoding="utf-8") as fh:
        fh.write(header + "\n" + "\n".join(lines) + "\n")
    print(header)
    print("saved ->", out_file)


if __name__ == "__main__":
    main()
