% ============================================================================
%  Resting-state preprocessing pipeline  —  Nencki-Symfonia / IBF-IBB project
%  EEGLAB | three-stage workflow:  TRIAGE  ->  PILOT  ->  FULL
% ============================================================================
%
%  WHY THREE STAGES (the whole point of this file)
%     Never run a fresh pipeline on all 42 subjects blind. Instead:
%
%     1) RUN_MODE = 'triage'
%        Fast amplitude scan of ALL 42 subjects (no real preprocessing).
%        Writes triage_summary.csv ranked by signal quality. Use it to PICK
%        pilot subjects that SPAN the quality range (clean / medium / dirty),
%        and to confirm the amplitude problem in your flagged subjects.
%
%     2) RUN_MODE = 'pilot'
%        Full preprocessing on a hand-picked handful. Inspect the per-subject
%        QC figures + pilot_qc_summary.csv. Tune thresholds HERE.
%        --> Then LOCK the parameters. Do not touch them again per-subject.
%
%     3) RUN_MODE = 'full'
%        Run the locked pipeline on all subjects (minus excluded). Review QC,
%        then move to feature extraction (IBF/IBB).
%
%  BETA-BAND CAUTION
%     EMG is broadband above ~20 Hz = right on top of the beta peak. Residual
%     muscle activity can create a FALSE beta peak. The QC step computes a quick
%     beta-peak indicator (log-log detrend + findpeaks) so you can sanity-check
%     each pilot subject BEFORE trusting the real feature extraction later.
%
%  REQUIRED PLUGINS:  bva-io, clean_rawdata, ICLabel, firfilt, CleanLine, dipfit
% ============================================================================

clear; clc;

% ============================ RUN MODE ======================================
RUN_MODE = 'triage';     % <-- 'triage' | 'pilot' | 'full'
% ============================================================================


% ---------------------------------------------------------------- CONFIG -----
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
cfg.bidsRoot   = P.bidsRoot;  % [path] folder containing sub-XX/ (read-only)
cfg.derivRoot  = rerunDir;    % [path] output folder
cfg.taskLabel  = 'rest';                          % filename token for rest run

cfg.allSubjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
cfg.exclude     = {'sub-09', 'sub-15'};           % flagged: >30,000 uV, unstable peaks

% --- pilot picks --------------------------------------------------------------
% Choose AFTER looking at triage_summary.csv: one clean, one dirty, one medium.
% Deliberately include a flagged subject (sub-09 / sub-15) to confirm the
% automatic pipeline reproduces your manual exclusion reasoning.
cfg.pilotSubjects = {'sub-01', 'sub-09', 'sub-20'};   % <-- edit after triage

% --- filtering ----------------------------------------------------------------
cfg.lineFreq    = 50;        % Poland mains (Warsaw recording)
cfg.hpFreq      = 0.1;       % high-pass (ERP-safe compromise)
cfg.lpFreq      = 100;       % low-pass
cfg.icaHpFreq   = 1.0;       % high-pass used ONLY to fit ICA
cfg.resampleHz  = 500;       % downsample target ([] to skip)

% --- bad channels / ASR -------------------------------------------------------
cfg.chanCriterion  = 0.80;   % min correlation a channel must reach
cfg.burstCriterion = 20;     % ASR burst SD; lower (10-15) = more aggressive
% NOTE: BurstRejection/WindowCriterion are OFF below -> ASR CORRECTS bursts in
% place instead of deleting time. Keeps data continuous = better for PSD.

% --- ICLabel ------------------------------------------------------------------
% Class order: 1 Brain | 2 Muscle | 3 Eye | 4 Heart | 5 LineNoise | 6 ChanNoise | 7 Other
cfg.icThresh = [0    0;   ... % Brain      : never reject
                0.80 1;   ... % Muscle     : reject if p>=0.80
                0.80 1;   ... % Eye
                0.80 1;   ... % Heart
                0.80 1;   ... % Line noise
                0.80 1;   ... % Channel noise
                0    0];      % Other      : keep

% --- epoching / QC beta check -------------------------------------------------
cfg.epochLen   = 2.0;        % seconds (0.5 Hz spectral resolution)
cfg.betaBand   = [13 30];    % Hz, where the QC looks for a beta peak
cfg.fitRange   = [2 40];     % Hz, range for the 1/f log-log fit (QC only)
cfg.pweOverlap = 50;         % pwelch overlap (%) for QC PSD

% --- triage threshold ---------------------------------------------------------
cfg.ampFlagUV  = 30000;      % flag subjects whose robust amplitude exceeds this


% ============================================================ DISPATCH =======
[ALLEEG, EEG, CURRENTSET] = eeglab; % ok<ASGLU>
if ~exist(cfg.derivRoot, 'dir'); mkdir(cfg.derivRoot); end

switch lower(RUN_MODE)
    case 'triage'
        run_triage(cfg);
    case 'pilot'
        run_batch(cfg.pilotSubjects, cfg, 'pilot');
    case 'full'
        subjects = setdiff(cfg.allSubjects, cfg.exclude, 'stable');
        run_batch(subjects, cfg, 'full');
    otherwise
        error('RUN_MODE must be triage | pilot | full');
end


% ============================================================================
%  STAGE 1 — TRIAGE  (fast, no real preprocessing)
% ============================================================================
function run_triage(cfg)
    fprintf('\n==== TRIAGE: scanning all %d subjects ====\n', numel(cfg.allSubjects));
    rows = struct([]);
    for i = 1:numel(cfg.allSubjects)
        subject = cfg.allSubjects{i};
        try
            hits = dir(fullfile(cfg.bidsRoot, [subject '*' cfg.taskLabel '*.vhdr']));
            assert(~isempty(hits), 'no .vhdr');
            EEG = pop_loadbv(hits(1).folder, hits(1).name);
            EEG = pop_select(EEG);%, 'chantype', 'data');
            EEG = pop_eegfiltnew(EEG, 'locutoff', 1.0);   % cheap HP to kill drift

            d = EEG.data;                                 % chan x time
            robustAmp = prctile(abs(d(:)), 99.9);         % ignores single spikes
            maxAmp    = max(abs(d(:)));
            chanRMS   = sqrt(mean(d.^2, 2));
            nLoudChan = sum(chanRMS > 5 * median(chanRMS));  % grossly noisy chans

            rows(end+1).subject   = subject;              %#ok<AGROW>
            rows(end).srate       = EEG.srate;
            rows(end).nchan       = EEG.nbchan;
            rows(end).robustAmpUV = round(robustAmp);
            rows(end).maxAmpUV    = round(maxAmp);
            rows(end).nLoudChan   = nLoudChan;
            rows(end).ampFlag     = robustAmp > cfg.ampFlagUV;
            fprintf('  %-8s  robustAmp=%8.0f uV  loudChans=%2d  %s\n', ...
                subject, robustAmp, nLoudChan, ternary(robustAmp>cfg.ampFlagUV,'<-- FLAG',''));
        catch ME
            fprintf('  %-8s  ERROR: %s\n', subject, ME.message);
        end
    end

    T = struct2table(rows);
    T = sortrows(T, 'robustAmpUV', 'descend');   % dirtiest first
    outFile = fullfile(cfg.derivRoot, 'triage_summary.csv');
    writetable(T, outFile);
    fprintf('\nTriage table -> %s\n', outFile);
    fprintf(['NEXT: open it, then pick cfg.pilotSubjects spanning the range\n' ...
             '      (top = dirty, middle = medium, bottom = clean), include a flagged one.\n']);
end


% ============================================================================
%  STAGES 2 & 3 — BATCH (full preprocessing + QC)
% ============================================================================
function run_batch(subjects, cfg, tag)
    fprintf('\n==== %s: %d subjects ====\n', upper(tag), numel(subjects));
    qc = struct([]); failures = {};
    for i = 1:numel(subjects)
        subject = subjects{i};
        fprintf('\n%s  %s\n', repmat('-',1,50), subject);
        try
            qc(end+1) = preprocess_subject(subject, cfg);   %#ok<AGROW>
        catch ME
            failures{end+1,1} = subject; failures{end,2} = ME.message; %#ok<AGROW>
            fprintf('  [FAILED] %s: %s\n', subject, ME.message);
        end
    end

    if ~isempty(qc)
        T = struct2table(qc);
        outFile = fullfile(cfg.derivRoot, sprintf('%s_qc_summary.csv', tag));
        writetable(T, outFile);
        fprintf('\nQC summary -> %s\n', outFile);
    end
    fprintf('\nprocessed %d/%d\n', numel(subjects)-size(failures,1), numel(subjects));
    for i = 1:size(failures,1)
        fprintf('  FAIL %s: %s\n', failures{i,1}, failures{i,2});
    end
    if strcmpi(tag,'pilot')
        fprintf(['\nNEXT: inspect per-subject figures + pilot_qc_summary.csv.\n' ...
                 '      Tune thresholds, then LOCK cfg and run RUN_MODE=''full''.\n']);
    end
end


% ====================================================== PER-SUBJECT FUNCTION =
function q = preprocess_subject(subject, cfg)
    outDir = fullfile(cfg.derivRoot, subject);
    if ~exist(outDir, 'dir'); mkdir(outDir); end

    % --- 1. LOAD ---------------------------------------------------------------
    hits = dir(fullfile(cfg.bidsRoot, subject, '**', ['*' cfg.taskLabel '*.vhdr']));
    assert(~isempty(hits), 'No .vhdr found for %s', subject);
    EEG = pop_loadbv(hits(1).folder, hits(1).name);
    EEG.setname = [subject '_' cfg.taskLabel];

    % --- 2. CHANNEL LOCATIONS --------------------------------------------------
    % VERIFY this template matches the 128-ch Nencki-Symfonia cap.
    if isempty(EEG.chanlocs(1).X)
        EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
    end
    % Save a montage figure for QC the FIRST time you run (sanity check positions)
    figure('visible','off'); topoplot([], EEG.chanlocs, 'style','blank', ...
        'electrodes','labelpoint','chaninfo', EEG.chaninfo);
    saveas(gcf, fullfile(outDir, [subject '_montage.png'])); close(gcf);

    % --- 3. LINE NOISE + BANDPASS ---------------------------------------------
    EEG = pop_cleanline(EEG, 'linefrequencies', [cfg.lineFreq cfg.lineFreq*2], ...
                        'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
    EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.hpFreq);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', cfg.lpFreq);

    % --- 4. RESAMPLE -----------------------------------------------------------
    if ~isempty(cfg.resampleHz) && EEG.srate > cfg.resampleHz
        EEG = pop_resample(EEG, cfg.resampleHz);
    end
    chanlocsFull = EEG.chanlocs;          % remember full set for interpolation

    % --- 5. BAD CHANNELS + ASR -------------------------------------------------
    nbefore = EEG.nbchan;
    EEG = pop_clean_rawdata(EEG, ...
        'FlatlineCriterion', 5, ...
        'ChannelCriterion',  cfg.chanCriterion, ...
        'LineNoiseCriterion',4, ...
        'Highpass',          'off', ...
        'BurstCriterion',    cfg.burstCriterion, ...
        'WindowCriterion',   'off', ...
        'BurstRejection',    'off', ...
        'Distance',          'Euclidian');
    nRemoved = nbefore - EEG.nbchan;
    badChanNames = setdiff({chanlocsFull.labels}, {EEG.chanlocs.labels});
    EEG = pop_interp(EEG, chanlocsFull, 'spherical');   % restore channel count

    % --- 6. AVERAGE REFERENCE --------------------------------------------------
    EEG = pop_reref(EEG, []);

    % --- 7. ICA (fit on 1 Hz copy, transplant onto 0.1 Hz data) ---------------
    EEG_ica = pop_eegfiltnew(EEG, 'locutoff', cfg.icaHpFreq);
    EEG_ica = pop_runica(EEG_ica, 'icatype', 'runica', 'extended', 1, ...
                         'pca', EEG_ica.nbchan - 1);
    EEG.icaweights  = EEG_ica.icaweights;
    EEG.icasphere   = EEG_ica.icasphere;
    EEG.icawinv     = EEG_ica.icawinv;
    EEG.icachansind = EEG_ica.icachansind;
    EEG = eeg_checkset(EEG, 'ica');

    EEG = iclabel(EEG);
    EEG = pop_icflag(EEG, cfg.icThresh);
    classes = EEG.etc.ic_classification.ICLabel.classifications;
    [~, top] = max(classes, [], 2);
    rejIC   = find(EEG.reject.gcompreject);
    nMuscle = sum(ismember(rejIC, find(top==2)));
    nEye    = sum(ismember(rejIC, find(top==3)));
    nHeart  = sum(ismember(rejIC, find(top==4)));

    if ~isempty(rejIC)
        pop_viewprops(EEG, 0, rejIC');
        saveas(gcf, fullfile(outDir, [subject '_flagged_ICs.png'])); close(gcf);
    end
    EEG = pop_subcomp(EEG, rejIC, 0);

    % --- 8. QC BETA-PEAK INDICATOR (on continuous, cleaned data) --------------
    [betaFound, betaHz, figPSD] = beta_peak_qc(EEG, cfg);
    saveas(figPSD, fullfile(outDir, [subject '_QC_PSD.png'])); close(figPSD);

    % --- 9. EPOCH + SAVE -------------------------------------------------------
    EEG = eeg_regepochs(EEG, 'recurrence', cfg.epochLen, ...
                        'limits', [0 cfg.epochLen], 'rmbase', NaN);
    EEG = eeg_checkset(EEG);
    pop_saveset(EEG, 'filename', [subject '_' cfg.taskLabel '_clean.set'], ...
                'filepath', outDir);

    % --- QC summary row --------------------------------------------------------
    q.subject       = subject;
    q.nBadChan      = nRemoved;
    q.badChans      = strjoin(badChanNames, ' ');
    q.nIC_removed   = numel(rejIC);
    q.nIC_muscle    = nMuscle;
    q.nIC_eye       = nEye;
    q.nIC_heart     = nHeart;
    q.nEpochs       = EEG.trials;
    q.betaPeak      = betaFound;
    q.betaPeakHz    = round(betaHz, 2);
    fprintf('  badChan=%d  ICrej=%d (musc=%d eye=%d)  betaPeak=%d @ %.1f Hz\n', ...
        nRemoved, numel(rejIC), nMuscle, nEye, betaFound, betaHz);
end


% ============================== QC: quick beta-peak check ====================
% Mirrors your established method (pwelch -> log-log 1/f detrend -> findpeaks).
% This is a QC INDICATOR ONLY, averaged over channels — not the final feature
% extraction (which uses your supervisor-chosen electrodes).
function [found, peakHz, fig] = beta_peak_qc(EEG, cfg)
    data = double(EEG.data);                 % chan x time (continuous)
    fs   = EEG.srate;
    win  = round(cfg.epochLen * fs);
    ov   = round(win * cfg.pweOverlap/100);

    [pxx, f] = pwelch(data', hann(win), ov, win, fs);   % freq x chan
    psd = mean(pxx, 2);                                  % average across channels

    % 1/f detrend in log-log space (essential for this dataset)
    sel = f >= cfg.fitRange(1) & f <= cfg.fitRange(2) & f > 0;
    lx  = log10(f(sel));  ly = log10(psd(sel));
    p   = polyfit(lx, ly, 1);
    detr = ly - polyval(p, lx);                          % residual above 1/f

    fb  = f(sel);
    bIdx = fb >= cfg.betaBand(1) & fb <= cfg.betaBand(2);
    [pks, locs] = findpeaks(detr(bIdx), 'SortStr','descend', 'NPeaks',1);
    bf = fb(bIdx);
    if isempty(pks)
        found = false; peakHz = NaN;
    else
        found = true;  peakHz = bf(locs(1));
    end

    fig = figure('visible','off');
    subplot(1,2,1); loglog(f, psd); grid on;
        xlabel('Hz'); ylabel('PSD'); title('PSD (log-log)');
    subplot(1,2,2); plot(fb, detr); grid on; hold on;
        xline(cfg.betaBand(1),'--'); xline(cfg.betaBand(2),'--');
        if found, plot(peakHz, pks(1), 'rv', 'MarkerFaceColor','r'); end
        xlabel('Hz'); ylabel('residual'); title('1/f-detrended (beta band marked)');
end


% small inline helper
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
