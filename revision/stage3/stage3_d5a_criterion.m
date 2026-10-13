function T = stage3_d5a_criterion(batchDir, nullBatchDir, bMergeFile, outFile)
%STAGE3_D5A_CRITERION  Decision table of the (a) residual test (S3a-D5a-test-amend1, S3a-D5a-width).
%   batchDir: finished A/B batch of stage3_d5a_compute_one on the 9 test-set recordings; nullBatchDir: the
%   same job on the two noise twins (S3a-D5b-null-amend1: one rest, one MSIT+); every canonical output is
%   hash-checked against its state file, and all 11 must use the same notch width a. bMergeFile: the (b)
%   merge output (d5bm_1), for the descriptive (a) vs (b) comparison.
%   Per real recording (twin matched by task, approved 2026-10-13):
%     rel_q95_db = a_q95_db - null_q95_db (q95 of the after-excess over the kept-channel x f0 cells)
%     recording_pass = rel_q95_db < 3 dB.  R-b2 is not evaluated (flank band inside the notch transition
%     band); its values are reported descriptively, with flank_in_transition.
%   a_passes = every recording_pass. Pre-registered rule: a_passes -> final D5 decision "(a), a = <a>, all
%   recordings"; otherwise stop and report to Amirhossein. The dated log entry is written by hand afterwards.
%   Writes outFile (CSV, never overwrites) and <outFile>_decision.txt with the verdict, the per-recording
%   table and the SHA-256 of every input and of the CSV.

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
[R, srcR] = loadBatch(batchDir);
[N, srcN] = loadBatch(nullBatchDir);
assert(numel(N) == 2 && all(sort([N.task]) == ["msit", "rest"]), 'the null must hold one rest and one MSIT+ twin');
aAll = [arrayfun(@(r) r.notch.a, R), arrayfun(@(r) r.notch.a, N)];
assert(all(aAll == aAll(1)), 'notch width differs between outputs');
a = aAll(1);
Bm = load(bMergeFile); Bs = Bm.summary;
rows = cell(numel(R), 1);
for k = 1:numel(R)
    r = R(k); q = r.afterCellQuantilesDb;
    n = N([N.task] == r.task); qn = n.afterCellQuantilesDb;
    e = r.excessAfterDb(r.kept, :);
    ib = find(Bs.subject == r.subject & Bs.task == r.task);
    assert(isscalar(ib), '%s %s: not exactly one (b) row', r.subject, r.task);
    rel = q(3) - qn(3);
    rows{k} = table(r.subject, r.task, r.role, a, r.nChunk, r.nCells, q(3), n.subject + " " + n.task, qn(3), rel, rel < 3, ...
        r.notch.flankInTransition, r.rb2Pass, r.maxAbsFlankChangeKeptDb, r.maxExcessAfterKeptDb, sum(e(:) > 3), q(4), ...
        Bs.q95_after_db(ib), q(3) - Bs.q95_after_db(ib), ...
        'VariableNames', {'subject', 'task', 'role', 'notch_a_hz', 'n_chunks', 'n_cells', 'a_q95_db', 'null_twin', ...
        'null_q95_db', 'rel_q95_db', 'recording_pass', 'flank_in_transition', 'rb2_pass_descriptive', ...
        'max_abs_flank_change_db', 'a_max_db', 'a_cells_gt3db', 'a_q99_db', 'b_q95_db', 'a_minus_b_q95_db'});
end
T = vertcat(rows{:});
T.a_passes = repmat(all(T.recording_pass), height(T), 1);
writetable(T, outFile);
[p, nm] = fileparts(outFile);
df = fullfile(p, [nm '_decision.txt']);
fid = fopen(df, 'w');
fprintf(fid, 'S3a-D5a-test (amend1, width a = %g Hz), %s\n', a, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'real batch %s, batch.json SHA-256 %s\n', batchDir, sha256File(fullfile(batchDir, 'batch.json')));
fprintf(fid, 'null batch %s, batch.json SHA-256 %s\n', nullBatchDir, sha256File(fullfile(nullBatchDir, 'batch.json')));
fprintf(fid, '(b) merge %s, SHA-256 %s\n', bMergeFile, sha256File(bMergeFile));
for k = 1:size(srcR, 1), fprintf(fid, 'input %s %s\n', srcR{k, 1}, srcR{k, 2}); end
for k = 1:size(srcN, 1), fprintf(fid, 'null input %s %s\n', srcN{k, 1}, srcN{k, 2}); end
fprintf(fid, 'null q95: %s\n', strjoin(arrayfun(@(n) sprintf('%s %s %.4f dB', n.subject, n.task, n.afterCellQuantilesDb(3)), N, 'uni', 0), '; '));
fprintf(fid, 'R-b2 not evaluated (flank band inside the notch transition band in %d of %d recordings)\n', sum(T.flank_in_transition), height(T));
fprintf(fid, '%-8s %-5s %9s %9s %9s %5s\n', 'subject', 'task', 'a_q95', 'null_q95', 'rel_q95', 'pass');
for k = 1:height(T)
    fprintf(fid, '%-8s %-5s %9.4f %9.4f %9.4f %5d\n', T.subject(k), T.task(k), T.a_q95_db(k), T.null_q95_db(k), T.rel_q95_db(k), T.recording_pass(k));
end
fprintf(fid, 'recordings passing (rel_q95 < 3 dB): %d of %d\n', sum(T.recording_pass), height(T));
if all(T.recording_pass)
    fprintf(fid, 'DECISION: PASS on all recordings -> final D5 decision "(a), a = %g, all recordings" (pre-registered; log entry to be added)\n', a);
else
    fprintf(fid, 'DECISION: FAIL -> STOP and report to Amirhossein (no further automatic step)\n');
end
fprintf(fid, 'output %s SHA-256 %s\n', outFile, sha256File(outFile));
fclose(fid);
disp(T);
fprintf('%s', fileread(df));
end

function [res, src] = loadBatch(dirName)
b = jsondecode(fileread(fullfile(dirName, 'batch.json')));
assert(strcmp(b.mode, 'Batch') && strcmp(b.status, 'DONE'), '%s is not a finished Batch-mode run', dirName);
S = dir(fullfile(dirName, 'state', '*.json'));
src = cell(numel(S), 2); res = [];
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(dirName, 'state', S(k).name)));
    assert(strcmp(st.status, 'verified'), '%s: status %s', S(k).name, st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', S(k).name);
    L = load(st.canonical.path);
    if isempty(res), res = L.res; else, res(end+1) = L.res; end %#ok<AGROW>
    src(k, :) = {st.canonical.path, st.canonical.sha256};
end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
