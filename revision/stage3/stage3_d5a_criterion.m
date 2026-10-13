function T = stage3_d5a_criterion(batchDir, nullBatchDir, bMergeFile, outFile)
%STAGE3_D5A_CRITERION  Decision table of the (a) residual test (S3a-D5a-crit2, replacing the relative
%   criterion of S3a-D5a-test-amend1 before any (a) run; width S3a-D5a-width).
%   batchDir: finished A/B batch of stage3_d5a_compute_one on the 9 test-set recordings; nullBatchDir: the
%   same job on the two noise twins (one rest, one MSIT+); every canonical output is hash-checked against
%   its state file, and all must use the same notch width a. bMergeFile: the (b) merge output (d5bm_1).
%   Residual per kept channel x f0 (stage3_d5a_residual): max over |f - f0| <= 0.5 Hz of the post-filter
%   PSD relative to the PRE-filter straight-line flank floor (dB) - the (b) measure, whose flanks are
%   unchanged. Per recording: q95 over the kept-channel x f0 cells (MATLAB quantile, as stage3_d5b_rules).
%     recording_pass = C1: q95 < 3 dB.  R-b2 is not evaluated (flank band inside the notch transition band).
%   Descriptive: the null twin's residual q95/max (matched by task), max, cells > 3 dB, q99, the excess
%   against the post-filter floor (old measure), the flank change, (b) q95 and (a) - (b).
%   a_passes = every recording_pass. Pre-registered rule: a_passes -> final D5 decision "(a), a = <a>, all
%   recordings"; otherwise stop and report to Amirhossein. The dated log entry is written by hand afterwards.
%   Writes outFile (CSV, never overwrites) and <outFile>_decision.txt with the verdict, the per-recording
%   table and the SHA-256 of every input and of the CSV.

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
d = (-30:30) / 10;
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pkwin = find(abs(d) <= 0.5 + 1e-9);
[R, srcR] = loadBatch(batchDir);
[N, srcN] = loadBatch(nullBatchDir);
assert(numel(N) == 2 && all(sort([N.task]) == ["msit", "rest"]), 'the null must hold one rest and one MSIT+ twin');
aAll = [arrayfun(@(r) r.notch.a, R), arrayfun(@(r) r.notch.a, N)];
assert(all(aAll == aAll(1)), 'notch width differs between outputs');
a = aAll(1);
nq = nan(1, 2); nm = nan(1, 2);
for i = 1:2
    c = resid(N(i)); nq(i) = quantile(c, 0.95); nm(i) = max(c);
end
Bm = load(bMergeFile); Bs = Bm.summary;
rows = cell(numel(R), 1);
for k = 1:numel(R)
    r = R(k); c = resid(r);
    q95 = quantile(c, 0.95); q99 = quantile(c, 0.99);
    in = find([N.task] == r.task);
    ib = find(Bs.subject == r.subject & Bs.task == r.task);
    assert(isscalar(ib), '%s %s: not exactly one (b) row', r.subject, r.task);
    rows{k} = table(r.subject, r.task, r.role, a, r.nChunk, numel(c), q95, q95 < 3, max(c), sum(c > 3), q99, ...
        N(in).subject + " " + N(in).task, nq(in), nm(in), r.afterCellQuantilesDb(3), r.notch.flankInTransition, ...
        r.rb2Pass, r.maxAbsFlankChangeKeptDb, Bs.q95_after_db(ib), q95 - Bs.q95_after_db(ib), ...
        'VariableNames', {'subject', 'task', 'role', 'notch_a_hz', 'n_chunks', 'n_cells', 'residual_q95_db', ...
        'recording_pass', 'residual_max_db', 'residual_cells_gt3db', 'residual_q99_db', 'null_twin', ...
        'null_residual_q95_db', 'null_residual_max_db', 'excess_postfloor_q95_db', 'flank_in_transition', ...
        'rb2_pass_descriptive', 'max_abs_flank_change_db', 'b_q95_db', 'a_minus_b_q95_db'});
end
T = vertcat(rows{:});
T.a_passes = repmat(all(T.recording_pass), height(T), 1);
writetable(T, outFile);
[p, nmF] = fileparts(outFile);
df = fullfile(p, [nmF '_decision.txt']);
fid = fopen(df, 'w');
fprintf(fid, 'S3a-D5a-test (criterion S3a-D5a-crit2, width a = %g Hz), %s\n', a, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'residual = max over f0 +/- 0.5 Hz of post-filter PSD / pre-filter flank floor (dB); C1: q95 < 3 dB\n');
fprintf(fid, 'real batch %s, batch.json SHA-256 %s\n', batchDir, sha256File(fullfile(batchDir, 'batch.json')));
fprintf(fid, 'null batch %s, batch.json SHA-256 %s\n', nullBatchDir, sha256File(fullfile(nullBatchDir, 'batch.json')));
fprintf(fid, '(b) merge %s, SHA-256 %s\n', bMergeFile, sha256File(bMergeFile));
for k = 1:size(srcR, 1), fprintf(fid, 'input %s %s\n', srcR{k, 1}, srcR{k, 2}); end
for k = 1:size(srcN, 1), fprintf(fid, 'null input %s %s\n', srcN{k, 1}, srcN{k, 2}); end
fprintf(fid, 'null residual (descriptive): %s\n', strjoin(arrayfun(@(i) sprintf('%s %s q95 %.4f dB, max %.4f dB', ...
    N(i).subject, N(i).task, nq(i), nm(i)), 1:2, 'uni', 0), '; '));
fprintf(fid, 'R-b2 not evaluated (flank band inside the notch transition band in %d of %d recordings)\n', sum(T.flank_in_transition), height(T));
fprintf(fid, '%-8s %-5s %10s %5s %10s %8s %10s\n', 'subject', 'task', 'res_q95', 'pass', 'res_max', 'n_gt3', 'b_q95');
for k = 1:height(T)
    fprintf(fid, '%-8s %-5s %10.4f %5d %10.4f %8d %10.4f\n', T.subject(k), T.task(k), T.residual_q95_db(k), ...
        T.recording_pass(k), T.residual_max_db(k), T.residual_cells_gt3db(k), T.b_q95_db(k));
end
fprintf(fid, 'recordings passing (residual q95 < 3 dB): %d of %d\n', sum(T.recording_pass), height(T));
if all(T.recording_pass)
    fprintf(fid, 'DECISION: PASS on all recordings -> final D5 decision "(a), a = %g, all recordings" (pre-registered; log entry to be added)\n', a);
else
    fprintf(fid, 'DECISION: FAIL -> STOP and report to Amirhossein (no further automatic step)\n');
end
fprintf(fid, 'output %s SHA-256 %s\n', outFile, sha256File(outFile));
fclose(fid);
disp(T);
fprintf('%s', fileread(df));

    function c = resid(r)
        e = stage3_d5a_residual(r.avgPBefore, r.avgPAfter, d, flank, pkwin);
        c = e(r.kept, :); c = c(:);
    end
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
