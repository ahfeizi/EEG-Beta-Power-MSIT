function stage3_d6_compute_one(params, outFile)
%STAGE3_D6_COMPUTE_ONE  D6 bad channels for one subject (S3a-D6, S3a-D2-close), as a runner job function.
%   params: subject; p1Rest, p1Msit (part-1 .set files) and p1Manifest (one or more export manifests: file,
%   bytes, sha256, canonical; each file is hash-checked against them); predTable (test P table,
%   predictability_by_channel.csv) and predSha (its expected SHA-256); plus rawRoot, manifest (common; for
%   the position files); optional posCentering (else S.d6.posCentering), logFile.
%   Steps (both conditions):
%     1. known-bad channels, removed before RANSAC:
%        - the D4e-4 pair of sub-13 (FFT8h, FCC6h) / sub-41 (FC5, FT9) (S3a-D6 item 5);
%        - dependent channels: 1 - R^2 < S.d6.r2Thr in rest or MSIT+ (test P table, tsv labels; item 6);
%     2. individual positions (stage3_positions, S3a-D2-close) on the remaining channels;
%     3. per condition, on a copy low-passed at S.d6.lowpassHz (pop_eegfiltnew default design):
%        pop_clean_rawdata with FlatlineCriterion S.d6.flatlineS, ChannelCriterion S.d6.chanCorr,
%        LineNoiseCriterion 'off', Highpass/Burst/Window criteria and BurstRejection 'off', Distance
%        'Euclidian' (v1 settings without the LineNoise criterion; item 1);
%     4. union over both conditions and categories (item 2); excluded if nBad / nChannels > S.d6.exclFrac.
%   Output: variable D6 (decisions only; no data are changed or interpolated here). sub-42 is refused
%   (excluded, item 4). OUTCOME-BLIND: no spectrum or power is computed or saved.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_clean_rawdata', 'file'), eeglab('nogui'); end
s = char(params.subject);
assert(~strcmp(s, 'sub-42'), 'stage3:d6', 'sub-42 is excluded (S3a-D6 item 4)');
cen = S.d6.posCentering;
if isfield(params, 'posCentering') && ~isempty(params.posCentering), cen = char(params.posCentering); end
assert(~isempty(cen), 'stage3:d6', 'centring of the individual positions is not decided (S3a-D2-close open point)');
if isfield(params, 'logFile') && ~isempty(params.logFile), logFile = char(params.logFile);
else, logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md'); end
pairs = struct('sub_13', {{'FFT8h', 'FCC6h'}}, 'sub_41', {{'FC5', 'FT9'}});

% ---- inputs ---------------------------------------------------------------------------------
mf = cellstr(params.p1Manifest);                         % one or more export manifests (one per part-1 batch)
Mc = cellfun(@(m) readtable(m, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string'), mf, 'uni', 0);
M = vertcat(Mc{:});
assert(numel(unique(M.file)) == height(M), 'stage3:d6', 'a part-1 file is listed in two manifests');
E = struct();
for c = {'rest', 'msit'}
    f = char(params.(['p1' upper(c{1}(1)) c{1}(2:end)]));
    [~, n, x] = fileparts(f);
    row = M(M.file == string([n x]), :);
    assert(height(row) == 1, 'stage3:d6', '%s not in the part-1 manifest', f);
    assert(strcmp(sha256File(f), char(row.sha256)), 'stage3:d6', '%s: SHA-256 differs from the part-1 manifest', f);
    L = load(f, '-mat', 'EEG'); E.(c{1}) = L.EEG;   % .set extension: MAT format must be stated
    assert(strcmp(E.(c{1}).etc.stage3.subject, s) && strcmp(E.(c{1}).etc.stage3.task, c{1}), 'stage3:d6', 'wrong part-1 file %s', f);
end
lab = string({E.rest.chanlocs.labels})';
assert(isequal(lab, string({E.msit.chanlocs.labels})'), 'stage3:d6', 'rest and MSIT+ channel sets differ');
nCh = numel(lab);
assert(strcmp(sha256File(char(params.predTable)), char(params.predSha)), 'stage3:d6', 'test P table SHA-256 differs');
T = readtable(char(params.predTable), 'TextType', 'string');
T = T(T.subject == s, :);

% ---- 1. known-bad channels ------------------------------------------------------------------
key = strrep(s, '-', '_');
if isfield(pairs, key), pairBad = string(pairs.(key))'; else, pairBad = strings(0, 1); end
assert(all(ismember(pairBad, lab)), 'stage3:d6', 'pair label not in the montage');
dep = struct();
for c = {'rest', 'msit'}
    t = T(T.task == c{1}, :);
    assert(height(t) == nCh, 'stage3:d6', '%s %s: test P rows %d, channels %d', s, c{1}, height(t), nCh);
    assert(all(ismember(t.label_tsv, lab)), 'stage3:d6', 'test P label not in the montage');
    k = t.one_minus_r2 < S.d6.r2Thr;
    dep.(c{1}) = struct('label', t.label_tsv(k), 'one_minus_r2', t.one_minus_r2(k));
end
depBad = unique([dep.rest.label; dep.msit.label]);
known = unique([pairBad; depBad]);

% ---- 2. positions ---------------------------------------------------------------------------
P = stage3_positions(s, params.rawRoot, params.manifest, cen);
[ok, ip] = ismember(lab, P.label);
assert(all(ok), 'stage3:d6', 'a channel without an individual position: %s', strjoin(lab(~ok), ', '));
for c = {'rest', 'msit'}
    for k = 1:nCh
        E.(c{1}).chanlocs(k).X = P.X(ip(k)); E.(c{1}).chanlocs(k).Y = P.Y(ip(k)); E.(c{1}).chanlocs(k).Z = P.Z(ip(k));
    end
    E.(c{1}) = pop_chanedit(E.(c{1}), 'convert', {'cart2all'});
end

% ---- 3. RANSAC / flatline per condition, on the 100 Hz copy, known-bad channels removed ----------
ransac = struct();
for c = {'rest', 'msit'}
    X = E.(c{1});
    if ~isempty(known), X = pop_select(X, 'nochannel', cellstr(known)); end
    X = pop_eegfiltnew(X, 'hicutoff', S.d6.lowpassHz);
    before = string({X.chanlocs.labels})';
    X = pop_clean_rawdata(X, 'FlatlineCriterion', S.d6.flatlineS, 'ChannelCriterion', S.d6.chanCorr, ...
        'LineNoiseCriterion', 'off', 'Highpass', 'off', 'BurstCriterion', 'off', 'WindowCriterion', 'off', ...
        'BurstRejection', 'off', 'Distance', 'Euclidian');
    after = string({X.chanlocs.labels})';
    ransac.(c{1}) = setdiff(before, after, 'stable');
    clear X
end

% ---- 4. union and exclusion -----------------------------------------------------------------
bad = lab(ismember(lab, unique([known; ransac.rest; ransac.msit])));   % montage order
D6 = struct('subject', s, 'nChannels', nCh, 'channels', lab, ...
    'pair', pairBad, 'dependent', dep, 'dependentUnion', depBad, 'ransac', ransac, ...
    'removedChannels', bad, 'nBad', numel(bad), 'fracBad', numel(bad) / nCh, ...
    'excluded', numel(bad) / nCh > S.d6.exclFrac, ...
    'positions', struct('label', P.label, 'X', P.X, 'Y', P.Y, 'Z', P.Z, 'source', P.source, ...
        'centering', P.centering, 'centre_ras_mm', P.centre, 'radius_mm', P.radius, 'fiducials', P.fiducials), ...
    'params', S.d6, 'centeringUsed', cen, ...
    'inputs', struct('p1Rest', char(params.p1Rest), 'p1Msit', char(params.p1Msit), ...
        'predTableSha256', char(params.predSha), 'positionsFile', P.file));
D6.params.posCentering = cen;
ids = {'S3a-D6', 'S3a-D2-close', 'S3a-D6-impl', 'S3a-D2-centring', 'S3a-D6-amend1'};
D6.logEntries = struct('id', ids, 'sha256', cellfun(@(i) stage3_log_entry(logFile, i), ids, 'uni', 0));
save(outFile, 'D6');
fprintf('%s: %d bad of %d (pair %d, dependent %d, RANSAC rest %d / MSIT+ %d) -> %.1f %%, excluded %d\n', s, numel(bad), nCh, ...
    numel(pairBad), numel(depBad), numel(ransac.rest), numel(ransac.msit), 100 * numel(bad) / nCh, D6.excluded);
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
