%% ---- sensitivity analysis: near-edge threshold for IBF detection methods ----
% The "nearEdge" flag used throughout this project classifies a detected
% IBF as an artifact of the search-window boundary (rather than a genuine
% local peak) if it falls within a fixed distance of the beta band edges
% [13, 30] Hz. That distance has been fixed at 0.5 Hz in every extraction
% script so far -- this script tests how sensitive the headline "roughly
% half of subjects lack a stable beta peak" finding is to that specific
% choice, by recomputing nearEdge classification directly from the already-
% extracted IBF_Hz values (no need to rerun PSD extraction) across a range
% of thresholds for all five detection methods.
%
% Five methods (matches the five-method convergence claim in the paper):
%   1. alpha-masked 1/f log-log fit + SGF        -> beta_features_full42_alphamasked_with_qc.csv
%   2. heuristic 1/f log-log detrend + SGF        -> beta_features_full42_detrend_sgf.csv
%   3. FOOOF, fixed (no-knee) aperiodic mode      -> beta_features_full42_fixed.csv
%   4. FOOOF, knee aperiodic mode                 -> beta_features_full42_knee.csv
%   5. Savitzky-Golay filtering, raw PSD          -> beta_features_full42_sgf.csv
%
% NOTE: this recomputes only the near-edge FLAG. It does NOT change which
% subjects have IBF_Hz values in the first place (i.e. it does not re-run
% any peak detection) -- it only asks, for each threshold, how many of the
% already-detected values would additionally be discarded as edge artifacts.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
betaBand  = [13, 30];   % Hz, same search window used by every method

methodFiles = struct( ...
    'AlphaMasked',    'beta_features_full42_alphamasked_with_qc.csv', ...
    'HeuristicDetrend','beta_features_full42_detrend_sgf.csv', ...
    'FOOOF_fixed',    'beta_features_full42_fixed.csv', ...
    'FOOOF_knee',     'beta_features_full42_knee.csv', ...
    'SGF_raw',        'beta_features_full42_sgf.csv');

methodNames = fieldnames(methodFiles);

% thresholds to test, in Hz, centered on the value used in the paper (0.5)
thresholds = [0.1 0.2 0.3 0.5 0.7 1.0 1.5 2.0];

nSubjTotal = 42;

summary = table();

for m = 1:numel(methodNames)
    mName = methodNames{m};
    fName = methodFiles.(mName);
    fPath = fullfile(derivRoot, fName);
    if ~exist(fPath, 'file')
        fprintf('[SKIP] %s: file not found (%s)\n', mName, fName);
        continue
    end
    T = readtable(fPath);
    if ~ismember('IBF_Hz', T.Properties.VariableNames)
        fprintf('[SKIP] %s: no IBF_Hz column\n', mName);
        continue
    end
    ibf = T.IBF_Hz;
    validIBF = ~isnan(ibf);
    nValid = sum(validIBF);

    for th = thresholds
        isEdge = validIBF & (ibf <= betaBand(1)+th | ibf >= betaBand(2)-th);
        nEdge = sum(isEdge);
        nStable = nValid - nEdge;   % "stable" = has a detected value AND not classified as edge artifact
        nNoPeak = nSubjTotal - nValid;   % subjects with no detected value at all (method-dependent)
        nWithoutStablePeak = nSubjTotal - nStable;

        summary = [summary; table({mName}, th, nValid, nEdge, nStable, nNoPeak, nWithoutStablePeak, ...
            round(100*nWithoutStablePeak/nSubjTotal,1), ...
            'VariableNames', {'method','threshold_Hz','nDetected','nEdge','nStable', ...
            'nNoDetection','nWithoutStablePeak','pctWithoutStablePeak'})]; %#ok<AGROW>
    end
end

disp(summary)
outFile = fullfile(rerunDir, 'nearEdge_sensitivity_analysis.csv');   % [path]
writetable(summary, outFile);
fprintf('Saved -> %s\n', outFile);

%% ---- headline-number check: what does the sensitivity look like at threshold=0.5 (the paper's value)? ----
fprintf('\n==== At the paper''s threshold (0.5 Hz) ====\n');
at05 = summary(summary.threshold_Hz == 0.5, :);
disp(at05(:, {'method','nWithoutStablePeak','pctWithoutStablePeak'}));
fprintf('Range across methods at 0.5 Hz: %d-%d / 42 subjects without a stable peak (%.0f-%.0f%%)\n', ...
    min(at05.nWithoutStablePeak), max(at05.nWithoutStablePeak), ...
    min(at05.pctWithoutStablePeak), max(at05.pctWithoutStablePeak));

%% ---- plot: how the "without stable peak" count moves with threshold, per method ----
figure('Color','w','Position',[100 100 750 450]);
hold on;
colors = lines(numel(methodNames));
legendH = gobjects(numel(methodNames),1);
for m = 1:numel(methodNames)
    mName = methodNames{m};
    rows = strcmp(summary.method, mName);
    if ~any(rows), continue; end
    legendH(m) = plot(summary.threshold_Hz(rows), summary.nWithoutStablePeak(rows), ...
        '-o', 'Color', colors(m,:), 'LineWidth', 1.8, 'MarkerFaceColor', colors(m,:), 'DisplayName', mName);
end
xline(0.5, '--', 'Color', [0.3 0.3 0.3], 'Label', 'threshold used in paper', 'LabelVerticalAlignment','bottom');
yline(21, ':', 'Color', [0.5 0.5 0.5], 'Label', 'half of sample (n=21)');
xlabel('Near-edge threshold (Hz)');
ylabel('Subjects without a stable beta peak (/ 42)');
title('Sensitivity of the "no stable peak" count to the near-edge threshold');
legend(legendH(isgraphics(legendH)), 'Location', 'eastoutside');
ylim([0 42]);
set(gca, 'FontSize', 10, 'Box', 'on');
exportgraphics(gcf, fullfile(rerunDir, 'fig_nearEdge_threshold_sensitivity.png'), 'Resolution', 220);   % [path]
fprintf('Saved -> fig_nearEdge_threshold_sensitivity.png\n');
