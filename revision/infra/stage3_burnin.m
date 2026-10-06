function stage3_burnin(params, outFile)
%STAGE3_BURNIN  Deterministic burn-in job (S3a-INF-1 §10; workload per S3a-INF-1-clar1).
%   stage3_burnin(params, outFile) runs params.nIter iterations; each iteration runs:
%     D5 block   the D5-0 kernel on seeded synthetic data, as d50_probe 'synth': 8 groups x 97
%                chunks of 16 channels x 10 s at 500 Hz; per chunk linear detrend, Hann window,
%                DFT product E.' * x at the 244 line-grid frequencies, one-sided PSD scaling and
%                stage3_d5_0_linepeaks. The generator is reset to rng(params.seedGlobal) at the
%                start of every block, so every iteration processes identical input.
%     GEMM block C = GA * GB with GA, GB 2000 x 2000, drawn once from rng(params.seedGlobal).
%   Within the process, each block's result is compared bitwise (isequal on its bytes) with that
%   block's iteration-1 result; the SHA-256 of every iteration's result is stored for the
%   cross-process comparison (stage3_compare kind 'burnin'). Output variables: hashes (.d5, .gemm:
%   nIter x 32 uint8), mismatchWithin (.d5, .gemm), final (.d5 struct, .gemm matrix of the last
%   iteration), nIterations, timing (.d5_s, .gemm_s per iteration; excluded from comparison).

S = stage3_params();
fs = S.fsOut;
f0s = [50 100 150 200];
d = (-30:30) / 10;
F = reshape(f0s + d', 1, []);
assert(~any(F >= 13 & F <= 30) && ~any(F >= 55 & F <= 95), 'outcome-blind: forbidden band in grid');
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pkwin = find(abs(d) <= 0.5 + 1e-9);
N = 10 * fs;
w = hann(N);
nn = (0:N-1)';
E = exp(-1i * 2 * pi * nn * F / fs);
psdScale = 2 / (fs * sum(w .^ 2));
nGroup = 8; nChunkPerGroup = 97; nChan = 16;

nIter = double(params.nIter);
seed = double(params.seedGlobal);
rng(seed, 'twister');
GA = randn(2000); GB = randn(2000);

hashes.d5 = zeros(nIter, 32, 'uint8'); hashes.gemm = zeros(nIter, 32, 'uint8');
mismatchWithin.d5 = 0; mismatchWithin.gemm = 0;
timing.d5_s = zeros(nIter, 1); timing.gemm_s = zeros(nIter, 1);
for it = 1:nIter
    t = tic;
    rng(seed, 'twister');
    r.exc = zeros(nChan, 4, nChunkPerGroup, nGroup); r.fpk = r.exc; r.amp = r.exc;
    r.sumP = zeros(nChan, numel(F), nGroup);
    for g = 1:nGroup
        for c = 1:nChunkPerGroup
            x = randn(N, nChan) * 50;
            x = detrend(x) .* w;
            Pc = psdScale * abs(E.' * x).^2;
            r.sumP(:, :, g) = r.sumP(:, :, g) + Pc';
            [r.exc(:, :, c, g), r.fpk(:, :, c, g), r.amp(:, :, c, g)] = ...
                stage3_d5_0_linepeaks(Pc', F, d, f0s, flank, pkwin);
        end
    end
    timing.d5_s(it) = toc(t);
    b = [typecast(r.exc(:), 'uint8'); typecast(r.fpk(:), 'uint8'); typecast(r.amp(:), 'uint8'); typecast(r.sumP(:), 'uint8')];
    hashes.d5(it, :) = sha256(b);
    if it == 1, ref.d5 = b; elseif ~isequal(b, ref.d5), mismatchWithin.d5 = mismatchWithin.d5 + 1; end

    t = tic;
    C = GA * GB;
    timing.gemm_s(it) = toc(t);
    b = typecast(C(:), 'uint8');
    hashes.gemm(it, :) = sha256(b);
    if it == 1, ref.gemm = b; elseif ~isequal(b, ref.gemm), mismatchWithin.gemm = mismatchWithin.gemm + 1; end
    fprintf('burn-in iteration %d/%d: D5 %.2f s, GEMM %.2f s, within-mismatches D5 %d GEMM %d\n', ...
        it, nIter, timing.d5_s(it), timing.gemm_s(it), mismatchWithin.d5, mismatchWithin.gemm);
end
final.d5 = r; final.gemm = C;
nIterations = nIter;
save(outFile, 'hashes', 'mismatchWithin', 'final', 'nIterations', 'timing');
end

function h = sha256(b)
md = java.security.MessageDigest.getInstance('SHA-256');
h = typecast(md.digest(typecast(b, 'int8')), 'uint8')';
end
