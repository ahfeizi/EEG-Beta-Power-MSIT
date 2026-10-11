function stage3_d5_0_compare_runs(dirOld, dirNew, outFile)
%STAGE3_D5_0_COMPARE_RUNS  Check required by S3a-D5-0-amend2: the D5-0 recompute (dirNew, d5_0_2) must
%   reproduce res.label, res.exc, res.amp, res.avgP and nChunk of the earlier run (dirOld, d5_0_1) for
%   every recording; res.fpk may differ only where the guarded refinement applies, and must then lie
%   within f0 +/- 0.55 Hz. Canonical outputs are hash-checked. Writes a text report (never overwrites).

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
S = dir(fullfile(dirOld, 'state', '*.json'));
f0 = [50 100 150 200];
lines = strings(0, 1); allOk = true; nDiff = 0; nTot = 0; maxOff = 0;
for k = 1:numel(S)
    a = jsondecode(fileread(fullfile(dirOld, 'state', S(k).name)));
    b = jsondecode(fileread(fullfile(dirNew, 'state', S(k).name)));
    assert(strcmp(sha256File(a.canonical.path), a.canonical.sha256) && strcmp(sha256File(b.canonical.path), b.canonical.sha256), 'hash mismatch %s', S(k).name);
    A = load(a.canonical.path); Bn = load(b.canonical.path);
    same = isequaln(A.res.label, Bn.res.label) && isequaln(A.res.exc, Bn.res.exc) && isequaln(A.res.amp, Bn.res.amp) ...
        && isequaln(A.res.avgP, Bn.res.avgP) && isequaln(A.nChunk, Bn.nChunk);
    dif = A.res.fpk ~= Bn.res.fpk & ~(isnan(A.res.fpk) & isnan(Bn.res.fpk));
    off = abs(Bn.res.fpk - f0); off = max(off(:), [], 'omitnan');
    nDiff = nDiff + sum(dif(:)); nTot = nTot + numel(dif); maxOff = max(maxOff, off);
    allOk = allOk && same && off <= 0.55 + 1e-9;
    if ~same, lines(end+1) = sprintf('%s: label/exc/amp/avgP/nChunk DIFFER', erase(S(k).name, '.json')); end %#ok<AGROW>
end
fid = fopen(outFile, 'w');
fprintf(fid, 'S3a-D5-0-amend2 check: %s vs %s (%d recordings), %s\n', dirOld, dirNew, numel(S), char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'res.label, res.exc, res.amp, res.avgP, nChunk identical in every recording: %d\n', isempty(lines));
fprintf(fid, '%s\n', lines);
fprintf(fid, 'res.fpk values changed by the guard: %d of %d; max |fpk - f0| after the fix: %.4f Hz\n', nDiff, nTot, maxOff);
fprintf(fid, 'CHECK %s\n', string(allOk).replace("true", "PASS").replace("false", "FAIL"));
fclose(fid);
fprintf('%s', fileread(outFile));
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
