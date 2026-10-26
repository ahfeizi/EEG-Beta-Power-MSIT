function ok = test_stage3_p2_compute_one(workDir, labelsTsv)
%TEST_STAGE3_P2_COMPUTE_ONE  Synthetic test of stage3_p2_compute_one, stage3_p2_rebuild and stage3_d12_trials
%   (S3a-P2, S3a-P2-impl). No real EEG data; labelsTsv is a channels.tsv (127 names).
%   Subject sub-90: part-1-like rest (60 s) and MSIT+ (80 s) at 500 Hz, 125 channels with template positions
%   on a 95 mm sphere (already centred), 25 smooth sources + a frontal blink-like source + a temporal
%   broadband source + sensor noise; D6 removes T7 and O2.
%   Checks: 1. bundle: 123 good channels + FCz, rank 123 = pca, ICA and ICLabel sizes, lists;
%   2. analysed data = part-1 minus bad channels, FCz added, average reference (no ASR on them);
%   3. A = B ('all'); 4. a dependent channel (Pz = mean of P1, P2) stops the job on the rank check;
%   5. rebuild: 126 channels in fullChanlocs order, average reference, deterministic; rejectOther required;
%   6. an excluded subject is refused; 7. D12 counts on a synthetic trial set.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
if ~exist('pop_runica', 'file'), eeglab('nogui'); end
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
mont = ct.name(~ismember(ct.name, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]));
rng(21, 'twister');
tpl = fullfile(fileparts(which('dipfitdefs')), 'standard_BESA', 'standard-10-5-cap385.elp');
tl = readlocs(tpl); tlab = lower(string({tl.labels}));
names = [mont; "FCz"]; U = nan(numel(names), 3);
for k = 1:numel(names)
    i = find(tlab == lower(names(k)), 1); v = [tl(i).X, tl(i).Y, tl(i).Z]; U(k, :) = v / norm(v);
end
pos = struct('label', names, 'X', 95 * U(:, 1), 'Y', 95 * U(:, 2), 'Z', 95 * U(:, 3));
fs = 500; Um = U(1:numel(mont), :);
src = randn(25, 3); src = src ./ vecnorm(src, 2, 2);
G = exp(-(acos(min(1, Um * src')) / 0.7) .^ 2);
gBlink = exp(-(acos(min(1, Um * [1 0 0.2]' / norm([1 0 0.2]))) / 0.4) .^ 2);
gMus = exp(-(acos(min(1, Um * [0 -1 0]')) / 0.3) .^ 2);
p1 = fullfile(workDir, 'p1'); mkdir(p1); files = struct();
for c = ["rest", "msit"]
    n = (60 + 20 * (c == "msit")) * fs; t = (0:n-1) / fs;
    S = filter(ones(1, 10) / 10, 1, randn(25, n), [], 2) * 10;
    S(1:3, :) = S(1:3, :) + 15 * sin(2 * pi * 10 * t + rand(3, 1) * 2 * pi);
    blink = zeros(1, n); blink(1 + (round(2 * fs):round(4 * fs):n - fs)) = 1; blink = conv(blink, hann(150)', 'same') * 150;
    X = G * S + gBlink * blink + gMus * (5 * randn(1, n)) + 0.5 * randn(numel(mont), n);
    EEG = eeg_emptyset; EEG.srate = fs; EEG.nbchan = numel(mont); EEG.pnts = n; EEG.trials = 1;
    EEG.xmin = 0; EEG.xmax = (n - 1) / fs; EEG.data = single(X); EEG.chanlocs = struct('labels', cellstr(mont)');
    EEG.event = struct('type', {'boundary'}, 'latency', {n / 2 + 0.5}, 'duration', {100});
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG.etc.stage3 = struct('subject', 'sub-90', 'task', char(c));
    f = fullfile(p1, sprintf('sub-90_task-%s_s3p1.set', c)); save(f, 'EEG', '-mat'); files.(char(c)) = f;
end
man = fullfile(p1, 'manifest.tsv'); writeMan(man, files);
D6 = struct('subject', 'sub-90', 'excluded', false, 'channels', mont, 'positions', pos, ...
    'removedChannels', ["T7"; "O2"]); %#ok<NASGU>
d6f = fullfile(workDir, 'd6.mat'); save(d6f, 'D6');
base = struct('subject', 'sub-90', 'p1Rest', files.rest, 'p1Msit', files.msit, 'p1Manifest', man, ...
    'd6File', d6f, 'd6Sha', sha(d6f), 'seedGlobal', 1);
fa = fullfile(workDir, 'a.mat'); fb = fullfile(workDir, 'b.mat');
stage3_p2_compute_one(base, fa); stage3_p2_compute_one(base, fb);
A = load(fa); P2 = A.P2;
% 1. bundle
c1 = P2.qc.nGood == 123 && P2.qc.rank == 123 && P2.rest.nbchan == 124 && strcmp(P2.rest.chanlocs(end).labels, 'FCz') ...
    && isequal(size(P2.rest.icaweights), [123 124]) && isequal(size(P2.classifications), [123 7]) ...
    && numel(P2.fullChanlocs) == 126 && isa(P2.rest.data, 'single') && all(isfield(P2.lists, {'beta_withoutOther', 'emg_withOther'}));
fprintf('1 bundle: good %d, rank %d, ICs %d, rejected beta %d/%d, EMG %d/%d; ASR modified %.3f -> %d\n', P2.qc.nGood, P2.qc.rank, ...
    P2.qc.nIC, numel(P2.lists.beta_withoutOther), numel(P2.lists.beta_withOther), numel(P2.lists.emg_withoutOther), ...
    numel(P2.lists.emg_withOther), P2.qc.asrModifiedFraction, c1);
% 2. analysed data untouched by ASR: part-1 minus bad, FCz added, average reference
L = load(files.rest, '-mat'); X = double(L.EEG.data); X(ismember(mont, ["T7", "O2"]), :) = [];
Y = [X; zeros(1, size(X, 2))]; Y = Y - mean(Y, 1);
d2 = max(abs(double(P2.rest.data(:)) - Y(:)));
c2 = d2 < 1e-3;
fprintf('2 analysed rest = re-referenced part-1 (max |diff| %.2g uV) -> %d\n', d2, c2);
% 3. A = B
j = fullfile(workDir, 'cmp.json'); stage3_compare(fa, fb, 'all', j); c3 = jsondecode(fileread(j)).equal;
fprintf('3 A = B: %d\n', c3);
% 4. rank check stops on a dependent channel
p1d = fullfile(workDir, 'p1dep'); mkdir(p1d); fd = struct();
for c = ["rest", "msit"]
    L = load(files.(c), '-mat'); EEG = L.EEG; i = find(mont == "Pz"); i1 = find(mont == "P1"); i2 = find(mont == "P2");
    EEG.data(i, :) = (EEG.data(i1, :) + EEG.data(i2, :)) / 2;
    f = fullfile(p1d, sprintf('sub-90_task-%s_s3p1.set', c)); save(f, 'EEG', '-mat'); fd.(char(c)) = f;
end
mand = fullfile(p1d, 'manifest.tsv'); writeMan(mand, fd);
r4 = refused(@() stage3_p2_compute_one(setf(base, 'p1Rest', fd.rest, 'p1Msit', fd.msit, 'p1Manifest', mand), fullfile(workDir, 'x4.mat')), 'rank');
fprintf('4 dependent channel stops the job (rank): %d\n', r4);
% 5. rebuild
R1 = stage3_p2_rebuild(P2, 'rest', 'beta', false); R2 = stage3_p2_rebuild(P2, 'rest', 'beta', false);
R0 = stage3_p2_rebuild(P2, 'msit', 'none');
c5 = R1.nbchan == 126 && isequal({R1.chanlocs.labels}, {P2.fullChanlocs.labels}) && max(abs(mean(R1.data, 1))) < 1e-8 ...
    && isequaln(R1.data, R2.data) && R0.nbchan == 126 && isempty(R0.etc.stage3.rejectedComponents) ...
    && refused(@() stage3_p2_rebuild(P2, 'rest', 'emg'), 'rejectOther');
fprintf('5 rebuild: 126 channels, average reference, deterministic, rejectOther required -> %d\n', c5);
% 6. excluded subject refused
D6.excluded = true; d6x = fullfile(workDir, 'd6x.mat'); save(d6x, 'D6');
r6 = refused(@() stage3_p2_compute_one(setf(base, 'd6File', d6x, 'd6Sha', sha(d6x)), fullfile(workDir, 'x6.mat')), 'excluded');
fprintf('6 excluded subject refused: %d\n', r6);
% 7. D12 counts
Z = eeg_emptyset; Z.srate = 500; Z.nbchan = 3; Z.pnts = 5000; Z.trials = 1; Z.xmin = 0; Z.xmax = 9.998;
Z.data = zeros(3, 5000); Z.chanlocs = struct('labels', {'Fz', 'Cz', 'C4'});
on = [1000 2000 3000 4000];                            % trial 2: 200 uV inside the window on Cz; trial 3: outside it
Z.data(2, 1950) = 200; Z.data(3, 3050) = 200;
Z.event = struct('type', {'S 6', 'S 6', 'S 6', 'S 6', 'boundary'}, 'latency', {on(1), on(2), on(3), on(4), 3950.5}, 'duration', {1, 1, 1, 1, 0});
[kp, Rd] = stage3_d12_trials(Z, "S 6", [-0.2 0], {'Fz', 'Cz', 'C4'}, 150);
c7 = isequal(kp, [true false true false]) && Rd.n_outside == 1 && Rd.n_rejected == 1 && Rd.n_kept == 2 && abs(Rd.frac_kept - 2 / 3) < 1e-12;
fprintf('7 D12: keep %s, outside %d, rejected %d -> %d\n', mat2str(kp), Rd.n_outside, Rd.n_rejected, c7);
% 8. S3a-P2-fix1: a subject with no bad channel (as sub-10) runs; analysed = part-1 + FCz, average reference
D6.excluded = false; D6.removedChannels = strings(0, 1); d60 = fullfile(workDir, 'd60.mat'); save(d60, 'D6');
f0 = fullfile(workDir, 'zero.mat'); stage3_p2_compute_one(setf(base, 'd6File', d60, 'd6Sha', sha(d60)), f0); Z0 = load(f0);
L = load(files.rest, '-mat'); Y0 = [double(L.EEG.data); zeros(1, L.EEG.pnts)]; Y0 = Y0 - mean(Y0, 1);
c8 = Z0.P2.qc.nGood == 125 && Z0.P2.qc.rank == 125 && Z0.P2.rest.nbchan == 126 && max(abs(double(Z0.P2.rest.data(:)) - Y0(:))) < 1e-3 ...
    && isempty(Z0.P2.rest.chaninfo.removedchans);
fprintf('8 no bad channel: good %d, rank %d, analysed = re-referenced part-1 -> %d\n', Z0.P2.qc.nGood, Z0.P2.qc.rank, c8);
ok = c1 && c2 && c3 && r4 && c5 && r6 && c7 && c8;
if ok, fprintf('P2 SYNTHETIC PASS\n'); else, fprintf('P2 SYNTHETIC FAIL\n'); end
end

function writeMan(man, files)
fid = fopen(man, 'w'); fprintf(fid, 'file\tbytes\tsha256\tcanonical\n');
for c = ["rest", "msit"], d = dir(files.(c)); fprintf(fid, '%s\t%d\t%s\t%s\n', d.name, d.bytes, sha(files.(c)), files.(c)); end
fclose(fid);
end

function s = setf(s, varargin)
for k = 1:2:numel(varargin), s.(varargin{k}) = varargin{k + 1}; end
end

function r = refused(f, msg)
r = false;
try, f(); catch ME, r = contains(ME.message, msg); if ~r, fprintf('unexpected error: %s\n', ME.message); end, end
end

function h = sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
