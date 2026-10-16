function stage3_compare(fileX, fileY, kind, outJson)
%STAGE3_COMPARE  Content comparison of two job outputs (S3a-INF-1 §3), in its own fresh process.
%   stage3_compare(fileX, fileY, kind, outJson) loads both MAT files into variables (never compares
%   file bytes) and writes outJson with, per compared field: equal (isequaln), the number of
%   differing elements (NaN = NaN counts as equal, NaN vs a number as different) and the maximum
%   absolute difference over finite pairs. It reports nothing else (outcome-blind).
%   kind:
%     'd5_0'    res.label, res.avgP, res.exc, res.fpk, res.amp, nChunk, F, d, f0s
%     'burnin'  every leaf of every variable except 'timing'; plus the number of iterations whose
%               block hash differs between the two files, per block type
%     'all'     every leaf of every variable (synthetic tests)
%     'set'     Stage 3 .set outputs (S3a-INF-1 sec. 3; specification S3a-INF-1-setspec): EEG.data, srate,
%               nbchan, pnts, xmin; chanlocs labels and X/Y/Z; event type/latency/duration;
%               etc.restBlocks / etc.taskBlocks (every leaf); etc.stage3.removedChannels; icaweights,
%               icasphere, icawinv, icachansind; etc.ic_classification.ICLabel.classifications;
%               etc.stage3.rejectedComponents. A field absent from both files counts as equal (reported
%               as '<absent>'); absent from one only, as different. The file holds variable EEG (or, in the
%               EEGLAB one-variable-per-field format, the EEG fields themselves). Nothing else is compared.

X = load(fileX);
Y = load(fileY);
switch kind
    case 'd5_0'
        names = {'res.label', 'res.avgP', 'res.exc', 'res.fpk', 'res.amp', 'nChunk', 'F', 'd', 'f0s'};
        LX = containers.Map(); LY = containers.Map();
        for k = 1:numel(names)
            LX(names{k}) = getPath(X, names{k});
            LY(names{k}) = getPath(Y, names{k});
        end
    case {'burnin', 'all'}
        if strcmp(kind, 'burnin')
            X = rmfield(X, intersect(fieldnames(X), {'timing'}));
            Y = rmfield(Y, intersect(fieldnames(Y), {'timing'}));
        end
        LX = containers.Map(); LY = containers.Map();
        flatten(X, '', LX); flatten(Y, '', LY);
        names = union(keys(LX), keys(LY));
    case 'set'
        [LX, names] = setFields(X); [LY, namesY] = setFields(Y);
        assert(isequal(names, namesY), 'stage3:compare', 'set field lists differ');
    otherwise
        error('stage3:compare', 'unknown kind %s', kind);
end

R = struct('field', {}, 'equal', {}, 'n_diff', {}, 'max_abs_diff', {});
for k = 1:numel(names)
    n = names{k};
    if ~isKey(LX, n) || ~isKey(LY, n)
        R(end+1) = struct('field', n, 'equal', false, 'n_diff', NaN, 'max_abs_diff', NaN); %#ok<AGROW>
        continue
    end
    [eq, nd, mx] = cmpOne(LX(n), LY(n));
    R(end+1) = struct('field', n, 'equal', eq, 'n_diff', nd, 'max_abs_diff', mx); %#ok<AGROW>
end
out.fileX = fileX; out.fileY = fileY; out.kind = kind;
out.equal = all([R.equal]);
out.fields = R;
if strcmp(kind, 'burnin')
    out.iterations_differing.d5 = sum(any(X.hashes.d5 ~= Y.hashes.d5, 2));
    out.iterations_differing.gemm = sum(any(X.hashes.gemm ~= Y.hashes.gemm, 2));
    out.within_mismatch_X = X.mismatchWithin;
    out.within_mismatch_Y = Y.mismatchWithin;
end
tmp = [outJson '.tmp'];
fid = fopen(tmp, 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(out), 'char');
fclose(fid);
movefile(tmp, outJson);
fprintf('STAGE3_COMPARE_DONE equal=%d\n', out.equal);
end

function v = getPath(S, p)
parts = strsplit(p, '.');
v = S;
for k = 1:numel(parts), v = v.(parts{k}); end
end

function flatten(v, prefix, L)
if isstruct(v) && isscalar(v)
    f = fieldnames(v);
    for k = 1:numel(f)
        flatten(v.(f{k}), joinName(prefix, f{k}), L);
    end
else
    L(prefix) = v;
end
end

function n = joinName(a, b)
if isempty(a), n = b; else, n = [a '.' b]; end
end

function [eq, nd, mx] = cmpOne(a, b)
eq = isequaln(a, b);
mx = NaN;
if eq, nd = 0; mx = 0; return; end
if ~isequal(size(a), size(b)) || ~strcmp(class(a), class(b))
    nd = max(numel(a), numel(b)); return
end
if isnumeric(a) || islogical(a)
    a = a(:); b = b(:);
    same = (a == b) | (isnan(double(a)) & isnan(double(b)));
    nd = sum(~same);
    fin = isfinite(double(a)) & isfinite(double(b)) & ~same;
    if any(fin), mx = max(abs(double(a(fin)) - double(b(fin)))); end
elseif isstring(a) || iscellstr(a) || ischar(a)
    nd = sum(~(string(a(:)) == string(b(:))));
else
    nd = numel(a);                                         % other types: count all as differing
end
end

function [L, names] = setFields(S)
% S3a-INF-1-setspec field list. Absent fields map to the marker string "<absent>".
if isfield(S, 'EEG'), E = S.EEG; else, E = S; end
names = {'data', 'srate', 'nbchan', 'pnts', 'xmin', 'chanlocs.labels', 'chanlocs.X', 'chanlocs.Y', 'chanlocs.Z', ...
    'event.type', 'event.latency', 'event.duration', 'etc.stage3.removedChannels', 'icaweights', 'icasphere', ...
    'icawinv', 'icachansind', 'etc.ic_classification.ICLabel.classifications', 'etc.stage3.rejectedComponents'};
L = containers.Map();
for k = 1:numel(names)
    L(names{k}) = getOpt(E, names{k});
end
for b = {'restBlocks', 'taskBlocks'}                       % every leaf of etc.restBlocks / etc.taskBlocks
    n = ['etc.' b{1}];
    if isfield(E, 'etc') && isfield(E.etc, b{1})
        M = containers.Map(); flattenAll(E.etc.(b{1}), n, M);
        kk = keys(M); for i = 1:numel(kk), L(kk{i}) = M(kk{i}); end
    else
        L(n) = "<absent>";
    end
end
names = sort(keys(L));
end

function v = getOpt(E, p)
parts = strsplit(p, '.');
if any(strcmp(parts{1}, {'chanlocs', 'event'})) && numel(parts) == 2
    if ~isfield(E, parts{1}) || ~isfield(E.(parts{1}), parts{2}), v = "<absent>"; return; end
    s = E.(parts{1});
    c = {s.(parts{2})};
    if all(cellfun(@(x) isnumeric(x) && isscalar(x), c)), v = cellfun(@double, c);
    elseif all(cellfun(@(x) (isnumeric(x) && isscalar(x)) || isempty(x), c))
        v = nan(1, numel(c)); for i = 1:numel(c), if ~isempty(c{i}), v(i) = double(c{i}); end, end
    else, v = string(cellfun(@toStr, c, 'uni', 0)); end
    return
end
v = E;
for k = 1:numel(parts)
    if ~isstruct(v) || ~isfield(v, parts{k}), v = "<absent>"; return; end
    v = v.(parts{k});
end
end

function s = toStr(x)
if ischar(x) || isstring(x), s = char(x); elseif isempty(x), s = ''; else, s = mat2str(x); end
end

function flattenAll(v, prefix, L)
% like flatten, but also descends into struct arrays (element index in the name)
if isstruct(v)
    f = fieldnames(v);
    for e = 1:numel(v)
        for k = 1:numel(f)
            flattenAll(v(e).(f{k}), sprintf('%s(%d).%s', prefix, e, f{k}), L);
        end
    end
    if isempty(v), L(prefix) = "<empty struct>"; end
else
    L(prefix) = v;
end
end
