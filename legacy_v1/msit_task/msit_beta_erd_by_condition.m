%% ---- MSIT+ task: baseline-normalized beta ERD by condition (+ control band) ----
bidsRoot  = fullfile(pwd, 'raw_data', 'ds004621');   % <-- EDIT: path to the downloaded OpenNeuro ds004621 dataset
derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder
taskDeriv = fullfile(derivRoot, 'MSIT_Output');
if ~exist(taskDeriv, 'dir'); mkdir(taskDeriv); end

subjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
targetChans = {'Fz','Cz','C4'};

condMarkers = struct('F0', {{'S  5'}}, 'FS', {{'S  6'}}, 'DD', {{'S  7'}}, 'S0', {{'S  8'}});
condNames = {'F0','FS','DD','S0'};
condLabelForDisplay = containers.Map({'F0','FS','DD','S0'}, {'F0','FS','00','S0'});

epochWin     = [-0.2 1.0];
baselineWin  = [-0.2 0];
postWin      = [0.2 0.6];
betaBand     = [13, 30];
controlBand  = [55, 95];

lineFreq = 50; hpFreq = 0.1; lpFreq = 100; icaHpFreq = 1.0; resampleHz = 500;
chanCriterion = 0.80; burstCriterion = 20;
icThresh = [0 0; 0.80 1; 0.80 1; 0.80 1; 0.80 1; 0.80 1; 0 0];

[ALLEEG, EEG, CURRENTSET] = eeglab;

outFile = fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv');
results = table();
if exist(outFile, 'file')
    fprintf('Found existing partial results, resuming from them.\n');
    results = readtable(outFile);
end
if ismember('subject', results.Properties.VariableNames)
    alreadyDone = unique(results.subject);
else
    alreadyDone = {};
end

for i = 1:numel(subjects)
    subject = subjects{i};
    if ismember(subject, alreadyDone)
        fprintf('%s already processed, skipping.\n', subject);
        continue
    end
    fprintf('\n%s  %s\n', repmat('-',1,50), subject);
    t_subj = tic;

    try
        allFiles = dir(fullfile(bidsRoot, subject, '**', '*.vhdr'));
        taskHit = allFiles(contains({allFiles.name}, 'task-msit'));
        assert(~isempty(taskHit), 'No MSIT+ file found for %s', subject);

        t = tic;
        EEG = pop_loadbv(taskHit(1).folder, taskHit(1).name);
        fprintf('  [TIME] load: %.1f min\n', toc(t)/60);
        EEG.setname = [subject '_msit'];

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

        t = tic;
        if EEG.srate > resampleHz
            EEG = pop_resample(EEG, resampleHz);
        end
        useCleanline = false;
        if useCleanline && exist('pop_cleanline', 'file')
            EEG = pop_cleanline(EEG, 'linefrequencies', [lineFreq lineFreq*2], ...
                'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
        else
            EEG = pop_eegfiltnew(EEG, 'locutoff', lineFreq-2, 'hicutoff', lineFreq+2, 'revfilt', 1);
        end
        EEG = pop_eegfiltnew(EEG, 'locutoff', hpFreq);
        EEG = pop_eegfiltnew(EEG, 'hicutoff', lpFreq);
        fprintf('  [TIME] resample+filter: %.1f min\n', toc(t)/60);
        chanlocsFull = EEG.chanlocs;

        t = tic;
        nbefore = EEG.nbchan;
        EEG = pop_clean_rawdata(EEG, 'FlatlineCriterion', 5, 'ChannelCriterion', chanCriterion, ...
            'LineNoiseCriterion', 4, 'Highpass', 'off', 'BurstCriterion', burstCriterion, ...
            'WindowCriterion', 'off', 'BurstRejection', 'off', 'Distance', 'Euclidian');
        fprintf('  [TIME] clean_rawdata: %.1f min (removed %d channels)\n', toc(t)/60, nbefore-EEG.nbchan);
        EEG = pop_interp(EEG, chanlocsFull, 'spherical');
        EEG = pop_reref(EEG, []);

        t = tic;
        EEG_ica = pop_eegfiltnew(EEG, 'locutoff', icaHpFreq);
        usePicard = exist('picard', 'file') > 0;
        if usePicard
            EEG_ica = pop_runica(EEG_ica, 'icatype', 'picard', 'pca', EEG_ica.nbchan - 1);
        else
            EEG_ica = pop_runica(EEG_ica, 'icatype', 'runica', 'extended', 1, 'pca', EEG_ica.nbchan - 1);
        end
        fprintf('  [TIME] ICA (%s): %.1f min\n', ternary(usePicard,'picard','runica'), toc(t)/60);

        EEG.icaweights = EEG_ica.icaweights; EEG.icasphere = EEG_ica.icasphere;
        EEG.icawinv = EEG_ica.icawinv; EEG.icachansind = EEG_ica.icachansind;
        EEG = eeg_checkset(EEG, 'ica');

        t = tic;
        EEG = iclabel(EEG);
        EEG = pop_icflag(EEG, icThresh);
        rejIC = find(EEG.reject.gcompreject);
        EEG = pop_subcomp(EEG, rejIC, 0);
        fprintf('  [TIME] iclabel+subcomp: %.1f min (removed %d comps)\n', toc(t)/60, numel(rejIC));

        chIdxAll = nan(1, numel(targetChans));
        for ch = 1:numel(targetChans)
            idx = find(strcmpi({EEG.chanlocs.labels}, targetChans{ch}));
            if ~isempty(idx), chIdxAll(ch) = idx(1); end
        end

        t = tic;
        for c = 1:numel(condNames)
            cField = condNames{c};
            markers = condMarkers.(cField);
            try
                EEGc = pop_epoch(EEG, markers, epochWin, 'newname', [subject '_' cField]);
            catch
                fprintf('  %s: no epochs, skipping\n', condLabelForDisplay(cField));
                continue
            end

            for ch = 1:numel(targetChans)
                if isnan(chIdxAll(ch)), continue; end
                chData = squeeze(EEGc.data(chIdxAll(ch), :, :));
                if isvector(chData), chData = chData(:); end

                fs = EEGc.srate;
                times = EEGc.times / 1000;

                bIdxTime = times >= baselineWin(1) & times <= baselineWin(2);
                pIdxTime = times >= postWin(1) & times <= postWin(2);

                winLen = min(sum(bIdxTime), round(0.2*fs));
                if winLen < 8, continue; end

                nEp = size(chData,2);
                basePow = nan(nEp,1); postPow = nan(nEp,1);
                baseCtrlPow = nan(nEp,1); postCtrlPow = nan(nEp,1);
                for e = 1:nEp
                    segB = chData(bIdxTime, e);
                    segP = chData(pIdxTime, e);
                    [pxxB, fB] = pwelch(segB, hann(min(winLen,numel(segB))), [], [], fs);
                    [pxxP, fP] = pwelch(segP, hann(min(winLen,numel(segP))), [], [], fs);
                    bib = fB >= betaBand(1) & fB <= betaBand(2);
                    bip = fP >= betaBand(1) & fP <= betaBand(2);
                    cib = fB >= controlBand(1) & fB <= controlBand(2);
                    cip = fP >= controlBand(1) & fP <= controlBand(2);
                    basePow(e) = mean(pxxB(bib));
                    postPow(e) = mean(pxxP(bip));
                    baseCtrlPow(e) = mean(pxxB(cib));
                    postCtrlPow(e) = mean(pxxP(cip));
                end

                validE = ~isnan(basePow) & ~isnan(postPow) & basePow > 0;
                meanBase = mean(basePow(validE));
                meanPost = mean(postPow(validE));
                meanBaseCtrl = mean(baseCtrlPow(validE));
                meanPostCtrl = mean(postCtrlPow(validE));
                erd = (meanPost - meanBase) / meanBase * 100;

                results = [results; table({subject}, {condLabelForDisplay(cField)}, {targetChans{ch}}, ...
                    sum(validE), meanBase, meanPost, erd, meanBaseCtrl, meanPostCtrl, ...
                    'VariableNames', {'subject','condition','channel','nEpochs','baselinePower','postPower','ERD_pct','baselineControlPower','postControlPower'})]; %#ok<AGROW>
            end
        end
        fprintf('  [TIME] epoch+ERD: %.1f min\n', toc(t)/60);

        writetable(results, outFile);
        fprintf('  [TIME] TOTAL for %s: %.1f min\n', subject, toc(t_subj)/60);
    catch ME
        fprintf('  [FAILED] %s: %s\n', subject, ME.message);
    end
end

fprintf('\nDone. Saved -> %s\n', outFile);

function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end
