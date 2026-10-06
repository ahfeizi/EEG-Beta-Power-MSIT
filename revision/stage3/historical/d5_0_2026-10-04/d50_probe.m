function d50_probe(rec, mode)
% Crash bisection for the D5-0 heap corruption. Mirrors stage3_d5_0_line_noise.m step by step,
% stopping after the stage named by MODE. Writes nothing to the results.
%   load     : pop_loadbv per 16-channel group only
%   loadevt  : + insert block events, eeg_checkset eventconsistency
%   resample : + pop_resample
%   nostim   : as resample, but all non-boundary, non-block events removed before resampling
%   nodft    : full without the DFT product
%   synth    : random data, same shapes, detrend + DFT product only (no EEG, no EEGLAB data)
%   full     : + chunking, detrend, Hann, DFT at the line grid (as in D5-0), results discarded
here = 'C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\github\eeg-beta-project\revision\stage3';
addpath(here, fileparts(fileparts(here)));
P = get_paths(); S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
parts = split(string(rec), "_"); s = char(parts(1)); task = char(parts(2));
B = readtable(fullfile(P.outRoot, 'stage3', 'd4e_block_clipping.csv'), 'TextType', 'string');
bk = B(B.subject == s & B.task == task, :);
eegDir = fullfile(P.bidsRoot, s, 'eeg'); hdr = [s '_task-' task '_eeg.vhdr'];
txt = fileread(fullfile(eegDir, hdr)); nCh = str2double(regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once'));
f0s = [50 100 150 200]; d = (-30:30) / 10; F = reshape(f0s + d', 1, []);
N = 10 * S.fsOut; w = hann(N); E = exp(-1i * 2 * pi * (0:N-1)' * F / S.fsOut);
t0 = tic;
if strcmp(mode, 'synth')        % no EEG, no EEGLAB data path: same shapes and the same number of products
    rng(1);
    for g = 1:8
        for c = 1:97
            x = randn(N, 16) * 50;
            x = detrend(x) .* w;
            Pc = abs(E.' * x).^2; %#ok<NASGU>
        end
    end
    fprintf('PROBE_DONE %s %s %.0f s\n', rec, mode, toc(t0)); return
end
for g = 1:16:nCh
    chans = g:min(g + 15, nCh);
    EEG = pop_loadbv(eegDir, hdr, [], chans);
    if strcmp(mode, 'load'), clear EEG; continue; end
    if isfield(EEG.event, 'urevent'), EEG.event = rmfield(EEG.event, 'urevent'); end
    EEG.urevent = [];
    if strcmp(mode, 'nostim')
        EEG.event = EEG.event(strcmp({EEG.event.type}, 'boundary'));
    end
    for k = 1:height(bk)
        EEG.event(end+1).type = 'd50_bs'; EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
        EEG.event(end+1).type = 'd50_be'; EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    if strcmp(mode, 'loadevt'), clear EEG; continue; end
    EEG = pop_resample(EEG, S.fsOut);
    if any(strcmp(mode, {'resample', 'nostim'})), clear EEG; continue; end
    typ = {EEG.event.type};
    bs = ceil([EEG.event(strcmp(typ, 'd50_bs')).latency]); be = floor([EEG.event(strcmp(typ, 'd50_be')).latency]);
    starts = [];
    for k = 1:numel(bs), starts = [starts, bs(k):N:(be(k) - N + 1)]; end %#ok<AGROW>
    for c = 1:numel(starts)
        x = double(EEG.data(:, starts(c):starts(c) + N - 1))';
        x = detrend(x) .* w;
        if ~strcmp(mode, 'nodft'), Pc = abs(E.' * x).^2; end %#ok<NASGU>
    end
    clear EEG
end
fprintf('PROBE_DONE %s %s %.0f s\n', rec, mode, toc(t0));
end
