%% ---- extract IBF (frequency) and amplitude using SGF, all pilot subjects ----
% Mirrors the reference paper's (Jiang et al.) IAF/IAB extraction method:
% smooth the raw PSD with a Savitzky-Golay filter, take the absolute max
% within the band of interest. No aperiodic subtraction, no significance
% gating -- just frequency + amplitude, as instructed.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand    = [13, 30];   % Hz
sgfOrder    = 3;          % polynomial order
sgfFrameLen = 9;          % must be odd; increase (e.g. 11, 13) for more smoothing

epochLen  = 2.0;          % seconds, same as preprocessing pipeline
pweOverlap = 50;          % percent

results = table();

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    EEG = pop_loadset('filename', setFile);

    data = double(EEG.data);
    if ndims(data) == 3
        data = reshape(data, size(data,1), []);   % epochs -> continuous concat
    end
    fs  = EEG.srate;
    win = round(epochLen * fs);
    ov  = round(win * pweOverlap/100);

    [pxx, f] = pwelch(data', hann(win), ov, win, fs);
    psd = mean(pxx, 2);   % average across channels

    [ibf, amp, isEdge] = extract_beta_sgf(f, psd, betaBand, sgfOrder, sgfFrameLen);

    results = [results; table({subject}, ibf, amp, isEdge, ...
        'VariableNames', {'subject','IBF_Hz','amplitude','nearEdge'})]; %#ok<AGROW>

    fprintf('%s: IBF=%.2f Hz  amplitude=%.5f  nearEdge=%d\n', ...
        subject, ibf, amp, isEdge);
end

disp(results)
writetable(results, fullfile(rerunDir, 'beta_features_full42_sgf.csv'));   % [path]


% ============================================================================
function [ibf, amp, isEdge] = extract_beta_sgf(f, psd, betaBand, sgfOrder, sgfFrameLen)
    bIdx = f >= betaBand(1) & f <= betaBand(2);
    bf   = f(bIdx);
    bp   = psd(bIdx);

    smoothed = sgolayfilt(bp, sgfOrder, sgfFrameLen);
    [amp, idxMax] = max(smoothed);
    ibf = bf(idxMax);

    isEdge = (ibf <= betaBand(1) + 0.5) || (ibf >= betaBand(2) - 0.5);
end