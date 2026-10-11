function stage3_d5b_test_set()
%STAGE3_D5B_TEST_SET  Test set of the D5 option (b) residual test (S3a-D5-opt; S3a-D14-draw):
%   the 3 D14 subjects x (rest, msit) plus the 3 highest-ranked recordings by D5-0 R2 severity whose
%   subject is not a D14 subject (R2 replacement step of S3a-D5-0).
%   Inputs: <outRoot>/stage3/d14_draw/d14_draw_result.txt and
%   <outRoot>/stage3/d5_0/line_noise_rules_by_recording.csv (d5asm_1; R2 uses excess_db only).
%   Writes <outRoot>/stage3/d5b/test_set.csv (refuses to overwrite). No EEG data.

here = fileparts(mfilename('fullpath'));
addpath(here, fileparts(fileparts(here)));
P = get_paths();
drawTxt = fileread(fullfile(P.outRoot, 'stage3', 'd14_draw', 'd14_draw_result.txt'));
tok = regexp(drawTxt, 'D14 test subjects: (sub-\d+), (sub-\d+), (sub-\d+)', 'tokens', 'once');
assert(numel(tok) == 3, 'no D14 result line');
d14 = string(tok(:));
R = readtable(fullfile(P.outRoot, 'stage3', 'd5_0', 'line_noise_rules_by_recording.csv'), 'TextType', 'string');
R = sortrows(R, 'r2_rank');
rank = R.r2_rank; isD14 = ismember(R.subject, d14);
worst = R(~isD14, :); worst = worst(1:3, :);
skipped = R(isD14 & R.r2_rank < worst.r2_rank(end), :);
role = [repmat("D14", 6, 1); repmat("R2 worst", 3, 1)];
subj = [repelem(d14, 2); worst.subject];
task = [repmat(["rest"; "msit"], 3, 1); worst.task];
r2 = nan(9, 1);
for i = 1:9, r2(i) = rank(R.subject == subj(i) & R.task == task(i)); end
T = table(subj, task, role, r2, 'VariableNames', {'subject', 'task', 'role', 'r2_rank'});
o = fullfile(P.outRoot, 'stage3', 'd5b');
if ~exist(o, 'dir'), mkdir(o); end
f = fullfile(o, 'test_set.csv');
assert(exist(f, 'file') ~= 2, 'refusing to overwrite %s', f);
writetable(T, f);
disp(T);
fprintf('R2 recordings skipped as D14 (rank above the 3rd worst): %s\n', strjoin(skipped.subject + " " + skipped.task + " (rank " + string(skipped.r2_rank) + ")", ', '));
end
