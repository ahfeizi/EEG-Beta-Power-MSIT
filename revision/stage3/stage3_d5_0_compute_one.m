function stage3_d5_0_compute_one(params, outFile)
%STAGE3_D5_0_COMPUTE_ONE  D5-0 line-noise diagnostic for one recording (S3a-D5-0), in function form
%   for the A/B runner (S3a-INF-1 §10). Job function: stage3_d5_0_compute_one(params, outFile).
%   params: subject, task (e.g. 'sub-06', 'msit'), rawRoot (the verified raw copy), manifest
%   (verified_manifest.tsv), blockTable (<outRoot>/stage3/d4e_block_clipping.csv).
%   The arithmetic is copied unchanged from stage3_d5_0_line_noise.m: lines 26-40 (grid, window,
%   DFT matrix) and 52-105 (one recording); linePeaks is stage3_d5_0_linepeaks.m (since S3a-D5-0-amend2 with a guarded refinement; before that a verbatim copy of
%   the script's local function), numChannels is the script's local function. Changes: no loop
%   and no cache check, raw files checked against the manifest before reading, output to outFile.
%   Equivalence with the script on synthetic data: revision/stage3/test_stage3_d5_0_compute_one.m.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
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

B = readtable(params.blockTable, 'TextType', 'string');
assert(all(B.status ~= "STOP_START_OUTSIDE_DATA" & B.status ~= "STOP_STIMULI_AFTER_RAW_BOUNDARY"));
s = char(params.subject); task = char(params.task);
P.bidsRoot = char(params.rawRoot);
% every raw file this job reads, checked against the verified manifest before any read (S3a-INF-1 §1)
vh = fullfile(P.bidsRoot, s, 'eeg', [s '_task-' task '_eeg.vhdr']);
stage3_check_input(vh, P.bidsRoot, params.manifest);
txt = fileread(vh);
for key = ["DataFile", "MarkerFile"]
    tok = regexp(txt, "^" + key + "=([^\r\n]+)", 'tokens', 'once', 'lineanchors');
    stage3_check_input(fullfile(P.bidsRoot, s, 'eeg', strtrim(tok{1})), P.bidsRoot, params.manifest);
end
stage3_check_input(fullfile(P.bidsRoot, s, 'eeg', [s '_task-' task '_channels.tsv']), P.bidsRoot, params.manifest);

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
        [exc(:, :, c), fpk(:, :, c), amp(:, :, c)] = stage3_d5_0_linepeaks(Pc', F, d, f0s, flank, pkwin);
    end
    res.label(chans) = lab;
    res.avgP(chans, :) = sumP / nC;
    res.exc(chans, :, 1:nC) = exc; res.fpk(chans, :, 1:nC) = fpk; res.amp(chans, :, 1:nC) = amp;
    nChunk(end+1) = nC; %#ok<AGROW>
    clear EEG
end
assert(all(nChunk == nChunk(1)));
save(outFile, 'res', 'F', 'd', 'f0s', 'nChunk');
fprintf('%s %s: %d chunks, %.0f s\n', s, task, nChunk(1), toc(t0));
end

function n = numChannels(vhdr)
txt = fileread(vhdr);
tok = regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once');
n = str2double(tok{1});
end
