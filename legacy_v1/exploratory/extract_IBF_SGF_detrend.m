%% ---- extract IBF (frequency) and amplitude: 1/f-detrend + SGF, all pilot subjects ----
% Combines the two things that turned out to matter across all prior tests:
%   1) detrend the 1/f background first (simple linear log-log fit --
%      the 'fixed' / no-knee model was the most stable option we tried)
%   2) smooth the residual with a Savitzky-Golay filter before taking the max
% Output: frequency + amplitude for every subject, no significance gating,
% per the supervisor's instruction -- plus a nearEdge flag so edge-artifact
% cases (residual EMG / alpha leakage) can be identified rather than silently
% averaged in.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects  = {'sub-17', 'sub-20', 'sub-08', 'sub-09', 'sub-15'};

betaBand    = [13, 30];   % Hz, region to search for the beta feature
fitRange    = [2, 40];    % Hz, range used for the 1/f log-log fit
sgfOrder    = 3;          % polynomial order for smoothing the residual
sgfFrameLen = 9;          % must be odd; increase (11, 13, ...) for more smoothing

epochLen   = 2.0;         % seconds, same as preprocessing pipeline
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

    [ibf, amp, isEdge, r2] = extract_beta_sgf_detrended(f, psd, betaBand, fitRange, sgfOrder, sgfFrameLen);

    results = [results; table({subject}, ibf, amp, isEdge, r2, ...
        'VariableNames', {'subject','IBF_Hz','amplitude','nearEdge','fitR2'})]; %#ok<AGROW>

    fprintf('%s: IBF=%.2f Hz  amplitude=%.5f  nearEdge=%d  fitR2=%.4f\n', ...
        subject, ibf, amp, isEdge, r2);
end

disp(results)
writetable(results, fullfile(rerunDir, 'beta_features_pilot_detrend_sgf.csv'));   % [path]


% ============================================================================
function [ibf, amp, isEdge, r2] = extract_beta_sgf_detrended(f, psd, betaBand, fitRange, sgfOrder, sgfFrameLen)
    sel = f >= fitRange(1) & f <= fitRange(2) & f > 0;
    fx  = f(sel);
    lx  = log10(fx);
    ly  = log10(psd(sel));

    p    = polyfit(lx, ly, 1);          % simple linear 1/f fit (no knee)
    fitY = polyval(p, lx);
    detr = ly - fitY;                    % residual above the 1/f background

    ss_res = sum((ly - fitY).^2);
    ss_tot = sum((ly - mean(ly)).^2);
    r2 = 1 - ss_res/ss_tot;

    bIdx = fx >= betaBand(1) & fx <= betaBand(2);
    bf   = fx(bIdx);
    bd   = detr(bIdx);

    smoothed = sgolayfilt(bd, sgfOrder, sgfFrameLen);
    [amp, idxMax] = max(smoothed);
    ibf = bf(idxMax);

    isEdge = (ibf <= betaBand(1) + 0.5) || (ibf >= betaBand(2) - 0.5);
end