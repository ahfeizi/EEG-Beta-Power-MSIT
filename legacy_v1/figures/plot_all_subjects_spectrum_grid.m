%% ---- plot detrended spectrum shape for all 42 subjects in one figure ----
% Shows the same alpha-masked 1/f-detrended residual curve used for the
% IBF/amplitude extraction, for every subject, in a 6x7 grid of subplots.
% The beta search band [13 30] Hz is shaded so it's visually obvious whether
% each subject has a real local bump inside the band, or whether the curve
% is simply rising/falling through it (which is why the peak-based feature
% failed for about half the sample).

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

displayRange = [5, 40];    % Hz, what to actually plot (wider than beta band for context)
fitRange     = [2, 40];    % Hz, range used for the 1/f log-log fit
alphaMask    = [7, 13];    % Hz, excluded from the fit regression (not from display)
betaBand     = [13, 30];   % Hz, shaded region

epochLen   = 2.0;
pweOverlap = 50;

nRows = 6; nCols = 7;   % 6*7 = 42

allF = {}; allDetr = {}; validSubj = {};

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    if ~exist(setFile, 'file')
        fprintf('%s: SKIPPED (no file)\n', subject);
        continue
    end
    try
        EEG = pop_loadset('filename', setFile);
        data = double(EEG.data);
        if ndims(data) == 3
            data = reshape(data, size(data,1), []);
        end
        fs  = EEG.srate;
        win = round(epochLen * fs);
        ov  = round(win * pweOverlap/100);
        [pxx, f] = pwelch(data', hann(win), ov, win, fs);
        psd = mean(pxx, 2);

        sel = f >= fitRange(1) & f <= fitRange(2) & f > 0;
        fx  = f(sel);
        ly  = log10(psd(sel));
        lx  = log10(fx);

        fitMask = ~(fx >= alphaMask(1) & fx <= alphaMask(2));
        p = polyfit(lx(fitMask), ly(fitMask), 1);
        detr = ly - polyval(p, lx);

        dispIdx = fx >= displayRange(1) & fx <= displayRange(2);

        allF{end+1}    = fx(dispIdx);       %#ok<AGROW>
        allDetr{end+1} = detr(dispIdx);     %#ok<AGROW>
        validSubj{end+1} = subject;         %#ok<AGROW>
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

% common y-axis across all subplots so shapes are visually comparable
allVals = vertcat(allDetr{:});
yPad = 0.05 * range(allVals);
yLimCommon = [min(allVals)-yPad, max(allVals)+yPad];

figure('Color', 'w', 'Position', [50 50 1500 1100]);
tl = tiledlayout(nRows, nCols, 'TileSpacing', 'compact', 'Padding', 'compact');

for k = 1:numel(validSubj)
    nexttile;
    hold on;

    % shade the beta search band
    ylims = yLimCommon;
    patch([betaBand(1) betaBand(2) betaBand(2) betaBand(1)], ...
          [ylims(1) ylims(1) ylims(2) ylims(2)], ...
          [0.93 0.93 0.90], 'EdgeColor', 'none');

    plot(allF{k}, allDetr{k}, 'Color', [0.11 0.36 0.68], 'LineWidth', 1.1);
    yline(0, ':', 'Color', [0.6 0.6 0.6]);

    xlim(displayRange);
    ylim(yLimCommon);
    title(validSubj{k}, 'FontSize', 9, 'FontWeight', 'normal');
    set(gca, 'FontSize', 7, 'XTick', [10 20 30], 'Box', 'on');
end

title(tl, 'Detrended spectrum shape (1/f removed), all subjects -- shaded region = beta search band [13-30 Hz]', ...
    'FontSize', 12);
xlabel(tl, 'Frequency (Hz)');
ylabel(tl, 'Residual above 1/f background');

outFile = fullfile(rerunDir, 'all_subjects_detrended_spectrum_grid.png');   % [path]
exportgraphics(gcf, outFile, 'Resolution', 200);
fprintf('\nSaved -> %s\n', outFile);
