%% ---- Figure 3 (corrected): rest vs task-baseline, beta band + control band ----
% Beta-band panels (top row): unchanged -- Wilcoxon signed-rank on raw power,
% matching Table 2 and the main-text Results paragraph.
%
% Control-band panels (bottom row): p-values now come from the SAME test used
% in the revised manuscript text (EMG Control-Band Verification / TOST
% analysis) -- a paired t-test on log10(task/rest), NOT a Wilcoxon test on
% raw values. This was previously a mismatch: the figure showed Wilcoxon-on-
% raw p-values (.1158/.2911/.2426) while the revised text reports log-ratio
% t-test p-values (.027/.114/.488). Using two different tests for the same
% comparison in the figure vs. the text is exactly the kind of inconsistency
% flagged for Figure 3 by the earlier reviewer round -- fixed here by making
% the figure match the text's test, using the same log-ratio transform as
% tost_control_band_equivalence.m.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
taskDeriv = P.taskDeriv;                                           % [path] v1 MSIT+ derivatives (read-only)

restBeta  = readtable(fullfile(derivRoot, 'beta_avgpower_per_channel.csv'));
restCtrl  = readtable(fullfile(derivRoot, 'rest_control_band_power.csv'));
task      = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

channels = {'Fz','Cz','C4'};

figure('Color','w','Position',[100 100 1300 800]);
tl = tiledlayout(2,3,'TileSpacing','compact','Padding','compact');

for c = 1:numel(channels)
    ch = channels{c};

    %% ---- BETA BAND (top row) -- unchanged, Wilcoxon on raw values ----
    rRows = strcmp(restBeta.channel, ch);
    restT = restBeta(rRows, {'subject','avgBetaPower_raw'});
    tRows = strcmp(task.channel, ch);
    taskSub = task(tRows, {'subject','baselinePower'});
    taskAvg = varfun(@mean, taskSub, 'GroupingVariables', 'subject');
    merged = innerjoin(restT, taskAvg, 'Keys', 'subject');
    restVals = merged.avgBetaPower_raw;
    taskVals = merged.mean_baselinePower;

    nexttile; hold on;
    for s = 1:numel(restVals)
        plot([1 2], [restVals(s) taskVals(s)], '-', 'Color', [0.7 0.7 0.7 0.5], 'LineWidth', 0.8);
    end
    scatter(ones(size(restVals)), restVals, 40, [0.2 0.4 0.8], 'filled', 'MarkerFaceAlpha',0.7);
    scatter(2*ones(size(taskVals)), taskVals, 40, [0.8 0.3 0.2], 'filled', 'MarkerFaceAlpha',0.7);
    errorbar(1, mean(restVals), std(restVals)/sqrt(numel(restVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);
    errorbar(2, mean(taskVals), std(taskVals)/sqrt(numel(taskVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);

    pBeta = signrank(restVals, taskVals, 'method', 'exact');   % Wilcoxon signed-rank -- matches Table 2
    pctChangeBeta = (mean(taskVals)-mean(restVals))/mean(restVals)*100;

    xlim([0.5 2.5]); xticks([1 2]); xticklabels({'Rest','Task baseline'});
    ylabel('Raw beta power (13-30 Hz)');
    title(sprintf('%s  (%+.0f%%, p=%.2g)', ch, pctChangeBeta, pBeta), 'FontWeight','normal');
    set(gca,'FontSize',10, 'Box','on');

    %% ---- CONTROL BAND (bottom row) -- log-ratio paired t-test, matches TOST script ----
    rcRows = strcmp(restCtrl.channel, ch);
    restCtrlT = restCtrl(rcRows, {'subject','restControlPower'});
    tcRows = strcmp(task.channel, ch);
    taskCtrlSub = task(tcRows, {'subject','baselineControlPower'});
    taskCtrlAvg = varfun(@mean, taskCtrlSub, 'GroupingVariables', 'subject');
    mergedCtrl = innerjoin(restCtrlT, taskCtrlAvg, 'Keys', 'subject');
    restCtrlVals = mergedCtrl.restControlPower;
    taskCtrlVals = mergedCtrl.mean_baselineControlPower;

    valid = restCtrlVals > 0 & taskCtrlVals > 0 & ~isnan(restCtrlVals) & ~isnan(taskCtrlVals);
    restCtrlVals = restCtrlVals(valid);
    taskCtrlVals = taskCtrlVals(valid);

    nexttile; hold on;
    for s = 1:numel(restCtrlVals)
        plot([1 2], [restCtrlVals(s) taskCtrlVals(s)], '-', 'Color', [0.7 0.7 0.7 0.5], 'LineWidth', 0.8);
    end
    scatter(ones(size(restCtrlVals)), restCtrlVals, 40, [0.2 0.4 0.8], 'filled', 'MarkerFaceAlpha',0.7);
    scatter(2*ones(size(taskCtrlVals)), taskCtrlVals, 40, [0.8 0.3 0.2], 'filled', 'MarkerFaceAlpha',0.7);
    errorbar(1, mean(restCtrlVals), std(restCtrlVals)/sqrt(numel(restCtrlVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);
    errorbar(2, mean(taskCtrlVals), std(taskCtrlVals)/sqrt(numel(taskCtrlVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);

    logRatio = log10(taskCtrlVals) - log10(restCtrlVals);
    [~, pCtrl] = ttest(logRatio);   % paired t-test on log-ratio -- SAME test as manuscript text
    pctChangeCtrl = (10^mean(logRatio) - 1) * 100;   % back-transformed mean %% change

    xlim([0.5 2.5]); xticks([1 2]); xticklabels({'Rest','Task baseline'});
    ylabel('Control-band power (55-95 Hz)');
    title(sprintf('%s  (%+.0f%%, p=%.3g)', ch, pctChangeCtrl, pCtrl), 'FontWeight','normal');
    set(gca,'FontSize',10, 'Box','on');

    fprintf('%s: beta %+.1f%% (Wilcoxon p=%.3g)  |  control %+.1f%% (log-ratio t-test p=%.3g)\n', ...
        ch, pctChangeBeta, pBeta, pctChangeCtrl, pCtrl);
end

title(tl, 'Beta-band vs. control-band power: resting-state vs. task pre-stimulus baseline (n=42)', 'FontSize',13);
outFile = fullfile(rerunDir, 'fig3_rest_vs_task_beta_and_control_CORRECTED.png');   % [path]
exportgraphics(gcf, outFile, 'Resolution', 220);
fprintf('\nSaved -> %s\n', outFile);
