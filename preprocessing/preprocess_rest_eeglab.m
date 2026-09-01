% ============================================================================
%  Automated resting-state preprocessing  —  Nencki-Symfonia / IBF-IBB project
%  EEGLAB pipeline
% ============================================================================
%
%  PURPOSE
%     Mirror of the MNE pipeline. Produces clean, average-referenced data ready
%     for pwelch + 1/f detrending + findpeaks beta-peak extraction (IBF/IBB).
%
%  DESIGN PHILOSOPHY
%     Fully scripted and identical across subjects, BUT each subject saves QC
%     figures (PSD + flagged ICs) that you inspect before trusting the result.
%     For a turnkey GUI-driven version of this same logic, AUTOMAGIC wraps these
%     steps (clean_rawdata + ICLabel) and rates each file Good / OK / Bad.
%
%  BETA-BAND CAUTION
%     EMG is broadband above ~20 Hz = right on top of the beta peak. ICLabel
%     muscle flagging + the QC PSD check are critical so you don't extract a
%     false beta peak from residual muscle activity.
%
%  REQUIRED PLUGINS
%     bva-io (pop_loadbv), clean_rawdata (ASR), ICLabel, firfilt, CleanLine
%
%  USAGE
%     Edit the CONFIG block, then run this script with EEGLAB on the path.
% ============================================================================

clear; clc;

% ---------------------------------------------------------------- CONFIG -----
cfg.bidsRoot   = fullfile(pwd, 'raw_data', 'ds004621');   % <-- EDIT: dataset path     % folder containing sub-XX/
cfg.derivRoot  = fullfile(pwd, 'derivatives');   % <-- EDIT: output folder    % output folder
cfg.taskLabel  = 'rest';                          % filename token for rest run

cfg.allSubjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
cfg.exclude     = {'sub-09', 'sub-15'};           % flagged for exclusion
cfg.subjects    = setdiff(cfg.allSubjects, cfg.exclude, 'stable');

cfg.lineFreq    = 50;        % Poland mains (Warsaw recording)
cfg.hpFreq      = 0.1;       % high-pass (ERP-safe compromise)
cfg.lpFreq      = 100;       % low-pass
cfg.icaHpFreq   = 1.0;       % high-pass used ONLY to fit ICA
cfg.resampleHz  = 500;       % downsample target ([] to skip)

% ICLabel: reject component if its top class is here AND prob >= threshold.
% Class order: 1 Brain | 2 Muscle | 3 Eye | 4 Heart | 5 LineNoise | 6 ChanNoise | 7 Other
cfg.icThresh = [0 0;      ... % Brain      : never reject
                0.80 1;   ... % Muscle     : reject if p>=0.80
                0.80 1;   ... % Eye        : reject if p>=0.80
                0.80 1;   ... % Heart
                0.80 1;   ... % Line noise
                0.80 1;   ... % Channel noise
                0 0];         % Other      : keep

cfg.epochLen = 2.0;          % seconds (fixed-length, for PSD)

% Start EEGLAB (headless)
[ALLEEG, EEG, CURRENTSET] = eeglab; %#ok<ASGLU>
if ~exist(cfg.derivRoot, 'dir'); mkdir(cfg.derivRoot); end


% ================================================================= BATCH =====
failures = {};
for s = 1:numel(cfg.subjects)
    subject = cfg.subjects{s};
    fprintf('\n%s\n  %s\n%s\n', repmat('=',1,60), subject, repmat('=',1,60));
    try
        preprocess_subject(subject, cfg);
    catch ME
        failures{end+1, 1} = subject; %#ok<SAGROW>
        failures{end,   2} = ME.message;
        fprintf('  [FAILED] %s: %s\n', subject, ME.message);
    end
end

fprintf('\n%s\nSUMMARY\n', repmat('=',1,60));
fprintf('  processed : %d/%d\n', numel(cfg.subjects)-size(failures,1), numel(cfg.subjects));
fprintf('  excluded  : %s\n', strjoin(cfg.exclude, ', '));
if ~isempty(failures)
    for i = 1:size(failures,1)
        fprintf('     %s: %s\n', failures{i,1}, failures{i,2});
    end
end


% ====================================================== PER-SUBJECT FUNCTION =
function preprocess_subject(subject, cfg)

    outDir = fullfile(cfg.derivRoot, subject);
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    % ------------------------------------------------------------- 1. LOAD
    % Adjust pattern to match the dataset's actual file naming.
    hits = dir(fullfile(cfg.bidsRoot, subject, '**', ['*' cfg.taskLabel '*.vhdr']));
    assert(~isempty(hits), 'No .vhdr found for %s', subject);
    EEG = pop_loadbv(hits(1).folder, hits(1).name);
    EEG.setname = [subject '_' cfg.taskLabel];

    % --------------------------------------------------------- 2. CHANLOCS
    % Use locations from the dataset if present; otherwise look up a template.
    % VERIFY the template matches the Nencki-Symfonia 128-ch cap.
    if isempty(EEG.chanlocs(1).X)
        EEG = pop_chanedit(EEG, 'lookup', ...
            'standard-10-5-cap385.elp');   % ships with the dipfit plugin
    end

    % --------------------------------------------------- 3. LINE + BANDPASS
    % CleanLine removes mains without the spectral notch-hole a band-stop leaves.
    EEG = pop_cleanline(EEG, 'linefrequencies', [cfg.lineFreq cfg.lineFreq*2], ...
                        'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
    EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.hpFreq);   % high-pass
    EEG = pop_eegfiltnew(EEG, 'hicutoff', cfg.lpFreq);   % low-pass

    % ----------------------------------------------------------- 4. RESAMPLE
    if ~isempty(cfg.resampleHz) && EEG.srate > cfg.resampleHz
        EEG = pop_resample(EEG, cfg.resampleHz);
    end

    EEG_full = EEG;   % keep a full-rank copy for figures

    % ----------------------------- 5. BAD CHANNELS + BURSTS (clean_rawdata)
    % ASR repairs transient high-amplitude bursts and removes flat/noisy chans.
    % 'BurstCriterion' 20 is standard; tighten to 10-15 if EMG is heavy.
    EEG = clean_rawdata(EEG, 5, -1, 0.8, 4, 20, 0.25);
    EEG = pop_interp(EEG, EEG_full.chanlocs, 'spherical');  % restore channel count

    % --------------------------------------------------- 6. AVERAGE REFERENCE
    EEG = pop_reref(EEG, []);

    % ------------------------------------------------------------- 7. ICA
    % Fit on a 1 Hz high-passed copy (slow drift destabilises ICA), then copy
    % the resulting weights onto the 0.1 Hz data we keep.
    EEG_ica = pop_eegfiltnew(EEG, 'locutoff', cfg.icaHpFreq);
    EEG_ica = pop_runica(EEG_ica, 'icatype', 'runica', 'extended', 1, ...
                         'pca', EEG_ica.nbchan - 1);  % rank-safe after avg ref

    % transplant decomposition onto the 0.1 Hz dataset
    EEG.icaweights  = EEG_ica.icaweights;
    EEG.icasphere   = EEG_ica.icasphere;
    EEG.icawinv     = EEG_ica.icawinv;
    EEG.icachansind = EEG_ica.icachansind;
    EEG = eeg_checkset(EEG, 'ica');

    % automatic labelling + flagging
    EEG = iclabel(EEG);
    EEG = pop_icflag(EEG, cfg.icThresh);
    rejIC = find(EEG.reject.gcompreject);
    fprintf('  [ICA] flagged %d components: %s\n', numel(rejIC), mat2str(rejIC'));

    % QC figure: the flagged components (audit muscle calls by eye)
    if ~isempty(rejIC)
        pop_viewprops(EEG, 0, rejIC');   % 0 = ICA components view
        saveas(gcf, fullfile(outDir, [subject '_flagged_ICs.png'])); close(gcf);
    end

    EEG = pop_subcomp(EEG, rejIC, 0);   % remove flagged components

    % ----------------------------------------------- 8. FIXED-LENGTH EPOCHS
    EEG = eeg_regepochs(EEG, 'recurrence', cfg.epochLen, ...
                        'limits', [0 cfg.epochLen], 'rmbase', NaN);

    % --------------------------------------------------------- 9. QC FIGURE
    % Final PSD = most diagnostic plot here. Eyeball that a plausible beta peak
    % survives and no broadband EMG ramp remains.
    figure('visible', 'off');
    pop_spectopo(EEG, 1, [], 'EEG', 'freqrange', [1 45], 'percent', 50);
    saveas(gcf, fullfile(outDir, [subject '_final_PSD.png'])); close(gcf);

    % ------------------------------------------------------------ 10. SAVE
    EEG = eeg_checkset(EEG);
    pop_saveset(EEG, 'filename', [subject '_' cfg.taskLabel '_clean.set'], ...
                'filepath', outDir);
    fprintf('  [done] outputs in %s\n', outDir);
end
