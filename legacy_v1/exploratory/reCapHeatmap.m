%% ---- rescaled heatmap: cap the color scale so the outlier doesn't wash out the rest ----
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
T = readtable(fullfile(derivRoot, 'beta_avgpower_per_channel.csv'));

subjects = unique(T.subject, 'stable');
subjNum = cellfun(@(s) str2double(s(5:6)), subjects);
[~, ord] = sort(subjNum);
subjects = subjects(ord);
channels = {'Fz','Cz','F3','F4','C3','C4'};

M = nan(numel(subjects), numel(channels));
for i = 1:numel(subjects)
    for j = 1:numel(channels)
        row = strcmp(T.subject, subjects{i}) & strcmp(T.channel, channels{j});
        if any(row), M(i,j) = T.avgBetaPower_raw(find(row,1)); end
    end
end

figure('Color','w','Position',[100 100 500 900]);
h = heatmap(channels, subjects, M);
h.Title = 'Average beta-band power (13-30 Hz) -- color capped at 95th percentile';
h.XLabel = 'Channel'; h.YLabel = 'Subject';
h.Colormap = parula;
h.CellLabelFormat = '%.2f';
h.FontSize = 8;
capVal = prctile(M(:), 95);           % <-- outlier no longer dominates the scale
h.ColorLimits = [0, capVal];

exportgraphics(gcf, fullfile(rerunDir, 'beta_avgpower_heatmap_capped.png'), 'Resolution', 200);   % [path]