function S = r1_phase2_synth_test(outDir, nRep, B)
%R1_PHASE2_SYNTH_TEST K1.7 synthetic validation of the Phase 2 code (decision log §11k K1.7; criteria §11l).
%   S = r1_phase2_synth_test(outDir, nRep, B)     defaults: nRep = 100 (§11l amendment), B = 200
%   Synthetic data only; no real trial is read. Writes r1_phase2_synth_results.mat and
%   r1_phase2_synth_summary.txt to outDir (never overwrites) and errors if any §11l criterion fails.
if nargin < 2, nRep = 100; end
if nargin < 3, B = 200; end
matF = fullfile(outDir, 'r1_phase2_synth_results.mat');
txtF = fullfile(outDir, 'r1_phase2_synth_summary.txt');
assert(~exist(matF, 'file') && ~exist(txtF, 'file'), 'r1:synth', 'outputs exist, not overwritten');
if ~exist(outDir, 'dir'), mkdir(outDir); end
warning('off', 'backtrace');

P = struct('nS', 39, 'nPer', 26, 'nSession', 400, 'r0', log(0.6), 'a', 0.16, 'sd_v0', 0.10, 'sd_va', 0.04, ...
    'sd_cell', 0.03, 'sd_trial', 0.15, 'b0', -0.8, 'sd_u0', 0.25, 'cp', -0.03, 'sd_uc', 0.02, 'gamma', 0.40, ...
    'delta', 0.01, 'b', -0.10, 'sd_ub', 0.05, 'sd_res', 0.15, 'sd_base_subj', 0.20, 'sd_base_trial', 0.15);
covs = {'base_c', 'order_z'};
lines = {};
say = @(varargin) fprintf('%s\n', sprintf(varargin{:}));
pass = struct();

%% T1 recovery over nRep replicates (+ T6 bootstrap on replicate 1, T7 REML on every fit)
names = {'cp (M1 nconf_c)', 'b (M1 rt_w)', 'gamma (M1 base_c)', 'a (a-model nconf_c)', 'M0 nconf_c ~ cp + a*b'};
truth = [P.cp, P.b, P.gamma, P.a, P.cp + P.a * P.b];
est = nan(nRep, 5); se = nan(nRep, 5); lo = nan(nRep, 5); hi = nan(nRep, 5); lev = nan(nRep, 3);
reml = true;
for r = 1:nRep
    D = r1_phase2_prepare(r1_phase2_synth_generate(P, 1000 + r));
    o = struct('dataKind', 'synthetic', 'B', 0);
    if r == 1, o.B = B; o.seed = 20261117; end
    K = r1_phase2_k3(D, covs, o);
    rowsK = {K.beta1, K.b_rtw, coefRowT(K.M1.coef, 'base_c'), K.a, K.beta0};
    for j = 1:5
        est(r, j) = rowsK{j}.Estimate; se(r, j) = rowsK{j}.SE; lo(r, j) = rowsK{j}.Lower; hi(r, j) = rowsK{j}.Upper;
    end
    lev(r, :) = [K.M0.level, K.M1.level, K.A.level];
    reml = reml && all(strcmp({K.M0.lme.FitMethod, K.M1.lme.FitMethod, K.A.lme.FitMethod}, 'REML'));
    if r == 1, K1 = K; end
    say('rep %2d: M0/M1/a structure levels %d/%d/%d; c''=%.4f b=%.4f a=%.4f', r, lev(r, :), est(r, 1), est(r, 2), est(r, 4));
end
cover = sum(lo <= truth & truth <= hi, 1);
bias = mean(est, 1) - truth;
mse_ = mean(se, 1);
t1 = true;
lines{end + 1} = sprintf('T1 recovery, %d replicates (structure levels reached, M0/M1/a: %s)', nRep, mat2str(unique(lev, 'rows')));
for j = 1:5
    okCov = (j == 5) || cover(j) >= 16 * nRep / 20;
    okBias = abs(bias(j)) <= 0.5 * mse_(j);
    t1 = t1 && okCov && okBias;
    lines{end + 1} = sprintf('  %-26s true %+.4f  mean est %+.4f  bias %+.5f (limit %.5f)  coverage %d/%d%s  -> %s', ...
        names{j}, truth(j), mean(est(:, j)), bias(j), 0.5 * mse_(j), cover(j), nRep, ...
        ternary(j == 5, ' (not a criterion)', ''), ternary(okCov && okBias, 'PASS', 'FAIL')); %#ok<AGROW>
end
pass.T1 = t1;

trueAB = P.a * P.b;
pass.T6 = K1.ab_ci(1) <= trueAB && trueAB <= K1.ab_ci(2) && K1.boot_failed <= 0.05 * B;
lines{end + 1} = sprintf('T6 bootstrap (rep 1, B = %d): a*b = %+.5f, 95%% CI [%+.5f, %+.5f], true %+.5f, failed resamples %d -> %s', ...
    B, K1.ab, K1.ab_ci, trueAB, K1.boot_failed, ternary(pass.T6, 'PASS', 'FAIL'));
lines{end + 1} = sprintf('   beta0 %+.5f, beta1 %+.5f, beta1 - beta0 %+.5f (expected about %+.5f)', ...
    K1.beta0.Estimate, K1.beta1.Estimate, K1.diff, -trueAB);
lv = K1.boot_level_M1(~isnan(K1.boot_level_M1)); la = K1.boot_level_A(~isnan(K1.boot_level_A));
lines{end + 1} = sprintf('   resample structure levels reached (full ladder per resample): M1 %s; a-model %s', ...
    mat2str(histcounts(lv, -0.5:1:3.5)), mat2str(histcounts(la, -0.5:1:2.5)));
if ~isempty(K1.boot_fail_msgs), lines{end + 1} = ['   failure messages: ' strjoin(unique(K1.boot_fail_msgs), ' | ')]; end
pass.T7 = reml;
lines{end + 1} = sprintf('T7 REML on every fit: %s', ternary(reml, 'PASS', 'FAIL'));

%% T2 natural simplification: random-slope SDs set to zero
P2 = P; P2.sd_uc = 0; P2.sd_ub = 0; P2.sd_va = 0;
D2 = r1_phase2_prepare(r1_phase2_synth_generate(P2, 2001));
F2 = r1_phase2_fit(D2, 'y', [{'nconf_c'}, covs, {'rt_w', 'rt_cm'}], {'nconf_c', 'rt_w'}, {'rt_w', 'nconf_c'}, ...
    struct('dataKind', 'synthetic'));
at = F2.attempts;
seqOK = height(at) >= 2 && at.level(1) == 0 && ~at.maxIterRaised(1) && at.level(2) == 0 && at.maxIterRaised(2) ...
    && all(diff(at.level(2:end)) == 1) && at.ok(end) && ~any(at.ok(1:end - 1));
warnOK = ~strcmp(F2.levelName, 'intercept only') || ~isempty(F2.interceptOnlyWarning);
pass.T2 = seqOK && warnOK && F2.level >= 1;
lines{end + 1} = sprintf('T2 natural simplification: reached level %d (%s) -> %s', F2.level, F2.levelName, ternary(pass.T2, 'PASS', 'FAIL'));
lines = [lines, attemptLines(at)];

%% T3 forced failure of levels 0-2 -> intercept only with the warning
F3 = r1_phase2_fit(r1_phase2_prepare(r1_phase2_synth_generate(P, 3001)), 'y', [{'nconf_c'}, covs, {'rt_w', 'rt_cm'}], ...
    {'nconf_c', 'rt_w'}, {'rt_w', 'nconf_c'}, struct('dataKind', 'synthetic', 'forceFail', [0 1 2]));
pass.T3 = F3.level == 3 && strcmp(F3.levelName, 'intercept only') && ~isempty(F3.interceptOnlyWarning) ...
    && isequal(F3.attempts.level', [0 0 1 2 3]) && all(contains(F3.attempts.reason(1:4), 'forced'));
lines{end + 1} = sprintf('T3 forced failure of levels 0-2: reached level %d (%s), warning present: %d -> %s', ...
    F3.level, F3.levelName, ~isempty(F3.interceptOnlyWarning), ternary(pass.T3, 'PASS', 'FAIL'));
lines = [lines, attemptLines(F3.attempts)];

%% T4 every level forced to fail -> error
try
    r1_phase2_fit(r1_phase2_prepare(r1_phase2_synth_generate(P, 4001)), 'y', [{'nconf_c'}, covs], {'nconf_c'}, {'nconf_c'}, ...
        struct('dataKind', 'synthetic', 'forceFail', 0:5));
    pass.T4 = false; m4 = 'no error raised';
catch ME
    pass.T4 = strcmp(ME.identifier, 'r1:fit'); m4 = ME.message;
end
lines{end + 1} = sprintf('T4 all levels forced to fail: %s -> %s', m4, ternary(pass.T4, 'PASS', 'FAIL'));

%% T5 the hook is refused on real data
try
    r1_phase2_fit(D2, 'y', [{'nconf_c'}, covs], {'nconf_c'}, {'nconf_c'}, struct('dataKind', 'real', 'forceFail', 0));
    pass.T5 = false; m5 = 'not refused';
catch ME
    pass.T5 = strcmp(ME.identifier, 'r1:fit') && contains(ME.message, 'refused'); m5 = ME.message;
end
lines{end + 1} = sprintf('T5 hook on real data: %s -> %s', m5, ternary(pass.T5, 'PASS', 'FAIL'));

%% T8 construction checks (asserted in r1_phase2_prepare; reached here only if they held)
pass.T8 = true;
lines{end + 1} = 'T8 coding/centring assertions in r1_phase2_prepare held for every dataset -> PASS';

allPass = all(cellfun(@(f) pass.(f), fieldnames(pass)));
lines{end + 1} = sprintf('OVERALL: %s', ternary(allPass, 'ALL CRITERIA PASS', 'AT LEAST ONE CRITERION FAILED'));
S = struct('P', P, 'truth', truth, 'est', est, 'se', se, 'lo', lo, 'hi', hi, 'levels', lev, 'pass', pass, ...
    'K1_ab', K1.ab, 'K1_ab_ci', K1.ab_ci, 'K1_boot_failed', K1.boot_failed, 'K1_boot_level_M1', K1.boot_level_M1, ...
    'K1_boot_level_A', K1.boot_level_A, 'attempts_T2', F2.attempts, ...
    'attempts_T3', F3.attempts, 'lines', {lines});
save(matF, 'S');
fid = fopen(txtF, 'w'); fprintf(fid, '%s\n', lines{:}); fclose(fid);
fprintf('%s\n', lines{:});
if ~allPass, error('r1:synth', 'synthetic validation failed; see %s', txtF); end
end


function r = coefRowT(st, name)
r = st(strcmp(string(st.Name), name), :);
end


function L = attemptLines(at)
L = cell(1, height(at));
for k = 1:height(at)
    L{k} = sprintf('     level %d %-34s maxIter raised %d  ok %d  %s', at.level(k), at.structure{k}, ...
        at.maxIterRaised(k), at.ok(k), at.reason{k});
end
end


function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
