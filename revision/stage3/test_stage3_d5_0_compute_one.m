function ok = test_stage3_d5_0_compute_one(workDir, step, labelsTsv)
%TEST_STAGE3_D5_0_COMPUTE_ONE  Equivalence of stage3_d5_0_compute_one with stage3_d5_0_line_noise.m,
%   on synthetic data only (S3a-INF-1 §10, "The equivalence test (C)").
%   ok = test_stage3_d5_0_compute_one(workDir, step, labelsTsv)
%     step 'data'    write synthetic BrainVision files (seeded random data plus line sinusoids,
%                    127 channels with the real labels read from labelsTsv, one raw boundary),
%                    synthetic channels.tsv, a synthetic D4e block table and a manifest into workDir;
%     step 'script'  run the UNCHANGED stage3_d5_0_line_noise.m and the pre-exc reconstruction,
%                    each from a temporary copy of the revision/stage3 layout whose own get_paths.m
%                    points at workDir;
%     step 'fn'      run stage3_d5_0_compute_one on the same files;
%     step 'compare' isequaln on every variable (res, F, d, f0s, nChunk) and stage3_compare 'd5_0';
%                    since S3a-D5-0-amend2 res.fpk is excluded (the guarded refinement differs from the
%                    unchanged script by design): values that differ must be grid points within
%                    f0 +/- 0.55 Hz, every other field must be identical;
%     step 'all'     data + script + fn + compare in this process.
%   Two synthetic recordings: sub-01_rest (labels in channels.tsv order) and sub-13_rest (two labels
%   swapped in the .vhdr, as in the real sub-13; exercises the S3a-D5-0-exc branch). The pre-exc
%   reconstruction is run on sub-01 only: it stops on sub-13 by design (the label assert).
%   No real EEG data are read; labelsTsv is a channels.tsv text file (channel names only).

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, fullfile(repo, 'revision', 'infra'));
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
recs = {'sub-01_rest', 'sub-13_rest'};
ok = true;
switch step
    case 'data',    makeData(workDir, labelsTsv);
    case 'script',  runScripts(workDir, repo, recs);
    case 'fn',      runFn(workDir, recs);
    case 'compare', ok = compareAll(workDir, recs);
    case 'all'
        makeData(workDir, labelsTsv); runScripts(workDir, repo, recs); runFn(workDir, recs);
        ok = compareAll(workDir, recs);
    otherwise, error('unknown step %s', step);
end
end

% ---------------------------------------------------------------------------------------------
function makeData(workDir, labelsTsv)
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
lab = ct.name;
assert(numel(lab) == 127, 'expected 127 channel labels');
fs = 1000; T = 100; n = fs * T;
blocks = [5 45; 55 95];                                    % s; raw boundary at 50 s (between blocks)
rows = {};
for r = ["sub-01", "sub-13"]
    rng(1, 'twister');
    t = (0:n-1) / fs;
    X = 20 * randn(127, n);
    for f0 = [50 100 150 200]                              % line components, varying per channel
        X = X + (5 + 10 * rand(127, 1)) .* sin(2 * pi * (f0 + 0.05 * randn) * t + 2 * pi * rand(127, 1));
    end
    X = X + cumsum(randn(127, n), 2) * 0.05;               % slow drift
    EEG = eeg_emptyset;
    EEG.srate = fs; EEG.nbchan = 127; EEG.pnts = n; EEG.trials = 1; EEG.xmin = 0; EEG.xmax = (n - 1) / fs;
    EEG.data = single(X);
    vlab = lab;
    if r == "sub-13", vlab([121 124]) = vlab([124 121]); end   % swapped labels in the .vhdr only
    EEG.chanlocs = struct('labels', cellstr(vlab)');
    EEG.event = struct('type', {'boundary'}, 'latency', {50 * fs + 1}, 'duration', {0});
    EEG = eeg_checkset(EEG);
    d = fullfile(workDir, 'raw', char(r), 'eeg');
    if ~exist(d, 'dir'), mkdir(d); end
    pop_writebva(EEG, fullfile(d, [char(r) '_task-rest_eeg']));
    writetable(table(lab, repmat("EEG", 127, 1), repmat("uV", 127, 1), 'VariableNames', {'name', 'type', 'units'}), ...
        fullfile(d, [char(r) '_task-rest_channels.tsv']), 'FileType', 'text', 'Delimiter', '\t');
    for k = 1:2
        rows(end+1, :) = {char(r), 'rest', 'unchanged', blocks(k, 1), blocks(k, 2)}; %#ok<AGROW>
    end
end
o = fullfile(workDir, 'out', 'stage3');
if ~exist(o, 'dir'), mkdir(o); end
writetable(cell2table(rows, 'VariableNames', {'subject', 'task', 'status', 'new_start_s', 'new_end_s'}), ...
    fullfile(o, 'd4e_block_clipping.csv'));
% manifest of every synthetic raw file (relpath, size, sha256)
L = dir(fullfile(workDir, 'raw', '**', '*'));
L = L(~[L.isdir]);
fid = fopen(fullfile(workDir, 'manifest.tsv'), 'w');
fprintf(fid, 'relpath\tsize\tsha256\n');
for k = 1:numel(L)
    f = fullfile(L(k).folder, L(k).name);
    rel = strrep(f(numel(fullfile(workDir, 'raw')) + 2:end), '\', '/');
    fprintf(fid, '%s\t%d\t%s\n', rel, L(k).bytes, sha256File(f));
end
fclose(fid);
fprintf('synthetic data written to %s\n', workDir);
end

function runScripts(workDir, repo, recs)
src = fullfile(repo, 'revision', 'stage3');
pre = fullfile(src, 'historical', 'd5_0_2026-10-04', 'stage3_d5_0_line_noise_pre_exc_reconstructed.m');
layouts = {'layout_current', fullfile(src, 'stage3_d5_0_line_noise.m'), 'out', recs;
           'layout_preexc', pre, 'out_preexc', recs(1)};
for k = 1:size(layouts, 1)
    L = fullfile(workDir, layouts{k, 1});
    s3 = fullfile(L, 'revision', 'stage3');
    if ~exist(s3, 'dir'), mkdir(s3); end
    copyfile(layouts{k, 2}, fullfile(s3, 'stage3_d5_0_line_noise.m'));
    copyfile(fullfile(src, 'stage3_params.m'), s3);
    copyfile(fullfile(src, 'stage3_log_entry.m'), s3);
    outRoot = fullfile(workDir, layouts{k, 3});
    if ~exist(fullfile(outRoot, 'stage3'), 'dir'), mkdir(fullfile(outRoot, 'stage3')); end
    if ~strcmp(outRoot, fullfile(workDir, 'out'))
        copyfile(fullfile(workDir, 'out', 'stage3', 'd4e_block_clipping.csv'), fullfile(outRoot, 'stage3'), 'f');
    end
    fid = fopen(fullfile(L, 'get_paths.m'), 'w');
    fprintf(fid, ['function p = get_paths()\n%% synthetic test layout (test_stage3_d5_0_compute_one)\n' ...
        'p.bidsRoot = ''%s'';\np.outRoot = ''%s'';\np.derivRoot = '''';\np.taskDeriv = '''';\np.eegOutRoot = '''';\nend\n'], ...
        fullfile(workDir, 'raw'), outRoot);
    fclose(fid);
    runOne(fullfile(s3, 'stage3_d5_0_line_noise.m'), layouts{k, 4});
    rmpath(s3, L);
    clear('get_paths', 'stage3_params');
end
end

function runOne(scriptFile, onlyRecordings) %#ok<INUSD>
run(scriptFile);                                           % the script reads onlyRecordings
end

function runFn(workDir, recs)
for k = 1:numel(recs)
    p = split(string(recs{k}), "_");
    params = struct('subject', p(1), 'task', p(2), 'rawRoot', fullfile(workDir, 'raw'), ...
        'manifest', fullfile(workDir, 'manifest.tsv'), ...
        'blockTable', fullfile(workDir, 'out', 'stage3', 'd4e_block_clipping.csv'));
    o = fullfile(workDir, 'fn');
    if ~exist(o, 'dir'), mkdir(o); end
    stage3_d5_0_compute_one(params, fullfile(o, [recs{k} '.mat']));
end
end

function ok = compareAll(workDir, recs)
ok = true;
pairs = {};
for k = 1:numel(recs)
    pairs(end+1, :) = {fullfile(workDir, 'out', 'stage3', 'd5_0', 'per_recording', [recs{k} '.mat']), ...
                       fullfile(workDir, 'fn', [recs{k} '.mat']), ['current vs fn, ' recs{k}]}; %#ok<AGROW>
end
pairs(end+1, :) = {fullfile(workDir, 'out_preexc', 'stage3', 'd5_0', 'per_recording', [recs{1} '.mat']), ...
                   fullfile(workDir, 'fn', [recs{1} '.mat']), ['pre-exc reconstruction vs fn, ' recs{1}]};
for k = 1:size(pairs, 1)
    A = load(pairs{k, 1}); B = load(pairs{k, 2});
    fA = A.res.fpk; fB = B.res.fpk; A.res.fpk = []; B.res.fpk = [];   % S3a-D5-0-amend2
    eqAll = isequaln(A, B) && isequal(sort(fieldnames(A)), sort(fieldnames(B)));
    j = fullfile(workDir, sprintf('compare_%d.json', k));
    stage3_compare(pairs{k, 1}, pairs{k, 2}, 'd5_0', j);
    c = jsondecode(fileread(j));
    cmpOthers = all([c.fields(~strcmp({c.fields.field}, 'res.fpk')).equal]);
    f0 = reshape([50 100 150 200], 1, 4);
    dif = fA ~= fB & ~(isnan(fA) & isnan(fB));
    off = fB - f0;                                         % fn output, chunks x f0 broadcast
    okF = all(abs(off(:)) <= 0.55 + 1e-9 | isnan(off(:))) && all(abs(off(dif) * 10 - round(off(dif) * 10)) < 1e-6);
    fprintf('%-45s isequaln(all but res.fpk) = %d; stage3_compare d5_0 fields but res.fpk equal = %d; fpk: %d of %d differ, all on the grid and within +/-0.55 Hz: %d; nChunk = %s\n', ...
        pairs{k, 3}, eqAll, cmpOthers, sum(dif(:)), numel(dif), okF, mat2str(A.nChunk));
    ok = ok && eqAll && cmpOthers && okF;
end
if ok, fprintf('EQUIVALENCE PASS\n'); else, fprintf('EQUIVALENCE FAIL\n'); end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
