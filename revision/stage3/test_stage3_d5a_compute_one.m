function ok = test_stage3_d5a_compute_one(workDir, labelsTsv)
%TEST_STAGE3_D5A_COMPUTE_ONE  Synthetic test of stage3_d5a_compute_one (S3a-D5a-test). No real EEG data.
%   Uses the synthetic recordings of test_stage3_d5b_compute_one (sub-90: white noise + stationary lines
%   at 50/100/150/200 Hz; sub-91: the same noise without lines; raw boundaries at 30 and 57.5 s).
%   Pass: lines present before (excess >= 20 dB); after (a) the line recording's q95 is < 3 dB (C1);
%   four kernels of order 826, cascade gain <= -40 dB at every f0, flank band flagged as inside the
%   transition band; two runs content-identical (stage3_compare 'all').

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
ok0 = test_stage3_d5b_compute_one(workDir, labelsTsv);
p = struct('subject', 'sub-90', 'task', 'rest', 'role', 'synthetic', 'rawRoot', fullfile(workDir, 'raw'), ...
    'manifest', fullfile(workDir, 'manifest.tsv'), 'blockTable', fullfile(workDir, 'blocks.csv'));
fa = fullfile(workDir, 'a_d5a.mat'); fb = fullfile(workDir, 'b_d5a.mat');
stage3_d5a_compute_one(p, fa); stage3_d5a_compute_one(p, fb);
p0 = p; p0.subject = 'sub-91'; fn = fullfile(workDir, 'noise_d5a.mat');
stage3_d5a_compute_one(p0, fn);
R = load(fa); R = R.res; R0 = load(fn); R0 = R0.res;
k = R.kept;
c1 = all(R.excessBeforeDb(k, :) >= 20, 'all') && R.afterCellQuantilesDb(3) < 3;
fprintf('before: min excess %.1f dB; after (a): q95 %.2f dB, max %.2f dB; noise-only q95 after %.2f dB -> %d\n', ...
    min(R.excessBeforeDb(k, :), [], 'all'), R.afterCellQuantilesDb(3), R.maxExcessAfterKeptDb, R0.afterCellQuantilesDb(3), c1);
g0 = R.notch.cascadeGainDbOnGrid(abs(R.F - round(R.F / 50) * 50) < 1e-9);
c2 = isequal(R.notch.order, [826 826 826 826]) && all(g0 <= -40) && R.notch.flankInTransition;
fprintf('orders %s; gain at f0 %s dB; transition widths %s Hz; flank in transition %d; flank gain %s dB -> %d\n', ...
    mat2str(R.notch.order), mat2str(round(g0, 2)), mat2str(round(R.notch.transitionWidthHz, 4)), ...
    R.notch.flankInTransition, mat2str(round(R.notch.flankGainDbRange, 3)), c2);
j = fullfile(workDir, 'cmp_d5a.json'); stage3_compare(fa, fb, 'all', j);
c3 = jsondecode(fileread(j)).equal;
fprintf('two runs content-identical: %d\n', c3);
% criterion on a synthetic verified batch (sub-90, sub-91) with a fake (b) summary
src = fullfile(workDir, 'd5a_batch'); mkdir(fullfile(src, 'state'));
fid = fopen(fullfile(src, 'batch.json'), 'w'); fwrite(fid, jsonencode(struct('mode', 'Batch', 'status', 'DONE'))); fclose(fid);
for f = {fa, fn}
    L = load(f{1}); id = char(L.res.subject + "_" + L.res.task);
    fid = fopen(fullfile(src, 'state', [id '.json']), 'w');
    fwrite(fid, jsonencode(struct('status', 'verified', 'canonical', struct('path', f{1}, 'sha256', sha256File(f{1}))))); fclose(fid);
end
summary = table(["sub-90"; "sub-91"], ["rest"; "rest"], [3.5; 1.0], 'VariableNames', {'subject', 'task', 'q95_after_db'}); %#ok<NASGU>
bm = fullfile(workDir, 'fake_b_merge.mat'); save(bm, 'summary');
mkdir(fullfile(workDir, 'crit'));
T = stage3_d5a_criterion(src, bm, fullfile(workDir, 'crit', 'criterion_a.csv'));
dec = fileread(fullfile(workDir, 'crit', 'criterion_a_decision.txt'));
c4 = height(T) == 2 && all(T.flank_in_transition) && all(T.recording_pass == T.C1_q95_lt3) ...
    && all(T.a_passes == all(T.C1_q95_lt3)) && abs(T.a_minus_b_q95_db(T.subject == "sub-90") - (R.afterCellQuantilesDb(3) - 3.5)) < 1e-12 ...
    && contains(dec, 'C1 only');
noOver = false; try, stage3_d5a_criterion(src, bm, fullfile(workDir, 'crit', 'criterion_a.csv')); catch, noOver = true; end
fprintf('criterion: C1 only when flank in transition, (a)-(b) difference, decision text %d; no overwrite %d\n', c4, noOver);
ok = ok0 && c1 && c2 && c3 && c4 && noOver;
if ok, fprintf('D5A SYNTHETIC PASS\n'); else, fprintf('D5A SYNTHETIC FAIL\n'); end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
