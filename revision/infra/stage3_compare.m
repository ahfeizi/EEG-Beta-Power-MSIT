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
%     'set'     reserved for Stage 3 .set outputs; not bound until the pipeline defines where it
%               stores the removed-channel and rejected-component lists (errors for now)

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
        error('stage3:compare', 'kind ''set'' is not bound yet (S3a-INF-1 §3)');
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
