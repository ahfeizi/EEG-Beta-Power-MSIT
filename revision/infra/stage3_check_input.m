function stage3_check_input(file, rawRoot, manifestFile)
%STAGE3_CHECK_INPUT  Check one raw input file against verified_manifest.tsv before it is read.
%   stage3_check_input(file, rawRoot, manifestFile) computes the SHA-256 of FILE and compares it
%   with the row of manifestFile whose relpath equals FILE relative to rawRoot ('/' separators).
%   Errors if FILE is outside rawRoot, is not in the manifest, or its size or hash differs.
%   Every job function must call this for every raw file it reads (S3a-INF-1 §1, "Inputs").

persistent M T mfile
if isempty(M) || ~strcmp(mfile, manifestFile)
    T = readtable(manifestFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string', ...
                  'ReadVariableNames', true);
    M = containers.Map(cellstr(T.relpath), num2cell(1:height(T)));
    mfile = manifestFile;
end
root = strrep(char(rawRoot), '/', '\');
f = strrep(char(file), '/', '\');
assert(strncmpi(f, [root '\'], numel(root) + 1), 'stage3:input', 'input outside the raw root: %s', f);
rel = strrep(f(numel(root) + 2:end), '\', '/');
assert(isKey(M, rel), 'stage3:input', 'input not in verified manifest: %s', rel);
row = T(M(rel), :);
info = dir(f);
assert(info.bytes == double(row.size), 'stage3:input', 'size differs from manifest: %s', rel);
h = sha256File(f);
assert(strcmp(h, char(row.sha256)), 'stage3:input', 'SHA-256 differs from manifest: %s', rel);
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'stage3:input', 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
