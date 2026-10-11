function stage3_d4e4_export(canonicalFile, canonicalSha256, outDir, batchId)
%STAGE3_D4E4_EXPORT  Write the S3a-D4e-4-test outputs from the verified canonical output of a D4e-4
%   assembly batch (S3a-D4e-4-asm): neighbour_scores.csv, rank_predictability_by_recording.csv,
%   predictability_by_channel.csv (named in S3a-D4e-4-test), test_n_by_recording.csv,
%   test_n_decisions.csv, near_perfect_predictors.csv and run_info.txt. Never overwrites.

assert(strcmp(sha256File(canonicalFile), canonicalSha256), 'canonical output does not match its recorded SHA-256');
files = {'neighbourScores', 'neighbour_scores.csv'; 'rankByRecording', 'rank_predictability_by_recording.csv';
         'predByChannel', 'predictability_by_channel.csv'; 'nByRecording', 'test_n_by_recording.csv';
         'nDecisions', 'test_n_decisions.csv'; 'nearPerfectPredictors', 'near_perfect_predictors.csv'};
if ~exist(outDir, 'dir'), mkdir(outDir); end
for k = 1:size(files, 1)
    assert(exist(fullfile(outDir, files{k, 2}), 'file') ~= 2, 'refusing to overwrite %s', files{k, 2});
end
assert(exist(fullfile(outDir, 'run_info.txt'), 'file') ~= 2, 'refusing to overwrite run_info.txt');
A = load(canonicalFile);
for k = 1:size(files, 1), writetable(A.(files{k, 1}), fullfile(outDir, files{k, 2})); end
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w');
fprintf(fid, 'S3a-D4e-4-test assembly (S3a-D4e-4-asm), exported %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'assembly batch %s; canonical output %s SHA-256 %s\n', batchId, canonicalFile, canonicalSha256);
fprintf(fid, 'source batch %s (batch.json SHA-256 %s); %d canonical per-recording outputs, each hash-checked\n', ...
    A.sourceBatch.dir, A.sourceBatch.batchJsonSha256, height(A.sources));
fprintf(fid, '%s\n', A.entryHashes{:});
fclose(fid);
fprintf('exported to %s\n', outDir);
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
