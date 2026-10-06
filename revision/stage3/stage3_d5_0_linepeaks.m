function [exc, fpk, amp] = stage3_d5_0_linepeaks(Pw, F, d, f0s, flank, pkwin)
%STAGE3_D5_0_LINEPEAKS  Verbatim copy of the local function linePeaks of stage3_d5_0_line_noise.m
%   (lines 180-202), shared by stage3_d5_0_compute_one.m and the burn-in (stage3_burnin.m).
% Pw: channels x 244 PSD. Per f0: straight-line floor (dB vs Hz) on the flank bins, peak excess
% within +/-0.5 Hz, parabolic peak frequency, and line amplitude sqrt(max(P - floor, 0)).
nCh = size(Pw, 1); exc = nan(nCh, 4); fpk = nan(nCh, 4); amp = nan(nCh, 4);
for j = 1:4
    idx = (j - 1) * 61 + (1:61);
    Ld = 10 * log10(Pw(:, idx));                               % channels x 61
    A = [ones(sum(flank), 1), d(flank)'];
    beta = A \ Ld(:, flank)';                                  % 2 x channels
    fl = [ones(61, 1), d'] * beta;                             % 61 x channels
    ex = Ld - fl';
    [mx, ii] = max(ex(:, pkwin), [], 2);
    i0 = pkwin(ii)';
    lin = sub2ind(size(Ld), (1:nCh)', i0);
    ym = Ld(lin - nCh); y0 = Ld(lin); yp = Ld(lin + nCh);      % neighbours (columns i0-1, i0+1)
    den = ym - 2 * y0 + yp;
    delta = 0.5 * (ym - yp) ./ den; delta(den == 0) = 0;
    exc(:, j) = mx;
    fpk(:, j) = F(idx(i0))' + delta * 0.1;
    flPk = fl(sub2ind(size(fl), i0, (1:nCh)'));                % floor (dB) at the peak bin
    amp(:, j) = sqrt(max(Pw(sub2ind(size(Pw), (1:nCh)', idx(i0)')) - 10 .^ (flPk / 10), 0));
end
end
