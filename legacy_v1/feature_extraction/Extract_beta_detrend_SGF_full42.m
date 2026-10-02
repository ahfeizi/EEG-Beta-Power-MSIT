%% ---- extract IBF (frequency) and amplitude: 1/f-detrend + SGF, ALL 42 subjects ----
% Generalized from the 5-subject pilot version. Implements the supervisor's
% instruction literally: for every subject, take the frequency and amplitude
% of the maximum in the beta band -- no significance gating, no peak/no-peak
% decision. The 1/f log-log detrend + SGF smoothing step is kept because
% (as established in the pilot) running this on the raw PSD without
% detrending just returns 13 Hz (the lower search-window edge) for almost
% everyone, which is not an informative feature.
%
% Also merges in the existing full_qc_summary.csv (nBadChan, nIC_muscle, etc.)
% so the beta feature table can be cross-checked against contamination
% indicators before anything is handed to correlation/ML analysis.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
qcSummaryFile = fullfile(derivRoot, 'full_qc_summary.csv');   % from RUN_MODE='full'

subjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand    = [13, 30];   % Hz, region to search for the beta feature
fitRange    = [2, 40];    % Hz, range used for the 1/f log-log fit
sgfOrder    = 3;          % polynomial order for smoothing the residual
sgfFrameLen = 9;          % must be odd; increase (11, 13, ...) for more smoothing

epochLen   = 2.0;         % seconds, same as preprocessing pipeline
pweOverlap = 50;          % percent

results = table();
missing = {};

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);

    if ~exist(setFile, 'file')
        fprintf('%s: SKIPPED (no clean .set file found)\n', subject);
        missing{end+1} = subject; %#ok<AGROW>
        continue
    end

    try
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
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
        missing{end+1} = subject; %#ok<AGROW>
    end
end

fprintf('\nExtracted %d/%d subjects (%d missing/failed)\n', ...
    height(results), numel(subjects), numel(missing));
if ~isempty(missing)
    fprintf('Missing/failed: %s\n', strjoin(missing, ', '));
end

outFile = fullfile(rerunDir, 'beta_features_full42_detrend_sgf.csv');   % [path]
writetable(results, outFile);
fprintf('\nSaved -> %s\n', outFile);

%% ---- merge with existing QC summary for cross-checking against contamination ----
if exist(qcSummaryFile, 'file')
    qcT = readtable(qcSummaryFile);
    merged = outerjoin(results, qcT, 'Keys', 'subject', 'MergeKeys', true);
    mergedFile = fullfile(rerunDir, 'beta_features_full42_with_qc.csv');   % [path]
    writetable(merged, mergedFile);
    fprintf('Merged with QC summary -> %s\n', mergedFile);

    % quick cross-check: does nearEdge co-occur with heavy muscle contamination?
    if all(ismember({'nIC_muscle','nIC_removed','nearEdge'}, merged.Properties.VariableNames))
        muscleRatio = merged.nIC_muscle ./ max(merged.nIC_removed, 1);
        fprintf('\nMean muscle-IC ratio | nearEdge=true:  %.2f\n', mean(muscleRatio(merged.nearEdge==1), 'omitnan'));
        fprintf('Mean muscle-IC ratio | nearEdge=false: %.2f\n', mean(muscleRatio(merged.nearEdge==0), 'omitnan'));
    end
else
    fprintf('\n[NOTE] %s not found -- skipping merge with QC summary.\n', qcSummaryFile);
end


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