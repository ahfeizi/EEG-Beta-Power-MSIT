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
%  REQUIRED PLUGINS:  bva-io, clean_rawdata, ICLabel, firfilt, dipfit
%                     (CleanLine optional — falls back to a band-stop notch)
%                     (Picard optional — falls back to runica if not installed)
%
%  NOTES FROM DIAGNOSTICS (already folded into this script):
%   - Channels are NOT tagged 'EEG' in these files, so we drop non-EEG by LABEL.
%   - Two ear-reference channels (TP9/TP10) have no coordinates; they are dropped
%     so RANSAC / interpolation / ICA work. Analysis runs on the scalp channels.
%   - NO subjects are excluded: the >30,000 uV "amplitude problem" was dataset-
%     wide sub-0.1 Hz drift (even the cleanest subject showed it) and vanishes
%     after the 0.1 Hz high-pass.
%   - runica (extended infomax) took ~975-1045 min for a single subject at full
%     PCA dimensionality (nbchan-1). Component count is kept UNCHANGED per
%     project decision. Instead, this version prefers the Picard ICA algorithm
%     (much faster convergence, similar quality) and falls back to runica
%     automatically if the Picard plugin isn't installed.
%   - Fixed: the qc-save line was previously misplaced inside run_batch (after
%     the loop, referencing an out-of-scope outDir/subject/q). It now lives at
%     the end of preprocess_subject, where those variables are actually valid.
%   - Fixed: pop_viewprops is now only called if the plugin is actually on the
%     path (guarded with exist(...,'file')), instead of relying on catching an
%     "Undefined function" error.
% ============================================================================

clear; clc;

% ============================ RUN MODE ======================================
RUN_MODE = 'full';     % <-- 'triage' | 'pilot' | 'full'
% ============================================================================


% ---------------------------------------------------------------- CONFIG -----
cfg.bidsRoot   = fullfile(pwd, 'raw_data', 'ds004621');   % <-- EDIT: path to the downloaded OpenNeuro ds004621 dataset    % folder containing sub-XX/
cfg.derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder % output folder
cfg.taskLabel  = 'rest';                                                    % filename token for rest run


cfg.allSubjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
cfg.exclude     = {};   % none — the amplitude "problem" was dataset-wide drift

% --- pilot picks --------------------------------------------------------------
% Spans the triage quality range (dirty -> clean) PLUS the two subjects that
% were once flagged, to confirm they now process cleanly like everyone else.
cfg.pilotSubjects = {'sub-17', 'sub-20', 'sub-08', 'sub-09', 'sub-15'};
% cfg.pilotSubjects = {'sub-08'};

% --- filtering ----------------------------------------------------------------
cfg.lineFreq    = 50;        % Poland mains (Warsaw recording)
cfg.hpFreq      = 0.1;       % high-pass (ERP-safe compromise)
cfg.lpFreq      = 100;       % low-pass
cfg.icaHpFreq   = 1.0;       % high-pass used ONLY to fit ICA
cfg.resampleHz  = 500;       % downsample target ([] to skip)

% --- ICA algorithm -------------------------------------------------------------
% Component count (PCA dimensionality) is left UNCHANGED (nbchan-1), per
% project decision. Picard is tried first for speed; runica is the fallback.
cfg.icaPreferPicard = true;

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
[ALLEEG, EEG, CURRENTSET] = eeglab; 
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
            hits = dir(fullfile(cfg.bidsRoot, subject, '**', ['*' cfg.taskLabel '*.vhdr']));
            assert(~isempty(hits), 'no .vhdr');

            t_load = tic;
            EEG = pop_loadbv(hits(1).folder, hits(1).name);
            fprintf('  [TIME] loadbv: %.1f min\n', toc(t_load)/60);

            EEG = prep_channels(EEG, false);              % drop non-EEG by label
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
            q = preprocess_subject(subject, cfg);
            if isempty(qc)
                qc = q;
            else
                qc(end+1) = q;
            end
        catch ME
            failures{end+1,1} = subject; failures{end,2} = ME.message;
            fprintf('%s\n', getReport(ME, 'extended'));
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
    t_load = tic;
    EEG = pop_loadbv(hits(1).folder, hits(1).name);
    fprintf('  [TIME] loadbv: %.1f min\n', toc(t_load)/60);
    EEG.setname = [subject '_' cfg.taskLabel];

    % --- 2. CHANNELS + LOCATIONS ----------------------------------------------
    % Drop non-EEG channels by label, look up coordinates, and drop any channel
    % that still has no location (TP9/TP10 ear refs) so RANSAC/interp/ICA work.
    EEG = prep_channels(EEG, true);
    % montage QC figure (positions sanity check) — first run especially
    figure('visible','off'); topoplot([], EEG.chanlocs, 'style','blank', ...
        'electrodes','labelpoint');
    saveas(gcf, fullfile(outDir, [subject '_montage.png'])); close(gcf);

    % --- 3. LINE NOISE + BANDPASS ---------------------------------------------
    if exist('pop_cleanline', 'file')
        EEG = pop_cleanline(EEG, 'linefrequencies', [cfg.lineFreq cfg.lineFreq*2], ...
                            'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
    else
        EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.lineFreq-2, ...
                             'hicutoff', cfg.lineFreq+2, 'revfilt', 1);  % band-stop
    end
    EEG = pop_eegfiltnew(EEG, 'locutoff', cfg.hpFreq);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', cfg.lpFreq);

    % --- 4. RESAMPLE -----------------------------------------------------------
    if ~isempty(cfg.resampleHz) && EEG.srate > cfg.resampleHz
        EEG = pop_resample(EEG, cfg.resampleHz);
    end
    chanlocsFull = EEG.chanlocs;          % remember full set for interpolation

    % --- 5. BAD CHANNELS + ASR -------------------------------------------------
    nbefore = EEG.nbchan;
    t_asr = tic;
    EEG = pop_clean_rawdata(EEG, ...
        'FlatlineCriterion', 5, ...
        'ChannelCriterion',  cfg.chanCriterion, ...
        'LineNoiseCriterion',4, ...
        'Highpass',          'off', ...
        'BurstCriterion',    cfg.burstCriterion, ...
        'WindowCriterion',   'off', ...
        'BurstRejection',    'off', ...
        'Distance',          'Euclidian');
    fprintf('  [TIME] clean_rawdata: %.1f min\n', toc(t_asr)/60);
    nRemoved = nbefore - EEG.nbchan;
    badChanNames = setdiff({chanlocsFull.labels}, {EEG.chanlocs.labels});

    t_interp = tic;
    EEG = pop_interp(EEG, chanlocsFull, 'spherical');   % restore channel count
    fprintf('  [TIME] interp: %.1f min\n', toc(t_interp)/60);

    % --- 6. AVERAGE REFERENCE --------------------------------------------------
    EEG = pop_reref(EEG, []);

    % --- 7. ICA (fit on 1 Hz copy, transplant onto 0.1 Hz data) ---------------
    t_ica = tic;
    EEG_ica = pop_eegfiltnew(EEG, 'locutoff', cfg.icaHpFreq);
    fprintf('  [TIME] ica-highpass: %.1f min\n', toc(t_ica)/60);

    usePicard = cfg.icaPreferPicard && (exist('picard', 'file') || exist('pop_runica_picard', 'file'));
    t_runica = tic;
    if usePicard
        fprintf('  [ICA] using Picard (pca dimensionality unchanged: %d)\n', EEG_ica.nbchan - 1);
        EEG_ica = pop_runica(EEG_ica, 'icatype', 'picard', ...
                             'pca', EEG_ica.nbchan - 1);
    else
        if cfg.icaPreferPicard
            fprintf('  [ICA] Picard plugin not found, falling back to runica (pca unchanged: %d)\n', ...
                EEG_ica.nbchan - 1);
        end
        EEG_ica = pop_runica(EEG_ica, 'icatype', 'runica', 'extended', 1, ...
                             'pca', EEG_ica.nbchan - 1);
    end
    fprintf('  [TIME] ica (%s): %.1f min\n', ternary(usePicard,'picard','runica'), toc(t_runica)/60);

    EEG.icaweights  = EEG_ica.icaweights;
    EEG.icasphere   = EEG_ica.icasphere;
    EEG.icawinv     = EEG_ica.icawinv;
    EEG.icachansind = EEG_ica.icachansind;
    EEG = eeg_checkset(EEG, 'ica');

    t_iclabel = tic;
    EEG = iclabel(EEG);
    EEG = pop_icflag(EEG, cfg.icThresh);
    fprintf('  [TIME] iclabel+icflag: %.1f min\n', toc(t_iclabel)/60);
    classes = EEG.etc.ic_classification.ICLabel.classifications;
    [~, top] = max(classes, [], 2);
    rejIC   = find(EEG.reject.gcompreject);
    nMuscle = sum(ismember(rejIC, find(top==2)));
    nEye    = sum(ismember(rejIC, find(top==3)));
    nHeart  = sum(ismember(rejIC, find(top==4)));

    if ~isempty(rejIC)
        t_viewprops = tic;
        if exist('pop_viewprops', 'file')
            origVis = get(0, 'DefaultFigureVisible');
            set(0, 'DefaultFigureVisible', 'off');
            try
                pop_viewprops(EEG, 0, rejIC');
                h = gcf;
                saveas(h, fullfile(outDir, [subject '_flagged_ICs.png']));
                close(h);
            catch ME
                fprintf('  [WARN] pop_viewprops failed for %s: %s\n', subject, ME.message);
            end
            set(0, 'DefaultFigureVisible', origVis);
        else
            fprintf('  [WARN] pop_viewprops plugin not on path, skipping flagged-IC figure\n');
        end
        fprintf('  [TIME] pop_viewprops: %.1f min\n', toc(t_viewprops)/60);
    end

    EEG = pop_subcomp(EEG, rejIC, 0);

    % --- 8. QC BETA-PEAK INDICATOR (on continuous, cleaned data) --------------
    t_qc = tic;
    [betaFound, betaHz, betaBW, figPSD] = beta_peak_qc(EEG, cfg);
    fprintf('  [TIME] beta_peak_qc: %.1f min\n', toc(t_qc)/60);
    saveas(figPSD, fullfile(outDir, [subject '_QC_PSD.png'])); close(figPSD);

    % --- 9. EPOCH + SAVE -------------------------------------------------------
    t_epoch = tic;
    EEG = eeg_regepochs(EEG, 'recurrence', cfg.epochLen, ...
                        'limits', [0 cfg.epochLen], 'rmbase', NaN);
    EEG = eeg_checkset(EEG);
    pop_saveset(EEG, 'filename', [subject '_' cfg.taskLabel '_clean.set'], ...
                'filepath', outDir);
    fprintf('  [TIME] epoch+save: %.1f min\n', toc(t_epoch)/60);

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
    q.betaBW = round(betaBW, 2);
    fprintf('  badChan=%d  ICrej=%d (musc=%d eye=%d)  betaPeak=%d @ %.1f Hz\n', ...
        nRemoved, numel(rejIC), nMuscle, nEye, betaFound, betaHz);

    save(fullfile(outDir, [subject '_qc.mat']), 'q');
end


% ============================== QC: quick beta-peak check ====================
% Mirrors your established method (pwelch -> log-log 1/f detrend -> findpeaks).
% This is a QC INDICATOR ONLY, averaged over channels — not the final feature
% extraction (which uses your supervisor-chosen electrodes).
function [found, peakHz, bw, fig] = beta_peak_qc(EEG, cfg)
    data = double(EEG.data);
    fs   = EEG.srate;
    win  = round(cfg.epochLen * fs);
    ov   = round(win * cfg.pweOverlap/100);

    [pxx, f] = pwelch(data', hann(win), ov, win, fs);
    psd = mean(pxx, 2);

    % --- aperiodic fit with an optional knee (nonlinear, not just a line) ---
    sel = f >= cfg.fitRange(1) & f <= cfg.fitRange(2) & f > 0;
    fx  = f(sel);  py = psd(sel);

    % model: log10(P) = b - log10(k + f^chi)   (knee model)
    ap_model = @(p, x) p(1) - log10(p(2) + x.^p(3));
    p0 = [log10(py(1)), 1, 1];   % offset, knee, exponent
    opts = optimset('Display','off');
    p_fit = lsqcurvefit(ap_model, p0, fx, log10(py), ...
                        [-Inf 0 0], [Inf Inf 6], opts);
    detr = log10(py) - ap_model(p_fit, fx);   % residual above the (curved) aperiodic fit

    % --- search for a beta peak with a REAL local max (not edge-of-band) ---
    bIdx = fx >= cfg.betaBand(1) & fx <= cfg.betaBand(2);
    bf   = fx(bIdx);  bd = detr(bIdx);

    [pks, locs, widths] = findpeaks(bd, bf, 'SortStr','descend', 'NPeaks',3, ...
                                     'WidthReference','halfheight');

    found = false; peakHz = NaN; bw = NaN;
    for k = 1:numel(pks)
        idxPk = locs(k) == bf;
        isEdge = (bf(idxPk) <= cfg.betaBand(1)+1) || (bf(idxPk) >= cfg.betaBand(2)-1);
        if ~isEdge && pks(k) > 0.02   % must clear a minimum height AND not sit on the boundary
            found = true; peakHz = locs(k); bw = widths(k);
            break
        end
    end

    fig = figure('visible','off');
    subplot(1,2,1); loglog(f, psd); grid on; xlabel('Hz'); ylabel('PSD'); title('PSD (log-log)');
    subplot(1,2,2); plot(fx, detr); grid on; hold on;
        xline(cfg.betaBand(1),'--'); xline(cfg.betaBand(2),'--');
        if found, plot(peakHz, interp1(fx,detr,peakHz), 'rv', 'MarkerFaceColor','r'); end
        xlabel('Hz'); ylabel('residual (knee-corrected)'); title('knee-corrected (beta band marked)');
end
% small inline helper
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end


% ====================== channel selection / locations =======================
% These BrainVision files do not tag channels with a 'EEG' type, so selecting
% by chantype strips everything. Instead drop non-EEG channels by LABEL.
% When doMontage=true, also look up coordinates and drop channels that still
% lack a location (e.g. TP9/TP10 ear references) so RANSAC, spherical
% interpolation and ICA — all of which need positions — work correctly.
function EEG = prep_channels(EEG, doMontage)
    nonEEG = {'EOG','VEOG','HEOG','IEOG','SEOG','ECG','EKG','EMG','GSR', ...
              'RESP','STATUS','TRIGGER','MARKER'};
    labels  = upper({EEG.chanlocs.labels});
    dropIdx = find(ismember(labels, nonEEG));
    if ~isempty(dropIdx)
        EEG = pop_select(EEG, 'nochannel', dropIdx);
    end

    if doMontage
        if ~isfield(EEG.chanlocs,'X') || isempty(EEG.chanlocs(1).X)
            EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
        end
        noLoc = find(cellfun(@isempty, {EEG.chanlocs.X}));
        if ~isempty(noLoc)
            fprintf('  dropping %d channel(s) without coordinates: %s\n', ...
                    numel(noLoc), strjoin({EEG.chanlocs(noLoc).labels}, ' '));
            EEG = pop_select(EEG, 'nochannel', noLoc);
        end
    end
    assert(EEG.nbchan > 0, 'no channels left after selection');
    EEG = eeg_checkset(EEG);
end