%% ---- TOST equivalence test: control-band (55-95 Hz) power, rest vs task baseline ----
% Tests whether the rest-vs-task-baseline difference in the HIGH-FREQUENCY
% CONTROL BAND is small enough to be considered practically equivalent to
% zero, rather than relying on a non-significant paired test (absence of
% evidence != evidence of absence). Mirrors the logic of
% paired_figure_rest_task_beta_power.m but for the control band, and adds
% a genuine equivalence test (TOST, two one-sided tests) instead of the
% paired t-test / Wilcoxon used there for the beta band itself.
%
% *** METHODOLOGICAL DECISION REQUIRING SUPERVISOR APPROVAL ***
% The equivalence bound (SESOI = smallest effect size of interest) below is
% a PLACEHOLDER. TOST results are only as meaningful as the bound choice --
% unlike a normal significance test, changing this number changes the
% conclusion directly. Two defaults are provided (a raw log-ratio bound and
% a Cohen's dz bound); do not treat either as final without discussing with
% your supervisor which corresponds to a scientifically meaningful EMG
% contamination magnitude for this dataset.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
taskDeriv = P.taskDeriv;                                           % [path] v1 MSIT+ derivatives (read-only)

rest = readtable(fullfile(derivRoot, 'rest_control_band_power.csv'));
task = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

channels = {'Fz','Cz','C4'};

% ---- EQUIVALENCE BOUND (SESOI) -- PLACEHOLDER, CONFIRM WITH SUPERVISOR ----
% Expressed as a bound on log10(task/rest), i.e. symmetric fold-change.
% logBound = log10(1.10) means +/-10% change is considered "equivalent to
% no change." This mirrors a conventional TOST default (Lakens, 2017) but
% the 10% figure itself is a judgment call, not a statistical constant --
% pick a value that corresponds to an EMG-contamination magnitude that
% would actually matter for the beta-power interpretation.
logBound = log10(1.10);
alphaTOST = 0.05;   % per one-sided test (standard for TOST)

fprintf('==== TOST equivalence bound: log10(ratio) = +/- %.4f  (=> +/- %.1f%% fold change) ====\n', ...
    logBound, 100*(10^logBound - 1));
fprintf('[[ CONFIRM THIS BOUND WITH YOUR SUPERVISOR BEFORE REPORTING RESULTS ]]\n\n');

results = table();

for c = 1:numel(channels)
    ch = channels{c};

    % rest values
    rRows = strcmp(rest.channel, ch);
    restT = rest(rRows, {'subject','restControlPower'});

    % task baseline control-band power: average across the 4 conditions per subject
    tRows = strcmp(task.channel, ch);
    taskSub = task(tRows, {'subject','baselineControlPower'});
    taskAvg = varfun(@mean, taskSub, 'GroupingVariables', 'subject');

    merged = innerjoin(restT, taskAvg, 'Keys', 'subject');
    restVals = merged.restControlPower;
    taskVals = merged.mean_baselineControlPower;

    % work in log space: control-band power is strictly positive and right-
    % skewed (same rationale as the log-log 1/f fitting used elsewhere in
    % this project), and log-ratio gives a symmetric, scale-free effect
    % measure appropriate for a fold-change equivalence bound.
    valid = restVals > 0 & taskVals > 0 & ~isnan(restVals) & ~isnan(taskVals);
    restVals = restVals(valid);
    taskVals = taskVals(valid);
    n = numel(restVals);

    logRatio = log10(taskVals) - log10(restVals);   % paired log-ratio per subject
    dbar = mean(logRatio);
    sdiff = std(logRatio);
    se = sdiff / sqrt(n);
    df = n - 1;

    % ---- two one-sided tests (TOST) ----
    % H0_1: true mean difference <= -logBound   (task meaningfully LOWER)
    % H0_2: true mean difference >=  logBound   (task meaningfully HIGHER)
    % Reject BOTH one-sided nulls => conclude equivalence.
    t1 = (dbar - (-logBound)) / se;   % tests against lower bound
    p1 = 1 - tcdf(t1, df);            % one-sided: dbar significantly > -bound

    t2 = (dbar - logBound) / se;      % tests against upper bound
    p2 = tcdf(t2, df);                % one-sided: dbar significantly < +bound

    pTOST = max(p1, p2);              % TOST p-value = the larger (weaker) of the two
    equivalent = pTOST < alphaTOST;

    % standard two-sided test for comparison (what the paper currently reports)
    [~, p_twosided] = ttest(logRatio);

    % 90% CI on the mean log-ratio (matches alpha=.05 one-sided bounds -- the
    % conventional way to visualize a TOST result: CI entirely inside the
    % shaded equivalence region = equivalent)
    tcrit90 = tinv(1 - 0.05, df);
    ci90 = [dbar - tcrit90*se, dbar + tcrit90*se];

    pctChange = (10^dbar - 1) * 100;   % back-transformed mean %% change

    fprintf('--- %s (n=%d) ---\n', ch, n);
    fprintf('  mean log-ratio = %.4f  (%.1f%% change), 90%% CI [%.1f%%, %.1f%%]\n', ...
        dbar, pctChange, (10^ci90(1)-1)*100, (10^ci90(2)-1)*100);
    fprintf('  two-sided paired t-test vs 0:  p = %.4f  (this is what "non-significant" alone tells you)\n', p_twosided);
    fprintf('  TOST vs +/-%.1f%% bound:         p = %.4f  -> %s\n\n', ...
        100*(10^logBound-1), pTOST, ternary(equivalent, 'EQUIVALENT (bound supported)', 'NOT equivalent (cannot rule out a meaningful change)'));

    results = [results; table({ch}, n, dbar, pctChange, ci90(1), ci90(2), p_twosided, pTOST, equivalent, ...
        'VariableNames', {'channel','n','meanLogRatio','pctChange','ci90_lo_pct','ci90_hi_pct', ...
        'p_twoSided','p_TOST','equivalent'})]; %#ok<AGROW>
end

% fix ci columns to percent scale for readability
results.ci90_lo_pct = (10.^results.ci90_lo_pct - 1) * 100;
results.ci90_hi_pct = (10.^results.ci90_hi_pct - 1) * 100;

disp(results)
outFile = fullfile(rerunDir, 'control_band_TOST_equivalence.csv');   % [path]
writetable(results, outFile);
fprintf('Saved -> %s\n', outFile);

%% ---- equivalence plot: mean log-ratio +/- 90% CI vs shaded bound region ----
figure('Color','w','Position',[100 100 650 400]);
hold on;
patch([0.4 numel(channels)+0.6 numel(channels)+0.6 0.4], ...
      [-logBound -logBound logBound logBound], ...
      [0.85 0.93 0.85], 'EdgeColor','none');   % shaded equivalence region
yline(0, '--', 'Color',[0.5 0.5 0.5]);

for c = 1:numel(channels)
    errorbar(c, results.meanLogRatio(c), ...
        results.meanLogRatio(c) - log10(1+results.ci90_lo_pct(c)/100), ...
        log10(1+results.ci90_hi_pct(c)/100) - results.meanLogRatio(c), ...
        'ko', 'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',12);
end

xlim([0.4 numel(channels)+0.6]);
xticks(1:numel(channels)); xticklabels(channels);
ylabel('log_{10}(task / rest) control-band power');
title(sprintf('Control-band equivalence (%d-95 Hz): 90%% CI vs +/-%.0f%% bound', 55, 100*(10^logBound-1)));
set(gca,'FontSize',10,'Box','on');
exportgraphics(gcf, fullfile(rerunDir, 'fig_control_band_TOST.png'), 'Resolution', 220);   % [path]
fprintf('Saved -> fig_control_band_TOST.png\n');

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
