%% Stage 3a / decision S3a-D4e: compute and save the filter-edge half-length H.
% No real data. Output (new file): <outRoot>/stage3/filter_halflengths.csv, one row per filter.
% stage3_raw_boundaries_d4e.py reads this file; H is never typed in by hand.

here = fileparts(mfilename('fullpath'));
addpath(here, fileparts(fileparts(here)));       % this folder + repository root (get_paths.m)
P = get_paths();
outDir = fullfile(P.outRoot, 'stage3');
if ~exist(outDir, 'dir'), mkdir(outDir); end

[H, T] = stage3_filter_halflengths(stage3_params());
writetable(T, fullfile(outDir, 'filter_halflengths.csv'));
disp(T);
fprintf('H = sum of half-lengths = %.4f s\n', H);
