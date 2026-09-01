%% ---- per-channel beta LOCAL PEAK extraction (raw PSD, no detrend) ----
% Correction based on supervisor's feedback: taking the absolute maximum of
% the raw PSD in [13 30] Hz almost always just grabs the descending tail of
% the (much larger) alpha peak at 13 Hz, even when a real, gentle local bump
% ("shoulder") exists further into the beta band. This version instead looks
% for a genuine LOCAL peak (rise then fall) using findpeaks with a small
% prominence threshold, evaluated in log10 power (so a modest bump is
% detected proportionally, matching what is visually apparent on the
% semilogy plots the supervisor reviewed). NO 1/f detrending is applied --
% this operates directly on the raw PSD, per the supervisor's instruction.
%
% If no local peak exists in the beta band (genuinely monotonic spectrum,
% expected for a small number of subjects), hasLocalPeak=false and the
% frequency/amplitude columns are left NaN rather than forced to an edge
% value.

derivRoot   = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
targetChans = {'Fz', 'Cz', 'F3', 'F4', 'C3', 'C4'};
subjects    = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);

betaBand      = [13, 30];   % Hz, region to search for a local peak
minProminence = 0.08;       % log10 units; tune up/down if too many/few peaks are found

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
            bf   = f(bIdx);
            bp   = pxx(bIdx);
            logbp = log10(bp);

            [pks, locs, ~, prom] = findpeaks(logbp, bf, 'MinPeakProminence', minProminence);

            if isempty(pks)
                hasPeak = false;
                peakFreq = NaN; peakAmp = NaN; peakProm = NaN;
            else
                [~, bestIdx] = max(prom);      % most prominent local peak
                hasPeak = true;
                peakFreq = locs(bestIdx);
                peakAmp  = 10^pks(bestIdx);     % back to linear power units
                peakProm = prom(bestIdx);
            end

            results = [results; table({subject}, {chName}, hasPeak, peakFreq, peakAmp, peakProm, ...
                'VariableNames', {'subject','channel','hasLocalPeak','peakFreq_Hz','peakAmp_raw','prominence'})]; %#ok<AGROW>

            fprintf('%s  %-3s: hasPeak=%d  freq=%.2f  amp=%.4f  prom=%.3f\n', ...
                subject, chName, hasPeak, peakFreq, peakAmp, peakProm);
        end
    catch ME
        fprintf('%s: FAILED (%s)\n', subject, ME.message);
    end
end

fprintf('\nExtracted %d channel x subject rows\n', height(results));

% quick summary: how many (subject, channel) combos have no local peak?
noPeakCount = sum(~results.hasLocalPeak);
fprintf('No local peak found in %d / %d (subject, channel) combinations (%.0f%%)\n', ...
    noPeakCount, height(results), 100*noPeakCount/height(results));

% which subjects have NO peak in ANY of the 6 channels (fully monotonic)?
subjList = unique(results.subject);
fullyMonotonic = {};
for s = 1:numel(subjList)
    rows = strcmp(results.subject, subjList{s});
    if all(~results.hasLocalPeak(rows))
        fullyMonotonic{end+1} = subjList{s}; %#ok<AGROW>
    end
end
fprintf('Subjects with NO local peak in ANY of the 6 channels: %s\n', strjoin(fullyMonotonic, ', '));

outFile = fullfile(derivRoot, 'beta_local_peaks_per_channel.csv');
writetable(results, outFile);
fprintf('Saved -> %s\n', outFile);
