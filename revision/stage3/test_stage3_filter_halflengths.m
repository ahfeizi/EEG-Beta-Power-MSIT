function ok = test_stage3_filter_halflengths()
%TEST_STAGE3_FILTER_HALFLENGTHS  Synthetic test of the D5 integration (S3a-D5-integ). No EEG data.
%   Default (D5 adopted): 6 filters, the 4 notches at S.lineFreqs +/- S.notchA = 3 Hz, order 826 each,
%   H = 6.637 s. 'none': the 2 pre-D5 filters, H = 3.333 s (S3a-D4e). 'a', 2: the S3a-D5a-H setting,
%   same H. Unknown option refused.

here = fileparts(mfilename('fullpath')); addpath(here);
S = stage3_params();
[H, T] = stage3_filter_halflengths(S);
[H0, T0] = stage3_filter_halflengths(S, 'none');
[H2, T2] = stage3_filter_halflengths(S, 'a', 2);
c1 = S.notchA == 3 && isequal(S.lineFreqs, [50 100 150 200]) && height(T) == 6 ...
    && all(contains(T.filter(3:6), "+/- 3 Hz")) && all(T.order(3:6) == 826) && abs(H - 6.637) < 1e-9;
c2 = height(T0) == 2 && abs(H0 - 3.333) < 1e-9 && isequal(T0, T(1:2, :));
c3 = abs(H2 - H) < 1e-12 && all(contains(T2.filter(3:6), "+/- 2 Hz"));
bad = false; try, stage3_filter_halflengths(S, 'b'); catch ME, bad = strcmp(ME.identifier, 'stage3:lineNoise'); end
fprintf('default (a, a = 3): H = %.4f s, %d filters -> %d; none: H = %.4f s -> %d; a = 2: same H -> %d; unknown refused %d\n', ...
    H, height(T), c1, H0, c2, c3, bad);
ok = c1 && c2 && c3 && bad;
if ok, fprintf('FILTER HALFLENGTHS PASS\n'); else, fprintf('FILTER HALFLENGTHS FAIL\n'); end
end
