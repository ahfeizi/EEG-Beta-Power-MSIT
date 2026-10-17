function ok = test_stage3_d6_compute_one(workDir, labelsTsv)
%TEST_STAGE3_D6_COMPUTE_ONE  Synthetic test of stage3_positions and stage3_d6_compute_one (S3a-D6,
%   S3a-D2-close, S3a-D6-impl). No real EEG data; labelsTsv is a channels.tsv (127 names).
%   Subject "sub-13" (so the D4e-4 pair FFT8h/FCC6h applies). Positions: the standard-10-5-cap385 template
%   on a 95 mm sphere whose centre lies 50 mm above the file origin (as in CapTrak), written as a .bvct.
%   Data: 125 channels, 500 Hz, 100 s per condition, 30 broad smooth spatial sources plus small sensor noise.
%   Defects: rest O1 flat for 20 s (flatline); MSIT+ P4 independent large noise (RANSAC); Pz 1 - R^2 = 1e-8
%   in rest only (dependent; union -> bad in both). Expected bad set: FFT8h, FCC6h, Pz, O1, P4.
%   Checks: 1. bad set, categories, not excluded; 2. 'spherefit' centre = [0 0 50] mm, 'origin' = 0;
%   3. A = B ('all' compare); 4. 19 dependent channels -> excluded; 5. refusals: undecided centring,
%   sub-42, a part-1 file whose hash differs from the manifest.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
if ~exist('pop_clean_rawdata', 'file'), eeglab('nogui'); end
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
lab127 = ct.name; mont = lab127(~ismember(lab127, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]));
s = 'sub-13'; rng(11, 'twister');
% ---- template positions -> RAS mm on a sphere centred at (0, 0, 50) ----------------------------
tpl = fullfile(fileparts(which('dipfitdefs')), 'standard_BESA', 'standard-10-5-cap385.elp');
tl = readlocs(tpl); tlab = lower(string({tl.labels}));
U = nan(numel(lab127) + 1, 3); names = [lab127; "FCz"];
for k = 1:numel(names)
    i = find(tlab == lower(names(k)), 1);
    if isempty(i), v = [-0.2, (2 * (names(k) == "TP9 LEFT EAR") - 1) * 0.9, -0.3];   % TP9/TP10: not in the template
    else, v = [tl(i).X, tl(i).Y, tl(i).Z]; end
    U(k, :) = v / norm(v);                                 % EEGLAB frame, unit sphere
end
ras = 95 * [-U(:, 2), U(:, 1), U(:, 3)] + [0 0 50];
fidN = ["Nasion"; "LPA"; "RPA"; "GND"]; fidP = [0 100 0; -80 0 0; 80 0 0; 0 60 120];
cdir = fullfile(workDir, 'raw', 'sourcedata', s, 'coords'); mkdir(cdir);
fid = fopen(fullfile(cdir, [s '_captrak.bvct']), 'w');
fprintf(fid, '<?xml version="1.0"?>\n<BrainVisionCapTrak>\n<CapTrakElectrodeList>\n');
allN = [names; fidN]; allP = [ras; fidP];
for k = 1:numel(allN)
    fprintf(fid, '<CapTrakElectrode>\n<Name>%s</Name>\n<X>%.6f</X>\n<Y>%.6f</Y>\n<Z>%.6f</Z>\n</CapTrakElectrode>\n', allN(k), allP(k, :));
end
fprintf(fid, '</CapTrakElectrodeList>\n</BrainVisionCapTrak>\n'); fclose(fid);
rawMan = fullfile(workDir, 'raw_manifest.tsv'); writeManifest(fullfile(workDir, 'raw'), rawMan);
% ---- part-1-like sets -----------------------------------------------------------------------
fs = 500; n = 100 * fs;
[~, im] = ismember(mont, names); Um = U(im, :);
src = randn(30, 3); src = src ./ vecnorm(src, 2, 2);
G = exp(-(acos(min(1, Um * src')) / 0.8) .^ 2);            % 125 x 30 smooth gains
p1 = fullfile(workDir, 'p1'); mkdir(p1);
files = struct();
for c = ["rest", "msit"]
    Sg = filter(ones(1, 25) / 25, 1, randn(30, n), [], 2) * 20;
    X = G * Sg + 0.3 * randn(numel(mont), n);
    if c == "rest", X(mont == "O1", 1001:11000) = 0; end
    if c == "msit", X(mont == "P4", :) = 40 * randn(1, n); end
    EEG = eeg_emptyset; EEG.srate = fs; EEG.nbchan = numel(mont); EEG.pnts = n; EEG.trials = 1;
    EEG.xmin = 0; EEG.xmax = (n - 1) / fs; EEG.data = single(X);
    EEG.chanlocs = struct('labels', cellstr(mont)');
    EEG.event = struct('type', {'boundary'}, 'latency', {n / 2 + 0.5}, 'duration', {100});
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG.etc.stage3 = struct('subject', s, 'task', char(c));
    f = fullfile(p1, sprintf('%s_task-%s_s3p1.set', s, c)); save(f, 'EEG', '-mat');
    files.(char(c)) = f;
end
p1Man = fullfile(p1, 'manifest.tsv'); fid = fopen(p1Man, 'w'); fprintf(fid, 'file\tbytes\tsha256\tcanonical\n');
for c = ["rest", "msit"], d = dir(files.(c)); fprintf(fid, '%s\t%d\t%s\t%s\n', d.name, d.bytes, sha(files.(c)), files.(c)); end
fclose(fid);
pt = writePred(workDir, 'pred.csv', s, mont, "Pz", 1);
pt19 = writePred(workDir, 'pred19.csv', s, mont, mont(40:58), 2);
base = struct('subject', s, 'p1Rest', files.rest, 'p1Msit', files.msit, 'p1Manifest', p1Man, 'predTable', pt, ...
    'predSha', sha(pt), 'rawRoot', fullfile(workDir, 'raw'), 'manifest', rawMan, 'posCentering', 'spherefit');
fa = fullfile(workDir, 'a.mat'); fb = fullfile(workDir, 'b.mat'); fo = fullfile(workDir, 'o.mat');
stage3_d6_compute_one(base, fa); stage3_d6_compute_one(base, fb);
po = base; po.posCentering = 'origin'; stage3_d6_compute_one(po, fo);
A = load(fa); D = A.D6; O = load(fo); Do = O.D6;
want = mont(ismember(mont, ["FFT8h", "FCC6h", "Pz", "O1", "P4"]));
c1 = isequal(D.removedChannels, want) && isequal(sort(D.pair), sort(["FFT8h"; "FCC6h"])) && isequal(D.dependentUnion, "Pz") ...
    && ismember("O1", D.ransac.rest) && ismember("P4", D.ransac.msit) && ~D.excluded && D.nBad == 5 && D.nChannels == 125;
fprintf('1 bad set %s (want %s); RANSAC rest %s, MSIT+ %s; excluded %d -> %d\n', strjoin(D.removedChannels, ','), ...
    strjoin(want, ','), strjoin(D.ransac.rest, ','), strjoin(D.ransac.msit, ','), D.excluded, c1);
c2 = all(abs(D.positions.centre_ras_mm - [0 0 50]) < 1e-6) && abs(D.positions.radius_mm - 95) < 1e-6 && isequal(Do.positions.centre_ras_mm, [0 0 0]) ...
    && strcmp(D.positions.source, 'bvct');
fprintf('2 centre spherefit %s mm, radius %.3f; origin %s -> %d\n', mat2str(round(D.positions.centre_ras_mm, 6)), D.positions.radius_mm, mat2str(Do.positions.centre_ras_mm), c2);
j = fullfile(workDir, 'cmp.json'); stage3_compare(fa, fb, 'all', j); c3 = jsondecode(fileread(j)).equal;
fprintf('3 A = B: %d\n', c3);
p19 = base; p19.predTable = pt19; p19.predSha = sha(pt19); f19 = fullfile(workDir, 'x19.mat'); stage3_d6_compute_one(p19, f19);
Q = load(f19); c4 = Q.D6.excluded && Q.D6.nBad >= 19;
fprintf('4 19 dependent channels: nBad %d, excluded %d -> %d\n', Q.D6.nBad, Q.D6.excluded, c4);
r1 = refused(@() stage3_d6_compute_one(rmfield(base, 'posCentering'), fullfile(workDir, 'r1.mat')), 'not decided');
r2 = refused(@() stage3_d6_compute_one(setf(base, 'subject', 'sub-42'), fullfile(workDir, 'r2.mat')), 'excluded');
copyfile(files.msit, fullfile(p1, 'tmp.set')); EEG = load(files.msit, '-mat'); EEG = EEG.EEG; EEG.data(1) = EEG.data(1) + 1; save(files.msit, 'EEG', '-mat');
r3 = refused(@() stage3_d6_compute_one(base, fullfile(workDir, 'r3.mat')), 'SHA-256');
movefile(fullfile(p1, 'tmp.set'), files.msit);
c5 = r1 && r2 && r3;
fprintf('5 refused: undecided centring %d, sub-42 %d, changed part-1 file %d\n', r1, r2, r3);
ok = c1 && c2 && c3 && c4 && c5;
if ok, fprintf('D6 SYNTHETIC PASS\n'); else, fprintf('D6 SYNTHETIC FAIL\n'); end
end

function f = writePred(workDir, name, s, mont, depLab, mode)
% test P table rows for both tasks; mode 1: depLab dependent in rest only; mode 2: in both
rows = {};
for c = ["rest", "msit"]
    v = 0.01 * ones(numel(mont), 1);
    if mode == 2 || c == "rest", v(ismember(mont, depLab)) = 1e-8; end
    rows{end+1} = table(repmat(string(s), numel(mont), 1), repmat(c, numel(mont), 1), (1:numel(mont))', mont, mont, v, ...
        double(v < 1e-4), 'VariableNames', {'subject', 'task', 'column', 'label_tsv', 'label_vhdr', 'one_minus_r2', 'near_perfect'}); %#ok<AGROW>
end
f = fullfile(workDir, name); writetable(vertcat(rows{:}), f);
end

function s = setf(s, varargin)
for k = 1:2:numel(varargin), s.(varargin{k}) = varargin{k + 1}; end
end

function r = refused(f, msg)
r = false;
try, f(); catch ME, r = contains(ME.message, msg); if ~r, fprintf('unexpected error: %s\n', ME.message); end, end
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
