%% ---- whole-scalp average beta power: topoplot (grand-average + per-subject grid) ----
% Unlike the earlier whole-scalp AVERAGING (which collapsed all channels into
% one number and lost spatial information -- rejected by the supervisor),
% this keeps every channel's value separate and displays the full spatial
% pattern as a scalp map. No information is discarded.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand   = [13, 30];   % Hz
epochLen   = 2.0;
pweOverlap = 50;

allPower = {};        % allPower{i} = nChan x 1 vector of avg beta power for subject i
validSubj = {};
refChanlocs = [];      % reference chanlocs (assumed consistent across subjects)

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    if ~exist(setFile, 'file')
        fprintf('%s: SKIPPED (no file)\n', subject);
        continue
    end

    try
        EEG = pop_loadset('filename', setFile);
        if isempty(refChanlocs)
            refChanlocs = EEG.chanlocs;   % use first successfully-loaded subject as reference
        end

        data = double(EEG.data);
        if ndims(data) == 3
            data = reshape(data, size(data,1), []);
        end
        fs  = EEG.srate;
        win = round(epochLen * fs);
        ov  = round(win * pweOverlap/100);

        [pxx, f] = pwelch(data', hann(win), ov, win, fs);   % freq x channel, raw PSD, no detrend

        bIdx = f >= betaBand(1) & f <= betaBand(2);
        chanPower = mean(pxx(bIdx, :), 1)';   % nChan x 1

        allPower{end+1}  = chanPower;   %#ok<AGROW>
        validSubj{end+1} = subject;     %#ok<AGROW>

        fprintf('%s: mean beta power across scalp = %.4f\n', subject, mean(chanPower));
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

fprintf('\nProcessed %d/%d subjects\n', numel(validSubj), numel(subjects));

%% ---- grand-average topoplot ----
allPowerMat = cell2mat(allPower)';    % nSubj x nChan
grandAvg = mean(allPowerMat, 1)';     % nChan x 1

figure('Color','w','Position',[100 100 500 500]);
topoplot(grandAvg, refChanlocs, 'electrodes','on', 'style','both');
colorbar;
title(sprintf('Grand-average raw beta power (%d-%d Hz), all %d subjects', ...
    betaBand(1), betaBand(2), numel(validSubj)));
exportgraphics(gcf, fullfile(rerunDir, 'beta_power_topoplot_grandaverage.png'), 'Resolution', 200);   % [path]

%% ---- per-subject topoplot grid (6x7) ----
nRows = 6; nCols = 7;
capVal = prctile(allPowerMat(:), 95);   % shared color scale, robust to outliers (e.g. sub-07)

figure('Color','w','Position',[50 50 1500 1300]);
tl = tiledlayout(nRows, nCols, 'TileSpacing','compact', 'Padding','compact');

for k = 1:numel(validSubj)
    nexttile;
    topoplot(allPower{k}, refChanlocs, 'electrodes','off', 'style','map', ...
        'maplimits', [0 capVal]);
    title(validSubj{k}, 'FontSize', 9, 'FontWeight','normal');
end

title(tl, sprintf('Per-subject raw beta power topography (%d-%d Hz) -- color capped at 95th percentile', ...
    betaBand(1), betaBand(2)), 'FontSize', 12);

exportgraphics(gcf, fullfile(rerunDir, 'beta_power_topoplot_per_subject_grid.png'), 'Resolution', 200);   % [path]

%% ---- save the underlying per-channel data too ----
chanLabels = {refChanlocs.labels}';
T = array2table(allPowerMat', 'VariableNames', validSubj, 'RowNames', chanLabels);
writetable(T, fullfile(rerunDir, 'beta_power_all_channels_all_subjects.csv'), 'WriteRowNames', true);   % [path]
fprintf('Saved full channel x subject table -> beta_power_all_channels_all_subjects.csv\n');
