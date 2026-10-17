function T = stage3_d6_summary(batchDir, outFile)
%STAGE3_D6_SUMMARY  One row per subject from the verified D6 outputs of batchDir (S3a-D6-impl); each
%   canonical output is hash-checked against its state file. Writes outFile (CSV, never overwrites).
assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
S = dir(fullfile(batchDir, 'state', '*.json'));
rows = {};
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(batchDir, 'state', S(k).name)));
    if ~any(strcmp(st.status, {'verified', 'flagged'})), continue; end
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', S(k).name);
    L = load(st.canonical.path); D = L.D6;
    rows{end+1} = table(string(D.subject), D.nChannels, D.nBad, D.fracBad, D.excluded, numel(D.pair), numel(D.dependentUnion), ...
        numel(D.ransac.rest), numel(D.ransac.msit), strjoin(D.removedChannels, ' '), string(D.positions.source), ...
        string(D.centeringUsed), D.positions.centre_ras_mm(1), D.positions.centre_ras_mm(2), D.positions.centre_ras_mm(3), ...
        string(st.canonical.sha256), 'VariableNames', {'subject', 'n_channels', 'n_bad', 'frac_bad', 'excluded', 'n_pair', ...
        'n_dependent', 'n_ransac_rest', 'n_ransac_msit', 'removed_channels', 'positions_source', 'centering', ...
        'centre_x_mm', 'centre_y_mm', 'centre_z_mm', 'd6_sha256'}); %#ok<AGROW>
end
T = vertcat(rows{:});
writetable(T, outFile);
fprintf('%d subjects; excluded: %s\n', height(T), strjoin(T.subject(T.excluded), ', '));
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
