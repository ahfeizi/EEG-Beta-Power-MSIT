function stage3_d5b_compute_one(params, outFile)
%STAGE3_D5B_COMPUTE_ONE  D5 option (b) residual test for one recording (S3a-D5-opt "Residual criterion
%   for (b)"; implementation S3a-D5b), as a runner job function.
%   params: subject, task, role, plus rawRoot, manifest, blockTable (common).
%   Per 16-channel group: pop_loadbv -> D4e block extents as events -> high-pass 0.5 Hz at 1000 Hz
%   (D4a, pop_eegfiltnew) -> pop_resample to 500 Hz (D4c order) -> MEASURE BEFORE -> CleanLine 2.1 new
%   implementation (cleanLineNoise) on each raw segment, parameters of S3a-D5-opt (b) -> MEASURE AFTER.
%   Segment rules (S3a-D5-opt): a segment shorter than one 4 s window is not processed and must not
%   overlap a block (asserted).
%   MEASURE = the D5-0 measure: non-overlapping 10 s chunks inside the clipped blocks, linear detrend,
%   Hann, one-sided PSD by a direct DFT at f0 +/- 3 Hz (0.1 Hz), straight-line floor on
%   1.5 <= |f - f0| <= 3 Hz, excess = max over |f - f0| <= 0.5 Hz (stage3_d5_0_linepeaks).
%   Rule inputs per kept channel (TP9/TP10 excluded) and f0:
%     R-b1: chunk-averaged excess after (b) < 3 dB;
%     R-b2: |change of the mean PSD over the flank bins, after vs before| <= 0.5 dB (dB of the mean
%           of the chunk-averaged PSD over the flank bins).
%   OUTCOME-BLIND: only the f0 +/- 3 Hz grid is computed (asserted). cleanLineNoise computes its own
%   multitaper spectra internally; they are not saved, printed or inspected. The cleaned data are not saved.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
assert(exist('cleanLineNoise', 'file') == 2, 'CleanLine 2.1 (cleanLineNoise) not on the path');
s = char(params.subject); task = char(params.task);
f0s = [50 100 150 200];
d = (-30:30) / 10;
F = reshape(f0s + d', 1, []);
assert(~any(F >= 13 & F <= 30) && ~any(F >= 55 & F <= 95), 'outcome-blind: forbidden band in grid');
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pkwin = find(abs(d) <= 0.5 + 1e-9);
provisionalLabels = ["sub-13", "sub-41", "sub-42"];       % S3a-D5-0-exc (none is in the test set)
N = 10 * S.fsOut; w = hann(N);
E = exp(-1i * 2 * pi * (0:N-1)' * F / S.fsOut);
psdScale = 2 / (S.fsOut * sum(w .^ 2));
ln = struct('lineNoiseMethod', 'clean', 'lineNoiseChannels', [], 'Fs', S.fsOut, ...
    'lineFrequencies', [50 100 150 200], 'p', 0.01, 'fScanBandWidth', 2, 'taperBandWidth', 2, ...
    'taperWindowSize', 4, 'taperWindowStep', 1, 'tau', 100, 'pad', 2, 'fPassBand', [0 S.fsOut / 2], ...
    'maximumIterations', 10);                              % S3a-D5-opt (b): cleanline.m new-path defaults + F_L
winS = ln.taperWindowSize * S.fsOut;

% ---- inputs ---------------------------------------------------------------------------------
B = readtable(char(params.blockTable), 'TextType', 'string');
rawRoot = char(params.rawRoot);
eegDir = fullfile(rawRoot, s, 'eeg'); hdr = [s '_task-' task '_eeg.vhdr'];
vh = fullfile(eegDir, hdr);
stage3_check_input(vh, rawRoot, params.manifest);
txt = fileread(vh);
for key = ["DataFile", "MarkerFile"]
    tok = regexp(txt, "^" + key + "=([^\r\n]+)", 'tokens', 'once', 'lineanchors');
    stage3_check_input(fullfile(eegDir, strtrim(tok{1})), rawRoot, params.manifest);
end
ctFile = fullfile(eegDir, [s '_task-' task '_channels.tsv']);
stage3_check_input(ctFile, rawRoot, params.manifest);
ct = readtable(ctFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
tok = regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once'); nCh = str2double(tok{1});
assert(height(ct) == nCh, 'channels.tsv and .vhdr disagree on the channel count');
bk = B(B.subject == s & B.task == task, :);
assert(height(bk) >= 1 && all(bk.status ~= "STOP_START_OUTSIDE_DATA" & bk.status ~= "STOP_STIMULI_AFTER_RAW_BOUNDARY"));

% ---- per channel group ----------------------------------------------------------------------
label = strings(nCh, 1);
avgB = nan(nCh, numel(F)); avgA = avgB; chunkExcA = []; segInfo = []; nChunk = [];
for g = 1:16:nCh
    chans = g:min(g + 15, nCh); nG = numel(chans);
    EEG = pop_loadbv(eegDir, hdr, [], chans);
    lab = string({EEG.chanlocs.labels});
    if ismember(string(s), provisionalLabels)
        assert(all(ismember(lab, ct.name)), 'a .vhdr label is not in channels.tsv');
    else
        assert(isequal(lab(:), ct.name(chans)), 'channel labels differ from channels.tsv');
    end
    if isfield(EEG.event, 'urevent'), EEG.event = rmfield(EEG.event, 'urevent'); end
    EEG.urevent = [];
    for k = 1:height(bk)
        EEG.event(end+1).type = 'd5b_bs'; EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
        EEG.event(end+1).type = 'd5b_be'; EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG = pop_eegfiltnew(EEG, 'locutoff', S.hpEdge);       % D4a, at fsRaw
    EEG = pop_resample(EEG, S.fsOut);                      % D4c
    typ = {EEG.event.type};
    bs = ceil([EEG.event(strcmp(typ, 'd5b_bs')).latency]);
    be = floor([EEG.event(strcmp(typ, 'd5b_be')).latency]);
    assert(numel(bs) == height(bk) && numel(be) == height(bk) && all(be > bs));
    % raw segments: boundary latency = first sample of the new segment (S3a-D4e-4 boundary check)
    bl = [EEG.event(strcmp(typ, 'boundary')).latency];
    bl = bl(bl > 1);
    assert(all(abs(bl - round(bl)) < 1e-6), 'non-integer boundary latency');
    segStart = unique([1, round(bl)]);
    segEnd = [segStart(2:end) - 1, EEG.pnts];
    proc = (segEnd - segStart + 1) >= winS;
    for k = find(~proc)                                    % short segment: not processed, must not overlap a block
        assert(~any(bs <= segEnd(k) & be >= segStart(k)), 'stage3:d5b', 'segment %d (%d samples) is shorter than one window and overlaps a block', k, segEnd(k) - segStart(k) + 1);
    end
    starts = [];
    for k = 1:numel(bs), starts = [starts, bs(k):N:(be(k) - N + 1)]; end %#ok<AGROW>
    X = double(EEG.data);
    [pB, ~] = measure(X, starts);
    for k = find(proc)
        sig = struct('data', X(:, segStart(k):segEnd(k)), 'srate', S.fsOut);
        lnk = ln; lnk.lineNoiseChannels = 1:nG;
        sig = cleanLineNoise(sig, lnk);
        X(:, segStart(k):segEnd(k)) = sig.data;
    end
    [pA, excChunkA] = measure(X, starts);
    label(chans) = lab;
    avgB(chans, :) = pB; avgA(chans, :) = pA;
    chunkExcA(chans, :, 1:numel(starts)) = excChunkA; %#ok<AGROW>
    if isempty(segInfo), segInfo = [segStart(:), segEnd(:), double(proc(:))]; else, assert(isequal(segInfo, [segStart(:), segEnd(:), double(proc(:))])); end
    nChunk(end+1) = numel(starts); %#ok<AGROW>
    clear EEG X
end
assert(all(nChunk == nChunk(1)) && nChunk(1) >= 1, 'chunk count differs between groups or is zero');

% ---- rule inputs ----------------------------------------------------------------------------
excB = stage3_d5_0_linepeaks(avgB, F, d, f0s, flank, pkwin);
excA = stage3_d5_0_linepeaks(avgA, F, d, f0s, flank, pkwin);
flankDbB = nan(nCh, 4); flankDbA = flankDbB;
for j = 1:4
    idx = (j - 1) * 61 + find(flank);
    flankDbB(:, j) = 10 * log10(mean(avgB(:, idx), 2));
    flankDbA(:, j) = 10 * log10(mean(avgA(:, idx), 2));
end
flankChangeDb = flankDbA - flankDbB;
kept = ~ismember(label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
chunkResMedian = median(chunkExcA, 3); chunkResMax = max(chunkExcA, [], 3);
rb1 = all(excA(kept, :) < 3, 'all');
rb2 = all(abs(flankChangeDb(kept, :)) <= 0.5, 'all');
res = struct('subject', string(s), 'task', string(task), 'role', string(params.role), 'label', label, 'kept', kept, ...
    'F', F, 'f0s', f0s, 'avgPBefore', avgB, 'avgPAfter', avgA, 'excessBeforeDb', excB, 'excessAfterDb', excA, ...
    'flankDbBefore', flankDbB, 'flankDbAfter', flankDbA, 'flankChangeDb', flankChangeDb, ...
    'chunkResidualMedianDb', chunkResMedian, 'chunkResidualMaxDb', chunkResMax, 'nChunk', nChunk(1), ...
    'segments', segInfo, 'lineNoise', ln, 'rb1Pass', rb1, 'rb2Pass', rb2, ...
    'maxExcessAfterKeptDb', max(excA(kept, :), [], 'all'), 'maxAbsFlankChangeKeptDb', max(abs(flankChangeDb(kept, :)), [], 'all'));
save(outFile, 'res');
fprintf('%s %s: %d chunks; %d segments (%d processed); R-b1 %d (max excess after %.2f dB); R-b2 %d (max |flank change| %.3f dB)\n', ...
    s, task, nChunk(1), size(segInfo, 1), sum(segInfo(:, 3)), rb1, res.maxExcessAfterKeptDb, rb2, res.maxAbsFlankChangeKeptDb);

    function [avgP, excC] = measure(Xm, st)
        nC = numel(st); sumP = zeros(size(Xm, 1), numel(F)); excC = nan(size(Xm, 1), 4, nC);
        for c = 1:nC
            x = Xm(:, st(c):st(c) + N - 1)';
            x = detrend(x) .* w;
            Pc = psdScale * abs(E.' * x) .^ 2;
            sumP = sumP + Pc';
            excC(:, :, c) = stage3_d5_0_linepeaks(Pc', F, d, f0s, flank, pkwin);
        end
        avgP = sumP / nC;
    end
end
