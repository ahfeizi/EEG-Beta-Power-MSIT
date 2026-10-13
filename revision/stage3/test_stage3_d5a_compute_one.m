function ok = test_stage3_d5a_compute_one(workDir, labelsTsv)
%TEST_STAGE3_D5A_COMPUTE_ONE  Synthetic test of stage3_d5a_compute_one and stage3_d5a_criterion
%   (S3a-D5a-test, -amend1, S3a-D5a-width). No real EEG data.
%   Uses the synthetic recordings of test_stage3_d5b_compute_one (sub-90: white noise + stationary lines
%   at 50/100/150/200 Hz; sub-91: the same noise without lines; raw boundaries at 30 and 57.5 s).
%   Pass: notchA is required; with a = 3 the lines are removed (q95 after < 3 dB); four kernels of order
%   826, cascade gain <= -40 dB at every f0, transition band [a - df, a] = [1.002, 3] Hz, flank band
%   flagged as inside it; two runs content-identical (stage3_compare 'all'). Residual (S3a-D5a-crit2):
%   with identical before/after flanks it equals the stage3_d5_0_linepeaks excess (the (b) measure); the
%   line recording after (a) passes C1 (residual q95 < 3 dB) and so does the noise twin; criterion table
%   matches an independent computation, null reported by task, decision PASS with hashes; a null with
%   another notch width is refused; no overwrite.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
ok0 = test_stage3_d5b_compute_one(workDir, labelsTsv);
p = struct('subject', 'sub-90', 'task', 'rest', 'role', 'synthetic', 'rawRoot', fullfile(workDir, 'raw'), ...
    'manifest', fullfile(workDir, 'manifest.tsv'), 'blockTable', fullfile(workDir, 'blocks.csv'));
need = false; try, stage3_d5a_compute_one(p, fullfile(workDir, 'x.mat')); catch ME, need = contains(ME.message, 'notchA'); end
p.notchA = 3;
fa = fullfile(workDir, 'a_d5a.mat'); fb = fullfile(workDir, 'b_d5a.mat');
stage3_d5a_compute_one(p, fa); stage3_d5a_compute_one(p, fb);
p0 = p; p0.subject = 'sub-91'; fn = fullfile(workDir, 'noise_d5a.mat');
stage3_d5a_compute_one(p0, fn);
p2 = p0; p2.notchA = 2; fn2 = fullfile(workDir, 'noise_d5a_a2.mat');
stage3_d5a_compute_one(p2, fn2);
R = load(fa); R = R.res; R0 = load(fn); R0 = R0.res;
k = R.kept;
c1 = need && all(R.excessBeforeDb(k, :) >= 20, 'all') && R.afterCellQuantilesDb(3) < 3;
fprintf('notchA required %d; before: min excess %.1f dB; after (a, a = 3): q95 %.2f dB, max %.2f dB; noise-only q95 %.2f dB -> %d\n', ...
    need, min(R.excessBeforeDb(k, :), [], 'all'), R.afterCellQuantilesDb(3), R.maxExcessAfterKeptDb, R0.afterCellQuantilesDb(3), c1);
g0 = R.notch.cascadeGainDbOnGrid(abs(R.F - round(R.F / 50) * 50) < 1e-9);
c2 = R.notch.a == 3 && isequal(R.notch.order, [826 826 826 826]) && all(g0 <= -40) && R.notch.flankInTransition ...
    && all(abs(R.notch.transitionBandHz(1, :) - (3 - 3.3 / 826 * 500)) < 1e-12) && all(R.notch.transitionBandHz(2, :) == 3);
fprintf('orders %s; gain at f0 %s dB; transition band %s Hz; flank in transition %d; flank gain %s dB -> %d\n', ...
    mat2str(R.notch.order), mat2str(round(g0, 2)), mat2str(round(R.notch.transitionBandHz(:, 1)', 4)), ...
    R.notch.flankInTransition, mat2str(round(R.notch.flankGainDbRange, 3)), c2);
j = fullfile(workDir, 'cmp_d5a.json'); stage3_compare(fa, fb, 'all', j);
c3 = jsondecode(fileread(j)).equal;
fprintf('two runs content-identical: %d\n', c3);
% criterion: real batch (sub-90, sub-91 rest); null batch (sub-91 rest; sub-91 relabelled MSIT+)
fm = fullfile(workDir, 'noise_d5a_msit.mat'); L = load(fn); res = L.res; res.task = "msit"; save(fm, 'res');
fm2 = fullfile(workDir, 'noise_d5a_a2_msit.mat'); L = load(fn2); res = L.res; res.task = "msit"; save(fm2, 'res');
realB = mkBatch(fullfile(workDir, 'd5a_real'), {fa, fn});
nul = mkBatch(fullfile(workDir, 'd5a_null'), {fn, fm});
nul2 = mkBatch(fullfile(workDir, 'd5a_null_a2'), {fn, fm2});
summary = table(["sub-90"; "sub-91"], ["rest"; "rest"], [3.5; 1.0], 'VariableNames', {'subject', 'task', 'q95_after_db'}); %#ok<NASGU>
bm = fullfile(workDir, 'fake_b_merge.mat'); save(bm, 'summary');
mkdir(fullfile(workDir, 'crit'));
out = fullfile(workDir, 'crit', 'criterion_a.csv');
T = stage3_d5a_criterion(realB, nul, bm, out);
dec = fileread(fullfile(workDir, 'crit', 'criterion_a_decision.txt'));
dd = (-30:30) / 10; fk = abs(dd) >= 1.5 - 1e-9 & abs(dd) <= 3 + 1e-9; pw = find(abs(dd) <= 0.5 + 1e-9);
FF = reshape([50 100 150 200] + dd', 1, []);
Px = R.avgPBefore; eq = stage3_d5a_residual(Px, Px, dd, fk, pw);
c5 = max(abs(eq - stage3_d5_0_linepeaks(Px, FF, dd, [50 100 150 200], fk, pw)), [], 'all') < 1e-10;
e90 = stage3_d5a_residual(R.avgPBefore, R.avgPAfter, dd, fk, pw); e90 = e90(k, :);
e91 = stage3_d5a_residual(R0.avgPBefore, R0.avgPAfter, dd, fk, pw); e91 = e91(R0.kept, :);
i90 = T.subject == "sub-90"; i91 = T.subject == "sub-91";
c4 = height(T) == 2 && all(T.null_twin == "sub-91 rest") && abs(T.residual_q95_db(i90) - quantile(e90(:), 0.95)) < 1e-12 ...
    && abs(T.null_residual_q95_db(i90) - quantile(e91(:), 0.95)) < 1e-12 && T.residual_cells_gt3db(i90) == sum(e90(:) > 3) ...
    && all(T.recording_pass) && all(T.a_passes) && abs(T.a_minus_b_q95_db(i90) - (T.residual_q95_db(i90) - 3.5)) < 1e-12 ...
    && contains(dec, 'R-b2 not evaluated') && contains(dec, 'SHA-256') && contains(dec, 'DECISION: PASS') && contains(dec, 'a = 3');
fprintf('residual == (b) excess when flanks unchanged %d; sub-90 residual q95 %.2f dB (max %.2f); null residual q95 %.2f dB\n', ...
    c5, T.residual_q95_db(i90), T.residual_max_db(i90), T.null_residual_q95_db(i90));
mix = false; try, stage3_d5a_criterion(realB, nul2, bm, fullfile(workDir, 'crit', 'mix.csv')); catch ME, mix = contains(ME.message, 'notch width'); end
noOver = false; try, stage3_d5a_criterion(realB, nul, bm, out); catch, noOver = true; end
fprintf('criterion: residual table, null by task, decision PASS %d; mixed widths refused %d; no overwrite %d\n', c4, mix, noOver);
ok = ok0 && c1 && c2 && c3 && c4 && c5 && mix && noOver;
if ok, fprintf('D5A SYNTHETIC PASS\n'); else, fprintf('D5A SYNTHETIC FAIL\n'); end
end

function src = mkBatch(src, files)
mkdir(fullfile(src, 'state'));
fid = fopen(fullfile(src, 'batch.json'), 'w'); fwrite(fid, jsonencode(struct('mode', 'Batch', 'status', 'DONE'))); fclose(fid);
for f = files
    L = load(f{1}); id = char(L.res.subject + "_" + L.res.task);
    fid = fopen(fullfile(src, 'state', [id '.json']), 'w');
    fwrite(fid, jsonencode(struct('status', 'verified', 'canonical', struct('path', f{1}, 'sha256', sha256File(f{1}))))); fclose(fid);
end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
