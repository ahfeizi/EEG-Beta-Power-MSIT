%% Stage 3a / decision S3a-D4e: compute and save the filter-edge half-length H.
% No real data. H is never typed in by hand; stage3_raw_boundaries_d4e.py reads the file written here.
% Since S3a-D5-integ (D5 = option (a), a = 3) the output goes to a NEW folder (never overwritten):
%   <outRoot>/stage3/d4e_d5a3/filter_halflengths.csv   (high-pass + anti-aliasing + 4 notches)
% The pre-D5 file <outRoot>/stage3/filter_halflengths.csv (H = 3.333 s, S3a-D4e) is kept unchanged.

here = fileparts(mfilename('fullpath'));
addpath(here, fileparts(fileparts(here)));       % this folder + repository root (get_paths.m)
P = get_paths();
outDir = fullfile(P.outRoot, 'stage3', 'd4e_d5a3');
f = fullfile(outDir, 'filter_halflengths.csv');
assert(exist(f, 'file') ~= 2, 'refusing to overwrite %s', f);
if ~exist(outDir, 'dir'), mkdir(outDir); end

[H, T] = stage3_filter_halflengths(stage3_params());
writetable(T, f);
disp(T);
fprintf('H = sum of half-lengths = %.4f s\n', H);
