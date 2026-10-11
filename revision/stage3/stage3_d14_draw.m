function stage3_d14_draw()
%STAGE3_D14_DRAW  D14 test subjects by a stratified seeded draw (decision S3a-D14-draw). Run once.
%   sub-25 fixed; one subject from the Fz-interpolated-in-v1 list (sub-25 excluded); one from the
%   drift list {sub-08, sub-09, sub-15}, not equal to the Fz subject. rng(1, 'twister').
%   Writes <outRoot>/stage3/d14_draw/d14_draw_result.txt; refuses to run if it exists. No EEG data.

here = fileparts(mfilename('fullpath'));
addpath(here, fileparts(fileparts(here)));
P = get_paths();
src = fullfile(P.outRoot, 'stage0', 'rest_markers_in_clean_sets.csv');
assert(strcmp(sha256File(src), '723035ec24cbca8a7383420f4629c6a2ea0f16a921326d4e31b6f527c650469f'), 'source file differs from S3a-D14-draw');
outDir = fullfile(P.outRoot, 'stage3', 'd14_draw');
outFile = fullfile(outDir, 'd14_draw_result.txt');
assert(exist(outFile, 'file') ~= 2, 'the draw has already been run: %s', outFile);

T = readtable(src, 'TextType', 'string');
T.interpolatedKeyChans(ismissing(T.interpolatedKeyChans)) = "";
hasFz = arrayfun(@(s) any(split(s) == "Fz"), T.interpolatedKeyChans);
fz = sort(T.subject(hasFz));
fz(fz == "sub-25") = [];
fixedList = ["sub-04" "sub-05" "sub-08" "sub-10" "sub-12" "sub-13" "sub-15" "sub-19" "sub-28" ...
             "sub-29" "sub-31" "sub-32" "sub-33" "sub-41"]';
assert(isequal(fz, fixedList), 'Fz list differs from the list fixed in S3a-D14-draw');
drift = ["sub-08" "sub-09" "sub-15"]';

rng(1, 'twister');
pF = randperm(numel(fz));
pickF = fz(pF(1));
pD = randperm(numel(drift));
cand = drift(pD);
pickD = cand(find(cand ~= pickF, 1));

if ~exist(outDir, 'dir'), mkdir(outDir); end
fid = fopen(outFile, 'w');
fprintf(fid, 'S3a-D14-draw result, %s, MATLAB %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), version);
fprintf(fid, 'source %s SHA-256 %s\n', src, sha256File(src));
fprintf(fid, 'rng(1, ''twister'')\n');
fprintf(fid, 'Fz list (%d): %s\n', numel(fz), strjoin(fz, ', '));
fprintf(fid, 'randperm(%d) = %s -> Fz subject %s\n', numel(fz), mat2str(pF), pickF);
fprintf(fid, 'drift list: %s\n', strjoin(drift, ', '));
fprintf(fid, 'randperm(3) = %s -> order %s -> drift subject %s\n', mat2str(pD), strjoin(cand, ', '), pickD);
fprintf(fid, 'D14 test subjects: sub-25, %s, %s\n', pickF, pickD);
fclose(fid);
fprintf('%s', fileread(outFile));
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
