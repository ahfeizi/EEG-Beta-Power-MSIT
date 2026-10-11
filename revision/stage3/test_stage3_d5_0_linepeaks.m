function ok = test_stage3_d5_0_linepeaks()
%TEST_STAGE3_D5_0_LINEPEAKS  Synthetic test of the guarded parabolic refinement (S3a-D5-0-amend2).
%   No EEG data. The pre-amendment function (linePeaksOld, verbatim from stage3_d5_0_line_noise.m
%   lines 180-202) is the reference.
%   1. Hann-window line at a known off-grid frequency in noise-free data: refined frequency close
%      to the true one, identical to the old refinement (the guard passes).
%   2. A spectrum whose maximum excess sits at the edge of the +/-0.5 Hz window on a rising slope
%      (not a local maximum): the old refinement leaves the grid range; the new one reports the grid peak.
%   3. 20000 random spectra: every new peak frequency lies within f0 +/- 0.55 Hz; excess and
%      amplitude are identical to the old function; where the guard passes, the frequency is too.

here = fileparts(mfilename('fullpath')); addpath(here);
f0s = [50 100 150 200]; d = (-30:30) / 10; F = reshape(f0s + d', 1, []);
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9; pkwin = find(abs(d) <= 0.5 + 1e-9);
ok = true;

% 1. clean line at 50.03 / 100.07 / 149.96 / 200.02 Hz (10 s Hann, 500 Hz, DFT at the grid)
fs = 500; N = 10 * fs; t = (0:N-1)' / fs; w = hann(N);
ftrue = [50.03 100.07 149.96 200.02];
x = sum(sin(2 * pi * t * ftrue), 2) + 1e-3 * sin(2 * pi * t * 37.3);   % tiny broadband stand-in
E = exp(-1i * 2 * pi * (0:N-1)' * F / fs);
P = abs(E.' * (detrend(x) .* w)).^2' + 1e-6;               % 1 x 244
[e1, f1, a1] = stage3_d5_0_linepeaks(P, F, d, f0s, flank, pkwin);
[e0, f0o, a0] = linePeaksOld(P, F, d, f0s, flank, pkwin);
c1 = all(abs(f1 - ftrue) < 0.02) && isequal(f1, f0o) && isequal(e1, e0) && isequal(a1, a0);
fprintf('1 clean lines: refined %s (true %s); equals old: %d -> %d\n', mat2str(f1, 5), mat2str(ftrue), isequal(f1, f0o), c1);
ok = ok && c1;

% 2. rising slope inside the window: max excess at +0.5 Hz, convex/flat neighbourhood
Ld = zeros(1, 61); Ld(31:36) = [0 1 2 3 4 5]; Ld(37) = 6.001;                  % max inside window at d = +0.5, rising beyond: den = 0.001 > 0
P2 = repmat(10 .^ (Ld / 10), 1, 4);
[~, fo] = linePeaksOld(P2, F, d, f0s, flank, pkwin);
[~, fn] = stage3_d5_0_linepeaks(P2, F, d, f0s, flank, pkwin);
c2 = any(abs(fo - f0s) > 0.55) && all(abs(fn - f0s - 0.5) < 1e-9);   % new: the grid peak (+0.5 Hz)
fprintf('2 edge peak: old offsets %s Hz; new %s Hz -> %d\n', mat2str(fo - f0s, 4), mat2str(fn - f0s, 4), c2);
ok = ok && c2;

% 3. random spectra
rng(11, 'twister');
nR = 20000;
Pr = 10 .^ (randn(nR, 244) * 1.5 / 10) .* (1 + 20 * (rand(nR, 244) < 0.02));
[en, fn, an] = stage3_d5_0_linepeaks(Pr, F, d, f0s, flank, pkwin);
[eo, fo, ao] = linePeaksOld(Pr, F, d, f0s, flank, pkwin);
inRange = all(abs(fn - f0s) <= 0.55 + 1e-9, 'all');
same = isequal(en, eo) && isequal(an, ao);
oldBad = sum(abs(fo - f0s) > 0.55, 'all');
moved = fn ~= fo;
om = fn - f0s; om = om(moved);
c3 = inRange && same && oldBad > 0 && all(abs(om * 10 - round(om * 10)) < 1e-6);   % changed values are grid points
fprintf('3 random: new within +/-0.55 Hz: %d; excess and amplitude identical: %d; old outside +/-0.55: %d of %d; changed values on the grid: %d -> %d\n', ...
    inRange, same, oldBad, numel(fo), c3, c3);
ok = ok && c3;
if ok, fprintf('LINEPEAKS GUARD PASS\n'); else, fprintf('LINEPEAKS GUARD FAIL\n'); end
end

function [exc, fpk, amp] = linePeaksOld(Pw, F, d, f0s, flank, pkwin)
% verbatim: stage3_d5_0_line_noise.m lines 180-202 (before S3a-D5-0-amend2)
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
