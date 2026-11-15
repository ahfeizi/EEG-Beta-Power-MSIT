function r1_phase2_run_k4a_recode(outDir)
%R1_PHASE2_RUN_K4A_RECODE Re-run of K4a only, with accuracy coded err = 1 - acc (decision log §11m amendment
%   R1-phase2-k4a-recode). The reported nconf_c is then the conflict effect at correct trials; nconf_c:err is the
%   error-trial difference. Same trials, covariates, ladder and estimation as the first run.
%   Check: when a model reaches the same random-effects structure as in the first run, the new nconf_c estimate,
%   SE and Satterthwaite DF must equal the first run's linear combination nconf_c + nconf_c:acc.
%   Writes r1_phase2_k4a_recode_raw.txt, _coefficients.csv and _results.mat to outDir; never overwrites.
txtF = fullfile(outDir, 'r1_phase2_k4a_recode_raw.txt');
csvF = fullfile(outDir, 'r1_phase2_k4a_recode_coefficients.csv');
matF = fullfile(outDir, 'r1_phase2_k4a_recode_results.mat');
assert(~exist(txtF, 'file') && ~exist(csvF, 'file') && ~exist(matF, 'file'), 'r1:k4a', 'outputs exist');
warning('off', 'backtrace');
io = detectImportOptions(fullfile(outDir, 'r1_phase2_trials.csv'));
io = setvartype(io, {'subject', 'cond', 'outcome'}, 'string');
T = readtable(fullfile(outDir, 'r1_phase2_trials.csv'), io);
cols = {'subject', 'cond', 'active_power', 'baseline_power', 'rt_ms', 'trial_index', 'mb_pos', 'correct'};
Da = r1_phase2_prepare(T(T.set_k4a == 1, cols));
assert(height(Da) == 4266, 'r1:k4a', 'K4a set has %d trials', height(Da));
Da.err = 1 - Da.acc;                                   % 0 = correct (reference level), 1 = error
assert(all(ismember(Da.err, [0 1])), 'r1:k4a', 'err coding');
fr = struct('dataKind', 'real');
fx = {'nconf_c', 'base_c', 'order_z', 'err', 'nconf_c:err'};
R.k4a_M0 = r1_phase2_fit(Da, 'y', fx, {'nconf_c'}, {'nconf_c'}, fr);
R.k4a_M1 = r1_phase2_fit(Da, 'y', [fx, {'rt_w', 'rt_cm'}], {'nconf_c', 'rt_w'}, {'rt_w', 'nconf_c'}, fr);

% equivalence check against the first run (acc coding): contrast nconf_c + nconf_c:acc
old = load(fullfile(outDir, 'r1_phase2_results.mat'), 'R');
L = {}; L{end + 1} = 'K4a RE-RUN RAW OUTPUT (err = 1 - acc; nconf_c = conflict effect at correct trials). No interpretation, no agreement verdict.';
L{end + 1} = sprintf('generated %s; trials %d (correct %d, error %d)', char(datetime('now')), height(Da), nnz(Da.err == 0), nnz(Da.err == 1));
chk = struct();
for m = {'k4a_M0', 'k4a_M1'}
    Fn = R.(m{1}); Fo = old.R.(m{1});
    names = string(Fo.lme.CoefficientNames);
    b = fixedEffects(Fo.lme);
    w = double(names == "nconf_c" | names == "nconf_c:acc");
    assert(nnz(w) == 2, 'r1:k4a', 'old terms not found');
    estO = w * b; seO = sqrt(w * Fo.lme.CoefficientCovariance * w');
    [~, ~, ~, dfO] = coefTest(Fo.lme, w, 0, 'DFMethod', 'satterthwaite');
    rn = Fn.coef(strcmp(string(Fn.coef.Name), 'nconf_c'), :);
    sameLevel = Fn.level == Fo.level;
    chk.(m{1}) = struct('sameLevel', sameLevel, 'levelNew', Fn.level, 'levelOld', Fo.level, ...
        'estNew', rn.Estimate, 'estOld', estO, 'seNew', rn.SE, 'seOld', seO, 'dfNew', rn.DF, 'dfOld', dfO);
    L{end + 1} = sprintf('CHECK %s: structure level new %d / first run %d; nconf_c new %+.8f vs first-run contrast %+.8f (diff %.2e); SE %.8f vs %.8f (diff %.2e); DF %.3f vs %.3f', ...
        m{1}, Fn.level, Fo.level, rn.Estimate, estO, rn.Estimate - estO, rn.SE, seO, rn.SE - seO, rn.DF, dfO);
end
coefRows = {};
for m = {'k4a_M0', 'k4a_M1'}
    F = R.(m{1});
    L{end + 1} = ''; L{end + 1} = repmat('=', 1, 100);
    L{end + 1} = sprintf('-- %s: n = %d, participants = %d, structure level %d (%s), pattern %s', m{1}, height(Da), ...
        numel(unique(Da.subject)), F.level, F.levelName, F.pattern);
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
    t = st; t.model = repmat(string(m{1}), height(t), 1); t.level = repmat(F.level, height(t), 1); t.Name = string(t.Name);
    coefRows{end + 1} = t(:, [{'model', 'level'}, setdiff(t.Properties.VariableNames, {'model', 'level'}, 'stable')]); %#ok<AGROW>
end
fid = fopen(txtF, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
writetable(vertcat(coefRows{:}), csvF);
save(matF, 'R', 'chk', '-v7.3');
fprintf('%s\n', L{:});
end
