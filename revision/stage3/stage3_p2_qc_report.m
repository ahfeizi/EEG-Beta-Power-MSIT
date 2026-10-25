function T = stage3_p2_qc_report(batchDir, outFile)
%STAGE3_P2_QC_REPORT  Counts-only QC table of a part-2 batch (S3a-P2-d14): per subject, from each verified
%   bundle (hash-checked): good channels, rank, ICs, ICs with p >= 0.8 per ICLabel class, and the number of
%   components removed in the decided versions (S3a-P2-other): primary = Eye, Muscle, Heart, Line Noise,
%   Channel Noise; EMG-test = the same without Muscle; Other never removed. Writes outFile (no overwrite).
assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
S = dir(fullfile(batchDir, 'state', '*.json')); rows = {};
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(S(k).folder, S(k).name)));
    if ~any(strcmp(st.status, {'verified', 'flagged'})), continue; end
    md = java.security.MessageDigest.getInstance('SHA-256'); fid = fopen(st.canonical.path, 'r');
    while true, x = fread(fid, 16 * 2^20, '*uint8'); if isempty(x), break; end, md.update(typecast(x, 'int8')); end
    fclose(fid); h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
    assert(strcmp(h, st.canonical.sha256), '%s: SHA-256 mismatch', S(k).name);
    L = load(st.canonical.path); q = L.P2.qc; c = q.nPerClass_p08;
    rows{end+1} = table(string(L.P2.subject), q.nGood, q.rank, q.nIC, c(1), c(2), c(3), c(4), c(5), c(6), c(7), ...
        numel(L.P2.lists.beta_withoutOther), numel(L.P2.lists.emg_withoutOther), q.asrModifiedFraction, ...
        'VariableNames', {'subject', 'n_good', 'rank', 'n_ic', 'p08_brain', 'p08_muscle', 'p08_eye', 'p08_heart', ...
        'p08_line', 'p08_chan', 'p08_other', 'removed_primary', 'removed_emg', 'asr_modified_fraction'}); %#ok<AGROW>
end
T = vertcat(rows{:}); writetable(T, outFile); disp(T);
end
