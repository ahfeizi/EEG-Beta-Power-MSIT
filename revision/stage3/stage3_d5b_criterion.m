function stage3_d5b_criterion(nullMergeFile, outFile, realMergeFile)
%STAGE3_D5B_CRITERION  Tabulate the R-b1 null calibration (S3a-D5b-null) and, once they exist, the real
%   (b) results next to it. nullMergeFile: stage3_d5b_merge output of the noise-only twins (cleaned by
%   the same job). For each recording: the after-excess distribution over its kept-channel x f0 cells
%   (max, 50/90/95/99th percentiles, cells >= 3 dB), null and (if given) real, and the candidate
%   criteria of S3a-D5b-null evaluated on the real data:
%     C0 committed R-b1   max over cells < 3 dB
%     C1 quantile         95th percentile over cells < 3 dB
%     C2 null max         max over cells <= max over the same recording's null cells
%     C3 null quantile    99th percentile over cells <= 99th percentile of the recording's null cells
%   Writes a CSV (never overwrites). The criterion is Amirhossein's decision; nothing is chosen here.

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
N = load(nullMergeFile); Ns = N.summary;
T = Ns(:, {'subject', 'task', 'role', 'n_chunks', 'n_cells'});
T.null_max_db = Ns.max_excess_after_db; T.null_q50_db = Ns.q50_after_db; T.null_q90_db = Ns.q90_after_db;
T.null_q95_db = Ns.q95_after_db; T.null_q99_db = Ns.q99_after_db; T.null_cells_ge3db = Ns.n_cells_ge3db;
T.null_c0_pass = Ns.max_excess_after_db < 3;
if nargin >= 3 && ~isempty(realMergeFile)
    R = load(realMergeFile); Rs = R.summary;
    [ok, ir] = ismember(T.subject + "_" + T.task, Rs.subject + "_" + Rs.task);
    assert(all(ok), 'real and null recordings differ');
    Rs = Rs(ir, :);
    T.real_max_db = Rs.max_excess_after_db; T.real_q95_db = Rs.q95_after_db; T.real_q99_db = Rs.q99_after_db;
    T.real_cells_ge3db = Rs.n_cells_ge3db; T.real_rb2_pass = Rs.rb2_pass;
    T.C0_committed = Rs.max_excess_after_db < 3;
    T.C1_q95_lt3 = Rs.q95_after_db < 3;
    T.C2_max_le_null_max = Rs.max_excess_after_db <= T.null_max_db;
    T.C3_q99_le_null_q99 = Rs.q99_after_db <= T.null_q99_db;
end
writetable(T, outFile);
disp(T);
end
