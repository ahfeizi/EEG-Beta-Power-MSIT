%% Stage 3a / decision S3a-D5-0: outcome-blind line-noise diagnostic (50/100/150/200 Hz)
% Rule, measures and outputs: docs/decision_log.md, entry S3a-D5-0 (logged before this script ran).
% Reading the binary .eeg files is approved for this diagnostic only.
%
% OUTCOME-BLIND: spectra are evaluated ONLY at f0-3 ... f0+3 Hz (0.1 Hz steps) by a direct DFT at
% exactly those frequencies. Nothing in 13-30 Hz or 55-95 Hz is computed, saved or printed
% (asserted below).
%
% Per recording: load 16 channels at a time with pop_loadbv (memory), insert the D4e block
% start/end as events, resample to 500 Hz with pop_resample (boundaries respected), cut each
% clipped block into non-overlapping 10 s chunks, detrend and Hann-window each chunk, and measure
% the line peak above a straight-line floor fitted to the flanks (1.5 <= |f-f0| <= 3 Hz).
% Usage: run from MATLAB; optional variable `onlyRecordings` (cellstr like {'sub-01_rest'}) limits
% the run (used for the first test). Results per recording are cached in <out>/per_recording/.

here = fileparts(mfilename('fullpath'));
addpath(here, fileparts(fileparts(here)));                 % this folder + repository root
P = get_paths();
S = stage3_params();
outDir = fullfile(P.outRoot, 'stage3', 'd5_0');
cacheDir = fullfile(outDir, 'per_recording');
if ~exist(cacheDir, 'dir'), mkdir(cacheDir); end
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end

% ---- frequency grid and the outcome-blind assertion ------------------------------------------
f0s = [50 100 150 200];
d = (-30:30) / 10;                                         % offsets from f0 (Hz), 0.1 Hz steps
F = reshape(f0s + d', 1, []);                              % 244 frequencies, grouped by f0 (61 each)
assert(~any(F >= 13 & F <= 30) && ~any(F >= 55 & F <= 95), 'outcome-blind: forbidden band in grid');
assert(all(F < S.fsOut / 2), 'a line frequency is not below the Nyquist frequency');
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;         % floor-fit bins
pkwin = find(abs(d) <= 0.5 + 1e-9);                        % peak-search bins
chunkLen = 10;                                             % s
provisionalLabels = ["sub-13", "sub-41", "sub-42"];       % S3a-D5-0-exc: .vhdr labels, D5-0 only
detDb = 6;                                                 % dB, "detected" chunk for drift
N = chunkLen * S.fsOut;
w = hann(N);
nn = (0:N-1)';
E = exp(-1i * 2 * pi * nn * F / S.fsOut);                  % N x 244 DFT matrix at the grid only
psdScale = 2 / (S.fsOut * sum(w .^ 2));                    % one-sided PSD (uV^2/Hz)

% ---- inputs ---------------------------------------------------------------------------------
B = readtable(fullfile(P.outRoot, 'stage3', 'd4e_block_clipping.csv'), 'TextType', 'string');
assert(all(B.status ~= "STOP_START_OUTSIDE_DATA" & B.status ~= "STOP_STIMULI_AFTER_RAW_BOUNDARY"));
recs = unique(B.subject + "_" + B.task, 'stable');
if exist('onlyRecordings', 'var') && ~isempty(onlyRecordings), recs = string(onlyRecordings(:)); end

for r = 1:numel(recs)
    parts = split(recs(r), "_"); s = char(parts(1)); task = char(parts(2));
    cacheFile = fullfile(cacheDir, [s '_' task '.mat']);
    if exist(cacheFile, 'file'), fprintf('%s %s: cached\n', s, task); continue; end
    t0 = tic;
    eegDir = fullfile(P.bidsRoot, s, 'eeg');
    hdr = [s '_task-' task '_eeg.vhdr'];
    nCh = numChannels(fullfile(eegDir, hdr));
    ct = readtable(fullfile(eegDir, [s '_task-' task '_channels.tsv']), 'FileType', 'text', ...
                   'Delimiter', '\t', 'TextType', 'string');
    assert(height(ct) == nCh, 'channels.tsv and .vhdr disagree on the channel count');
    bk = B(B.subject == s & B.task == task, :);
    groups = 1:16:nCh;
    res = struct('label', strings(nCh, 1), 'avgP', nan(nCh, numel(F)), 'exc', [], 'fpk', [], 'amp', []);
    nChunk = [];
    for g = groups
        chans = g:min(g + 15, nCh);
        EEG = pop_loadbv(eegDir, hdr, [], chans);
        lab = string({EEG.chanlocs.labels});
        if ismember(string(s), provisionalLabels)            % S3a-D5-0-exc: keep .vhdr order, flag rows
            assert(all(ismember(lab, ct.name)), 'a .vhdr label is not in channels.tsv');
        else
            assert(isequal(lab(:), ct.name(chans)), 'channel labels differ from channels.tsv');
        end
        % block extents as events (raw sample = onset * 1000, the pop_loadbv latency convention)
        if isfield(EEG.event, 'urevent'), EEG.event = rmfield(EEG.event, 'urevent'); end
        EEG.urevent = [];
        for k = 1:height(bk)
            EEG.event(end+1).type = 'd50_bs'; EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
            EEG.event(end+1).type = 'd50_be'; EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
        end
        EEG = eeg_checkset(EEG, 'eventconsistency');
        EEG = pop_resample(EEG, S.fsOut);
        typ = {EEG.event.type};
        bs = ceil([EEG.event(strcmp(typ, 'd50_bs')).latency]);
        be = floor([EEG.event(strcmp(typ, 'd50_be')).latency]);
        assert(numel(bs) == height(bk) && numel(be) == height(bk) && all(be > bs));
        % chunks: non-overlapping 10 s inside each clipped block
        starts = [];
        for k = 1:numel(bs)
            starts = [starts, bs(k):N:(be(k) - N + 1)]; %#ok<AGROW>
        end
        nC = numel(starts); nG = numel(chans);
        exc = nan(nG, 4, nC); fpk = nan(nG, 4, nC); amp = nan(nG, 4, nC); sumP = zeros(nG, numel(F));
        for c = 1:nC
            x = double(EEG.data(:, starts(c):starts(c) + N - 1))';   % N x channels
            x = detrend(x) .* w;                                     % linear detrend, Hann
            Pc = psdScale * abs(E.' * x).^2;                         % 244 x channels
            sumP = sumP + Pc';
            [exc(:, :, c), fpk(:, :, c), amp(:, :, c)] = linePeaks(Pc', F, d, f0s, flank, pkwin);
        end
        res.label(chans) = lab;
        res.avgP(chans, :) = sumP / nC;
        res.exc(chans, :, 1:nC) = exc; res.fpk(chans, :, 1:nC) = fpk; res.amp(chans, :, 1:nC) = amp;
        nChunk(end+1) = nC; %#ok<AGROW>
        clear EEG
    end
    assert(all(nChunk == nChunk(1)));
    save(cacheFile, 'res', 'F', 'd', 'f0s', 'nChunk');
    fprintf('%s %s: %d chunks, %.0f s\n', s, task, nChunk(1), toc(t0));
end

% ---- assemble (only when every recording is cached) ----------------------------------------
if exist('onlyRecordings', 'var') && ~isempty(onlyRecordings), return; end
rowsC = {}; rowsR = {};
for r = 1:numel(recs)
    parts = split(recs(r), "_"); s = parts(1); task = parts(2);
    L = load(fullfile(cacheDir, char(s + "_" + task + ".mat")));
    R = L.res; nCh = numel(R.label);
    [excA, fpkA] = linePeaks(R.avgP, F, d, f0s, flank, pkwin);      % chunk-averaged PSD
    kept = ~ismember(R.label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
    prov = double(ismember(s, provisionalLabels));          % S3a-D5-0-exc flag
    for j = 1:4
        e = squeeze(R.exc(:, j, :)); fp = squeeze(R.fpk(:, j, :)); a = squeeze(R.amp(:, j, :));
        det = e >= detDb;
        fpD = fp; fpD(~det) = NaN;
        nDet = sum(det, 2);
        fsd = std(fpD, 0, 2, 'omitnan'); frg = max(fpD, [], 2) - min(fpD, [], 2);
        fsd(nDet < 2) = NaN; frg(nDet < 2) = NaN;
        off = max(abs(fpD - f0s(j)), [], 2);                 % NaN if no detected chunk
        cv = std(a, 0, 2) ./ mean(a, 2);
        T = table(repmat(s, nCh, 1), repmat(task, nCh, 1), R.label, double(kept), repmat(f0s(j), nCh, 1), ...
            repmat(size(e, 2), nCh, 1), nDet, excA(:, j), fpkA(:, j), median(e, 2), max(e, [], 2), cv, ...
            fsd, frg, off, repmat(prov, nCh, 1), 'VariableNames', {'subject', 'task', 'channel', 'kept', 'f0', 'n_chunks', ...
            'n_chunks_det6db', 'excess_db', 'peak_freq_hz', 'chunk_excess_median_db', 'chunk_excess_max_db', ...
            'amp_cv', 'freq_sd_det_hz', 'freq_range_det_hz', 'max_abs_offset_det_hz', 'labels_provisional'});
        rowsC{end+1} = T; %#ok<AGROW>
        k = kept;
        rowsR{end+1} = table(s, task, f0s(j), sum(k), median(excA(k, j)), max(excA(k, j)), ...
            sum(excA(k, j) >= 3), median(cv(k), 'omitnan'), max(frg(k)), max(off(k)), ...
            max(excA(~k, j)), prov, 'VariableNames', {'subject', 'task', 'f0', 'n_kept_channels', ...
            'excess_db_median_kept', 'excess_db_max_kept', 'n_kept_excess_ge3db', 'amp_cv_median_kept', ...
            'freq_range_det_max_kept_hz', 'max_abs_offset_det_kept_hz', 'excess_db_max_tp9_tp10', 'labels_provisional'}); %#ok<AGROW>
    end
end
TC = vertcat(rowsC{:}); TR = vertcat(rowsR{:});
writetable(TC, fullfile(outDir, 'line_noise_by_channel.csv'));
writetable(TR, fullfile(outDir, 'line_noise_by_recording.csv'));

% ---- decision rules R1-R3 (S3a-D5-0) -------------------------------------------------------
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w');
out = @(varargin) [fprintf(varargin{:}), fprintf(fid, varargin{:})];
out('S3a-D5-0 run finished %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md');
for id = ["S3a-D5-0", "S3a-D5-opt", "S3a-INF-1"]                % S3a-D5-0-amend1: exact heading locator
    out('SHA-256 of the %s log entry as read by this script: %s\n', id, stage3_log_entry(logFile, char(id)));
end
out('Recordings: %d; chunk %d s; grid f0 +/- 3 Hz in 0.1 Hz steps\n', numel(recs), chunkLen);
[p, q] = rat(S.fsOut / S.fsRaw, 1e-12);
m = pop_firwsord('kaiser', 2, 0.2 / max([p q]), 0.002);
bAA = firws(m, 0.9 / max([p q]), windows('kaiser', m + 1, 5));
fg = [147 150 153 197 200 203];
out('Anti-aliasing gain (pop_resample design, dB): %s\n', ...
    strjoin(arrayfun(@(f, v) sprintf('%g Hz %.3f', f, v), fg, 20 * log10(abs(freqz(bAA, 1, fg, p * S.fsRaw))), 'uni', 0), ', '));
for j = 1:4
    k = TC.kept == 1 & TC.f0 == f0s(j);
    mx = max(TC.excess_db(k));
    out('R1 %3d Hz: max excess over all kept channels x recordings = %.2f dB -> %s\n', f0s(j), mx, ...
        ternary(mx < 3, 'ABSENT', 'present'));
end
sev = groupsummary(TR, {'subject', 'task'}, 'max', 'excess_db_median_kept');
sev = sortrows(sev, 'max_excess_db_median_kept', 'descend');
out('R2 severity S = max over f0 of median kept-channel excess; ranking (top 10):\n');
for i = 1:min(10, height(sev))
    out('  %2d. %s %s  S = %.2f dB\n', i, sev.subject(i), sev.task(i), sev.max_excess_db_median_kept(i));
end
off = TC.max_abs_offset_det_hz(TC.kept == 1);
out('R3 largest |peak - f0| in any detected chunk (kept channels): %.3f Hz -> %s\n', max(off), ...
    ternary(max(off) > 0.5, 'RE-EXAMINE notch width', 'within 0.5 Hz'));
fclose(fid);

% =================================================================================================
function [exc, fpk, amp] = linePeaks(Pw, F, d, f0s, flank, pkwin)
% Pw: channels x 244 PSD. Per f0: straight-line floor (dB vs Hz) on the flank bins, peak excess
% within +/-0.5 Hz, parabolic peak frequency, and line amplitude sqrt(max(P - floor, 0)).
nCh = size(Pw, 1); exc = nan(nCh, 4); fpk = nan(nCh, 4); amp = nan(nCh, 4);
for j = 1:4
    idx = (j - 1) * 61 + (1:61);
    Ld = 10 * log10(Pw(:, idx));                               % channels x 61
    A = [ones(sum(flank), 1), d(flank)'];
    beta = A \ Ld(:, flank)';                                  % 2 x channels
    fl = [ones(61, 1), d'] * beta;                             % 61 x channels
    ex = Ld - fl';
    [mx, ii] = max(ex(:, pkwin), [], 2);
    i0 = pkwin(ii)';
    lin = sub2ind(size(Ld), (1:nCh)', i0);
    ym = Ld(lin - nCh); y0 = Ld(lin); yp = Ld(lin + nCh);      % neighbours (columns i0-1, i0+1)
    den = ym - 2 * y0 + yp;
    delta = 0.5 * (ym - yp) ./ den; delta(den == 0) = 0;
    exc(:, j) = mx;
    fpk(:, j) = F(idx(i0))' + delta * 0.1;
    flPk = fl(sub2ind(size(fl), i0, (1:nCh)'));                % floor (dB) at the peak bin
    amp(:, j) = sqrt(max(Pw(sub2ind(size(Pw), (1:nCh)', idx(i0)')) - 10 .^ (flPk / 10), 0));
end
end

function n = numChannels(vhdr)
txt = fileread(vhdr);
tok = regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once');
n = str2double(tok{1});
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
