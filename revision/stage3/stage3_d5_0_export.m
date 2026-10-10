function stage3_d5_0_export(canonicalFile, canonicalSha256, outDir, batchId)
%STAGE3_D5_0_EXPORT  Write the D5-0 outputs named in S3a-D5-0 from the verified canonical output of a
%   D5-0 assembly batch (S3a-D5-0-asm): line_noise_by_channel.csv, line_noise_by_recording.csv,
%   run_info.txt, plus line_noise_rules_by_recording.csv. The MAT file is checked against its
%   recorded SHA-256 first. Refuses to overwrite any existing output (new results, new files).

assert(strcmp(sha256File(canonicalFile), canonicalSha256), 'canonical output does not match its recorded SHA-256');
names = {'line_noise_by_channel.csv', 'line_noise_by_recording.csv', 'line_noise_rules_by_recording.csv', 'run_info.txt'};
if ~exist(outDir, 'dir'), mkdir(outDir); end
for k = 1:numel(names)
    assert(exist(fullfile(outDir, names{k}), 'file') ~= 2, 'refusing to overwrite %s', fullfile(outDir, names{k}));
end
A = load(canonicalFile);
writetable(A.TC, fullfile(outDir, names{1}));
writetable(A.TR, fullfile(outDir, names{2}));
writetable(A.rulesByRecording, fullfile(outDir, names{3}));
fid = fopen(fullfile(outDir, names{4}), 'w');
fprintf(fid, 'S3a-D5-0 assembly (S3a-D5-0-asm), exported %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'assembly batch %s; canonical output %s SHA-256 %s\n', batchId, canonicalFile, canonicalSha256);
fprintf(fid, 'source batch %s (batch.json SHA-256 %s); %d canonical per-recording outputs, each hash-checked before loading\n', ...
    A.sourceBatch.dir, A.sourceBatch.batchJsonSha256, height(A.sources));
fprintf(fid, '%s\n', A.runInfo{:});
fclose(fid);
fprintf('exported to %s\n', outDir);
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
