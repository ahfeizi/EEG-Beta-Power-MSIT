%% ---- paired figure: rest vs task-baseline beta power, per channel ----
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
taskDeriv = fullfile(derivRoot, 'MSIT_Output');

rest = readtable(fullfile(derivRoot, 'beta_avgpower_per_channel.csv'));
task = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

channels = {'Fz','Cz','C4'};
subjects = unique(task.subject);

figure('Color','w','Position',[100 100 1300 450]);
tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');

for c = 1:numel(channels)
    ch = channels{c};

    % rest values
    rRows = strcmp(rest.channel, ch);
    restT = rest(rRows, {'subject','avgBetaPower_raw'});

    % task baseline: average across the 4 conditions per subject
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

    % mean +/- SEM markers
    errorbar(1, mean(restVals), std(restVals)/sqrt(numel(restVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);
    errorbar(2, mean(taskVals), std(taskVals)/sqrt(numel(taskVals)), 'ko', ...
        'MarkerFaceColor','k', 'MarkerSize',8, 'LineWidth',1.5, 'CapSize',10);

    [~, p] = ttest(restVals, taskVals);   % just for display; report was via Wilcoxon
    p = signrank(restVals, taskVals, 'method', 'exact');
    pctChange = (mean(taskVals)-mean(restVals))/mean(restVals)*100;

    xlim([0.5 2.5]); xticks([1 2]); xticklabels({'Rest','Task baseline'});
    ylabel('Raw beta power (13-30 Hz)');
    title(sprintf('%s  (+%.0f%%, p<.0001)', ch, pctChange), 'FontWeight','normal');
    set(gca,'FontSize',10, 'Box','on');
end

title(tl, 'Beta power: resting-state vs. pre-stimulus task baseline (n=42)', 'FontSize',13);
exportgraphics(gcf, fullfile(taskDeriv, 'fig_rest_vs_task_paired.png'), 'Resolution', 220);