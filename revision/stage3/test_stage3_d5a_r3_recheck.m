function ok = test_stage3_d5a_r3_recheck(workDir)
%TEST_STAGE3_D5A_R3_RECHECK  Synthetic test of stage3_d5a_r3_recheck (S3a-D5a-R3). No EEG data.
%   Two fake verified D5-0 outputs (3 channels incl. TP9, 4 f0, 5 chunks). Mains drift d(c) per chunk,
%   offset at k*50 Hz = k*d(c). Cells below 10 dB and TP9 carry large offsets that must be ignored.
%   Pass: pooled max per f0 = k*max|d|; cell counts exact; harmonic slope = k; decision KEEP when all
%   offsets are small, STOP when one f0 exceeds 0.2 Hz; tampered output refused; no overwrite.

here = fileparts(mfilename('fullpath')); addpath(here);
d = [0.01 -0.02 0.03 0.04 -0.05];                       % drift at 50 Hz per chunk
src = mkBatch(fullfile(workDir, 'b1'), d, false);
o = stage3_d5a_r3_recheck(src, fullfile(workDir, 'out1'));
P = o.pooled;
% n cells: 2 recordings x (2 kept channels x 5 chunks - 1 weak cell) = 18 per f0
c1 = isequal(P.n_cells', [18 18 18 18]) && all(abs(P.max_abs_offset_hz' - (1:4) * 0.05) < 1e-12) && o.pass ...
    && all(abs(o.harmonic.slope_through_origin' - (2:4)) < 1e-12);
src2 = mkBatch(fullfile(workDir, 'b2'), 2 * d + 0.06, false);       % 200 Hz offsets up to 4 * 0.16 = 0.64 Hz
o2 = stage3_d5a_r3_recheck(src2, fullfile(workDir, 'out2'));
c2 = ~o2.pass && contains(fileread(fullfile(workDir, 'out2', 'r3_decision.txt')), 'STOP');
src3 = mkBatch(fullfile(workDir, 'b3'), d, true);
bad = false; try, stage3_d5a_r3_recheck(src3, fullfile(workDir, 'out3')); catch ME, bad = contains(ME.message, 'SHA-256'); end
noOver = false; try, stage3_d5a_r3_recheck(src, fullfile(workDir, 'out1')); catch, noOver = true; end
fprintf('offsets, counts, slope, KEEP %d; STOP when > 0.2 Hz %d; tampered refused %d; no overwrite %d\n', c1, c2, bad, noOver);
ok = c1 && c2 && bad && noOver;
if ok, fprintf('D5A R3 RECHECK PASS\n'); else, fprintf('D5A R3 RECHECK FAIL\n'); end
end

function src = mkBatch(src, d, tamper)
mkdir(fullfile(src, 'state'));
fid = fopen(fullfile(src, 'batch.json'), 'w'); fwrite(fid, jsonencode(struct('mode', 'Batch', 'status', 'DONE'))); fclose(fid);
f0s = [50 100 150 200]; nChunk = numel(d);
for r = 1:2
    res = struct('label', ["Fz"; "Cz"; "TP9 LEFT EAR"]);
    res.exc = 20 * ones(3, 4, nChunk + 2); res.fpk = nan(3, 4, nChunk + 2);   % 2 unused trailing chunks
    for j = 1:4, res.fpk(:, j, 1:nChunk) = repmat(f0s(j) + j * d, 3, 1); end
    res.fpk(3, :, 1:nChunk) = res.fpk(3, :, 1:nChunk) + 0.5;               % TP9: ignored
    res.exc(1, :, 1) = 9.9; res.fpk(1, :, 1) = f0s + 0.5;                    % below 10 dB: ignored
    f = fullfile(src, sprintf('r%d.mat', r)); save(f, 'res', 'f0s', 'nChunk');
    h = sha(f);
    if tamper && r == 2, fid = fopen(f, 'a'); fwrite(fid, uint8(1)); fclose(fid); end
    fid = fopen(fullfile(src, 'state', sprintf('sub-9%d_rest.json', r)), 'w');
    fwrite(fid, jsonencode(struct('status', 'verified', 'canonical', struct('path', f, 'sha256', h)))); fclose(fid);
end
end

function h = sha(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
