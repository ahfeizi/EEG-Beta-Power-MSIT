% ============================================================================
%  DIAGNOSTIC  —  resolve the exclusion question for flagged subjects
%  Nencki-Symfonia / IBF-IBB project  |  EEGLAB
% ============================================================================
%
%  PURPOSE
%     The triage scan showed sub-09 and sub-15 as CLEAN (robustAmp ~92 / ~156),
%     contradicting the earlier manual flag (>30,000 uV, inconsistent peak freq).
%     This script tests the two competing concerns directly, with NO ICA / NO
%     cleaning, so we see the genuine state of the data before deciding.
%
%  TEST 1 — "Was the big amplitude just drift?"
%     Measures robust amplitude on RAW vs 0.1 Hz HP vs 1 Hz HP.
%       raw >> 0.1Hz ~ 1Hz   -> it was sub-0.1 Hz drift (harmless; HP removes it)
%       raw ~ 0.1Hz >> 1Hz   -> drift sits in 0.1-1 Hz (MATTERS: pipeline uses 0.1)
%       raw ~ 0.1Hz ~ 1Hz    -> not drift; genuinely high-amplitude signal
%     Plus a time-series snapshot so you can SEE drift vs noise.
%
%  TEST 2 — "Is the beta peak frequency inconsistent across channels?"
%     Per-channel pwelch -> log-log 1/f detrend -> findpeaks in beta band.
%     A genuine individual beta clusters tightly across channels (low spread).
%     Scattered peak frequencies / few channels with any peak = concern confirmed.
%
%  A clean reference subject (sub-08) is included for visual contrast.
%
%  REQUIRED PLUGINS:  bva-io, firfilt, dipfit (for chan lookup), ICLabel not needed
% ============================================================================

clear; clc;

% ---------------------------------------------------------------- CONFIG -----
cfg.bidsRoot  = fullfile(pwd, 'raw_data', 'ds004621');   % <-- EDIT: path to the downloaded OpenNeuro ds004621 dataset
cfg.outDir    = fullfile(pwd, 'derivatives');   % <-- EDIT if needed
cfg.taskLabel = 'rest';

% the two flagged subjects + one clean reference (from triage: sub-08 was cleanest)
cfg.subjects  = {'sub-09', 'sub-15', 'sub-08'};
cfg.refSubject = 'sub-08';      % labelled as reference in output

cfg.lineFreq   = 50;
cfg.lpFreq     = 100;
cfg.resampleHz = 500;
cfg.betaBand   = [13 30];
cfg.fitRange   = [2 40];        % range for 1/f log-log fit
cfg.epochLen   = 2.0;          % pwelch window length (s)
cfg.snippetSec = 10;           % seconds of time-series to plot
cfg.snippetCh  = 12;           % how many channels in the time-series plot

% rule-of-thumb thresholds for INTERPRETATION (not hard decisions)
cfg.spreadOKHz   = 2.0;        % std of per-channel peak freq below this = consistent
cfg.minPctPeak   = 60;         % at least this % of channels should show a beta peak

% ----------------------------------------------------------------------------
[ALLEEG, EEG, CURRENTSET] = eeglab; %#ok<ASGLU>
if ~exist(cfg.outDir, 'dir'); mkdir(cfg.outDir); end

for i = 1:numel(cfg.subjects)
    diagnose_subject(cfg.subjects{i}, cfg);
end

fprintf('\n%s\nINTERPRETATION GUIDE\n%s\n', repmat('=',1,60), repmat('=',1,60));
fprintf([ ...
 ' TEST 1 (drift): compare robustAmp across raw / 0.1Hz / 1Hz.\n' ...
 '   If raw is huge but 0.1Hz is small -> the old >30k flag was drift. Safe.\n' ...
 '   If 0.1Hz is still large but 1Hz is small -> drift in 0.1-1Hz; the REAL\n' ...
 '   pipeline (0.1 HP) will carry it. Watch closely or raise HP for these subs.\n\n' ...
 ' TEST 2 (consistency): compare the flagged subjects'' peak-freq spread &\n' ...
 '   %%-channels-with-peak against the reference (sub-08).\n' ...
 '   Spread < %.1f Hz and >%d%% channels with a peak = consistent (keep).\n' ...
 '   Wide spread / few peaks vs the reference = original concern confirmed.\n'], ...
 cfg.spreadOKHz, cfg.minPctPeak);


% ====================================================== PER-SUBJECT =========
function diagnose_subject(subject, cfg)
    isRef = strcmp(subject, cfg.refSubject);
    tag = subject; if isRef, tag = [subject ' (REFERENCE)']; end
    fprintf('\n%s\n  %s\n%s\n', repmat('=',1,60), tag, repmat('=',1,60));

    % --- load ------------------------------------------------------------------
    hits = dir(fullfile(cfg.bidsRoot, subject, '**', ['*' cfg.taskLabel '*.vhdr']));
    assert(~isempty(hits), 'No .vhdr for %s', subject);
    EEGraw = pop_loadbv(hits(1).folder, hits(1).name);

    % --- channel selection (robust) -------------------------------------------
    % This BrainVision export does NOT tag channels with a 'EEG' type, so
    % pop_select(...,'chantype','EEG') matches nothing and strips all channels.
    % Instead keep everything and drop only channels with known non-EEG labels.
    nonEEG = {'EOG','VEOG','HEOG','IEOG','SEOG','ECG','EKG','EMG','GSR', ...
              'RESP','STATUS','TRIGGER','MARKER'};
    labels  = upper({EEGraw.chanlocs.labels});
    dropIdx = find(ismember(labels, nonEEG));
    if ~isempty(dropIdx)
        fprintf('  dropping %d non-EEG channel(s): %s\n', numel(dropIdx), ...
                strjoin({EEGraw.chanlocs(dropIdx).labels}, ' '));
        EEGraw = pop_select(EEGraw, 'nochannel', dropIdx);
    end
    assert(EEGraw.nbchan > 0, 'No channels left after selection for %s', subject);
    fprintf('  channels kept: %d\n', EEGraw.nbchan);

    % --- channel locations ----------------------------------------------------
    if ~isfield(EEGraw.chanlocs, 'X') || isempty(EEGraw.chanlocs(1).X)
        EEGraw = pop_chanedit(EEGraw, 'lookup', 'standard-10-5-cap385.elp');
    end

    % ================= TEST 1: drift =========================================
    EEG01 = pop_eegfiltnew(EEGraw, 'locutoff', 0.1);   % matches real pipeline
    EEG1  = pop_eegfiltnew(EEGraw, 'locutoff', 1.0);   % aggressive (like triage)

    ampRaw = prctile(abs(double(EEGraw.data(:))), 99.9);
    amp01  = prctile(abs(double(EEG01.data(:))),  99.9);
    amp1   = prctile(abs(double(EEG1.data(:))),   99.9);
    fprintf('  [Test1 drift] robustAmp(99.9%%):  raw=%8.0f  0.1Hz=%7.0f  1Hz=%7.0f uV\n', ...
            ampRaw, amp01, amp1);
    if     ampRaw > 5*amp01 && amp01 < 2*amp1
        verdict1 = 'sub-0.1Hz DRIFT -> harmless, HP removes it';
    elseif amp01  > 2*amp1
        verdict1 = 'drift in 0.1-1Hz -> WILL reach the 0.1Hz pipeline';
    else
        verdict1 = 'NOT drift -> genuinely high-amplitude signal';
    end
    fprintf('     verdict: %s\n', verdict1);

    % time-series snapshot: raw vs 0.1 Hz (see drift vs noise with your eyes)
    nCh = min(cfg.snippetCh, EEGraw.nbchan);
    nS  = round(cfg.snippetSec * EEGraw.srate);
    s0  = max(1, round(EEGraw.pnts/2) - round(nS/2));
    idx = s0:(s0+nS-1);
    t   = (0:nS-1)/EEGraw.srate;
    offsets = (1:nCh)' * 6 * median(prctile(abs(double(EEG01.data(1:nCh,:))),95,2));

    f1 = figure('visible','off','position',[100 100 1100 600]);
    subplot(1,2,1); plot(t, double(EEGraw.data(1:nCh,idx))' + offsets', 'k'); 
        title('RAW (unfiltered)'); xlabel('s'); set(gca,'ytick',[]); axis tight;
    subplot(1,2,2); plot(t, double(EEG01.data(1:nCh,idx))' + offsets', 'b'); 
        title('0.1 Hz high-pass'); xlabel('s'); set(gca,'ytick',[]); axis tight;
    sgtitle(sprintf('%s — time series (%d channels)', tag, nCh));
    saveas(f1, fullfile(cfg.outDir, [subject '_T1_timeseries.png'])); close(f1);

    % per-channel amplitude at 0.1 Hz (is it global, or a few bad channels?)
    ampCh = prctile(abs(double(EEG01.data)), 99.9, 2);
    f2 = figure('visible','off');
    topoplot(ampCh, EEG01.chanlocs, 'electrodes','on'); colorbar;
    title(sprintf('%s — per-channel robustAmp @0.1Hz (uV)', tag));
    saveas(f2, fullfile(cfg.outDir, [subject '_T1_ampTopo.png'])); close(f2);

    % ================= TEST 2: peak-frequency consistency ===================
    % use the 0.1Hz data, finish the pipeline-style cleaning of mains+LP+resample,
    % but deliberately NO ICA (we want the raw spectral picture per channel).
    EEG = pop_cleanline(EEG01, 'linefrequencies', [cfg.lineFreq cfg.lineFreq*2], ...
                        'bandwidth', 2, 'computepower', 0, 'normSpectrum', 0);
    EEG = pop_eegfiltnew(EEG, 'hicutoff', cfg.lpFreq);
    if EEG.srate > cfg.resampleHz, EEG = pop_resample(EEG, cfg.resampleHz); end
    EEG = pop_reref(EEG, []);

    fs  = EEG.srate;
    win = round(cfg.epochLen * fs);
    [pxx, f] = pwelch(double(EEG.data)', hann(win), round(win/2), win, fs); % freq x chan

    sel = f >= cfg.fitRange(1) & f <= cfg.fitRange(2) & f > 0;
    fsel = f(sel);
    bIdx = fsel >= cfg.betaBand(1) & fsel <= cfg.betaBand(2);
    fb   = fsel(bIdx);

    nch = size(pxx,2);
    peakFreq = nan(nch,1);
    for c = 1:nch
        ly  = log10(pxx(sel,c));
        p   = polyfit(log10(fsel), ly, 1);
        det = ly - polyval(p, log10(fsel));         % 1/f-detrended residual
        [pk, loc] = findpeaks(det(bIdx), 'SortStr','descend', 'NPeaks',1);
        if ~isempty(pk), peakFreq(c) = fb(loc(1)); end
    end

    valid   = ~isnan(peakFreq);
    pctPeak = 100 * sum(valid) / nch;
    meanF   = mean(peakFreq(valid));
    stdF    = std(peakFreq(valid));
    fprintf('  [Test2 consistency] channels with beta peak: %.0f%%  (%d/%d)\n', ...
            pctPeak, sum(valid), nch);
    fprintf('     peak freq across channels: mean=%.2f  std=%.2f  range=[%.1f %.1f] Hz\n', ...
            meanF, stdF, min(peakFreq(valid)), max(peakFreq(valid)));
    if pctPeak >= cfg.minPctPeak && stdF <= cfg.spreadOKHz
        verdict2 = 'CONSISTENT -> beta peak is spatially coherent (keep)';
    else
        verdict2 = 'INCONSISTENT -> original concern supported (consider exclude)';
    end
    fprintf('     verdict: %s\n', verdict2);

    % butterfly of all-channel detrended spectra (do channels agree?)
    f3 = figure('visible','off','position',[100 100 1100 450]);
    subplot(1,3,1);
        loglog(f, pxx); hold on; xline(cfg.betaBand,'--k');
        xlim([1 45]); xlabel('Hz'); ylabel('PSD'); title('all-channel PSD (log-log)');
    subplot(1,3,2);
        histogram(peakFreq(valid), cfg.betaBand(1):0.5:cfg.betaBand(2));
        xlabel('beta peak freq (Hz)'); ylabel('# channels');
        title(sprintf('peak-freq spread (std=%.2f Hz)', stdF));
    subplot(1,3,3);
        pf = peakFreq; noPk = find(~valid); pf(noPk) = meanF;  % fill for surface
        topoplot(pf, EEG.chanlocs, 'maplimits', cfg.betaBand, ...
                 'electrodes','on', 'emarker2', {noPk, 'x', 'w', 6});
        colorbar; title('peak freq topo (x = no peak)');
    sgtitle(sprintf('%s — beta peak consistency', tag));
    saveas(f3, fullfile(cfg.outDir, [subject '_T2_consistency.png'])); close(f3);

    fprintf('  figures -> %s\n', cfg.outDir);
end
