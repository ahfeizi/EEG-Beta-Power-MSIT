function res = stage3_d5a_residual(Pbefore, Pafter, d, flank, pkwin)
%STAGE3_D5A_RESIDUAL  Residual line of D5 fallback (a) against the PRE-filter floor (S3a-D5a-crit2).
%   Pbefore, Pafter: channels x 244 chunk-averaged PSD on the f0 +/- 3 Hz grid (4 f0 x 61 bins), before and
%   after (a). Per channel and f0: the straight-line floor (dB vs Hz) fitted on the flank bins of Pbefore,
%   exactly as in stage3_d5_0_linepeaks, and
%       res = max over the peak window (|f - f0| <= 0.5 Hz) of 10*log10(Pafter) - floor_before   (dB).
%   With Pafter's flanks equal to Pbefore's this is the stage3_d5_0_linepeaks excess of Pafter, i.e. the
%   (b) measure (whose flanks are unchanged, R-b2).
nCh = size(Pbefore, 1); res = nan(nCh, 4);
A = [ones(sum(flank), 1), d(flank)'];
for j = 1:4
    idx = (j - 1) * 61 + (1:61);
    Lb = 10 * log10(Pbefore(:, idx));
    La = 10 * log10(Pafter(:, idx));
    beta = A \ Lb(:, flank)';                                  % 2 x channels
    fl = ([ones(61, 1), d'] * beta)';                          % channels x 61
    res(:, j) = max(La(:, pkwin) - fl(:, pkwin), [], 2);
end
end
