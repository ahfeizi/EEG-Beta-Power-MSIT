%% ---- per-channel (NOT averaged) beta feature extraction: Fz, Cz, F3, F4, C3, C4 ----
% Per supervisor's correction: these six channels are NOT an ROI to average
% together -- analyze each one separately. For every subject and every one
% of these six channels: raw PSD (Welch, 2s Hanning, 50% overlap), NO
% detrending, take the frequency + amplitude of the maximum in the beta band
% [13 30] Hz. Produces one long-format table (subject x channel x feature)
% plus one spectrum-grid figure PER CHANNEL (6 figures total), each showing
% all 42 subjects' raw PSD for that single channel.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
targetChans = {'Fz', 'Cz', 'F3', 'F4', 'C3', 'C4'};
subjects    = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand     = [13, 30];   % Hz, region to report the peak from
displayRange = [3, 40];    % Hz, range to show in the spectrum grid

epochLen   = 2.0;
pweOverlap = 50;

results = table();                          % long format: subject, channel, IBF_Hz, amplitude, nearEdge
spectra = struct();                         % spectra.(channel) = {f, psd, subject} per subject, for plotting

for c = 1:numel(targetChans)
    spectra.(targetChans{c}).f = {};
    spectra.(targetChans{c}).psd = {};
    spectra.(targetChans{c}).subj = {};
end

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
            data = reshape(data, 1, []);   % epochs -> continuous concat, single channel

            [pxx, f] = pwelch(data', hann(win), ov, win, fs);   % raw PSD, NO detrend

            bIdx = f >= betaBand(1) & f <= betaBand(2);
            bf   = f(bIdx);
            bp   = pxx(bIdx);

            [amp, idxMax] = max(bp);
            ibf = bf(idxMax);
            isEdge = (ibf <= betaBand(1)+0.5) || (ibf >= betaBand(2)-0.5);

            results = [results; table({subject}, {chName}, ibf, amp, isEdge, ...
                'VariableNames', {'subject','channel','IBF_Hz','amplitude_raw','nearEdge'})]; %#ok<AGROW>

            fprintf('%s  %-3s: IBF=%.2f Hz  amp=%.5f  nearEdge=%d\n', ...
                subject, chName, ibf, amp, isEdge);

            dispIdx = f >= displayRange(1) & f <= displayRange(2);
            spectra.(chName).f{end+1}    = f(dispIdx);
            spectra.(chName).psd{end+1}  = pxx(dispIdx);
            spectra.(chName).subj{end+1} = subject;
        end
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

fprintf('\nExtracted %d channel x subject rows\n', height(results));
outFile = fullfile(rerunDir, 'beta_features_per_channel_raw.csv');   % [path]
writetable(results, outFile);
fprintf('Saved -> %s\n', outFile);

%% ---- one spectrum-grid figure PER CHANNEL, all 42 subjects ----
nRows = 6; nCols = 7;

for c = 1:numel(targetChans)
    chName = targetChans{c};
    fList   = spectra.(chName).f;
    pList   = spectra.(chName).psd;
    subjList = spectra.(chName).subj;

    if isempty(fList)
        fprintf('No data for channel %s, skipping figure\n', chName);
        continue
    end

    ylims = [min(cellfun(@(x) min(x), pList)), max(cellfun(@(x) max(x), pList))];

    figure('Color', 'w', 'Position', [50 50 1500 1100]);
    tl = tiledlayout(nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');

    for k = 1:numel(subjList)
        nexttile;
        hold on;
        patch([betaBand(1) betaBand(2) betaBand(2) betaBand(1)], ...
              [ylims(1) ylims(1) ylims(2) ylims(2)], ...
              [0.93 0.93 0.90], 'EdgeColor', 'none');
        semilogy(fList{k}, pList{k}, 'Color', [0.11 0.36 0.68], 'LineWidth', 1.1);
        xlim(displayRange);
        ylim(ylims);
        set(gca, 'YScale', 'log');
        title(subjList{k}, 'FontSize', 9, 'FontWeight', 'normal');
        set(gca, 'FontSize', 7, 'XTick', [10 20 30], 'Box', 'on');
    end

    title(tl, sprintf('Raw PSD at %s, all subjects -- shaded = beta band [%d-%d Hz]', ...
        chName, betaBand(1), betaBand(2)), 'FontSize', 12);
    xlabel(tl, 'Frequency (Hz)');
    ylabel(tl, 'Power (\muV^2/Hz)');

    figFile = fullfile(rerunDir, sprintf('all_subjects_%s_raw_spectrum_grid.png', chName));   % [path]
    exportgraphics(gcf, figFile, 'Resolution', 200);
    fprintf('Saved -> %s\n', figFile);
end
