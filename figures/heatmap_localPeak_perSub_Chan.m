%% ---- heatmap: hasLocalPeak per subject x channel ----
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
T = readtable(fullfile(derivRoot, 'beta_local_peaks_per_channel.csv'));

subjects = unique(T.subject, 'stable');
% ensure subjects are sorted sub-01..sub-42 numerically
subjNum = cellfun(@(s) str2double(s(5:6)), subjects);
[~, ord] = sort(subjNum);
subjects = subjects(ord);

channels = {'Fz','Cz','F3','F4','C3','C4'};

M = nan(numel(subjects), numel(channels));
for i = 1:numel(subjects)
    for j = 1:numel(channels)
        row = strcmp(T.subject, subjects{i}) & strcmp(T.channel, channels{j});
        if any(row)
            M(i,j) = T.hasLocalPeak(find(row,1));
        end
    end
end

figure('Color','w','Position',[100 100 500 900]);
h = heatmap(channels, subjects, M);
h.Title = 'Local beta-band peak detected? (raw PSD, per channel)';
h.XLabel = 'Channel';
h.YLabel = 'Subject';
h.Colormap = [0.85 0.33 0.30; 0.20 0.55 0.35];   % red = no peak, green = peak
h.ColorbarVisible = 'off';
h.CellLabelColor = 'none';
h.GridVisible = 'on';
h.FontSize = 9;

figFile = fullfile(derivRoot, 'beta_peak_heatmap_subject_x_channel.png');
exportgraphics(gcf, figFile, 'Resolution', 200);
fprintf('Saved -> %s\n', figFile);