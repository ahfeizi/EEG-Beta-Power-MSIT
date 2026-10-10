function ok = test_stage3_d4e4_compute_one(workDir, labelsTsv)
%TEST_STAGE3_D4E4_COMPUTE_ONE  Synthetic test of stage3_d4e4_compute_one (S3a-D4e-4-test-approval).
%   No real EEG data are read; labelsTsv is a channels.tsv text file (channel names only).
%   Synthetic recordings (1000 Hz, 100 s, raw boundary at 50 s, blocks 5-45 s and 55-95 s):
%     - 127 channels at seeded random positions on a sphere; each channel = spatially smooth mixture
%       of 40 seeded random sources (Gaussian kernel of distance) + independent noise, so neighbours
%       correlate;
%     - sub-01_rest: channel 50 = exact mean of its 3 nearest channels (an "interpolated" channel);
%     - sub-13_rest: data columns in channels.tsv order, .vhdr labels 121/124 swapped (as the real
%       sub-13); a synthetic .bvct with the positions (digitised list) plus a decoy ElectrodeLayout.
%   Checks: chunk positions honour the band-pass margin; sub-01 channel 50 is near-perfectly
%   predicted with its 3 sources as the 3 largest weights; sub-13 test N scores the true
%   hypothesis (tsv) above the false one (vhdr) for both affected labels; unaffected labels score
%   identically under both; two runs give content-identical outputs (stage3_compare 'all').

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, fullfile(repo, 'revision', 'infra'));
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
lab = ct.name; assert(numel(lab) == 127);
fs = 1000; T = 100; n = fs * T;
rng(7, 'twister');
pos = randn(127, 3); pos = pos ./ sqrt(sum(pos .^ 2, 2));
src = randn(40, 3); src = src ./ sqrt(sum(src .^ 2, 2));
K = exp(-sum((permute(pos, [1 3 2]) - permute(src, [3 1 2])) .^ 2, 3) / 0.15);   % 127 x 40
Dch = sqrt(sum((permute(pos, [1 3 2]) - permute(pos, [3 1 2])) .^ 2, 3)); Dch(logical(eye(127))) = Inf;
[~, o50] = sort(Dch(50, :)); interp3 = o50(1:3);
for r = ["sub-01", "sub-13"]
    S = randn(40, n);
    X = 30 * K * S + 3 * randn(127, n);
    if r == "sub-01", X(50, :) = mean(X(interp3, :), 1); end
    EEG = eeg_emptyset;
    EEG.srate = fs; EEG.nbchan = 127; EEG.pnts = n; EEG.trials = 1; EEG.xmin = 0; EEG.xmax = (n - 1) / fs;
    EEG.data = single(X);
    vlab = lab;
    if r == "sub-13", vlab([121 124]) = vlab([124 121]); end
    EEG.chanlocs = struct('labels', cellstr(vlab)');
    EEG.event = struct('type', {'boundary'}, 'latency', {50 * fs + 1}, 'duration', {0});
    EEG = eeg_checkset(EEG);
    d = fullfile(workDir, 'raw', char(r), 'eeg');
    if ~exist(d, 'dir'), mkdir(d); end
    pop_writebva(EEG, fullfile(d, [char(r) '_task-rest_eeg']));
    writetable(table(lab, repmat("EEG", 127, 1), repmat("uV", 127, 1), 'VariableNames', {'name', 'type', 'units'}), ...
        fullfile(d, [char(r) '_task-rest_channels.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
% synthetic .bvct for sub-13 (positions in mm; TP labels as in the real files)
cd13 = fullfile(workDir, 'raw', 'sourcedata', 'sub-13', 'coords'); if ~exist(cd13, 'dir'), mkdir(cd13); end
bl = regexprep(lab, ' (LEFT|RIGHT) EAR$', '');
fid = fopen(fullfile(cd13, 'sub-13_captrak.bvct'), 'w');
fprintf(fid, '<?xml version="1.0"?>\n<BrainVisionCapTrakFileV1>\n  <CapTrakElectrodeList>\n');
for k = 1:127
    fprintf(fid, '    <CapTrakElectrode>\n      <Name>%s</Name>\n      <X>%.12f</X>\n      <Y>%.12f</Y>\n      <Z>%.12f</Z>\n      <Channel>0</Channel>\n    </CapTrakElectrode>\n', ...
        bl(k), 90 * pos(k, 1), 90 * pos(k, 2), 90 * pos(k, 3));
end
fprintf(fid, '  </CapTrakElectrodeList>\n  <ElectrodeLayout>\n');
for k = 1:127                                              % decoy with the same names: must be ignored
    fprintf(fid, '    <CapTrakElectrode>\n      <Name>%s</Name>\n      <X>0</X>\n      <Y>0</Y>\n      <Z>0</Z>\n    </CapTrakElectrode>\n', bl(k));
end
fprintf(fid, '  </ElectrodeLayout>\n</BrainVisionCapTrakFileV1>\n');
fclose(fid);
o = fullfile(workDir, 'out', 'stage3'); if ~exist(o, 'dir'), mkdir(o); end
rows = {'sub-01', 'rest', 'unchanged', 5, 45; 'sub-01', 'rest', 'unchanged', 55, 95; ...
        'sub-13', 'rest', 'unchanged', 5, 45; 'sub-13', 'rest', 'unchanged', 55, 95};
bt = fullfile(o, 'd4e_block_clipping.csv');
writetable(cell2table(rows, 'VariableNames', {'subject', 'task', 'status', 'new_start_s', 'new_end_s'}), bt);
L = dir(fullfile(workDir, 'raw', '**', '*')); L = L(~[L.isdir]);
fid = fopen(fullfile(workDir, 'manifest.tsv'), 'w');
fprintf(fid, 'relpath\tsize\tsha256\n');
for k = 1:numel(L)
    f = fullfile(L(k).folder, L(k).name);
    fprintf(fid, '%s\t%d\t%s\n', strrep(f(numel(fullfile(workDir, 'raw')) + 2:end), '\', '/'), L(k).bytes, sha256File(f));
end
fclose(fid);

% ---- runs -----------------------------------------------------------------------------------
base = struct('rawRoot', fullfile(workDir, 'raw'), 'manifest', fullfile(workDir, 'manifest.tsv'), 'blockTable', bt, 'task', 'rest');
p1 = base; p1.subject = 'sub-01'; p1.testN = false;
p13 = base; p13.subject = 'sub-13'; p13.testN = true;
f1 = fullfile(workDir, 'sub-01_rest.mat'); f13a = fullfile(workDir, 'sub-13_rest_a.mat'); f13b = fullfile(workDir, 'sub-13_rest_b.mat');
stage3_d4e4_compute_one(p1, f1);
stage3_d4e4_compute_one(p13, f13a);
stage3_d4e4_compute_one(p13, f13b);

ok = true;
A = load(f1);
bs500 = A.info.blocks(:, 1); h = A.info.halfBPSamples;
c1 = A.info.chunkStarts(1) == bs500(1) + h && all(A.info.chunkStarts + 5000 - 1 <= max(A.info.blocks(:, 4)));
fprintf('margin: half-length %d samples (order %d); first chunk at block start + half-length: %d; %d chunks\n', ...
    h, A.info.bandpassOrder, c1, A.info.nChunk); ok = ok && c1;
j50 = find(A.info.keptColumns == 50);
[~, src3] = ismember(interp3, A.info.keptColumns);
c2 = A.P.nearPerfect(j50) && isequal(sort(A.P.top6Col(j50, 1:3)), sort(src3(:)')) && sum(A.P.nearPerfect) >= 1;
fprintf('interpolated channel: 1-R^2 = %.3g; top-3 predictors = its sources: %d; near-perfect channels: %d\n', ...
    A.P.oneMinusR2(j50), isequal(sort(A.P.top6Col(j50, 1:3)), sort(src3(:)')), sum(A.P.nearPerfect)); ok = ok && c2;
B = load(f13a);
aff = find(B.Nres.affected);
c3 = numel(aff) == 2 && all(B.Nres.sTsv(aff, 2) > B.Nres.sVhdr(aff, 2));
fprintf('test N: affected labels %s; s_tsv (k=6) %s > s_vhdr %s: %d\n', strjoin(B.Nres.labels(aff), ', '), ...
    mat2str(B.Nres.sTsv(aff, 2)', 3), mat2str(B.Nres.sVhdr(aff, 2)', 3), c3); ok = ok && c3;
u = ~B.Nres.affected;
nbAff = any(ismember(B.Nres.neighbours(:, 1:max(B.Nres.k)), aff), 2);   % labels with an affected neighbour (any k)
c4 = isequal(B.Nres.sTsv(u & ~nbAff, :), B.Nres.sVhdr(u & ~nbAff, :));
fprintf('unaffected labels (no affected neighbour) score identically under both hypotheses: %d\n', c4); ok = ok && c4;
j = fullfile(workDir, 'compare_ab.json');
stage3_compare(f13a, f13b, 'all', j);
c5 = jsondecode(fileread(j)).equal;
fprintf('two runs content-identical (stage3_compare all): %d\n', c5); ok = ok && c5;
if ok, fprintf('D4E4 SYNTHETIC PASS\n'); else, fprintf('D4E4 SYNTHETIC FAIL\n'); end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
