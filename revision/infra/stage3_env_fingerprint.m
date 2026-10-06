function fp = stage3_env_fingerprint(jobFunc, configSha, testMode)
%STAGE3_ENV_FINGERPRINT  Environment fingerprint of one job process (S3a-INF-1 §1).
%   fp = stage3_env_fingerprint(jobFunc, configSha, testMode) returns a struct that must be
%   identical across the replicas of a job (no time stamps, no PIDs). It then asserts:
%   no parallel pool, parallel.Settings Pool.AutoCreate == false, option_parallel == 0, and
%   hlp_diskcache not on the path. With testMode true (synthetic tests only), a failed assertion
%   is recorded in fp.assertion_failures instead of raising an error.

fp = struct();
fp.version = version;
fp.blas = version('-blas');
fp.lapack = version('-lapack');
fp.maxNumCompThreads = maxNumCompThreads;
fp.MKL_CBWR = getenv('MKL_CBWR');
fp.fftw_planner = fftw('planner');
fp.which_eeglab = which('eeglab');
fp.which_pop_loadbv = which('pop_loadbv');
fp.which_pop_resample = which('pop_resample');
fp.which_resample = which('resample');
fp.which_jobfunc = which(jobFunc);
fp.which_hlp_diskcache = which('hlp_diskcache');
fp.path_sha256 = sha256Text(path);
optFile = fullfile(getenv('USERPROFILE'), 'eeg_options.m');
fp.eeg_options_file = optFile;
if exist(optFile, 'file') == 2, fp.eeg_options_sha256 = sha256Text(fileread(optFile));
else, fp.eeg_options_sha256 = ''; end
fp.runner_config_sha256 = char(configSha);
fp.pool_empty = isempty(gcp('nocreate'));
ps = parallel.Settings;
fp.pool_autocreate = logical(ps.Pool.AutoCreate);
eeglab_options;                                            % defines option_* from eeg_options.m
fp.option_parallel = option_parallel;                      %#ok<NODEF>
fp.option_single = option_single;                          %#ok<NODEF>

fail = {};
if ~fp.pool_empty, fail{end+1} = 'a parallel pool exists'; end
if fp.pool_autocreate, fail{end+1} = 'parallel.Settings Pool.AutoCreate is true'; end
if fp.option_parallel ~= 0, fail{end+1} = 'EEGLAB option_parallel is not 0'; end
if ~isempty(fp.which_hlp_diskcache), fail{end+1} = 'hlp_diskcache is on the path'; end
fp.assertion_failures = fail;
if ~isempty(fail) && ~testMode
    error('stage3:fingerprint', 'environment assertion failed: %s', strjoin(fail, '; '));
end
end

function h = sha256Text(t)
md = java.security.MessageDigest.getInstance('SHA-256');
h = lower(reshape(dec2hex(typecast(md.digest(uint8(unicode2native(t, 'UTF-8'))), 'uint8'), 2)', 1, []));
end
