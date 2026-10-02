%% Stage 2, pass 2 (decision S2-2): were the v1 conclusions sensitive to the Wilcoxon method?
% Reads ONLY v1 CSVs (read-only) and writes to <outRoot>/stage2/. NOT a source of
% manuscript numbers (see S2-2): it documents method sensitivity only.
%
% For every test this script
%   1. re-creates the v1 computation exactly (same inputs, same signrank call), and checks
%      it against the p-value saved by v1 where one was saved ("replicates_v1");
%   2. recomputes the same test with signrank(..., 'method', 'exact');
%   3. reports the significance status at the threshold v1 used.
% Tests (S2-2): (a) channel screening + BH-FDR, (b) FS vs 00, (c) Table 2 (control check),
% (d) exploratory post-hoc pairwise tests of statComparison (v1 p-values were never saved).
% Page's L is not recomputed (S2-2, option (a)).

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % revision/stage2/<this> -> repository root
addpath(repoRoot);
P = get_paths();
outDir = fullfile(P.outRoot, 'stage2');
if ~exist(outDir, 'dir'), mkdir(outDir); end
repTol = 1e-12;   % "replicates v1": relative difference allowed by the 15-significant-digit CSV round trip

%% (a) channel screening: one-sample signed-rank of within-subject z-scores, BH-FDR q = .05
T = readtable(fullfile(P.derivRoot, 'beta_power_all_channels_all_subjects.csv'), ...
    'ReadRowNames', true, 'VariableNamingRule', 'preserve');          % as in v1
chan = T.Properties.RowNames;
X = table2array(T);                                                    % nChan x nSubj
Z = (X - mean(X, 1)) ./ std(X, 0, 1);                                 % per-subject z across channels (v1: (col-mean)/std)
nC = numel(chan);
[pV1m, pEx] = deal(nan(nC, 1));
for c = 1:nC
    row = Z(c, :);
    if all(row == row(1)), pV1m(c) = 1; pEx(c) = 1; continue; end    % v1 guard against degenerate rows
    pV1m(c) = signrank(row);                                           % v1 call (n = 42 -> normal approximation)
    pEx(c)  = signrank(row, 0, 'method', 'exact');
end
dV1m = bh_fdr(pV1m, 0.05);
dEx  = bh_fdr(pEx, 0.05);
v1 = readtable(fullfile(P.derivRoot, 'beta_distinct_channels_stats.csv'), 'TextType', 'string');
[~, ix] = ismember(string(chan), v1.channel);
pV1saved = v1.pValue(ix);
A = table(string(chan), mean(Z, 2), pV1saved, pV1m, relDiff(pV1m, pV1saved) <= repTol, ...
    logical(v1.distinct_FDR05(ix)), dV1m, pEx, dEx, dEx ~= dV1m, ...
    'VariableNames', {'channel','meanZ','p_v1_saved','p_v1_method','replicates_v1', ...
    'distinct_v1_saved','distinct_v1_method','p_exact','distinct_exact','fdr_status_changed'});
writetable(A, fullfile(outDir, 'pass2_a_channel_screening.csv'));

%% (b) planned FS vs 00 contrast of pre-stimulus beta (Fz, Cz, C4)
E = readtable(fullfile(P.taskDeriv, 'msit_beta_erd_by_condition.csv'), 'TextType', 'string');
cs = readtable(fullfile(P.taskDeriv, 'prestim_beta_conflict_specificity.csv'), 'TextType', 'string');
chans = ["Fz" "Cz" "C4"];
conds = ["00" "S0" "F0" "FS"];
subjects = unique(E.subject, 'stable');
B = table();
for ch = chans
    M = nan(numel(subjects), numel(conds));
    for s = 1:numel(subjects)
        for k = 1:numel(conds)
            r = E.subject == subjects(s) & E.channel == ch & E.condition == conds(k);
            if any(r), M(s, k) = E.baselinePower(r); end
        end
    end
    M = M(all(~isnan(M), 2), :);                                        % complete cases, as in v1
    pm = signrank(M(:, 4), M(:, 1));                                   % v1 call
    pe = signrank(M(:, 4), M(:, 1), 'method', 'exact');
    ps = cs.p_FSvs00(cs.channel == ch);
    B = [B; table(ch, size(M, 1), ps, pm, relDiff(pm, ps) <= repTol, pe, ps < 0.05, pe < 0.05, ...
        (ps < 0.05) ~= (pe < 0.05), 'VariableNames', {'channel','n','p_v1_saved','p_v1_method', ...
        'replicates_v1','p_exact','sig05_v1','sig05_exact','crosses_05'})]; %#ok<AGROW>
end
writetable(B, fullfile(outDir, 'pass2_b_fs_vs_00.csv'));

%% (c) Table 2 rest vs task beta (v1 already exact): control check
R  = readtable(fullfile(P.derivRoot, 'beta_avgpower_per_channel.csv'), 'TextType', 'string');
t2 = readtable(fullfile(P.taskDeriv, 'Table2_with_effect_sizes.csv'), 'TextType', 'string');
C = table();
for ch = chans
    restT = R(R.channel == ch, {'subject', 'avgBetaPower_raw'});
    taskAvg = varfun(@mean, E(E.channel == ch, {'subject', 'baselinePower'}), 'GroupingVariables', 'subject');
    m = innerjoin(restT, taskAvg, 'Keys', 'subject');                  % as in v1
    pm = signrank(m.mean_baselinePower, m.avgBetaPower_raw, 'method', 'exact');   % v1 call (already exact)
    pe = signrank(m.mean_baselinePower, m.avgBetaPower_raw, 'method', 'exact');
    ps = t2.p_Wilcoxon(t2.Channel == ch);
    C = [C; table(ch, height(m), ps, pm, relDiff(pm, ps) <= repTol, pe, relDiff(pe, ps), ...
        ps < 0.05/3, pe < 0.05/3, 'VariableNames', {'channel','n','p_v1_saved','p_v1_method', ...
        'replicates_v1','p_exact','relDiff_exact_vs_v1','sigBonf_v1','sigBonf_exact'})]; %#ok<AGROW>
end
writetable(C, fullfile(outDir, 'pass2_c_table2_control.csv'));

%% (d) exploratory post-hoc pairwise tests of statComparison (whole epoch; v1 p never saved)
W = readtable(fullfile(P.taskDeriv, 'msit_beta_power_by_condition.csv'), 'TextType', 'string');
condsD = ["F0" "FS" "00" "S0"];                                        % v1 order
pairs = nchoosek(1:4, 2);
D = table();
for ch = chans
    subs = unique(W.subject, 'stable');
    M = nan(numel(subs), 4);
    for s = 1:numel(subs)
        for k = 1:4
            r = W.subject == subs(s) & W.channel == ch & W.condition == condsD(k);
            if any(r), M(s, k) = W.betaPower_raw(r); end
        end
    end
    M = M(all(~isnan(M), 2), :);
    [pm, pe] = deal(nan(size(pairs, 1), 1));
    for q = 1:size(pairs, 1)
        pm(q) = signrank(M(:, pairs(q, 1)), M(:, pairs(q, 2)));                       % v1 call
        pe(q) = signrank(M(:, pairs(q, 1)), M(:, pairs(q, 2)), 'method', 'exact');
    end
    D = [D; table(repmat(ch, size(pairs, 1), 1), condsD(pairs(:, 1))', condsD(pairs(:, 2))', ...
        pm, bh_fdr(pm, 0.05), pe, bh_fdr(pe, 0.05), ...
        'VariableNames', {'channel','condA','condB','p_v1_method','fdr_v1_method','p_exact','fdr_exact'})]; %#ok<AGROW>
end
writetable(D, fullfile(outDir, 'pass2_d_posthoc_exploratory.csv'));

%% apply the S2-2 decision rule
cand = ["Fz" "Cz" "C4" "C3" "F3" "F4"];
fid = fopen(fullfile(outDir, 'pass2_summary.txt'), 'w');
pr = @(varargin) cellfun(@(h) fprintf(h, varargin{:}), {1, fid});
pr('Stage 2 pass 2 (S2-2): method sensitivity of v1 Wilcoxon tests\n\n');
pr('Replication of the v1 computation (relative tolerance %g):\n', repTol);
pr('  (a) %d/%d channel p-values replicate v1; FDR set replicates v1: %d\n', sum(A.replicates_v1), nC, ...
    isequal(A.distinct_v1_method, A.distinct_v1_saved));
pr('  (b) %d/%d FS-vs-00 p-values replicate v1\n', sum(B.replicates_v1), height(B));
pr('  (c) %d/%d Table 2 p-values replicate v1\n\n', sum(C.replicates_v1), height(C));
stopC = ~all(C.replicates_v1) || any(C.relDiff_exact_vs_v1 > repTol);
pr('Rule (c) control check: %s\n', ternary(stopC, 'FAILED -> STOP, investigate before interpreting (a), (b), (d)', ...
    'passed (exact p equals the saved v1 p)'));
ca = A(ismember(A.channel, cand), :);
flipA = ca.channel(ca.fdr_status_changed);
f4 = A(A.channel == "F4", :);
pr('Rule (a): FDR-set changes among Fz/Cz/C4/C3/F3/F4: %s\n', strjoin_or_none(flipA));
pr('          FDR-distinct channels overall: v1 method %d, exact %d; status changed for %d channel(s): %s\n', ...
    sum(A.distinct_v1_method), sum(A.distinct_exact), sum(A.fdr_status_changed), strjoin_or_none(A.channel(A.fdr_status_changed)));
pr('          F4: p v1 = %.4g, p exact = %.4g, crosses .05: %d\n', f4.p_v1_saved, f4.p_exact, (f4.p_v1_saved < .05) ~= (f4.p_exact < .05));
pr('Rule (b): FS-vs-00 p crossing .05: %s\n', strjoin_or_none(B.channel(B.crosses_05)));
flagA = ~isempty(flipA) || ((f4.p_v1_saved < .05) ~= (f4.p_exact < .05));
flagB = any(B.crosses_05);
if stopC
    verdict = 'STOP (control check failed)';
elseif ~flagA && ~flagB
    verdict = 'the exact method changes no v1 conclusion';
else
    verdict = sprintf('flags: Stage 4 (#9) = %d, Stage 6 = %d', flagA, flagB);
end
pr('\nVERDICT: %s\n', verdict);
pr('Differences are listed in pass2_a/b/c/d_*.csv. No manuscript number changes in Stage 2.\n');
fclose(fid);


function d = bh_fdr(p, q)
% Benjamini-Hochberg step-up exactly as implemented in v1: largest sorted p <= (i/m)q is the cut-off.
[s, ~] = sort(p);
m = numel(p);
below = s <= (1:m)' / m * q;
if any(below), crit = s(find(below, 1, 'last')); else, crit = 0; end
d = p <= crit;
end

function r = relDiff(a, b)
r = abs(a - b) ./ max(abs(a), abs(b));
r(a == b) = 0;
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function s = strjoin_or_none(x)
if isempty(x), s = 'none'; else, s = strjoin(string(x), ', '); end
end
