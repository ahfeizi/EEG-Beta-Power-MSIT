function r1_phase2_run_real(outDir, B)
%R1_PHASE2_RUN_REAL Phase 2 on the real trial table, exactly per decision log §11k and §11m.
%   r1_phase2_run_real(outDir)   outDir = <outRoot>\review1\phase2_real (holds r1_phase2_trials.csv and
%   r1_phase2_k4b_cells.csv). Writes r1_phase2_raw_output.txt, r1_phase2_coefficients.csv and
%   r1_phase2_results.mat. Raw output only: no agreement verdict and no interpretation is computed here.
%   Never overwrites. B = bootstrap resamples for the K3 runs (default 1000, the §11m value; B = 0 is a
%   dry run of the code path only).
if nargin < 2, B = 1000; end
txtF = fullfile(outDir, 'r1_phase2_raw_output.txt');
csvF = fullfile(outDir, 'r1_phase2_coefficients.csv');
matF = fullfile(outDir, 'r1_phase2_results.mat');
assert(~exist(txtF, 'file') && ~exist(csvF, 'file') && ~exist(matF, 'file'), 'r1:real', 'outputs exist');
warning('off', 'backtrace');

io = detectImportOptions(fullfile(outDir, 'r1_phase2_trials.csv'));
io = setvartype(io, {'subject', 'cond', 'outcome'}, 'string');
T = readtable(fullfile(outDir, 'r1_phase2_trials.csv'), io);
ic = detectImportOptions(fullfile(outDir, 'r1_phase2_k4b_cells.csv'));
ic = setvartype(ic, {'subject', 'cond'}, 'string');
C = readtable(fullfile(outDir, 'r1_phase2_k4b_cells.csv'), ic);
assert(height(T) == 15492, 'r1:real', 'trial table has %d rows', height(T));
assert(nnz(T.set_primary) == 4093 && nnz(T.set_later) == 10578, 'r1:real', 'set sizes');
cols = {'subject', 'cond', 'active_power', 'baseline_power', 'rt_ms', 'trial_index', 'mb_pos', 'correct'};
sel = @(m) T(m == 1, cols);
o = struct('dataKind', 'real', 'B', B, 'seed', 20261117);
o0 = struct('dataKind', 'real', 'B', 0);
fr = struct('dataKind', 'real');
covs = {'base_c', 'order_z'};
R = struct();
stamp = @(s) fprintf('[%s] %s\n', char(datetime('now', 'Format', 'HH:mm:ss')), s);

stamp(sprintf('1 primary K3 (B = %d)', B));
R.primary = r1_phase2_k3(r1_phase2_prepare(sel(T.set_primary)), covs, o);
stamp(sprintf('2 later K3 (B = %d)', B));
R.later = r1_phase2_k3(r1_phase2_prepare(sel(T.set_later)), [covs, {'mb_pos'}], o);

stamp('3 K1.2(c) Simon x Flanker, primary set');
Dp = r1_phase2_prepare(sel(T.set_primary));
fx = [{'simon', 'flanker', 'simon:flanker'}, covs];
R.sxf_M0 = r1_phase2_fit(Dp, 'y', fx, {'simon', 'flanker'}, {'flanker', 'simon'}, fr);
R.sxf_M1 = r1_phase2_fit(Dp, 'y', [fx, {'rt_w', 'rt_cm'}], {'simon', 'flanker', 'rt_w'}, {'rt_w', 'flanker', 'simon'}, fr);

stamp('4 K4a all responded trials, accuracy term');
Da = r1_phase2_prepare(sel(T.set_k4a));
fa = [{'nconf_c'}, covs, {'acc', 'nconf_c:acc'}];
R.k4a_M0 = r1_phase2_fit(Da, 'y', fa, {'nconf_c'}, {'nconf_c'}, fr);
R.k4a_M1 = r1_phase2_fit(Da, 'y', [fa, {'rt_w', 'rt_cm'}], {'nconf_c', 'rt_w'}, {'rt_w', 'nconf_c'}, fr);

stamp('5 K4b aperiodic-adjusted outcome (fixed, knee, knee excluding flagged cells)');
Tp = T(T.set_primary == 1, :);
[tf, loc] = ismember(Tp.subject + "|" + Tp.cond, C.subject + "|" + C.cond);
assert(all(tf), 'r1:real', 'primary trials without a K4b cell');
for v = {'fixed', 'knee', 'knee_excl'}
    mode = strrep(v{1}, '_excl', '');
    keep = true(height(Tp), 1);
    if strcmp(v{1}, 'knee_excl'), keep = C.knee_flag(loc) == 0; end
    okFit = C.(['act_' mode '_ok'])(loc) == 1 & C.(['base_' mode '_ok'])(loc) == 1;
    keep = keep & okFit;
    Tv = Tp(keep, cols);
    Tv.active_power = Tv.active_power ./ C.(['act_' mode '_ap_band'])(loc(keep));
    Tv.baseline_power = Tv.baseline_power ./ C.(['base_' mode '_ap_band'])(loc(keep));
    R.(['k4b_' v{1}]) = r1_phase2_k3(r1_phase2_prepare(Tv), covs, o0);
    R.(['k4b_' v{1} '_n']) = [height(Tv), numel(unique(Tv.subject + "|" + Tv.cond))];
end

stamp(sprintf('6 K4c primary set without RT > 1000 ms (B = %d)', B));
R.k4c = r1_phase2_k3(r1_phase2_prepare(sel(T.set_k4c)), covs, o);
stamp('writing outputs');

% ---- raw output ----
L = {};
L{end + 1} = 'PHASE 2 RAW OUTPUT (decision log §11k, §11m). No interpretation, no agreement verdicts.';
L{end + 1} = sprintf('generated %s; bootstrap B = %d', char(datetime('now')), B);
K3s = {'primary', 'Primary K3: first-in-mini-block, retained, n = %d'; ...
       'later', 'Later-trials K3 (+ mb_pos), n = %d'; ...
       'k4b_fixed', 'K4b fixed-adjusted K3 (no bootstrap), n = %d'; ...
       'k4b_knee', 'K4b knee-adjusted K3 (no bootstrap), n = %d'; ...
       'k4b_knee_excl', 'K4b knee-adjusted excluding flagged cells (no bootstrap), n = %d'; ...
       'k4c', 'K4c primary without RT > 1000 ms, n = %d'};
coefRows = {};
for i = 1:size(K3s, 1)
    K = R.(K3s{i, 1});
    L{end + 1} = ''; L{end + 1} = repmat('=', 1, 100);
    L{end + 1} = sprintf(K3s{i, 2}, height(K.M1.lme.Variables) - sum(K.M1.lme.ObservationInfo.Excluded));
    if startsWith(K3s{i, 1}, 'k4b_'), L{end + 1} = sprintf('  trials %d, cells %d', R.([K3s{i, 1} '_n'])); end
    L{end + 1} = sprintf('  beta0 (M0 nconf_c) %+.6f  [%+.6f, %+.6f]  SE %.6f  DF %.2f  p %.4g', ...
        K.beta0.Estimate, K.beta0.Lower, K.beta0.Upper, K.beta0.SE, K.beta0.DF, K.beta0.pValue);
    L{end + 1} = sprintf('  beta1 (M1 nconf_c) %+.6f  [%+.6f, %+.6f]  SE %.6f  DF %.2f  p %.4g', ...
        K.beta1.Estimate, K.beta1.Lower, K.beta1.Upper, K.beta1.SE, K.beta1.DF, K.beta1.pValue);
    L{end + 1} = sprintf('  beta1 - beta0 %+.6f', K.diff);
    L{end + 1} = sprintf('  b (M1 rt_w) %+.6f  [%+.6f, %+.6f]  p %.4g;  rt_cm %+.6f  [%+.6f, %+.6f]  p %.4g', ...
        K.b_rtw.Estimate, K.b_rtw.Lower, K.b_rtw.Upper, K.b_rtw.pValue, K.b_rtcm.Estimate, K.b_rtcm.Lower, ...
        K.b_rtcm.Upper, K.b_rtcm.pValue);
    L{end + 1} = sprintf('  a (a-model nconf_c, ln RT) %+.6f  [%+.6f, %+.6f]  p %.4g', K.a.Estimate, K.a.Lower, K.a.Upper, K.a.pValue);
    L{end + 1} = sprintf('  a*b %+.6f  bootstrap 95%% CI [%+.6f, %+.6f]  resamples ok %d, failed %d  (%s)', ...
        K.ab, K.ab_ci, K.boot_n_ok, K.boot_failed, K.label_ab);
    if K.boot_n_ok > 0
        L{end + 1} = sprintf('  bootstrap structure levels: M1 %s; a-model %s', ...
            mat2str(histcounts(K.boot_level_M1(~isnan(K.boot_level_M1)), -0.5:1:3.5)), ...
            mat2str(histcounts(K.boot_level_A(~isnan(K.boot_level_A)), -0.5:1:2.5)));
    end
    for mname = {'M0', 'A', 'M1'}
        [L, coefRows] = modelBlock(L, coefRows, [K3s{i, 1} '.' mname{1}], K.(mname{1}));
    end
end
for m = {'sxf_M0', 'sxf_M1', 'k4a_M0', 'k4a_M1'}
    L{end + 1} = ''; L{end + 1} = repmat('=', 1, 100);
    [L, coefRows] = modelBlock(L, coefRows, m{1}, R.(m{1}));
end
fid = fopen(txtF, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
CT = vertcat(coefRows{:});
writetable(CT, csvF);
save(matF, 'R', '-v7.3');
fprintf('%s\n', L{:});
end


function [L, rows] = modelBlock(L, rows, name, F)
n = height(F.lme.Variables) - sum(F.lme.ObservationInfo.Excluded);
L{end + 1} = sprintf('-- %s: n = %d, participants = %d, structure level %d (%s), pattern %s', name, n, ...
    numel(unique(F.lme.Variables.subject)), F.level, F.levelName, F.pattern);
L{end + 1} = sprintf('   formula: %s', F.formula);
if ~isempty(F.interceptOnlyWarning), L{end + 1} = ['   ' F.interceptOnlyWarning]; end
for k = 1:height(F.attempts)
    L{end + 1} = sprintf('   attempt level %d %-30s maxIter raised %d ok %d %s', F.attempts.level(k), ...
        F.attempts.structure{k}, F.attempts.maxIterRaised(k), F.attempts.ok(k), F.attempts.reason{k}); %#ok<AGROW>
end
L{end + 1} = sprintf('   random-effect SDs %s; residual SD %.6f', mat2str(F.randomSD, 6), F.residualSD);
st = F.coef;
for k = 1:height(st)
    L{end + 1} = sprintf('   %-16s %+.6f  SE %.6f  t %+8.3f  DF %8.2f  p %.4g  [%+.6f, %+.6f]', string(st.Name(k)), ...
        st.Estimate(k), st.SE(k), st.tStat(k), st.DF(k), st.pValue(k), st.Lower(k), st.Upper(k)); %#ok<AGROW>
end
t = st; t.model = repmat(string(name), height(t), 1); t.level = repmat(F.level, height(t), 1);
t.Name = string(t.Name);
rows{end + 1} = t(:, [{'model', 'level'}, setdiff(t.Properties.VariableNames, {'model', 'level'}, 'stable')]);
end
