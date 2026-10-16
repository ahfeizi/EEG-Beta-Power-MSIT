function H = stage3_compute_H_d5a(outDir)
%STAGE3_COMPUTE_H_D5A  H with D5 option (a) included (S3a-D5a-H). No real data.
%   Writes <outDir>/filter_halflengths.csv (refuses to overwrite) from
%   stage3_filter_halflengths(stage3_params(), 'a'), for stage3_raw_boundaries_d4e.py run with
%   out_dir = outDir. The D4e outputs in <outRoot>/stage3/ (without D5) are not touched.

here = fileparts(mfilename('fullpath'));
addpath(here);
f = fullfile(outDir, 'filter_halflengths.csv');
assert(exist(f, 'file') ~= 2, 'refusing to overwrite %s', f);
if ~exist(outDir, 'dir'), mkdir(outDir); end
[H, T] = stage3_filter_halflengths(stage3_params(), 'a', 2);   % a = 2: the setting of S3a-D5a-H
writetable(T, f);
disp(T);
fprintf('H = sum of half-lengths = %.4f s\n', H);
end
