%% ---- average beta-band power per channel (raw PSD, no detrend, no peak-finding) ----
% Per supervisor's decision: use average beta power, not peak frequency, as
% the feature of interest (it is defined for every subject, unlike a local
% peak which some subjects lack). For every subject and every one of the six
% channels (analyzed separately, NOT averaged together), compute the mean of
% the raw PSD (Welch, 2s Hanning, 50% overlap, NO 1/f detrending) across the
% beta band [13 30] Hz.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
targetChans = {'Fz', 'Cz', 'F3', 'F4', 'C3', 'C4'};
subjects    = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand = [13, 30];   % Hz

epochLen   = 2.0;
pweOverlap = 50;

results = table();

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    if ~exist(setFile, 'file')
        fprintf('%s: SKIPPED (no file)\n', subject);
        continue
    end

    try
        EEG = pop_loadset('filename', setFile);
        labels = {EEG.chanlocs.labels};
        fs = EEG.srate;
        win = round(epochLen * fs);
        ov  = round(win * pweOverlap/100);

        for c = 1:numel(targetChans)
            chName = targetChans{c};
            chIdx = find(strcmpi(labels, chName));
            if isempty(chIdx)
                fprintf('%s: channel "%s" not found, skipping\n', subject, chName);
                continue
            end
            chIdx = chIdx(1);

            data = double(EEG.data(chIdx, :, :));
            data = reshape(data, 1, []);

            [pxx, f] = pwelch(data', hann(win), ov, win, fs);   % raw PSD, NO detrend

            bIdx = f >= betaBand(1) & f <= betaBand(2);
            avgBetaPower = mean(pxx(bIdx));

            results = [results; table({subject}, {chName}, avgBetaPower, ...
                'VariableNames', {'subject','channel','avgBetaPower_raw'})]; %#ok<AGROW>

            fprintf('%s  %-3s: avgBetaPower=%.5f\n', subject, chName, avgBetaPower);
        end
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

fprintf('\nExtracted %d channel x subject rows\n', height(results));
outFile = fullfile(rerunDir, 'beta_avgpower_per_channel.csv');   % [path]
writetable(results, outFile);
fprintf('Saved -> %s\n', outFile);

%% ---- heatmap figure: average beta power, subject x channel ----
subjNum = cellfun(@(s) str2double(s(5:6)), subjects);
[~, ord] = sort(subjNum);
subjectsSorted = subjects(ord);

M = nan(numel(subjectsSorted), numel(targetChans));
for i = 1:numel(subjectsSorted)
    for j = 1:numel(targetChans)
        row = strcmp(results.subject, subjectsSorted{i}) & strcmp(results.channel, targetChans{j});
        if any(row)
            M(i,j) = results.avgBetaPower_raw(find(row,1));
        end
    end
end

figure('Color','w','Position',[100 100 500 900]);
h = heatmap(targetChans, subjectsSorted, M);
h.Title = 'Average beta-band power (13-30 Hz), raw PSD, per channel';
h.XLabel = 'Channel';
h.YLabel = 'Subject';
h.Colormap = parula;
h.ColorbarVisible = 'on';
h.CellLabelFormat = '%.2f';
h.FontSize = 8;

figFile = fullfile(rerunDir, 'beta_avgpower_heatmap_subject_x_channel.png');   % [path]
exportgraphics(gcf, figFile, 'Resolution', 200);
fprintf('Saved -> %s\n', figFile);
