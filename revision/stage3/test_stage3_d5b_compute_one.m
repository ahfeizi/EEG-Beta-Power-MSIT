function ok = test_stage3_d5b_compute_one(workDir, labelsTsv)
%TEST_STAGE3_D5B_COMPUTE_ONE  Synthetic test of stage3_d5b_compute_one (S3a-D5b). No real EEG data;
%   labelsTsv is a channels.tsv text file (names only; the first 20 are used, TP9 among them).
%   Recording sub-90: 20 channels, 1000 Hz, 60 s, white noise (10 uV) plus stationary lines at 50,
%   100, 150 and 200 Hz (4 uV, channel-specific phase); raw boundaries at 30 s and 57.5 s, so the last
%   segment (2.5 s) is shorter than one 4 s window; blocks 5-25 s and 33-53 s.
%   Companion sub-91: the identical noise without lines (noise-only reference). With only 4 chunks,
%   the max-over-bins excess of pure noise is itself several dB, so a strict 3 dB check on this short
%   signal would test the measure's noise, not the job.
%   Checks: lines present before (excess >= 20 dB); after (b) the line recording's maximum excess is
%   within 1 dB of the noise-only recording's maximum excess (synthetic tolerance, not the real rule;
%   R-b1 is printed); flank change within 0.5 dB (R-b2); 3 segments, the short one not processed;
%   a block overlapping the short segment is refused; two runs content-identical (stage3_compare 'all').

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
lab = ct.name(1:20);
fs = 1000; n = 60 * fs; t = (0:n-1) / fs;
rng(3, 'twister');
X0 = 10 * randn(20, n); X = X0;
for f0 = [50 100 150 200], X = X + 4 * sin(2 * pi * f0 * t + 2 * pi * rand(20, 1)); end
for sid = ["sub-90", "sub-91"]
    if sid == "sub-91", X = X0; end
    EEG = eeg_emptyset;
    EEG.srate = fs; EEG.nbchan = 20; EEG.pnts = n; EEG.trials = 1; EEG.xmin = 0; EEG.xmax = (n - 1) / fs;
    EEG.data = single(X); EEG.chanlocs = struct('labels', cellstr(lab)');
    EEG.event = struct('type', {'boundary', 'boundary'}, 'latency', {30 * fs + 1, 57.5 * fs + 1}, 'duration', {0, 0});
    EEG = eeg_checkset(EEG);
    d = fullfile(workDir, 'raw', char(sid), 'eeg'); if ~exist(d, 'dir'), mkdir(d); end
    pop_writebva(EEG, fullfile(d, [char(sid) '_task-rest_eeg']));
    writetable(table(lab, repmat("EEG", 20, 1), repmat("uV", 20, 1), 'VariableNames', {'name', 'type', 'units'}), ...
        fullfile(d, [char(sid) '_task-rest_channels.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
L = dir(fullfile(workDir, 'raw', '**', '*')); L = L(~[L.isdir]);
fid = fopen(fullfile(workDir, 'manifest.tsv'), 'w'); fprintf(fid, 'relpath\tsize\tsha256\n');
for k = 1:numel(L)
    f = fullfile(L(k).folder, L(k).name);
    fprintf(fid, '%s\t%d\t%s\n', strrep(f(numel(fullfile(workDir, 'raw')) + 2:end), '\', '/'), L(k).bytes, sha256File(f));
end
fclose(fid);
bt = fullfile(workDir, 'blocks.csv'); btBad = fullfile(workDir, 'blocks_bad.csv');
writetable(cell2table({'sub-90', 'rest', 'unchanged', 5, 25; 'sub-90', 'rest', 'unchanged', 33, 53; ...
    'sub-91', 'rest', 'unchanged', 5, 25; 'sub-91', 'rest', 'unchanged', 33, 53}, ...
    'VariableNames', {'subject', 'task', 'status', 'new_start_s', 'new_end_s'}), bt);
writetable(cell2table({'sub-90', 'rest', 'unchanged', 5, 25; 'sub-90', 'rest', 'unchanged', 46, 59.9}, ...
    'VariableNames', {'subject', 'task', 'status', 'new_start_s', 'new_end_s'}), btBad);
p = struct('subject', 'sub-90', 'task', 'rest', 'role', 'synthetic', 'rawRoot', fullfile(workDir, 'raw'), ...
    'manifest', fullfile(workDir, 'manifest.tsv'), 'blockTable', bt);
fa = fullfile(workDir, 'a.mat'); fb = fullfile(workDir, 'b.mat');
stage3_d5b_compute_one(p, fa); stage3_d5b_compute_one(p, fb);
p0 = p; p0.subject = 'sub-91'; fn0 = fullfile(workDir, 'noise.mat');
stage3_d5b_compute_one(p0, fn0);
R = load(fa); R = R.res; R0 = load(fn0); R0 = R0.res;
k = R.kept;
noiseMax = max(R0.excessBeforeDb(k, :), [], 'all');
c1 = all(R.excessBeforeDb(k, :) >= 20, 'all') && R.maxExcessAfterKeptDb <= noiseMax + 1;
fprintf('before: min excess %.1f dB; after: max excess %.2f dB (R-b1 %d); noise-only max excess %.2f dB -> %d\n', ...
    min(R.excessBeforeDb(k, :), [], 'all'), R.maxExcessAfterKeptDb, R.rb1Pass, noiseMax, c1);
c2 = R.rb2Pass;
fprintf('max |flank change| %.3f dB (R-b2 %d) -> %d\n', R.maxAbsFlankChangeKeptDb, R.rb2Pass, c2);
c3 = size(R.segments, 1) == 3 && isequal(R.segments(:, 3)', [1 1 0]) && sum(k) == 19;
fprintf('segments %s; kept channels %d -> %d\n', mat2str(R.segments), sum(k), c3);
pb = p; pb.blockTable = btBad; refused = false;
try, stage3_d5b_compute_one(pb, fullfile(workDir, 'bad.mat')); catch ME, refused = strcmp(ME.identifier, 'stage3:d5b'); end
fprintf('block overlapping a short segment refused: %d\n', refused);
j = fullfile(workDir, 'cmp.json'); stage3_compare(fa, fb, 'all', j);
c5 = jsondecode(fileread(j)).equal;
fprintf('two runs content-identical: %d\n', c5);
ok = c1 && c2 && c3 && refused && c5;
if ok, fprintf('D5B SYNTHETIC PASS\n'); else, fprintf('D5B SYNTHETIC FAIL\n'); end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
