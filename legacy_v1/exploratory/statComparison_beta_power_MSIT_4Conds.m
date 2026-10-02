%% ---- statistical comparison of beta power across the 4 MSIT+ conditions ----
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
taskDeriv = fullfile(derivRoot, 'MSIT_Output');
T = readtable(fullfile(taskDeriv, 'msit_beta_power_by_condition.csv'));

channels   = {'Fz','Cz','C4'};
conditions = {'F0','FS','00','S0'};
subjects   = unique(T.subject, 'stable');

results = table();

for c = 1:numel(channels)
    ch = channels{c};

    % build subject x condition matrix
    M = nan(numel(subjects), numel(conditions));
    for s = 1:numel(subjects)
        for k = 1:numel(conditions)
            row = strcmp(T.subject, subjects{s}) & strcmp(T.channel, ch) & strcmp(T.condition, conditions{k});
            if any(row)
                M(s,k) = T.betaPower_raw(row);
            end
        end
    end
    M = M(all(~isnan(M),2), :);   % keep only complete rows

    % Friedman test (nonparametric repeated-measures, >2 conditions)
    [p, tbl] = friedman(M, 1, 'off');
    chi2 = tbl{2,5};

    fprintf('\n=== %s ===\n', ch);
    fprintf('Friedman test: chi2=%.2f, p=%.4f (n=%d subjects)\n', chi2, p, size(M,1));
    fprintf('Means: F0=%.3f  FS=%.3f  00=%.3f  S0=%.3f\n', mean(M));

    % post-hoc pairwise Wilcoxon signed-rank (all 6 pairs), FDR-corrected
    pairs = nchoosek(1:4, 2);
    pPost = nan(size(pairs,1),1);
    for pr = 1:size(pairs,1)
        pPost(pr) = signrank(M(:,pairs(pr,1)), M(:,pairs(pr,2)), 'method', 'exact');
    end
    [~, sortIdx] = sort(pPost);
    m = numel(pPost);
    fdrThresh = (1:m)'/m*0.05;
    sortedP = pPost(sortIdx);
    below = sortedP <= fdrThresh;
    if any(below)
        pCrit = sortedP(find(below,1,'last'));
    else
        pCrit = 0;
    end
    sig = pPost <= pCrit;

    for pr = 1:size(pairs,1)
        fprintf('  %s vs %s: p=%.4f %s\n', conditions{pairs(pr,1)}, conditions{pairs(pr,2)}, ...
            pPost(pr), ternary(sig(pr), '*** FDR-significant', ''));
    end

    results = [results; table({ch}, chi2, p, ...
        'VariableNames', {'channel','friedman_chi2','friedman_p'})]; %#ok<AGROW>
end

writetable(results, fullfile(taskDeriv, 'msit_beta_condition_comparison_summary.csv'));

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end