function ok = test_stage3_d5b_chunked(workDir, labelsTsv)
%TEST_STAGE3_D5B_CHUNKED  Synthetic test of the chunked (b) residual test (S3a-D5b-amend1) and of the
%   null generator (S3a-D5b-null). No real EEG data.
%   1. Synthetic data and the unsplit result (groupSize 16) from test_stage3_d5b_compute_one.
%   2. Unsplit with groupSize 6, and units of 6 channels (1-6, 7-12, 13-18, 19-20) merged by
%      stage3_d5b_merge from a synthetic verified batch: merged == unsplit(6) exactly (isequaln).
%   3. merged vs unsplit(16): maximum absolute difference reported; pass if <= 1e-6 (dB / PSD units),
%      because the filters may round differently for different group widths.
%   4. A batch with a missing unit is refused.
%   5. stage3_d5b_null_make on the synthetic recording: header, markers and channels.tsv identical,
%      .eeg of identical size with different content, manifest written; one unit runs on the twin.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
ok0 = test_stage3_d5b_compute_one(workDir, labelsTsv);
base = struct('subject', 'sub-90', 'task', 'rest', 'role', 'synthetic', 'rawRoot', fullfile(workDir, 'raw'), ...
    'manifest', fullfile(workDir, 'manifest.tsv'), 'blockTable', fullfile(workDir, 'blocks.csv'));
p6 = base; p6.groupSize = 6; f6 = fullfile(workDir, 'full_g6.mat');
stage3_d5b_compute_one(p6, f6);
ranges = [1 6; 7 12; 13 18; 19 20];
src = fullfile(workDir, 'unitbatch'); mkdir(fullfile(src, 'state'));
writeJson(fullfile(src, 'batch.json'), struct('mode', 'Batch', 'status', 'DONE'));
for k = 1:size(ranges, 1)
    pu = base; pu.chans = ranges(k, :);
    f = fullfile(workDir, sprintf('unit_%02d.mat', k));
    stage3_d5b_compute_one(pu, f);
    writeJson(fullfile(src, 'state', sprintf('sub-90_rest_u%02d.json', k)), struct('status', 'verified', ...
        'canonical', struct('path', f, 'sha256', sha256File(f))));
end
mf = fullfile(workDir, 'merged.mat');
stage3_d5b_merge(struct('sourceBatchDir', src), mf);
M = load(mf); m = M.results(1);
G6 = load(f6); g6 = G6.res;
c2 = isequaln(m, g6);
fprintf('2 merged == unsplit(groupSize 6): %d\n', c2);
G16 = load(fullfile(workDir, 'a.mat')); g16 = G16.res;
fn = {'avgPBefore', 'avgPAfter', 'excessBeforeDb', 'excessAfterDb', 'flankChangeDb', 'chunkResidualMaxDb'};
mx = 0;
for i = 1:numel(fn), mx = max(mx, max(abs(m.(fn{i})(:) - g16.(fn{i})(:)))); end
c3 = mx <= 1e-6 && m.rb1Pass == g16.rb1Pass && m.rb2Pass == g16.rb2Pass;
fprintf('3 merged vs unsplit(groupSize 16): max abs difference %.3g -> %d\n', mx, c3);
delete(fullfile(src, 'state', 'sub-90_rest_u03.json'));
refused = false;
try, stage3_d5b_merge(struct('sourceBatchDir', src), fullfile(workDir, 'merged_bad.mat')); catch ME, refused = contains(ME.message, 'cover'); end
fprintf('4 missing unit refused: %d\n', refused);
% 5. null generator
ts = fullfile(workDir, 'ts.csv');
writetable(table("sub-90", "rest", "synthetic", 1, 'VariableNames', {'subject', 'task', 'role', 'r2_rank'}), ts);
nd = fullfile(workDir, 'null');
stage3_d5b_null_make(fullfile(workDir, 'raw'), ts, nd, 100);
a = fullfile(workDir, 'raw', 'sub-90', 'eeg'); b = fullfile(nd, 'raw', 'sub-90', 'eeg');
same = @(n) isequal(fileread(fullfile(a, n)), fileread(fullfile(b, n)));
ia = dir(fullfile(a, 'sub-90_task-rest_eeg.eeg')); ib = dir(fullfile(b, 'sub-90_task-rest_eeg.eeg'));
c5 = same('sub-90_task-rest_eeg.vhdr') && same('sub-90_task-rest_eeg.vmrk') && same('sub-90_task-rest_channels.tsv') ...
    && ia.bytes == ib.bytes && ~strcmp(sha256File(fullfile(a, ia.name)), sha256File(fullfile(b, ib.name))) ...
    && exist(fullfile(nd, 'manifest.tsv'), 'file') == 2;
pn = base; pn.rawRoot = fullfile(nd, 'raw'); pn.manifest = fullfile(nd, 'manifest.tsv'); pn.chans = [1 6];
stage3_d5b_compute_one(pn, fullfile(workDir, 'null_unit.mat'));
fprintf('5 null twin: headers identical, size identical, content different, manifest, unit runs: %d\n', c5);
ok = ok0 && c2 && c3 && refused && c5;
if ok, fprintf('D5B CHUNKED PASS\n'); else, fprintf('D5B CHUNKED FAIL\n'); end
end

function writeJson(file, s)
fid = fopen(file, 'w', 'n', 'UTF-8'); fwrite(fid, jsonencode(s), 'char'); fclose(fid);
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
