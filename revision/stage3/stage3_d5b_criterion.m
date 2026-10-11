function T = stage3_d5b_criterion(nullMergeFile, outFile, realMergeFile)
%STAGE3_D5B_CRITERION  R-b1 as decided in S3a-D5b-rb1 (criterion C1, conditional on the null).
%   nullMergeFile: stage3_d5b_merge output of the noise-only twins (S3a-D5b-null-amend1: the rest and
%   the MSIT+ test recording with the fewest chunks), cleaned by the same job.
%
%   Null only (2 arguments): one row per twin with the after-excess distribution over its kept-channel
%   x f0 cells (max, 50/90/95/99th percentiles, cells >= 3 dB, cells > 3 dB) and
%     null_q95_le_2db   null 95th percentile <= 2 dB.
%   The C1 criterion is VALID only if null_q95_le_2db holds in both twins (column null_c1_valid,
%   the same value in every row). The caller (Invoke-Stage3D5bNullThenReal.ps1) reads that column.
%
%   With the real merge (3 arguments): one row per real test-set recording with
%     C1_q95_lt3       R-b1 = C1: 95th percentile of the after-excess over the cells < 3 dB
%     rb2_pass         R-b2 (committed, unchanged)
%     recording_pass   C1_q95_lt3 && rb2_pass
%   and, as descriptives only, the maximum and the number of cells > 3 dB. null_c1_valid is repeated;
%   b_passes = null_c1_valid && every recording_pass (the same value in every row).
%   Percentiles are those of stage3_d5b_rules (MATLAB quantile). Writes a CSV (never overwrites).

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
N = load(nullMergeFile);
assert(height(N.summary) == 2 && all(sort(N.summary.task) == ["msit"; "rest"]), ...
    'the null must hold exactly one rest and one MSIT+ twin (S3a-D5b-null-amend1)');
nullValid = all(N.summary.q95_after_db <= 2);
if nargin < 3 || isempty(realMergeFile)
    Ns = N.summary;
    T = Ns(:, {'subject', 'task', 'role', 'n_chunks', 'n_cells'});
    T.null_max_db = Ns.max_excess_after_db; T.null_q50_db = Ns.q50_after_db; T.null_q90_db = Ns.q90_after_db;
    T.null_q95_db = Ns.q95_after_db; T.null_q99_db = Ns.q99_after_db; T.null_cells_ge3db = Ns.n_cells_ge3db;
    T.null_cells_gt3db = cellsAbove(N.results, T, 3);
    T.null_q95_le_2db = Ns.q95_after_db <= 2;
    T.null_c1_valid = repmat(nullValid, height(T), 1);
else
    R = load(realMergeFile); Rs = R.summary;
    T = Rs(:, {'subject', 'task', 'role', 'n_chunks', 'n_cells'});
    T.real_q95_db = Rs.q95_after_db;
    T.C1_q95_lt3 = Rs.q95_after_db < 3;
    T.rb2_pass = Rs.rb2_pass;
    T.recording_pass = T.C1_q95_lt3 & T.rb2_pass;
    T.real_max_db = Rs.max_excess_after_db;                % descriptive only
    T.real_cells_gt3db = cellsAbove(R.results, T, 3);      % descriptive only
    T.real_q99_db = Rs.q99_after_db; T.real_max_abs_flank_change_db = Rs.max_abs_flank_change_db;
    T.null_c1_valid = repmat(nullValid, height(T), 1);
    T.b_passes = repmat(nullValid && all(T.recording_pass), height(T), 1);
end
writetable(T, outFile);
disp(T);
end

function n = cellsAbove(results, T, thr)
% number of kept-channel x f0 cells with after-excess > thr, in the row order of T
n = nan(height(T), 1);
for i = 1:height(T)
    k = find(arrayfun(@(r) r.subject == T.subject(i) && r.task == T.task(i), results));
    assert(isscalar(k), '%s %s: not exactly one result', T.subject(i), T.task(i));
    e = results(k).excessAfterDb(results(k).kept, :);
    n(i) = sum(e(:) > thr);
end
end
