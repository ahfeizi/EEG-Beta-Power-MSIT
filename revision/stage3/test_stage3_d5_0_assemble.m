function ok = test_stage3_d5_0_assemble(workDir, labelsTsv)
%TEST_STAGE3_D5_0_ASSEMBLE  Equivalence of stage3_d5_0_assemble + stage3_d5_0_export with the assembly
%   section of the UNCHANGED stage3_d5_0_line_noise.m, on synthetic data only (S3a-D5-0-asm).
%   1. Synthetic per-recording outputs: test_stage3_d5_0_compute_one steps 'data' and 'fn'
%      (sub-01_rest, sub-13_rest; seeded random data, no real EEG).
%   2. The script runs from a temporary layout whose get_paths.m points at workDir, with those
%      outputs in its per_recording cache, so it only assembles.
%   3. A synthetic source batch (batch.json DONE, state files verified, with canonical paths and
%      SHA-256) points at the same files; stage3_d5_0_assemble and stage3_d5_0_export run on it.
%   Pass: both CSVs byte-identical; R1 values, the R2 ranking, R3, the anti-aliasing line and the
%   S3a-D5-0 entry hash equal; a tampered canonical file is refused.

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, fullfile(repo, 'revision', 'infra'));
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
recs = {'sub-01_rest', 'sub-13_rest'};
test_stage3_d5_0_compute_one(workDir, 'data', labelsTsv);
test_stage3_d5_0_compute_one(workDir, 'fn', labelsTsv);
blockTable = fullfile(workDir, 'out', 'stage3', 'd4e_block_clipping.csv');

% ---- 2. the unchanged script, assembly only ---------------------------------------------------
L = fullfile(workDir, 'asm_layout'); s3 = fullfile(L, 'revision', 'stage3'); outRoot = fullfile(workDir, 'asm_out');
cache = fullfile(outRoot, 'stage3', 'd5_0', 'per_recording');
for dd = {s3, fullfile(L, 'docs'), cache}, if ~exist(dd{1}, 'dir'), mkdir(dd{1}); end, end
copyfile(fullfile(here, 'stage3_d5_0_line_noise.m'), s3);
copyfile(fullfile(here, 'stage3_params.m'), s3);
copyfile(fullfile(here, 'stage3_log_entry.m'), s3);
copyfile(fullfile(repo, 'docs', 'decision_log.md'), fullfile(L, 'docs'));
copyfile(blockTable, fullfile(outRoot, 'stage3'));
for k = 1:numel(recs), copyfile(fullfile(workDir, 'fn', [recs{k} '.mat']), cache); end
fid = fopen(fullfile(L, 'get_paths.m'), 'w');
fprintf(fid, ['function p = get_paths()\n%% synthetic test layout (test_stage3_d5_0_assemble)\n' ...
    'p.bidsRoot = ''%s'';\np.outRoot = ''%s'';\np.derivRoot = '''';\np.taskDeriv = '''';\np.eegOutRoot = '''';\nend\n'], ...
    fullfile(workDir, 'raw'), outRoot);
fclose(fid);
runScript(fullfile(s3, 'stage3_d5_0_line_noise.m'));
rmpath(s3, L); clear('get_paths', 'stage3_params');

% ---- 3. synthetic source batch, job function, export ------------------------------------------
src = fullfile(workDir, 'srcbatch');
if ~exist(fullfile(src, 'state'), 'dir'), mkdir(fullfile(src, 'state')); end
writeJson(fullfile(src, 'batch.json'), struct('batchId', 'synthetic', 'mode', 'Batch', 'status', 'DONE'));
for k = 1:numel(recs)
    p = fullfile(workDir, 'fn', [recs{k} '.mat']);
    writeJson(fullfile(src, 'state', [recs{k} '.json']), struct('id', recs{k}, 'status', 'verified', 'flags', {{}}, ...
        'canonical', struct('replica', 'A', 'path', p, 'sha256', sha256File(p))));
end
params = struct('sourceBatchDir', src, 'blockTable', blockTable);
asm = fullfile(workDir, 'asm.mat');
stage3_d5_0_assemble(params, asm);
exp = fullfile(workDir, 'export');
if exist(exp, 'dir'), rmdir(exp, 's'); end
stage3_d5_0_export(asm, sha256File(asm), exp, 'synthetic');

% ---- compare --------------------------------------------------------------------------------
ok = true;
sd = fullfile(outRoot, 'stage3', 'd5_0');
for f = {'line_noise_by_channel.csv', 'line_noise_by_recording.csv'}
    e = isequal(readBytes(fullfile(sd, f{1})), readBytes(fullfile(exp, f{1})));
    fprintf('%-30s byte-identical: %d\n', f{1}, e); ok = ok && e;
end
a = splitlines(string(fileread(fullfile(sd, 'run_info.txt'))));
b = splitlines(string(fileread(fullfile(exp, 'run_info.txt'))));
pick = @(x, pat) x(startsWith(x, pat));
checks = {
    'S3a-D5-0 entry hash', pick(a, "SHA-256 of the S3a-D5-0 log"), pick(b, "SHA-256 of the S3a-D5-0 log")
    'anti-aliasing gains', pick(a, "Anti-aliasing"), pick(b, "Anti-aliasing")
    'R1 values', regexprep(pick(a, "R1 "), ' -> .*', ''), regexprep(pick(b, "R1 "), ' -> .*', '')
    'R1 verdicts', regexprep(pick(a, "R1 "), '.* -> (\w+).*', '$1'), regexprep(pick(b, "R1 "), '.* -> (\w+).*', '$1')
    'R2 ranking (top 10 of the script)', pick(a, "  "), pick(b, "  ")
    'R3', pick(a, "R3 "), pick(b, "R3 ")};
for k = 1:size(checks, 1)
    x = checks{k, 2}; y = checks{k, 3};
    e = ~isempty(x) && isequal(x, y(1:min(numel(y), numel(x))));
    fprintf('%-35s equal: %d (%d line(s))\n', checks{k, 1}, e, numel(x)); ok = ok && e;
end
% a tampered canonical output is refused
t = fullfile(workDir, 'fn', [recs{2} '.mat']);
fidt = fopen(t, 'a'); fwrite(fidt, uint8(0)); fclose(fidt);
refused = false;
try, stage3_d5_0_assemble(params, fullfile(workDir, 'asm_tampered.mat')); catch ME, refused = contains(ME.message, 'SHA-256'); end
fprintf('%-35s %d\n', 'tampered canonical file refused:', refused); ok = ok && refused;
if ok, fprintf('ASSEMBLY EQUIVALENCE PASS\n'); else, fprintf('ASSEMBLY EQUIVALENCE FAIL\n'); end
end

function runScript(f)
run(f);
end

function b = readBytes(f)
fid = fopen(f, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
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
