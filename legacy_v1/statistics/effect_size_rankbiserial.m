%% ---- effect size (matched-pairs rank-biserial correlation) for rest vs task-baseline beta power ----
% Extends paired_figure_rest_task_beta_power.m, which reports only p-values
% (Wilcoxon signed-rank) and percent change for the rest-vs-task-baseline
% beta power comparison at Fz, Cz, C4. This adds a standardized effect size
% appropriate to that same nonparametric test.
%
% Matched-pairs rank-biserial correlation (Kerby, 2014):
%   r_rb = (W+ - W-) / (W+ + W-)
% where W+ and W- are the sums of the Wilcoxon signed ranks for positive
% and negative differences respectively. This is computed directly from
% ranks (no normal approximation needed) and is on a -1 to +1 scale, with
% sign indicating direction (positive = task > rest) and magnitude
% interpretable like a correlation coefficient. It is the standard paired
% effect-size companion to the Wilcoxon signed-rank test used throughout
% this project, and needs no additional assumptions beyond those the test
% itself already makes.
%
% For cross-checking, the script also reports the normal-approximation Z
% and the Z-based effect size r = Z/sqrt(N) (a common alternative
% convention). The two will be close but not identical; report r_rb as the
% primary value since it does not depend on the large-sample approximation.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
taskDeriv = P.taskDeriv;                                           % [path] v1 MSIT+ derivatives (read-only)

rest = readtable(fullfile(derivRoot, 'beta_avgpower_per_channel.csv'));
task = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

channels = {'Fz','Cz','C4'};

results = table();

for c = 1:numel(channels)
    ch = channels{c};

    rRows = strcmp(rest.channel, ch);
    restT = rest(rRows, {'subject','avgBetaPower_raw'});

    tRows = strcmp(task.channel, ch);
    taskSub = task(tRows, {'subject','baselinePower'});
    taskAvg = varfun(@mean, taskSub, 'GroupingVariables', 'subject');

    merged = innerjoin(restT, taskAvg, 'Keys', 'subject');
    restVals = merged.avgBetaPower_raw;
    taskVals = merged.mean_baselinePower;

    diffs = taskVals - restVals;
    nonzero = diffs ~= 0;          % Wilcoxon signed-rank drops exact-zero differences
    d = diffs(nonzero);
    N = numel(d);

    ranks = tiedrank(abs(d));
    Wpos = sum(ranks(d > 0));
    Wneg = sum(ranks(d < 0));
    r_rb = (Wpos - Wneg) / (Wpos + Wneg);

    % Wilcoxon signed-rank test, requesting stats for the normal-approx Z
    p = signrank(taskVals, restVals, 'method', 'exact');
    [~, ~, stats] = signrank(taskVals, restVals, 'method', 'approximate');
    if isfield(stats, 'zval')
        Z = stats.zval;
        r_z = Z / sqrt(N);
    else
        Z = NaN; r_z = NaN;   % falls back if MATLAB used exact method instead
    end

    pctChange = (mean(taskVals) - mean(restVals)) / mean(restVals) * 100;

    fprintf('--- %s (N=%d, %d ties dropped) ---\n', ch, N, sum(~nonzero));
    fprintf('  W+ = %.1f, W- = %.1f\n', Wpos, Wneg);
    fprintf('  r_rb (rank-biserial) = %+.3f\n', r_rb);
    fprintf('  Z = %.3f, r (Z/sqrt(N)) = %+.3f\n', Z, r_z);
    fprintf('  Wilcoxon p = %.3g, mean change = %+.1f%%\n\n', p, pctChange);

    results = [results; table({ch}, N, Wpos, Wneg, r_rb, Z, r_z, p, pctChange, ...
        'VariableNames', {'channel','N','Wplus','Wminus','r_rankBiserial','Z','r_ZapproxN','p_wilcoxon','pctChange'})]; %#ok<AGROW>
end

disp(results)
outFile = fullfile(rerunDir, 'beta_power_effect_sizes_rankbiserial.csv');   % [path]
writetable(results, outFile);
fprintf('Saved -> %s\n', outFile);

%% ---- merge effect sizes into a Table-2-ready summary (percent change + p + r_rb) ----
tableForPaper = results(:, {'channel','N','pctChange','p_wilcoxon','r_rankBiserial'});
tableForPaper.Properties.VariableNames = {'Channel','n','PctChange','p_Wilcoxon','r_rb'};
outFile2 = fullfile(rerunDir, 'Table2_with_effect_sizes.csv');   % [path]
writetable(tableForPaper, outFile2);
fprintf('Saved (paper-ready) -> %s\n', outFile2);
