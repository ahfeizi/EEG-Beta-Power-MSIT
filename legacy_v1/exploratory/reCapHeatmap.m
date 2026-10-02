%% ---- rescaled heatmap: cap the color scale so the outlier doesn't wash out the rest ----
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
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

exportgraphics(gcf, fullfile(derivRoot, 'beta_avgpower_heatmap_capped.png'), 'Resolution', 200);