%% ---- conflict specificity of PRE-STIMULUS beta power across MSIT+ conditions ----
% Addresses reviewer concern: the headline pre-stimulus beta increase was
% computed by averaging across all four MSIT+ trial types, which does not
% by itself establish whether the effect is specific to conflict
% anticipation (Engel & Fries status-quo hypothesis) or reflects general
% task engagement/arousal that would appear regardless of upcoming trial
% demands.
%
% This tests whether PRE-STIMULUS (baseline, -0.2 to 0 s, i.e. BEFORE the
% subject could know the upcoming trial's condition) beta power differs
% systematically by the condition of the trial that is about to occur,
% using the same four conditions and established conflict ordering from
% Dzianok et al. (2022) / Wojciechowski et al. (2024):
%     00 (no conflict) < S0 (Simon) < F0 (Flanker) < FS (double conflict)
% This ordering is well-established for POST-stimulus ERP/behavioral
% measures (N450 amplitude, RT, accuracy); here it is applied to the
% PRE-stimulus window as an a priori trend contrast.
%
% Interpretation:
%   - If pre-stimulus beta power does NOT vary with upcoming condition,
%     this is consistent with general task-engagement/arousal rather than
%     conflict-specific anticipatory control, and should be reported as
%     such (strengthens the "general engagement" account, does not
%     support or refute conflict-specific preparation).
%   - If it DOES vary and tracks the conflict ordering, this would suggest
%     either (a) some predictability/blocking in trial presentation that
%     allows genuine anticipation, or (b) a sequential/conflict-adaptation
%     effect carried over from the preceding trial (Gratton-type effect)
%     rather than true prospective conflict anticipation -- trial order
%     would need to be checked to distinguish these before over-interpreting.
%
% Uses the SAME pre-stimulus (baselinePower) values already extracted per
% condition in msit_beta_erd_by_condition.m -- no new EEG processing needed.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
taskDeriv = P.taskDeriv;                                           % [path] v1 MSIT+ derivatives (read-only)
T = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

channels   = {'Fz','Cz','C4'};
% conflict-ordered (established from Dzianok 2022 / Wojciechowski 2024: N450, RT, accuracy)
conditions = {'00','S0','F0','FS'};
conflictRank = [1 2 3 4];   % for the trend contrast below
subjects   = unique(T.subject, 'stable');

results = table();
trendResults = table();

for c = 1:numel(channels)
    ch = channels{c};

    % build subject x condition matrix of PRE-STIMULUS (baseline) power
    M = nan(numel(subjects), numel(conditions));
    for s = 1:numel(subjects)
        for k = 1:numel(conditions)
            row = strcmp(T.subject, subjects{s}) & strcmp(T.channel, ch) & strcmp(T.condition, conditions{k});
            if any(row)
                M(s,k) = T.baselinePower(row);
            end
        end
    end
    M = M(all(~isnan(M),2), :);   % complete cases only
    n = size(M,1);

    % ---- omnibus test: does pre-stimulus power differ across the 4 upcoming conditions? ----
    [pFriedman, tbl] = friedman(M, 1, 'off');
    chi2 = tbl{2,5};

    fprintf('\n=== %s: pre-stimulus power by UPCOMING condition (n=%d) ===\n', ch, n);
    fprintf('Friedman test: chi2=%.2f, p=%.4f\n', chi2, pFriedman);
    fprintf('Means: 00=%.4f  S0=%.4f  F0=%.4f  FS=%.4f\n', mean(M));

    % ---- planned contrast: highest-conflict (FS) vs no-conflict (00) ----
    % this is the single most direct test of conflict-specificity
    pFSvs00 = signrank(M(:,4), M(:,1));   % FS vs 00
    pctDiffFSvs00 = (mean(M(:,4)) - mean(M(:,1))) / mean(M(:,1)) * 100;

    % ---- planned trend test: does pre-stimulus power track the conflict ORDERING? ----
    % Page's L trend test (nonparametric test for ordered alternatives) is the
    % appropriate complement to Friedman when there is an a priori order
    % hypothesis (00 < S0 < F0 < FS), rather than treating conditions as
    % unordered categories. Implemented directly since MATLAB has no
    % built-in pagetest.
    [pPage, L, pageDirection] = pages_trend_test(M, conflictRank);

    fprintf('Planned contrast FS vs 00: p=%.4f (%.1f%% difference)\n', pFSvs00, pctDiffFSvs00);
    fprintf('Page trend test (00<S0<F0<FS ordering): L=%.1f, p=%.4f, direction=%s\n', ...
        L, pPage, pageDirection);

    results = [results; table({ch}, n, chi2, pFriedman, pFSvs00, pctDiffFSvs00, L, pPage, {pageDirection}, ...
        'VariableNames', {'channel','n','friedman_chi2','friedman_p','p_FSvs00','pctDiff_FSvs00', ...
        'pageL','page_p','pageDirection'})]; %#ok<AGROW>
end

disp(results)
outFile = fullfile(rerunDir, 'prestim_beta_conflict_specificity.csv');   % [path]
writetable(results, outFile);
fprintf('\nSaved -> %s\n', outFile);

fprintf('\n==== SUMMARY: is the pre-stimulus beta increase conflict-specific? ====\n');
if all(results.friedman_p > 0.05) && all(results.page_p > 0.05)
    fprintf(['No channel shows pre-stimulus power varying by upcoming trial condition.\n' ...
        'This is consistent with GENERAL task engagement/arousal rather than conflict-\n' ...
        'specific anticipatory control -- the effect does not appear to require the\n' ...
        'subject to be anticipating a *specific* conflict level.\n']);
else
    fprintf(['At least one channel shows condition-dependent pre-stimulus power.\n' ...
        'Check trial order for blocking/predictability or sequential (previous-trial)\n' ...
        'effects before concluding this reflects prospective conflict anticipation.\n']);
end

%% ---- figure: pre-stimulus beta power by upcoming condition, per channel ----
figure('Color','w','Position',[100 100 1200 400]);
tl = tiledlayout(1,numel(channels),'TileSpacing','compact','Padding','compact');
for c = 1:numel(channels)
    ch = channels{c};
    M = nan(numel(subjects), numel(conditions));
    for s = 1:numel(subjects)
        for k = 1:numel(conditions)
            row = strcmp(T.subject, subjects{s}) & strcmp(T.channel, ch) & strcmp(T.condition, conditions{k});
            if any(row), M(s,k) = T.baselinePower(row); end
        end
    end
    M = M(all(~isnan(M),2), :);

    nexttile; hold on;
    for s = 1:size(M,1)
        plot(1:4, M(s,:), '-', 'Color', [0.7 0.7 0.7 0.3], 'LineWidth', 0.6);
    end
    means = mean(M); sems = std(M)/sqrt(size(M,1));
    errorbar(1:4, means, sems, '-o', 'Color', [0.2 0.3 0.7], 'LineWidth', 2, ...
        'MarkerFaceColor', [0.2 0.3 0.7], 'MarkerSize', 8, 'CapSize', 10);
    xlim([0.5 4.5]); xticks(1:4); xticklabels(conditions);
    xlabel('Upcoming trial condition (conflict order: 00 < S0 < F0 < FS)');
    ylabel('Pre-stimulus beta power');
    title(ch, 'FontWeight', 'normal');
    set(gca, 'FontSize', 10, 'Box', 'on');
end
title(tl, 'Pre-stimulus beta power vs. upcoming trial conflict level (n=42)', 'FontSize', 13);
exportgraphics(gcf, fullfile(rerunDir, 'fig_prestim_conflict_specificity.png'), 'Resolution', 220);   % [path]
fprintf('Saved -> fig_prestim_conflict_specificity.png\n');


% ============================================================================
function [p, L, direction] = pages_trend_test(M, rank)
    % Page's L trend test for ordered alternatives in a repeated-measures
    % design (nonparametric complement to Friedman for a priori ordering).
    % M: n subjects x k conditions, columns already in the hypothesized order.
    % rank: 1 x k vector of the a priori rank order (e.g. [1 2 3 4]).
    [n, k] = size(M);
    R = nan(n, k);
    for i = 1:n
        R(i,:) = tiedrank(M(i,:));   % rank within each subject (row)
    end
    L = sum(rank .* sum(R,1));   % Page's L statistic

    % normal approximation (adequate for n=42, k=4; exact tables only go to small n)
    muL = n*k*(k+1)^2/4;
    varL = n*k^2*(k+1)*(k^2-1)/144;
    z = (L - muL) / sqrt(varL);
    p = 1 - normcdf(z);   % one-sided: testing for the specific increasing order

    if p < 0.05
        direction = 'increasing (00<S0<F0<FS supported)';
    else
        direction = 'no significant trend';
    end
end
