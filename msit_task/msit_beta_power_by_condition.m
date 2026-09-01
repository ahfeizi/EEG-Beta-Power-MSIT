%% ---- MSIT+ task preprocessing + beta power extraction by condition ----
% Mirrors the resting-state pipeline (same filtering/ASR/ICA parameters) so
% results are comparable. ICA is re-run on the task file (not transplanted
% from resting-state) because after pop_subcomp removed bad components from
% the saved resting .set, the original unmixing matrix / rejected-component
% list needed to replicate the exact same rejection is no longer available.
%
% Marker -> condition mapping is from Dzianok et al. (2022), GigaScience,
% Table 3: S5=F0, S6=FS, S7=00, S8=S0.

bidsRoot  = fullfile(pwd, 'raw_data', 'ds004621');   % <-- EDIT: path to the downloaded OpenNeuro ds004621 dataset
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
taskDeriv = fullfile(derivRoot, 'MSIT_Output');
if ~exist(taskDeriv, 'dir'); mkdir(taskDeriv); end

subjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
% subjects = {'sub-01'};
targetChans = {'Fz','Cz','C4'};    % the three channels found clean in resting-state

condMarkers = struct('F0', {{'S  5'}}, 'FS', {{'S  6'}}, 'DD', {{'S  7'}}, 'S0', {{'S  8'}});
condNames = {'F0','FS','DD','S0'};   % 'DD' used internally for '00' (MATLAB fieldnames can't start with a digit)
condLabelForDisplay = containers.Map({'F0','FS','DD','S0'}, {'F0','FS','00','S0'});

epochWin = [-0.2 1.0];   % seconds relative to stimulus onset; adjust if needed
betaBand = [13, 30];     % Hz

% --- same ASR/ICA parameters as the resting-state pipeline, for consistency ---
lineFreq = 50; hpFreq = 0.1; lpFreq = 100; icaHpFreq = 1.0; resampleHz = 500;
chanCriterion = 0.80; burstCriterion = 20;
icThresh = [0 0; 0.80 1; 0.80 1; 0.80 1; 0.80 1; 0.80 1; 0 0];

[ALLEEG, EEG, CURRENTSET] = eeglab;

results = table();

for i = 1:numel(subjects)
    subject = subjects{i};
    fprintf('\n%s  %s\n', repmat('-',1,50), subject);

    try
        allFiles = dir(fullfile(bidsRoot, subject, '**', '*.vhdr'));
        taskHit = allFiles(contains({allFiles.name}, 'task-msit'));
        assert(~isempty(taskHit), 'No MSIT+ file found for %s', subject);

        EEG = pop_loadbv(taskHit(1).folder, taskHit(1).name);
        EEG.setname = [subject '_msit'];

        % --- channels (same as rest pipeline) ---
        nonEEG = {'EOG','VEOG','HEOG','IEOG','SEOG','ECG','EKG','EMG','GSR', ...
                  'RESP','STATUS','TRIGGER','MARKER'};
        labelsUp = upper({EEG.chanlocs.labels});
        dropIdx = find(ismember(labelsUp, nonEEG));
        if ~isempty(dropIdx), EEG = pop_select(EEG, 'nochannel', dropIdx); end
        if ~isfield(EEG.chanlocs,'X') || isempty(EEG.chanlocs(1).X)
            EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
        end
        noLoc = find(cellfun(@isempty, {EEG.chanlocs.X}));
        if ~isempty(noLoc), EEG = pop_select(EEG, 'nochannel', noLoc); end
        EEG = eeg_checkset(EEG);

        % --- filtering ---
        if exist('pop_cleanline', 'file')
            EEG = pop_cleanline(EEG, 'linefrequencies', [lineFreq lineFreq*2], ...
                'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
        else
            EEG = pop_eegfiltnew(EEG, 'locutoff', lineFreq-2, 'hicutoff', lineFreq+2, 'revfilt', 1);
        end
        EEG = pop_eegfiltnew(EEG, 'locutoff', hpFreq);
        EEG = pop_eegfiltnew(EEG, 'hicutoff', lpFreq);
        if EEG.srate > resampleHz
            EEG = pop_resample(EEG, resampleHz);
        end
        chanlocsFull = EEG.chanlocs;

        % --- bad channels / ASR ---
        nbefore = EEG.nbchan;
        EEG = pop_clean_rawdata(EEG, 'FlatlineCriterion', 5, 'ChannelCriterion', chanCriterion, ...
            'LineNoiseCriterion', 4, 'Highpass', 'off', 'BurstCriterion', burstCriterion, ...
            'WindowCriterion', 'off', 'BurstRejection', 'off', 'Distance', 'Euclidian');
        fprintf('  removed %d bad channels\n', nbefore - EEG.nbchan);
        EEG = pop_interp(EEG, chanlocsFull, 'spherical');
        EEG = pop_reref(EEG, []);

        % --- ICA (Picard, same as rest pipeline) ---
        EEG_ica = pop_eegfiltnew(EEG, 'locutoff', icaHpFreq);
        usePicard = exist('picard', 'file') || exist('pop_runica_picard', 'file');
        if usePicard
            EEG_ica = pop_runica(EEG_ica, 'icatype', 'picard', 'pca', EEG_ica.nbchan - 1);
        else
            EEG_ica = pop_runica(EEG_ica, 'icatype', 'runica', 'extended', 1, 'pca', EEG_ica.nbchan - 1);
        end
        EEG.icaweights = EEG_ica.icaweights; EEG.icasphere = EEG_ica.icasphere;
        EEG.icawinv = EEG_ica.icawinv; EEG.icachansind = EEG_ica.icachansind;
        EEG = eeg_checkset(EEG, 'ica');

        EEG = iclabel(EEG);
        EEG = pop_icflag(EEG, icThresh);
        rejIC = find(EEG.reject.gcompreject);
        EEG = pop_subcomp(EEG, rejIC, 0);
        fprintf('  removed %d IC components\n', numel(rejIC));

        % --- epoch by condition and extract beta power ---
        chIdxAll = nan(1, numel(targetChans));
        for ch = 1:numel(targetChans)
            idx = find(strcmpi({EEG.chanlocs.labels}, targetChans{ch}));
            if ~isempty(idx), chIdxAll(ch) = idx(1); end
        end

        for c = 1:numel(condNames)
            cField = condNames{c};
            markers = condMarkers.(cField);
            try
                EEGc = pop_epoch(EEG, markers, epochWin, 'newname', [subject '_' cField]);
            catch
                fprintf('  %s: no epochs for condition %s, skipping\n', subject, condLabelForDisplay(cField));
                continue
            end

            for ch = 1:numel(targetChans)
                if isnan(chIdxAll(ch))
                    fprintf('  channel %s not found for %s\n', targetChans{ch}, subject);
                    continue
                end
                chData = squeeze(EEGc.data(chIdxAll(ch), :, :));   % time x epochs
                if isvector(chData), chData = chData(:); end

                fs = EEGc.srate;
                winLen = min(size(chData,1), round(0.5*fs));   % adapt window to short epochs
                if winLen < 8, continue; end
                [pxx, f] = pwelch(chData, hann(winLen), round(winLen/2), winLen, fs);
                bIdx = f >= betaBand(1) & f <= betaBand(2);
                betaPow = mean(mean(pxx(bIdx, :), 1));   % avg over freq, then over epochs

                results = [results; table({subject}, {condLabelForDisplay(cField)}, {targetChans{ch}}, ...
                    EEGc.trials, betaPow, ...
                    'VariableNames', {'subject','condition','channel','nEpochs','betaPower_raw'})]; %#ok<AGROW>
            end
        end

        fprintf('  %s done\n', subject);
    catch ME
        fprintf('  [FAILED] %s: %s\n', subject, ME.message);
    end
end

outFile = fullfile(taskDeriv, 'msit_beta_power_by_condition.csv');
writetable(results, outFile);
fprintf('\nSaved -> %s\n', outFile);
