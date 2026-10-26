function stage3_p2_compute_one(params, outFile)
%STAGE3_P2_COMPUTE_ONE  Stage 3 part 2 for one subject (S3a-P2, S3a-P2-impl), as a runner job function.
%   params: subject; p1Rest, p1Msit, p1Manifest (one or more export manifests; each part-1 file is
%   hash-checked); d6File and d6Sha (the subject's verified D6 output); seedGlobal (common); optional
%   logFile, asrMaxMemMB (default 1024).
%   Steps (both conditions; data in double throughout, stored as single):
%     1. part-1 rest and MSIT+; the D6 decision (refused if excluded); individual centred positions from D6;
%     2. bad channels removed (D6 removedChannels);
%     3. ICA-training copy (S3a-P2 items 2, 3): rest + MSIT+ merged, high-pass 1 Hz (pop_eegfiltnew), ASR
%        burst criterion 20 (clean_asr, explicit MaxMem; asserted: no hlp_diskcache, no RAM-dependent branch);
%     4. re-reference R1 (item 1) of the analysed rest, MSIT+ and the training copy: FCz added with its
%        individual position and the average reference computed (pop_reref [], 'refloc');
%     5. rank check (item 3): eigenvalues of the training covariance above 1e-10 x the largest must number
%        exactly the good channels, else the job STOPS;
%     6. Picard (pop_runica 'picard', pca = number of good channels) on the training copy; weights
%        transplanted to the analysed data (never ASR-modified);
%     7. ICLabel on the merged analysed data; the global RNG is reseeded with seedGlobal afterwards
%        (S3a-INF-1 sec. 2); rejection lists at p >= 0.8: beta (all non-brain) and EMG (all non-brain
%        except Muscle), each with and without the class Other (S3a-P2 flagged point i);
%   Output: variable P2 = the S1 bundle (item 6): rest and msit (pre-component-removal EEG with ICA matrices),
%   ICLabel classifications, lists, removed channels, full 126-channel locations for interpolation, QC counts
%   (D13; no spectral quantity). Versions are rebuilt by stage3_p2_rebuild. OUTCOME-BLIND: no spectrum or
%   power is computed or saved by this code (ICLabel computes its own features internally; S3a-P2).

here = fileparts(mfilename('fullpath'));
addpath(here);
if ~exist('pop_runica', 'file'), eeglab('nogui'); end
assert(exist('picard', 'file') == 2, 'stage3:p2', 'Picard is not installed');
assert(~exist('hlp_diskcache', 'file'), 'stage3:p2', 'hlp_diskcache found (S3a-INF-1 sec. 2)');
s = char(params.subject);
if isfield(params, 'logFile') && ~isempty(params.logFile), logFile = char(params.logFile);
else, logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md'); end
maxmem = 1024; if isfield(params, 'asrMaxMemMB') && ~isempty(params.asrMaxMemMB), maxmem = double(params.asrMaxMemMB); end
seed = double(params.seedGlobal);

% ---- 1. inputs ------------------------------------------------------------------------------
assert(strcmp(sha256File(char(params.d6File)), char(params.d6Sha)), 'stage3:p2', 'D6 output SHA-256 differs');
L = load(char(params.d6File)); D6 = L.D6;
assert(strcmp(D6.subject, s), 'stage3:p2', 'D6 output of another subject');
assert(~D6.excluded, 'stage3:p2', '%s is excluded (S3a-D6-final)', s);
mf = cellstr(params.p1Manifest);
Mc = cellfun(@(m) readtable(m, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string'), mf, 'uni', 0);
M = vertcat(Mc{:});
E = struct();
for c = {'rest', 'msit'}
    f = char(params.(['p1' upper(c{1}(1)) c{1}(2:end)]));
    [~, n, x] = fileparts(f);
    row = M(M.file == string([n x]), :);
    assert(height(row) == 1 && strcmp(sha256File(f), char(row.sha256)), 'stage3:p2', '%s: not in the manifest or SHA-256 differs', f);
    Lc = load(f, '-mat', 'EEG'); X = Lc.EEG;
    assert(strcmp(X.etc.stage3.subject, s) && strcmp(X.etc.stage3.task, c{1}), 'stage3:p2', 'wrong part-1 file %s', f);
    X.data = double(X.data);
    E.(c{1}) = X;
end
lab = string({E.rest.chanlocs.labels})';
assert(isequal(lab, string({E.msit.chanlocs.labels})') && isequal(lab, D6.channels), 'stage3:p2', 'channel sets differ');
Pz = D6.positions;
[ok, ip] = ismember([lab; "FCz"], Pz.label);
assert(all(ok), 'stage3:p2', 'a channel (or FCz) without an individual position');
for c = {'rest', 'msit'}
    for k = 1:numel(lab)
        E.(c{1}).chanlocs(k).X = Pz.X(ip(k)); E.(c{1}).chanlocs(k).Y = Pz.Y(ip(k)); E.(c{1}).chanlocs(k).Z = Pz.Z(ip(k));
    end
    E.(c{1}) = pop_chanedit(E.(c{1}), 'convert', {'cart2all'});
end
fullLocs = E.rest.chanlocs; fullLocs(end+1) = fullLocs(1);                  % 125 montage channels + FCz (same fields)
fullLocs(end).labels = 'FCz'; fullLocs(end).X = Pz.X(ip(end)); fullLocs(end).Y = Pz.Y(ip(end)); fullLocs(end).Z = Pz.Z(ip(end));
fullLocs = convertlocs(fullLocs, 'cart2all');
fcz = fullLocs(end);

% ---- 2. bad channels removed ------------------------------------------------------------------
bad = cellstr(D6.removedChannels);
for c = {'rest', 'msit'}
    if ~isempty(bad), E.(c{1}) = pop_select(E.(c{1}), 'nochannel', bad); end
end
nGood = E.rest.nbchan;
assert(nGood == numel(lab) - numel(bad), 'stage3:p2', 'channel count after removal');

% ---- 3. ICA-training copy: merge, 1 Hz high-pass, ASR (training copy only) ----------------------
T = pop_mergeset(E.rest, E.msit, 0);
T = pop_eegfiltnew(T, 'locutoff', 1);
win = max(0.5, 1.5 * T.nbchan / T.srate); P = round(win / 2 * T.srate);   % clean_asr / asr_process defaults
assert(maxmem * 1024 * 1024 - T.nbchan ^ 2 * P * 8 * 3 > 0, 'stage3:p2', 'ASR MaxMem too small (RAM-dependent branch)');
before = T.data;
T = clean_asr(T, 20, [], [], [], [], [], [], false, false, maxmem);
asrModifiedFraction = mean(any(T.data ~= before, 1));
clear before

% ---- 4. re-reference R1 (FCz recovered) --------------------------------------------------------
for c = {'rest', 'msit'}, E.(c{1}) = rerefFCz(E.(c{1}), fcz); end
T = rerefFCz(T, fcz);
assert(isequal({E.rest.chanlocs.labels}, {T.chanlocs.labels}) && strcmp(E.rest.chanlocs(end).labels, 'FCz'), 'stage3:p2', 'montage after re-reference');

% ---- 5. rank check -----------------------------------------------------------------------------
Xc = T.data - mean(T.data, 2);
ev = sort(eig((Xc * Xc') / size(Xc, 2)), 'descend'); clear Xc
rk = sum(ev / ev(1) > 1e-10);
assert(rk == nGood, 'stage3:p2', 'rank %d of the training copy differs from the %d good channels', rk, nGood);

% ---- 6. Picard, transplanted ---------------------------------------------------------------------
T = pop_runica(T, 'icatype', 'picard', 'pca', nGood);
for c = {'rest', 'msit'}
    E.(c{1}).icaweights = T.icaweights; E.(c{1}).icasphere = T.icasphere;
    E.(c{1}).icawinv = T.icawinv; E.(c{1}).icachansind = T.icachansind;
    E.(c{1}).icaact = [];
end
clear T

% ---- 7. ICLabel on the merged analysed data; lists ---------------------------------------------------
A = pop_mergeset(E.rest, E.msit, 0);                  % pop_mergeset drops the ICA matrices: set them again
A.icaweights = E.rest.icaweights; A.icasphere = E.rest.icasphere; A.icawinv = E.rest.icawinv;
A.icachansind = E.rest.icachansind;
A.icaact = (A.icaweights * A.icasphere) * double(A.data(A.icachansind, :));
A = iclabel(A);
rng(seed, 'twister');                                  % ICLabel leaves the global RNG clock-seeded
cls = A.etc.ic_classification.ICLabel;
assert(isequal(cellstr(cls.classes), {'Brain', 'Muscle', 'Eye', 'Heart', 'Line Noise', 'Channel Noise', 'Other'}), 'stage3:p2', 'ICLabel classes');
p = cls.classifications;
lists = struct( ...
    'beta_withoutOther', find(any(p(:, 2:6) >= 0.8, 2))', ...  % reject Muscle, Eye, Heart, Line Noise, Channel Noise
    'beta_withOther', find(any(p(:, 2:7) >= 0.8, 2))', ...     % also Other
    'emg_withoutOther', find(any(p(:, 3:6) >= 0.8, 2))', ...   % Muscle kept
    'emg_withOther', find(any(p(:, [3:6 7]) >= 0.8, 2))');
clear A
qc = struct('nGood', nGood, 'rank', rk, 'pca', nGood, 'nIC', size(p, 1), ...
    'nPerClass_p08', sum(p >= 0.8, 1), 'nTopClass', histcounts(maxIdx(p), 0.5:1:7.5), ...
    'nRejected', structfun(@numel, lists)', 'asrModifiedFraction', asrModifiedFraction, ...
    'removedChannels', {cellstr(D6.removedChannels)});

% ---- output: the S1 bundle -------------------------------------------------------------------------
for c = {'rest', 'msit'}
    E.(c{1}).data = single(E.(c{1}).data);
    E.(c{1}).etc.stage3.part = 2;
    E.(c{1}).etc.stage3.removedChannels = cellstr(D6.removedChannels);
    E.(c{1}).etc.ic_classification.ICLabel = cls;
end
ids = {'S3a-P2', 'S3a-P2-impl', 'S3a-D6-final', 'S3a-D2-centring', 'S3a-D6-amend1'};
P2 = struct('subject', s, 'rest', E.rest, 'msit', E.msit, 'classes', {cellstr(cls.classes)}, ...
    'classifications', p, 'lists', lists, 'removedChannels', {cellstr(D6.removedChannels)}, ...
    'fullChanlocs', fullLocs, 'qc', qc, ...
    'settings', struct('asrCutoff', 20, 'asrMaxMemMB', maxmem, 'icaHighpassHz', 1, 'icatype', 'picard', ...
        'rankTolRel', 1e-10, 'iclabelThreshold', 0.8, 'seedGlobal', seed), ...
    'inputs', struct('p1Rest', char(params.p1Rest), 'p1Msit', char(params.p1Msit), 'd6File', char(params.d6File), ...
        'd6Sha', char(params.d6Sha)), ...
    'logEntries', struct('id', ids, 'sha256', cellfun(@(i) stage3_log_entry(logFile, i), ids, 'uni', 0)));
save(outFile, 'P2', '-v7');
fprintf('%s: %d good channels, rank %d, %d ICs; ASR modified %.4f of training samples; rejected beta %d/%d, EMG %d/%d (without/with Other)\n', ...
    s, nGood, rk, size(p, 1), asrModifiedFraction, numel(lists.beta_withoutOther), numel(lists.beta_withOther), ...
    numel(lists.emg_withoutOther), numel(lists.emg_withOther));
end

function X = rerefFCz(X, fcz)
% S3a-P2-fix1: pop_reref(..., 'refloc') errors if EEG.chaninfo.removedchans is empty (pop_reref.m:357-368; only
% its bookkeeping, after the arithmetic in reref.m). The list is filled by the D6 pop_select; a subject with no
% bad channel (sub-10) has none, so the FCz entry is placed there first and pop_reref removes it again. With
% bad channels the list is non-empty and this branch is not taken (unchanged code path).
if ~isfield(X.chaninfo, 'removedchans') || isempty(X.chaninfo.removedchans)
    X.chaninfo.removedchans = fcz;
end
X = pop_reref(X, [], 'refloc', fcz);
end

function k = maxIdx(p)
[~, k] = max(p, [], 2);
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
