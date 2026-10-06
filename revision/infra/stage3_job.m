function stage3_job(specFile)
%STAGE3_JOB  Worker: run one replica of one job in this (fresh) MATLAB process (S3a-INF-1 §1, §5).
%   stage3_job(specFile) reads the JSON job spec written by Invoke-Stage3Batch.ps1 and:
%     1. sets maxNumCompThreads(spec.threads) and rng(spec.seedGlobal, 'twister');
%     2. puts spec.paths on the path and starts EEGLAB (nogui) if needed;
%     3. writes the environment fingerprint (stage3_env_fingerprint) to spec.fingerprintFile;
%     4. calls feval(spec.func, params, partialFile), where params = spec.common merged with
%        spec.params (job fields win) and partialFile = <outFile without .mat>.partial.mat;
%     5. moves partialFile to spec.outFile only after the job function has returned, then prints
%        the DONE marker that the runner requires.
%
%   Job-function contract (how a new job type is added; see revision/infra/README.md):
%     func(params, partialFile)  must write exactly one MAT file, partialFile, with save(), and
%     must call stage3_check_input(file, params.rawRoot, params.manifest) for every raw input
%     file before reading it. Any error is left uncaught: the process exits non-zero.

spec = jsondecode(fileread(specFile));
maxNumCompThreads(spec.threads);
rng(spec.seedGlobal, 'twister');
paths = cellstr(spec.paths);
for k = numel(paths):-1:1
    addpath(paths{k});
end
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end

fp = stage3_env_fingerprint(spec.func, spec.configSha256, logical(spec.testMode));
writeJson(spec.fingerprintFile, fp);

params = spec.common;
f = fieldnames(spec.params);
for k = 1:numel(f), params.(f{k}) = spec.params.(f{k}); end
params.replica = spec.replica;
params.attempt = spec.attempt;

[d, n] = fileparts(spec.outFile);
partialFile = fullfile(d, [n '.partial.mat']);
feval(spec.func, params, partialFile);
assert(exist(partialFile, 'file') == 2, 'stage3:job', 'job function wrote no output file');
movefile(partialFile, spec.outFile);
fprintf('STAGE3_JOB_DONE %s %s attempt %d\n', spec.jobId, spec.replica, spec.attempt);
end

function writeJson(file, s)
tmp = [file '.tmp'];
fid = fopen(tmp, 'w', 'n', 'UTF-8');
fwrite(fid, jsonencode(s), 'char');
fclose(fid);
movefile(tmp, file);
end
