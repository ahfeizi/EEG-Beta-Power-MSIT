function F = r1_phase2_fit(D, response, fixedTerms, slopes, dropOrder, opts)
%R1_PHASE2_FIT Fit one Phase 2 mixed model with the decided random-effects rule (decision log §11k, K1.6(a)).
%   F = r1_phase2_fit(D, response, fixedTerms, slopes, dropOrder, opts)
%   D           table from r1_phase2_prepare
%   response    'y' (log10 active band power) or 'lrt' (log RT, the K3 a-model)
%   fixedTerms  cellstr of fixed-effect terms besides the intercept, e.g. {'nconf_c','base_c','order_z'}
%   slopes      cellstr of by-participant random slopes in the maximal structure, e.g. {'nconf_c','rt_w'}
%   dropOrder   the same slopes in the order they are removed (§11k: rt_w before nconf_c; the slope of the
%               effect of interest is removed last)
%   opts        struct: dataKind ('synthetic' | 'real', required); forceFail (vector of structure levels to treat
%               as failed: TEST HOOK, refused unless dataKind is 'synthetic'); maxIterFactor (default 10);
%               fixedStructure (optional struct with fields slopes, pattern: fit only that structure, no
%               simplification - used inside the bootstrap)
%
%   Structure levels, tried in order until one fits (K1.6(a) as decided):
%     0  intercept + all slopes, full covariance          (if it fails: refit once with the iteration limit
%                                                          raised, Barr et al.'s first step, before simplifying)
%     1  intercept + all slopes, diagonal (correlations removed)
%     2.. drop the slopes in dropOrder, diagonal
%     last  intercept only  -> reported with an explicit anticonservativity warning
%   A fit fails on: a fitting error, any warning issued while fitting (CheckHessian on), or singularity
%   (any random-effect SD < 1e-4 x residual SD, or any |correlation| > 0.99).
%   Estimation: REML set explicitly (fitlme's default is ML); fixed-effect tests and 95 % CIs with
%   Satterthwaite degrees of freedom.
if ~isfield(opts, 'dataKind') || ~ismember(opts.dataKind, {'synthetic', 'real'})
    error('r1:fit', 'opts.dataKind must be ''synthetic'' or ''real''');
end
if ~isfield(opts, 'forceFail'), opts.forceFail = []; end
if ~isempty(opts.forceFail) && ~strcmp(opts.dataKind, 'synthetic')
    error('r1:fit', 'forceFail is a test hook and is refused on real data');
end
if ~isfield(opts, 'maxIterFactor'), opts.maxIterFactor = 10; end
assert(isempty(setxor(slopes, dropOrder)), 'r1:fit', 'dropOrder must list exactly the slopes');

% the ladder of structures
levels = struct('slopes', {}, 'pattern', {}, 'name', {});
if isfield(opts, 'fixedStructure') && ~isempty(opts.fixedStructure)
    levels(1) = struct('slopes', {opts.fixedStructure.slopes}, 'pattern', opts.fixedStructure.pattern, ...
        'name', 'fixed (bootstrap)');
else
    levels(end + 1) = struct('slopes', {slopes}, 'pattern', 'FullCholesky', 'name', 'maximal, full covariance');
    if ~isempty(slopes)
        levels(end + 1) = struct('slopes', {slopes}, 'pattern', 'Diagonal', 'name', 'maximal, no correlations');
        kept = slopes;
        for k = 1:numel(dropOrder)
            kept = setdiff(kept, dropOrder(k), 'stable');
            if isempty(kept)
                levels(end + 1) = struct('slopes', {{}}, 'pattern', 'Diagonal', 'name', 'intercept only'); %#ok<AGROW>
            else
                levels(end + 1) = struct('slopes', {kept}, 'pattern', 'Diagonal', ...
                    'name', ['without slope ' strjoin(setdiff(slopes, kept, 'stable'), ', ')]); %#ok<AGROW>
            end
        end
    end
end

oo = statset('fitlme');                      % the documented OptimizerOptions source for 'quasinewton'
assert(~isempty(oo.MaxIter) && isfinite(oo.MaxIter), 'r1:fit', 'statset(''fitlme'') has no finite MaxIter');
attempts = cell(0, 5);                         % level, name, maxIter raised, ok, reason
F = struct('ok', false, 'level', NaN, 'levelName', '', 'interceptOnlyWarning', '', 'lme', [], ...
    'coef', table(), 'randomSD', [], 'residualSD', NaN, 'formula', '', 'pattern', '', 'slopes', {{}});
for L = 1:numel(levels)
    raiseList = false;
    if L == 1 && ~(isfield(opts, 'fixedStructure') && ~isempty(opts.fixedStructure)), raiseList = [false true]; end
    for raise = raiseList
        o = oo;
        if raise, o.MaxIter = oo.MaxIter * opts.maxIterFactor; end
        [lme, ok, reason, frm] = tryFit(D, response, fixedTerms, levels(L), o, ismember(L - 1, opts.forceFail));
        attempts(end + 1, :) = {L - 1, levels(L).name, raise, ok, reason}; %#ok<AGROW>
        if ok, break, end
    end
    if ok
        F.ok = true; F.level = L - 1; F.levelName = levels(L).name; F.lme = lme; F.formula = frm;
        F.pattern = levels(L).pattern; F.slopes = levels(L).slopes;
        if isempty(levels(L).slopes) && numel(levels) > 1
            F.interceptOnlyWarning = ['WARNING: only the intercept-only random-effects structure could be fitted. ' ...
                'Barr et al. (2013) found intercept-only models anticonservative for effects that vary across ' ...
                'participants; the conflict estimate below does not meet the maximal-structure standard of ' ...
                'decision log §11k K1.6(a).'];
            warning('r1:interceptOnly', '%s', F.interceptOnlyWarning);
        end
        break
    end
end
F.attempts = cell2table(attempts, 'VariableNames', {'level', 'structure', 'maxIterRaised', 'ok', 'reason'});
if ~F.ok
    error('r1:fit', 'no random-effects structure could be fitted, intercept only included (%s); last reason: %s', ...
        response, attempts{end, 5});
end
assert(strcmp(F.lme.FitMethod, 'REML'), 'r1:fit', 'fit method is %s, REML required', F.lme.FitMethod);
[~, ~, st] = fixedEffects(F.lme, 'DFMethod', 'satterthwaite', 'Alpha', 0.05);
if isa(st, 'dataset'), st = dataset2table(st); end
F.coef = st;
[psi, mse] = covarianceParameters(F.lme);
F.randomSD = sqrt(diag(psi{1}))';
F.residualSD = sqrt(mse);
end


function [lme, ok, reason, frm] = tryFit(D, response, fixedTerms, lev, o, forced)
fx = strjoin([{'1'}, fixedTerms], ' + ');
re = strjoin([{'1'}, lev.slopes], ' + ');
frm = sprintf('%s ~ %s + (%s | subject)', response, fx, re);
lme = []; ok = false;
if forced
    reason = 'forced failure (synthetic test hook)';
    return
end
lastwarn('', '');
try
    lme = fitlme(D, frm, 'FitMethod', 'REML', 'CheckHessian', true, 'CovariancePattern', {lev.pattern}, ...
        'Optimizer', 'quasinewton', 'OptimizerOptions', o);
catch ME
    reason = ['error: ' ME.message];
    return
end
[wmsg, wid] = lastwarn;
if ~isempty(wmsg)
    reason = sprintf('warning %s: %s', wid, wmsg);
    return
end
[psi, mse] = covarianceParameters(lme);
P = psi{1};
sds = sqrt(max(diag(P), 0));
if any(sds < 1e-4 * sqrt(mse))
    reason = sprintf('singular: random-effect SD %s below 1e-4 x residual SD', mat2str(sds', 3));
    return
end
if size(P, 1) > 1
    C = P ./ (sds * sds');
    C(logical(eye(size(C)))) = 0;
    if any(abs(C(:)) > 0.99)
        reason = sprintf('singular: |correlation| %.4f > 0.99', max(abs(C(:))));
        return
    end
end
ok = true; reason = '';
end
