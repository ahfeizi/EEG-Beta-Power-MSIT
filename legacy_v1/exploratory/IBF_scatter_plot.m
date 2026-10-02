%% ---- reproduce the IBF scatter plot (edge vs interior) in MATLAB ----
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
T = readtable(fullfile(derivRoot, 'beta_features_full42_alphamasked_with_qc.csv'));

betaBand = [13, 30];

n = height(T);
subjectNum = (1:n)';

isEdge = logical(T.nearEdge);
interiorIdx = ~isEdge;
edgeIdx     = isEdge;

figure;
hold on;

yline(betaBand(1), '--', 'Color', [0.55 0.55 0.5], 'LineWidth', 1);
yline(betaBand(2), '--', 'Color', [0.55 0.55 0.5], 'LineWidth', 1);

scatter(subjectNum(interiorIdx), T.IBF_Hz(interiorIdx), 60, ...
    [0.165 0.471 0.839], 'filled');
scatter(subjectNum(edgeIdx), T.IBF_Hz(edgeIdx), 60, ...
    [0.890 0.286 0.282], 'filled');

xlabel('Subject number');
ylabel('Beta frequency (Hz)');
ylim([8 35]);
xlim([0 n+1]);
grid on;
box on;

set(gca, 'FontSize', 11);

saveas(gcf, fullfile(rerunDir, 'IBF_scatter_edge_vs_interior.png'));   % [path]