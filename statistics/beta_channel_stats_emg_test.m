%% ---- whole-scalp analysis: distinct channels (stats) + EMG contamination test ----
% Per supervisor's instructions:
%   1) work on ALL channels (already done -- beta_power_all_channels_all_subjects.csv)
%   2) use a statistical method to identify DISTINCT channels (not manual selection)
%   3) test whether the signal contains EMG noise
%
% METHOD RATIONALE (for citing in the paper):
%   - Within-subject z-scoring of channel power before pooling across subjects is
%     standard practice because absolute EEG power varies hugely between
%     individuals (skull conductance, electrode impedance, etc.), so raw power
%     cannot be pooled directly across subjects.
%   - A one-sample Wilcoxon signed-rank test (nonparametric, since EEG power
%     distributions are typically right-skewed) is used per channel to test
%     whether its mean z-score across the 42 subjects differs from zero.
%   - Benjamini-Hochberg FDR correction (Benjamini & Hochberg, 1995, J R Stat
%     Soc B) is applied across the ~125 simultaneous channel-wise tests.
%   - EMG contamination is assessed via the cross-subject Spearman correlation
%     between each channel's beta-band (13-30 Hz) power and its power in a
%     high-frequency control band (55-95 Hz), where genuine neural beta activity
%     is not expected to track broadband high-frequency power, but EMG
%     contamination (which is broadband) would produce a shared source driving
%     both bands together.

derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
[ALLEEG, EEG, CURRENTSET] = eeglab;

%% ---- 0. load and verify completeness ----
T = readtable(fullfile(derivRoot, 'beta_power_all_channels_all_subjects.csv'), ...
    'ReadRowNames', true, 'VariableNamingRule', 'preserve');fprintf('Table size: %d channels x %d subjects\n', size(T,1), size(T,2));
nMissing = sum(ismissing(T), 'all');
fprintf('Missing values: %d\n', nMissing);
if any(all(ismissing(T),1))
    fprintf('WARNING: at least one subject column is entirely missing\n');
end
if any(all(ismissing(T),2))
    fprintf('WARNING: at least one channel row is entirely missing\n');
end
if nMissing > 0
    error('Fix missing values before proceeding -- do not silently impute.');
end

chanLabels = T.Properties.RowNames;
subjLabels = T.Properties.VariableNames;
betaPower = table2array(T);            % nChan x nSubj, beta-band [13-30 Hz] power
nChan = size(betaPower,1);
nSubj = size(betaPower,2);

%% ---- 1. within-subject z-scoring, then FDR-corrected Wilcoxon per channel ----
zPower = nan(size(betaPower));
for s = 1:nSubj
    col = betaPower(:,s);
    zPower(:,s) = (col - mean(col)) / std(col);
end

pvals = nan(nChan,1);
meanZ = mean(zPower, 2);
for c = 1:nChan
    row = zPower(c,:);
    if all(row == row(1))          % guard against degenerate rows
        pvals(c) = 1;
    else
        pvals(c) = signrank(row, 0, 'method', 'exact');   % Wilcoxon signed-rank test vs. 0 (exact method; see Methods)
    end
end

% Benjamini-Hochberg FDR correction
[sortedP, sortIdx] = sort(pvals);
m = numel(pvals);
fdrThresh = (1:m)' / m * 0.05;
belowThresh = sortedP <= fdrThresh;
if any(belowThresh)
    cutoffRank = find(belowThresh, 1, 'last');
    pFDRcrit = sortedP(cutoffRank);
else
    pFDRcrit = 0;
end
isDistinct = pvals <= pFDRcrit;

distinctTable = table(chanLabels, meanZ, pvals, isDistinct, ...
    'VariableNames', {'channel','meanZscore','pValue','distinct_FDR05'});
distinctTable = sortrows(distinctTable, 'meanZscore', 'descend');
disp(distinctTable);

outFile1 = fullfile(derivRoot, 'beta_distinct_channels_stats.csv');
writetable(distinctTable, outFile1);
fprintf('Saved -> %s\n', outFile1);

nDistinctHigh = sum(isDistinct & meanZ > 0);
nDistinctLow  = sum(isDistinct & meanZ < 0);
fprintf('\n%d channels significantly ABOVE the whole-head average (FDR<.05)\n', nDistinctHigh);
fprintf('%d channels significantly BELOW the whole-head average (FDR<.05)\n', nDistinctLow);

%% ---- 2. EMG contamination test: beta power vs. high-frequency control band ----
% Recompute PSD per subject/channel to get the control-band power (not saved
% previously -- only beta-band power was stored). Uses the same raw,
% non-detrended Welch PSD as before.

controlBand = [55, 95];   % Hz, safely inside the passband (avoids 50 Hz notch, 100 Hz lowpass edge)
betaBand    = [13, 30];   % Hz, for cross-check consistency with saved table

epochLen   = 2.0;
pweOverlap = 50;

controlPower = nan(nChan, nSubj);
betaPowerRecomputed = nan(nChan, nSubj);   % sanity check against loaded table

subjFiles = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
colIdxMap = containers.Map(subjLabels, 1:numel(subjLabels));

for i = 1:numel(subjFiles)
    subject = subjFiles{i};
    if ~isKey(colIdxMap, subject)
        continue   % subject not in the loaded table (e.g. failed earlier)
    end
    sIdx = colIdxMap(subject);

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

        cIdx = f >= controlBand(1) & f <= controlBand(2);
        bIdx = f >= betaBand(1) & f <= betaBand(2);

        controlPower(:, sIdx) = mean(pxx(cIdx, :), 1)';
        betaPowerRecomputed(:, sIdx) = mean(pxx(bIdx, :), 1)';

        fprintf('%s: control-band power computed\n', subject);
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

% sanity check: recomputed beta power should closely match the saved table
diffCheck = abs(betaPowerRecomputed - betaPower);
fprintf('\nSanity check -- max abs diff between saved and recomputed beta power: %.6f\n', ...
    max(diffCheck(:), [], 'omitnan'));

% per-channel cross-subject Spearman correlation: beta power vs control-band power
emgCorr = nan(nChan,1);
emgP    = nan(nChan,1);
for c = 1:nChan
    x = betaPower(c,:)';
    y = controlPower(c,:)';
    valid = ~isnan(x) & ~isnan(y);
    if sum(valid) > 5
        [r, p] = corr(x(valid), y(valid), 'Type', 'Spearman');
        emgCorr(c) = r;
        emgP(c) = p;
    end
end

% FDR correction on EMG correlation p-values
[sortedPe, ~] = sort(emgP);
me = sum(~isnan(emgP));
fdrThreshE = (1:numel(sortedPe))' / numel(sortedPe) * 0.05;
belowE = sortedPe <= fdrThreshE;
if any(belowE)
    pFDRcritE = sortedPe(find(belowE,1,'last'));
else
    pFDRcritE = 0;
end
likelyEMG = emgP <= pFDRcritE & emgCorr > 0.4;   % positive, significant, and meaningfully sized

emgTable = table(chanLabels, emgCorr, emgP, likelyEMG, ...
    'VariableNames', {'channel','betaVsControlBand_r','pValue','likelyEMG_contaminated'});
emgTable = sortrows(emgTable, 'betaVsControlBand_r', 'descend');
disp(emgTable);

outFile2 = fullfile(derivRoot, 'beta_emg_contamination_test.csv');
writetable(emgTable, outFile2);
fprintf('Saved -> %s\n', outFile2);

fprintf('\n%d / %d channels flagged as likely EMG-contaminated (r>0.4, FDR<.05)\n', ...
    sum(likelyEMG), nChan);
