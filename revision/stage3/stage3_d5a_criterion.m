function T = stage3_d5a_criterion(batchDir, bMergeFile, outFile)
%STAGE3_D5A_CRITERION  Decision table of the (a) residual test (S3a-D5a-test).
%   batchDir: the finished A/B batch of stage3_d5a_compute_one (9 test-set recordings); every canonical
%   output is hash-checked against its state file. bMergeFile: the (b) merge output (d5bm_1), for the
%   descriptive (a) vs (b) comparison. Writes outFile (CSV, never overwrites) and <outFile>_decision.txt.
%   Per recording:
%     C1_q95_lt3        95th percentile of the after-excess over the kept-channel x f0 cells < 3 dB (as (b))
%     flank_in_transition  the R-b2 flank band (1.5-3 Hz from f0) overlaps a notch transition band
%     rb2_pass          R-b2 as for (b) (|flank change| <= 0.5 dB); evaluated only if flank_in_transition is false
%     recording_pass    C1_q95_lt3, and rb2_pass unless flank_in_transition
%   a_passes = every recording_pass (same value in every row). Decision rule: a_passes -> adopt (a) for all
%   recordings; otherwise stop and report to Amirhossein (no further automatic step).
%   Descriptive: max excess, cells > 3 dB, max |flank change|, flank gain range, (b) q95 and (a) - (b).

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
batch = jsondecode(fileread(fullfile(batchDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');
S = dir(fullfile(batchDir, 'state', '*.json'));
Bm = load(bMergeFile); Bs = Bm.summary;
rows = cell(numel(S), 1);
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(batchDir, 'state', S(k).name)));
    assert(strcmp(st.status, 'verified'), '%s: status %s', S(k).name, st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', S(k).name);
    L = load(st.canonical.path); r = L.res;
    q = r.afterCellQuantilesDb;
    e = r.excessAfterDb(r.kept, :);
    ib = find(Bs.subject == r.subject & Bs.task == r.task);
    assert(isscalar(ib), '%s %s: not exactly one (b) row', r.subject, r.task);
    c1 = q(3) < 3; fit = r.notch.flankInTransition;
    rows{k} = table(r.subject, r.task, r.role, r.nChunk, r.nCells, q(3), c1, fit, r.rb2Pass, ...
        c1 && (fit || r.rb2Pass), r.maxExcessAfterKeptDb, sum(e(:) > 3), q(4), r.maxAbsFlankChangeKeptDb, ...
        r.notch.flankGainDbRange(1), r.notch.flankGainDbRange(2), Bs.q95_after_db(ib), q(3) - Bs.q95_after_db(ib), ...
        'VariableNames', {'subject', 'task', 'role', 'n_chunks', 'n_cells', 'a_q95_db', 'C1_q95_lt3', ...
        'flank_in_transition', 'rb2_pass', 'recording_pass', 'a_max_db', 'a_cells_gt3db', 'a_q99_db', ...
        'a_max_abs_flank_change_db', 'flank_gain_min_db', 'flank_gain_max_db', 'b_q95_db', 'a_minus_b_q95_db'});
end
T = vertcat(rows{:});
T.a_passes = repmat(all(T.recording_pass), height(T), 1);
writetable(T, outFile);
[p, n] = fileparts(outFile);
fid = fopen(fullfile(p, [n '_decision.txt']), 'w');
fprintf(fid, 'S3a-D5a-test; batch %s (batch.json SHA-256 %s); (b) merge %s (SHA-256 %s)\n', batchDir, ...
    sha256File(fullfile(batchDir, 'batch.json')), bMergeFile, sha256File(bMergeFile));
fprintf(fid, 'flank band in a notch transition band: %d of %d recordings -> R-b2 %s\n', sum(T.flank_in_transition), ...
    height(T), ternary(all(T.flank_in_transition), 'not evaluated (C1 only)', 'evaluated where not in transition'));
fprintf(fid, 'recordings passing: %d of %d\n', sum(T.recording_pass), height(T));
if all(T.recording_pass), fprintf(fid, 'DECISION: (a) passes on all recordings -> adopt (a) for all recordings\n');
else, fprintf(fid, 'DECISION: (a) does not pass on all recordings -> STOP and report to Amirhossein\n'); end
fclose(fid);
disp(T);
fprintf('%s', fileread(fullfile(p, [n '_decision.txt'])));
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
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
