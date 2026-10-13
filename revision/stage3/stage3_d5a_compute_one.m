function stage3_d5a_compute_one(params, outFile)
%STAGE3_D5A_COMPUTE_ONE  Residual test of D5 fallback (a) for one recording (S3a-D5a-test), as a runner
%   job function. The same pipeline steps and MEASURE as stage3_d5b_compute_one (S3a-D5b), with the
%   CleanLine step replaced by option (a) of S3a-D5-opt: four FIR band-stop filters in cascade,
%   pop_eegfiltnew(EEG, 'locutoff', f0-a, 'hicutoff', f0+a, 'revfilt', 1) for f0 = 50, 100, 150, 200 Hz,
%   applied at 500 Hz after resampling (firfilt filters each raw segment separately).
%   params: subject, task, role, notchA (band edges f0 +/- notchA Hz; REQUIRED, S3a-D5a-width: 3), plus rawRoot,
%   manifest, blockTable (common); optional groupSize (default 16).
%   Per channel group: pop_loadbv -> D4e block extents as events -> high-pass 0.5 Hz at 1000 Hz (D4a) ->
%   pop_resample to 500 Hz (D4c) -> MEASURE BEFORE -> (a) -> MEASURE AFTER.
%   Rule inputs: stage3_d5b_rules (identical to (b)): per kept channel and f0, chunk-averaged excess
%   after, its quantiles over the kept cells (C1 uses q95), and the flank-level change (R-b2).
%   Also stored: the four kernels' orders and transition widths, the cascade gain on the f0 +/- 3 Hz grid
%   (freqz), and whether the R-b2 flank band (1.5 <= |f - f0| <= 3 Hz) overlaps a notch transition band.
%   OUTCOME-BLIND: only the f0 +/- 3 Hz grid is computed (asserted). The filtered data are not saved.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
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
assert(isfield(params, 'notchA') && isscalar(params.notchA) && params.notchA > 0, 'params.notchA is required');
notchA = double(params.notchA);
gs = 16; if isfield(params, 'groupSize') && ~isempty(params.groupSize), gs = double(params.groupSize); end
groups = arrayfun(@(g) g:min(g + gs - 1, nCh), 1:gs:nCh, 'uni', 0);
bk = B(B.subject == s & B.task == task, :);
assert(height(bk) >= 1 && all(bk.status ~= "STOP_START_OUTSIDE_DATA" & bk.status ~= "STOP_STIMULI_AFTER_RAW_BOUNDARY"));

% ---- per channel group ----------------------------------------------------------------------
label = strings(nCh, 1);
avgB = nan(nCh, numel(F)); avgA = avgB; chunkExcA = []; nChunk = []; chunkStarts = []; kern = {};
for gi = 1:numel(groups)
    chans = groups{gi};
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
        EEG.event(end+1).type = 'd5a_bs'; EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
        EEG.event(end+1).type = 'd5a_be'; EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG = pop_eegfiltnew(EEG, 'locutoff', S.hpEdge);       % D4a, at fsRaw
    EEG = pop_resample(EEG, S.fsOut);                      % D4c
    typ = {EEG.event.type};
    bs = ceil([EEG.event(strcmp(typ, 'd5a_bs')).latency]);
    be = floor([EEG.event(strcmp(typ, 'd5a_be')).latency]);
    assert(numel(bs) == height(bk) && numel(be) == height(bk) && all(be > bs));
    starts = [];
    for k = 1:numel(bs), starts = [starts, bs(k):N:(be(k) - N + 1)]; end %#ok<AGROW>
    [pB, ~] = measure(double(EEG.data), starts);
    kg = cell(1, 4);
    for j = 1:4                                            % option (a): four band-stop filters in cascade
        [EEG, ~, kg{j}] = pop_eegfiltnew(EEG, 'locutoff', f0s(j) - notchA, 'hicutoff', f0s(j) + notchA, 'revfilt', 1);
    end
    if isempty(kern), kern = kg; else, assert(isequal(kern, kg), 'notch kernels differ between groups'); end
    [pA, excChunkA] = measure(double(EEG.data), starts);
    label(chans) = lab;
    avgB(chans, :) = pB; avgA(chans, :) = pA;
    chunkExcA(chans, :, 1:numel(starts)) = excChunkA; %#ok<AGROW>
    nChunk(end+1) = numel(starts); %#ok<AGROW>
    if isempty(chunkStarts), chunkStarts = starts; else, assert(isequal(chunkStarts, starts)); end
    clear EEG
end
assert(all(nChunk == nChunk(1)) && nChunk(1) >= 1, 'chunk count differs between groups or is zero');

% ---- notch design facts (from the kernels actually applied) ----------------------------------
order = cellfun(@numel, kern) - 1;
df = 3.3 ./ order * S.fsOut;                               % Hamming transition width (pop_eegfiltnew.m)
casc = 1; for j = 1:4, casc = conv(casc, kern{j}); end
gainDb = 20 * log10(abs(freqz(casc, 1, F, S.fsOut)));      % f0 +/- 3 Hz grid only
trans = [max(notchA - df, 0); notchA * ones(1, 4)];       % transition band: notchA - df <= |f - f0| <= notchA
flankInTransition = any(trans(1, :) < 3 - 1e-9 & trans(2, :) > 1.5 + 1e-9);   % overlaps the flank band 1.5-3 Hz
notch = struct('a', notchA, 'transitionBandHz', trans, 'order', order, 'transitionWidthHz', df, 'cascadeGainDbOnGrid', gainDb, ...
    'flankBandHz', [1.5 3], 'flankInTransition', flankInTransition, ...
    'flankGainDbRange', [min(gainDb(repmat(flank, 1, 4))) max(gainDb(repmat(flank, 1, 4)))]);

% ---- rule inputs (identical to (b)) -----------------------------------------------------------
res = stage3_d5b_rules(avgB, avgA, chunkExcA, label);
res.subject = string(s); res.task = string(task); res.role = string(params.role);
res.F = F; res.f0s = f0s; res.avgPBefore = avgB; res.avgPAfter = avgA; res.nChunk = nChunk(1);
res.chunkStarts = chunkStarts; res.notch = notch;
save(outFile, 'res');
q = res.afterCellQuantilesDb;
fprintf('%s %s: %d chunks; q95 after %.3f dB (C1 %d); max %.2f dB; R-b2 %d (max |flank change| %.3f dB); flank in transition %d\n', ...
    s, task, nChunk(1), q(3), q(3) < 3, res.maxExcessAfterKeptDb, res.rb2Pass, res.maxAbsFlankChangeKeptDb, flankInTransition);

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
