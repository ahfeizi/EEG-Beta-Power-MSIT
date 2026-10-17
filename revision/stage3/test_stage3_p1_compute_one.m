function ok = test_stage3_p1_compute_one(workDir, labelsTsv)
%TEST_STAGE3_P1_COMPUTE_ONE  Synthetic test of stage3_p1_compute_one and of the 'set' compare kind
%   (S3a-P1, S3a-INF-1-setspec). No real EEG data; labelsTsv is a channels.tsv (names only, 127 channels).
%   sub-90 MSIT+: 60 s at 1000 Hz, a raw boundary at 30 s, per-segment DC offsets, stimuli/responses;
%   blocks [8, 22] s and [37, 52] s (>= H = 6.637 s from every edge). sub-90 rest: 320 s, S12/S10/S11/S12
%   as in the real files (S10 = S12 + 300 s).
%   Checks: 1. output: 125 channels (TP9/TP10 dropped) with template positions, 500 Hz, single, the
%   cropped length, block events at the block edges, etc.taskBlocks/restBlocks, no raw boundary inside a
%   block, the Time 0 marker removed; 2. group size 16 vs 50 and two runs: 'set' compare equal;
%   3. pop_loadset reads the output under a .set name; 4. an events.tsv shifted by 1 ms is refused;
%   a rest S10 off by 20 ms is refused; sub-42 is refused; a .vhdr swap of exactly the sub-13 pair is accepted
%   (channels.tsv labels used), any other swap is refused; 5. 'set' compare reports a changed data
%   sample and a field present in one file only as different.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
lab = ct.name; assert(numel(lab) == 127);
fs = 1000; raw = fullfile(workDir, 'raw');
rng(7, 'twister');
% ---- sub-90 MSIT+ --------------------------------------------------------------------------
n = 60 * fs; stimS = [9 11 13 15 17 19 38 40 42 44 46 48 50]; respS = stimS + 0.6;
mk = [struct('type', 'boundary', 'latency', 30 * fs + 1, 'duration', 0), ...
      arrayfun(@(t) struct('type', 'S  6', 'latency', round(t * fs), 'duration', 1), stimS), ...
      arrayfun(@(t) struct('type', 'S  3', 'latency', round(t * fs), 'duration', 1), respS)];
X = 10 * randn(127, n); X(:, 30 * fs + 1:end) = X(:, 30 * fs + 1:end) + 800;
writeRec(raw, 'sub-90', 'msit', X, lab, mk, fs);
evRows = [stimS(:), repmat("S 6", numel(stimS), 1), repmat("stimulus", numel(stimS), 1); ...
          respS(:), repmat("S 3", numel(respS), 1), repmat("response", numel(respS), 1)];
writeEvents(fullfile(raw, 'sub-90', 'eeg', 'sub-90_task-msit_events.tsv'), evRows);
% ---- sub-90 rest -----------------------------------------------------------------------------
n2 = 320 * fs; rs = [5 305 310 312];
mk2 = arrayfun(@(t, k) struct('type', char(k), 'latency', round(t * fs), 'duration', 1), rs, ["S 12" "S 10" "S 11" "S 12"]);
writeRec(raw, 'sub-90', 'rest', 10 * randn(127, n2), lab, mk2, fs);
writeEvents(fullfile(raw, 'sub-90', 'eeg', 'sub-90_task-rest_events.tsv'), [rs(:), ["S 12"; "S 10"; "S 11"; "S 12"], repmat("n/a", 4, 1)]);
% ---- copies with defects (each in its own raw root) -----------------------------------------
copyfile(raw, fullfile(workDir, 'raw_badev')); copyfile(raw, fullfile(workDir, 'raw_bads10'));
e = evRows; e(1, 1) = string(stimS(1) + 0.001);
writeEvents(fullfile(workDir, 'raw_badev', 'sub-90', 'eeg', 'sub-90_task-msit_events.tsv'), e);
writeEvents(fullfile(workDir, 'raw_bads10', 'sub-90', 'eeg', 'sub-90_task-rest_events.tsv'), ...
    [[5; 305.02; 310; 312], ["S 12"; "S 10"; "S 11"; "S 12"], repmat("n/a", 4, 1)]);
for r = {'raw', 'raw_badev', 'raw_bads10'}, writeManifest(fullfile(workDir, r{1}), fullfile(workDir, [r{1} '_manifest.tsv'])); end
% ---- block table -----------------------------------------------------------------------------
bt = fullfile(workDir, 'blocks.csv');
rows = {'sub-90', 'msit', 'task_b1', 6, 0, 8, 22, 'CLIPPED', 'recording_start'; 'sub-90', 'msit', 'task_b2', 7, 0, 37, 52, 'unchanged', ''; ...
        'sub-90', 'rest', 'rest_b1', NaN, 0, 5, 304.999, 'unchanged', ''; 'sub-90', 'rest', 'rest_b2', NaN, 0, 312, 312 + 6, 'CLIPPED', ''};
rows{4, 7} = 320 - 6.637 - 0.001; rows{4, 9} = '';
T = cell2table(rows, 'VariableNames', {'subject', 'task', 'block', 'n_stim', 'split_10s', 'new_start_s', 'new_end_s', 'status', 'clip_start_reason'});
T.start_s = T.new_start_s; T.end_s = T.new_end_s; T.dur_s = T.new_end_s - T.new_start_s; T.seg_start_s = zeros(4, 1);
T.seg_end_s = T.new_end_s; T.raw_bnd_inside_block = repmat("", 4, 1); T.clip_start_s = zeros(4, 1);
T.clip_end_s = zeros(4, 1); T.clip_end_reason = repmat("", 4, 1); T.new_dur_s = T.dur_s;
T.stim_before_new_start = [0; 0; NaN; NaN]; T.stim_after_new_end = [0; 0; NaN; NaN];
writetable(T, bt);
p = struct('subject', 'sub-90', 'task', 'msit', 'rawRoot', raw, 'manifest', fullfile(workDir, 'raw_manifest.tsv'), 'blockTable', bt);
fa = fullfile(workDir, 'a.mat'); fb = fullfile(workDir, 'b.mat'); fg = fullfile(workDir, 'g50.mat');
stage3_p1_compute_one(p, fa); stage3_p1_compute_one(p, fb);
pg = p; pg.groupSize = 50; stage3_p1_compute_one(pg, fg);
% ---- 1. output -------------------------------------------------------------------------------
L = load(fa); E = L.EEG;
labs = string({E.chanlocs.labels});
ed = vertcat(E.etc.taskBlocks.samples_500hz_uncropped); lens = (ed(:, 2) - ed(:, 1) + 1)';
nominal = [(22 - 8) * 500 + 1, (52 - 37) * 500 + 1];          % ceil/floor of half-sample edges: <= 1 sample shorter
typ = string({E.event.type}); lat = [E.event.latency];
c1 = E.nbchan == 125 && ~any(ismember(labs, ["TP9 LEFT EAR", "TP10 RIGHT EAR"])) && isequal(labs(:), lab(~ismember(lab, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]))) ...
    && all(arrayfun(@(c) ~isempty(c.X) && ~isnan(c.X), E.chanlocs)) && E.srate == 500 && isa(E.data, 'single') ...
    && all(nominal - lens >= 0 & nominal - lens <= 1) && E.pnts == sum(lens) && lat(typ == "task_b1_start") == 1 && lat(typ == "task_b1_end") == lens(1) ...
    && lat(typ == "task_b2_start") == lens(1) + 1 && lat(typ == "task_b2_end") == sum(lens) ...
    && isequal(lat(typ == "boundary" & lat > 1 & lat < E.pnts), lens(1) + 0.5) && numel(E.etc.taskBlocks) == 2 && isequal(E.etc.taskBlocks(1).samples_cropped, [1 lens(1)]) ...
    && sum(typ == "S 6" | typ == "S  6") == numel(stimS) && E.etc.stage3.removedTime0Events >= 0 && abs(E.etc.stage3.H_s - 6.637) < 1e-9;
fprintf('1 output: 125 channels, positions, 500 Hz single, %d samples, block events, 1 boundary between blocks -> %d\n', E.pnts, c1);
% ---- 2. group size and A/B --------------------------------------------------------------------
j1 = fullfile(workDir, 'cmp_ab.json'); stage3_compare(fa, fb, 'set', j1);
j2 = fullfile(workDir, 'cmp_g.json'); stage3_compare(fa, fg, 'set', j2);
c2 = jsondecode(fileread(j1)).equal && jsondecode(fileread(j2)).equal;
fprintf('2 set compare: A = B %d; group 16 = group 50 %d\n', jsondecode(fileread(j1)).equal, jsondecode(fileread(j2)).equal);
% ---- 3. pop_loadset --------------------------------------------------------------------------
sd = fullfile(workDir, 'set'); mkdir(sd); copyfile(fa, fullfile(sd, 'sub-90_task-msit_s3p1.set'));
E2 = pop_loadset('filename', 'sub-90_task-msit_s3p1.set', 'filepath', sd);
c3 = isequal(E2.data, E.data) && E2.nbchan == 125;
fprintf('3 pop_loadset reads the output: %d\n', c3);
% ---- 4. refusals and rest ----------------------------------------------------------------------
pr = p; pr.task = 'rest'; fr = fullfile(workDir, 'rest.mat'); stage3_p1_compute_one(pr, fr);
R = load(fr); c4a = isfield(R.EEG.etc, 'restBlocks') && numel(R.EEG.etc.restBlocks) == 2 && ~R.EEG.etc.restBlocks(1).sub25_flag;
r1 = refused(@() stage3_p1_compute_one(setf(p, 'rawRoot', fullfile(workDir, 'raw_badev'), 'manifest', fullfile(workDir, 'raw_badev_manifest.tsv')), fullfile(workDir, 'x1.mat')), 'events differ');
r2 = refused(@() stage3_p1_compute_one(setf(pr, 'rawRoot', fullfile(workDir, 'raw_bads10'), 'manifest', fullfile(workDir, 'raw_bads10_manifest.tsv')), fullfile(workDir, 'x2.mat')), 'S10 check');
r3 = refused(@() stage3_p1_compute_one(setf(p, 'subject', 'sub-42'), fullfile(workDir, 'x3.mat')), 'excluded');
% sub-13: .vhdr labels FFT8h/FCC6h swapped against channels.tsv (the D4e-4 pair) -> accepted, tsv labels used;
% sub-90 with a non-pair swap (Fp1/Fz) -> refused
labS = lab; i1 = find(lab == "FFT8h"); i2 = find(lab == "FCC6h"); labS([i1 i2]) = lab([i2 i1]);
writeRec(fullfile(workDir, 'raw_s13'), 'sub-13', 'msit', X, labS, mk, fs);
writetable(table(lab, repmat("EEG", 127, 1), repmat("uV", 127, 1), 'VariableNames', {'name', 'type', 'units'}), ...
    fullfile(workDir, 'raw_s13', 'sub-13', 'eeg', 'sub-13_task-msit_channels.tsv'), 'FileType', 'text', 'Delimiter', '\t');
writeEvents(fullfile(workDir, 'raw_s13', 'sub-13', 'eeg', 'sub-13_task-msit_events.tsv'), evRows);
labB = lab; j1 = find(lab == "Fp1"); j2 = find(lab == "Fz"); labB([j1 j2]) = lab([j2 j1]);
writeRec(fullfile(workDir, 'raw_badlab'), 'sub-90', 'msit', X, labB, mk, fs);
writetable(table(lab, repmat("EEG", 127, 1), repmat("uV", 127, 1), 'VariableNames', {'name', 'type', 'units'}), ...
    fullfile(workDir, 'raw_badlab', 'sub-90', 'eeg', 'sub-90_task-msit_channels.tsv'), 'FileType', 'text', 'Delimiter', '\t');
writeEvents(fullfile(workDir, 'raw_badlab', 'sub-90', 'eeg', 'sub-90_task-msit_events.tsv'), evRows);
for r = {'raw_s13', 'raw_badlab'}, writeManifest(fullfile(workDir, r{1}), fullfile(workDir, [r{1} '_manifest.tsv'])); end
T13 = T(T.subject == "sub-90" & T.task == "msit", :); T13.subject(:) = {'sub-13'}; bt13 = fullfile(workDir, 'blocks13.csv'); writetable(T13, bt13);
p13 = setf(p, 'subject', 'sub-13', 'rawRoot', fullfile(workDir, 'raw_s13'), 'manifest', fullfile(workDir, 'raw_s13_manifest.tsv'), 'blockTable', bt13);
f13 = fullfile(workDir, 's13.mat'); stage3_p1_compute_one(p13, f13); S13 = load(f13);
r4 = isequal(string({S13.EEG.chanlocs.labels}), string({E.chanlocs.labels})) && S13.EEG.etc.stage3.labelsRelabelledFromTsv == 2;
r5 = refused(@() stage3_p1_compute_one(setf(p, 'rawRoot', fullfile(workDir, 'raw_badlab'), 'manifest', fullfile(workDir, 'raw_badlab_manifest.tsv')), fullfile(workDir, 'x5.mat')), 'labels differ');
c4 = c4a && r1 && r2 && r3 && r4 && r5;
fprintf('4 rest blocks %d; shifted events refused %d; S10 off refused %d; sub-42 refused %d; sub-13 pair swap accepted with tsv labels %d; other swap refused %d\n', c4a, r1, r2, r3, r4, r5);
% ---- 5. set compare detects differences --------------------------------------------------------
EEG = E; EEG.data(5, 100) = EEG.data(5, 100) + 1; fd = fullfile(workDir, 'd.mat'); save(fd, 'EEG');
EEG = E; EEG.etc.stage3.removedChannels = {'Fz'}; fe = fullfile(workDir, 'e.mat'); save(fe, 'EEG');
j3 = fullfile(workDir, 'cmp_d.json'); stage3_compare(fa, fd, 'set', j3); D = jsondecode(fileread(j3));
j4 = fullfile(workDir, 'cmp_e.json'); stage3_compare(fa, fe, 'set', j4); Q = jsondecode(fileread(j4));
fd_ = D.fields(strcmp({D.fields.field}, 'data'));
fq_ = Q.fields(strcmp({Q.fields.field}, 'etc.stage3.removedChannels'));
c5 = ~D.equal && fd_.n_diff == 1 && abs(fd_.max_abs_diff - 1) < 1e-3 && ~Q.equal && ~fq_.equal;
fprintf('5 set compare: changed sample found %d; field in one file only = different %d\n', ~D.equal && fd_.n_diff == 1, ~Q.equal && ~fq_.equal);
ok = c1 && c2 && c3 && c4 && c5;
if ok, fprintf('P1 SYNTHETIC PASS\n'); else, fprintf('P1 SYNTHETIC FAIL\n'); end
end

function s = setf(s, varargin)
for k = 1:2:numel(varargin), s.(varargin{k}) = varargin{k + 1}; end
end

function r = refused(f, msg)
r = false;
try, f(); catch ME, r = contains(ME.message, msg); if ~r, fprintf('unexpected error: %s\n', ME.message); end, end
end

function writeRec(raw, sid, task, X, lab, mk, fs)
EEG = eeg_emptyset;
EEG.srate = fs; EEG.nbchan = size(X, 1); EEG.pnts = size(X, 2); EEG.trials = 1; EEG.xmin = 0; EEG.xmax = (EEG.pnts - 1) / fs;
EEG.data = single(X); EEG.chanlocs = struct('labels', cellstr(lab)');
EEG.event = mk;
EEG = eeg_checkset(EEG, 'eventconsistency');
d = fullfile(raw, sid, 'eeg'); if ~exist(d, 'dir'), mkdir(d); end
pop_writebva(EEG, fullfile(d, sprintf('%s_task-%s_eeg', sid, task)));
writetable(table(lab, repmat("EEG", numel(lab), 1), repmat("uV", numel(lab), 1), 'VariableNames', {'name', 'type', 'units'}), ...
    fullfile(d, sprintf('%s_task-%s_channels.tsv', sid, task)), 'FileType', 'text', 'Delimiter', '\t');
end

function writeEvents(f, rows)
fid = fopen(f, 'w'); fprintf(fid, 'onset\tduration\tevent_type\ttrial_type\n');
for k = 1:size(rows, 1), fprintf(fid, '%s\tn/a\t%s\t%s\n', rows(k, 1), rows(k, 2), rows(k, 3)); end
fclose(fid);
end

function writeManifest(raw, out)
L = dir(fullfile(raw, '**', '*')); L = L(~[L.isdir]);
fid = fopen(out, 'w'); fprintf(fid, 'relpath\tsize\tsha256\n');
for k = 1:numel(L)
    f = fullfile(L(k).folder, L(k).name);
    fprintf(fid, '%s\t%d\t%s\n', strrep(f(numel(raw) + 2:end), '\', '/'), L(k).bytes, sha(f));
end
fclose(fid);
end

function h = sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
