%% ---- extract IBF/amplitude: ALPHA-MASKED 1/f-detrend + SGF, ALL 42 subjects ----
% Same as extract_beta_detrend_sgf_full42.m, but the 1/f log-log linear fit
% now EXCLUDES the alpha band (default 7-13 Hz) from the regression, so the
% huge alpha peak cannot bias/pull the fitted background line. The fitted
% line is still evaluated across the full range and subtracted from the beta
% band as before. This directly tests the hypothesis that the previous
% lower-edge clustering (19/23 edge cases at 13-13.5 Hz) was a fit artifact
% from alpha, not genuine beta signal.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
qcSummaryFile = fullfile(derivRoot, 'full_qc_summary.csv');

subjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand    = [13, 30];   % Hz, region to search for the beta feature
fitRange    = [2, 40];    % Hz, range used for the 1/f log-log fit
alphaMask   = [7, 13];    % Hz, region EXCLUDED from the fit (but not from detrending)
sgfOrder    = 3;
sgfFrameLen = 9;          % must be odd

epochLen   = 2.0;
pweOverlap = 50;

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
            data = reshape(data, size(data,1), []);
        end
        fs  = EEG.srate;
        win = round(epochLen * fs);
        ov  = round(win * pweOverlap/100);

        [pxx, f] = pwelch(data', hann(win), ov, win, fs);
        psd = mean(pxx, 2);

        [ibf, amp, isEdge, r2] = extract_beta_sgf_masked(f, psd, betaBand, fitRange, alphaMask, sgfOrder, sgfFrameLen);

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

nEdge = sum(results.nearEdge);
fprintf('\nnearEdge=true: %d/%d (%.0f%%)\n', nEdge, height(results), 100*nEdge/height(results));
nLowEdge = sum(results.nearEdge==1 & results.IBF_Hz <= betaBand(1)+0.5);
nHighEdge = sum(results.nearEdge==1 & results.IBF_Hz >= betaBand(2)-0.5);
fprintf('  lower-edge (near alpha): %d\n', nLowEdge);
fprintf('  upper-edge (near EMG):   %d\n', nHighEdge);

outFile = fullfile(rerunDir, 'beta_features_full42_alphamasked.csv');   % [path]
writetable(results, outFile);
fprintf('\nSaved -> %s\n', outFile);

%% ---- merge with existing QC summary ----
if exist(qcSummaryFile, 'file')
    qcT = readtable(qcSummaryFile);
    merged = outerjoin(results, qcT, 'Keys', 'subject', 'MergeKeys', true);
    mergedFile = fullfile(rerunDir, 'beta_features_full42_alphamasked_with_qc.csv');   % [path]
    writetable(merged, mergedFile);
    fprintf('Merged with QC summary -> %s\n', mergedFile);

    if all(ismember({'nIC_muscle','nIC_removed','nearEdge'}, merged.Properties.VariableNames))
        muscleRatio = merged.nIC_muscle ./ max(merged.nIC_removed, 1);
        fprintf('\nMean muscle-IC ratio | nearEdge=true:  %.2f\n', mean(muscleRatio(merged.nearEdge==1), 'omitnan'));
        fprintf('Mean muscle-IC ratio | nearEdge=false: %.2f\n', mean(muscleRatio(merged.nearEdge==0), 'omitnan'));
    end
else
    fprintf('\n[NOTE] %s not found -- skipping merge with QC summary.\n', qcSummaryFile);
end


% ============================================================================
function [ibf, amp, isEdge, r2] = extract_beta_sgf_masked(f, psd, betaBand, fitRange, alphaMask, sgfOrder, sgfFrameLen)
    sel = f >= fitRange(1) & f <= fitRange(2) & f > 0;
    fx  = f(sel);
    ly  = log10(psd(sel));
    lx  = log10(fx);

    % exclude the alpha peak region from the REGRESSION only
    fitMask = ~(fx >= alphaMask(1) & fx <= alphaMask(2));
    p = polyfit(lx(fitMask), ly(fitMask), 1);

    % evaluate the fitted line across the FULL range to detrend beta
    fitY_full = polyval(p, lx);
    detr = ly - fitY_full;

    % R^2 computed only on the points actually used for the fit
    fitY_used = polyval(p, lx(fitMask));
    ss_res = sum((ly(fitMask) - fitY_used).^2);
    ss_tot = sum((ly(fitMask) - mean(ly(fitMask))).^2);
    r2 = 1 - ss_res/ss_tot;

    bIdx = fx >= betaBand(1) & fx <= betaBand(2);
    bf   = fx(bIdx);
    bd   = detr(bIdx);

    smoothed = sgolayfilt(bd, sgfOrder, sgfFrameLen);
    [amp, idxMax] = max(smoothed);
    ibf = bf(idxMax);

    isEdge = (ibf <= betaBand(1) + 0.5) || (ibf >= betaBand(2) - 0.5);
end
