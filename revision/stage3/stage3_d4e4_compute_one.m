function stage3_d4e4_compute_one(params, outFile)
%STAGE3_D4E4_COMPUTE_ONE  S3a-D4e-4-test for one recording, as a runner job function
%   (S3a-D4e-4-test-approval). Job function: stage3_d4e4_compute_one(params, outFile).
%   params: subject, task, testN (true for sub-13/41/42), plus rawRoot, manifest, blockTable (common).
%   Computes per recording the statistics that the pre-registered rules need; the rules themselves
%   (test N needs rest AND MSIT+; test P's predictor-neighbour check) are applied by a later
%   assembly step from the verified outputs.
%
%   Common preparation (S3a-D4e-4-test):
%     load with pop_loadbv in groups of 16 channels, resample to 500 Hz (pop_resample, boundary-
%     aware), band-pass 1-10 Hz (pop_eegfiltnew, firfilt filters each raw segment separately);
%     keep the D4e-clipped blocks, shrunk at each edge by the band-pass half-length (computed from
%     the installed design, not typed in); non-overlapping 10 s chunks; TP9/TP10 excluded (125 channels).
%   OUTCOME-BLIND: only time-domain channel x channel statistics of the 1-10 Hz band-passed data.
%   No spectrum is computed; nothing in 13-30 Hz or 55-95 Hz is computed, saved or printed.
%
%   Test P (every recording; 125 channels as recorded, chunks concatenated):
%     covariance eigenvalues (all, ascending) and their level relative to the median (dB);
%     per-chunk ratio RMS(channel mean) / median(channel SD) (also over all 127 channels, additional);
%     1 - R^2 of each channel regressed on the other 124, from the inverse covariance;
%     standardised regression weights and the 6 largest |weights| per channel (column indices).
%   Test N (testN): common-average reference over the 125 channels; per chunk the 125 x 125 Pearson
%     correlation, Fisher z; median over chunks. Neighbours: k nearest labels by Euclidean distance
%     in the subject's CapTrak X/Y/Z (.bvct, digitised list only), among the 125 recorded labels.
%     Scores s_H(L) = mean z between column_H(L) and column_H(N) over the neighbours N of L, for
%     H = vhdr and H = tsv, k = 4, 6, 8.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
s = char(params.subject); task = char(params.task); testN = logical(params.testN);
rawRoot = char(params.rawRoot);
bandHz = [1 10];                                           % S3a-D4e-4-test, band as committed (approval note)
assert(isequal(bandHz, [1 10]));
chunkLen = 10; N = chunkLen * S.fsOut;
kList = [4 6 8];
excl = ["TP9 LEFT EAR", "TP10 RIGHT EAR"];

% ---- inputs, each checked against the verified manifest before it is read ----------------------
B = readtable(char(params.blockTable), 'TextType', 'string');
assert(all(B.status ~= "STOP_START_OUTSIDE_DATA" & B.status ~= "STOP_STIMULI_AFTER_RAW_BOUNDARY"));
eegDir = fullfile(rawRoot, s, 'eeg');
hdr = [s '_task-' task '_eeg.vhdr'];
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
tok = regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once');
nCh = str2double(tok{1});
assert(height(ct) == nCh, 'channels.tsv and .vhdr disagree on the channel count');
tlab = ct.name;

% ---- band-pass kernel at 500 Hz from the installed default design (zero-valued synthetic set) ----
E = eeg_emptyset;
E.srate = S.fsOut; E.nbchan = 1; E.trials = 1; E.pnts = 120 * S.fsOut;
E.data = zeros(1, E.pnts); E.xmin = 0; E.xmax = (E.pnts - 1) / E.srate;
E = eeg_checkset(E);
[~, ~, bBP] = pop_eegfiltnew(E, 'locutoff', bandHz(1), 'hicutoff', bandHz(2));
halfBP = (numel(bBP) - 1) / 2;                             % samples at fsOut
assert(halfBP == round(halfBP), 'band-pass order is not even');

% ---- load, resample, band-pass, cut chunks (16 channels at a time) -----------------------------
bk = B(B.subject == s & B.task == task, :);
vlab = strings(nCh, 1); X = []; starts0 = []; blk = [];
for g = 1:16:nCh
    chans = g:min(g + 15, nCh);
    EEG = pop_loadbv(eegDir, hdr, [], chans);
    vlab(chans) = string({EEG.chanlocs.labels});
    if isfield(EEG.event, 'urevent'), EEG.event = rmfield(EEG.event, 'urevent'); end
    EEG.urevent = [];
    for k = 1:height(bk)                                    % block extents as events (as D5-0)
        EEG.event(end+1).type = 'd4e4_bs'; EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
        EEG.event(end+1).type = 'd4e4_be'; EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG = pop_resample(EEG, S.fsOut);
    EEG = pop_eegfiltnew(EEG, 'locutoff', bandHz(1), 'hicutoff', bandHz(2));
    typ = {EEG.event.type};
    bs = ceil([EEG.event(strcmp(typ, 'd4e4_bs')).latency]);
    be = floor([EEG.event(strcmp(typ, 'd4e4_be')).latency]);
    assert(numel(bs) == height(bk) && numel(be) == height(bk) && all(be > bs));
    bs2 = bs + halfBP; be2 = be - halfBP;                  % further margin: band-pass half-length
    st = [];
    for k = 1:numel(bs2)
        st = [st, bs2(k):N:(be2(k) - N + 1)]; %#ok<AGROW>
    end
    if isempty(X)
        starts0 = st; blk = [bs(:) be(:) bs2(:) be2(:)];
        X = zeros(nCh, N, numel(st), 'single');
    else
        assert(isequal(st, starts0), 'chunk positions differ between channel groups');
    end
    for c = 1:numel(st)
        X(chans, :, c) = EEG.data(:, st(c):st(c) + N - 1);
    end
    clear EEG
end
nC = numel(starts0);
assert(nC >= 2, 'fewer than 2 chunks');
assert(all(ismember(vlab, tlab)) && all(ismember(tlab, vlab)), '.vhdr and channels.tsv label sets differ');
keptV = find(~ismember(vlab, excl)); keptT = find(~ismember(tlab, excl));
assert(numel(keptV) == 125 && isequal(keptV, keptT), 'TP9/TP10 positions differ between .vhdr and channels.tsv');
kept = keptV;
vlabK = vlab(kept); tlabK = tlab(kept);                    % label of data column j under H_vhdr / H_tsv

% ---- test P ---------------------------------------------------------------------------------
Xk = double(reshape(X(kept, :, :), numel(kept), []));      % 125 x (N * nC), chunks concatenated
C = cov(Xk');
clear Xk
rcondC = rcond(C);
ev = sort(eig((C + C') / 2));
evRelDb = 10 * log10(max(ev, 0) / median(ev));
nDeficient = sum(evRelDb < -60);
avgRefRatio125 = nan(nC, 1); avgRefRatio127 = nan(nC, 1);
for c = 1:nC
    x = double(X(kept, :, c));
    avgRefRatio125(c) = rms(mean(x, 1)) / median(std(x, 0, 2));
    x = double(X(:, :, c));
    avgRefRatio127(c) = rms(mean(x, 1)) / median(std(x, 0, 2));
end
exportedAvgRef125 = all(avgRefRatio125 < 1e-4);
Pinv = inv(C);
oneMinusR2 = 1 ./ (diag(C) .* diag(Pinv));
nearPerfect = oneMinusR2 < 1e-4;
sd = sqrt(diag(C));
Wstd = -(Pinv ./ diag(Pinv)) .* (sd' ./ sd);              % W(c, j) = beta_cj * sd_j / sd_c
Wstd(logical(eye(numel(kept)))) = 0;
[~, ix] = sort(abs(Wstd), 2, 'descend');
top6Col = ix(:, 1:6);
top6W = Wstd(sub2ind(size(Wstd), repmat((1:numel(kept))', 1, 6), top6Col));
P = struct('cov', C, 'rcond', rcondC, 'eig', ev, 'eigRelDb', evRelDb, 'eigRelDbSmallest5', evRelDb(1:5), ...
    'nDeficient', nDeficient, 'avgRefRatio125', avgRefRatio125, 'avgRefRatio127', avgRefRatio127, ...
    'exportedAvgRef125', exportedAvgRef125, 'oneMinusR2', oneMinusR2, 'nearPerfect', nearPerfect, ...
    'wStd', Wstd, 'top6Col', top6Col, 'top6W', top6W);

% ---- test N ---------------------------------------------------------------------------------
Nres = struct();
if testN
    bv = fullfile(rawRoot, 'sourcedata', s, 'coords', [s '_captrak.bvct']);
    stage3_check_input(bv, rawRoot, params.manifest);
    [pn, pxyz] = readCapTrak(bv);
    Z = nan(numel(kept), numel(kept), nC);
    for c = 1:nC
        x = double(X(kept, :, c));
        x = x - mean(x, 1);                                % common-average reference (125 channels)
        R = corrcoef(x');
        z = atanh(R); z(logical(eye(numel(kept)))) = NaN;
        Z(:, :, c) = z;
    end
    Zmed = median(Z, 3);
    labs = tlabK;                                          % the 125 labels (same set under both H)
    [okp, ip] = ismember(labs, pn);
    assert(all(okp), 'a recorded label has no CapTrak position');
    xyz = pxyz(ip, :);
    D = sqrt(sum((permute(xyz, [1 3 2]) - permute(xyz, [3 1 2])) .^ 2, 3));
    D(logical(eye(numel(labs)))) = Inf;
    [~, nbOrd] = sort(D, 2, 'ascend');
    nb = nbOrd(:, 1:max(kList));                           % neighbour label indices (into labs), nearest first
    [~, colV] = ismember(labs, vlabK);                     % column of label L under H_vhdr
    [~, colT] = ismember(labs, tlabK);                     % column of label L under H_tsv (= identity)
    affected = colV ~= colT;
    sV = nan(numel(labs), numel(kList)); sT = sV;
    for i = 1:numel(labs)
        for kk = 1:numel(kList)
            n = nb(i, 1:kList(kk));
            sV(i, kk) = mean(Zmed(sub2ind(size(Zmed), repmat(colV(i), 1, numel(n)), colV(n)')));
            sT(i, kk) = mean(Zmed(sub2ind(size(Zmed), repmat(colT(i), 1, numel(n)), colT(n)')));
        end
    end
    Nres = struct('labels', labs, 'colVhdr', colV, 'colTsv', colT, 'affected', affected, 'k', kList, ...
        'neighbours', nb, 'zMedian', Zmed, 'sVhdr', sV, 'sTsv', sT, 'bvctSha256', string(sha256File(bv)));
end

info = struct('subject', string(s), 'task', string(task), 'testN', testN, 'bandHz', bandHz, ...
    'bandpassOrder', numel(bBP) - 1, 'halfBPSamples', halfBP, 'fsOut', S.fsOut, 'chunkLen', chunkLen, ...
    'nChunk', nC, 'chunkStarts', starts0, 'blocks', blk, 'keptColumns', kept, 'vhdrLabels', vlab, 'tsvLabels', tlab);
save(outFile, 'info', 'P', 'Nres');
fprintf('%s %s: %d chunks; band-pass order %d (half %d samples); deficient %d; near-perfect %d\n', ...
    s, task, nC, numel(bBP) - 1, halfBP, nDeficient, sum(nearPerfect));
end

function [names, xyz] = readCapTrak(f)
% digitised points only: the <CapTrakElectrodeList> block (the file also holds an ElectrodeLayout)
t = fileread(f);
blk = regexp(t, '<CapTrakElectrodeList>(.*?)</CapTrakElectrodeList>', 'tokens', 'once');
assert(~isempty(blk), 'no CapTrakElectrodeList in %s', f);
el = regexp(blk{1}, '<CapTrakElectrode>(.*?)</CapTrakElectrode>', 'tokens');
names = strings(numel(el), 1); xyz = nan(numel(el), 3); ax = 'XYZ';
for k = 1:numel(el)
    e = el{k}{1};
    names(k) = string(regexp(e, '<Name>([^<]*)</Name>', 'tokens', 'once'));
    for a = 1:3
        v = regexp(e, sprintf('<%s>([^<]*)</%s>', ax(a), ax(a)), 'tokens', 'once');
        xyz(k, a) = str2double(v{1});
    end
end
assert(numel(unique(names)) == numel(names), 'duplicate names in the digitised list of %s', f);
assert(all(isfinite(xyz(:))), 'non-numeric coordinate in %s', f);
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
