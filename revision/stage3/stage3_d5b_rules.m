function R = stage3_d5b_rules(avgB, avgA, chunkExcA, label)
%STAGE3_D5B_RULES  Rule inputs of the D5 option (b) residual test for one recording (S3a-D5b), shared
%   by stage3_d5b_compute_one (unsplit) and stage3_d5b_merge (chunked, S3a-D5b-amend1), so both compute
%   identically. avgB/avgA: channels x 244 chunk-averaged PSD before/after (b) on the f0 +/- 3 Hz grid;
%   chunkExcA: channels x 4 x chunks per-chunk excess after (b); label: channel labels.
%   R-b1 (committed): chunk-averaged excess after (b) < 3 dB in every kept channel and f0.
%   R-b2 (committed): |flank-level change| <= 0.5 dB in every kept channel and f0.
%   Also returned for the revised R-b1 under discussion (S3a-D5b-null): the distribution of the
%   after-excess over the kept-channel x f0 cells (quantiles, count >= 3 dB).
f0s = [50 100 150 200]; d = (-30:30) / 10;
F = reshape(f0s + d', 1, []);
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pkwin = find(abs(d) <= 0.5 + 1e-9);
excB = stage3_d5_0_linepeaks(avgB, F, d, f0s, flank, pkwin);
excA = stage3_d5_0_linepeaks(avgA, F, d, f0s, flank, pkwin);
flankDbB = nan(size(avgB, 1), 4); flankDbA = flankDbB;
for j = 1:4
    idx = (j - 1) * 61 + find(flank);
    flankDbB(:, j) = 10 * log10(mean(avgB(:, idx), 2));
    flankDbA(:, j) = 10 * log10(mean(avgA(:, idx), 2));
end
kept = ~ismember(label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
cells = excA(kept, :); cells = cells(:);
R = struct('label', label, 'kept', kept, 'excessBeforeDb', excB, 'excessAfterDb', excA, ...
    'flankDbBefore', flankDbB, 'flankDbAfter', flankDbA, 'flankChangeDb', flankDbA - flankDbB, ...
    'chunkResidualMedianDb', median(chunkExcA, 3), 'chunkResidualMaxDb', max(chunkExcA, [], 3), ...
    'rb1Pass', all(cells < 3), 'rb2Pass', all(abs(flankDbA(kept, :) - flankDbB(kept, :)) <= 0.5, 'all'), ...
    'maxExcessAfterKeptDb', max(cells), 'maxAbsFlankChangeKeptDb', max(abs(flankDbA(kept, :) - flankDbB(kept, :)), [], 'all'), ...
    'afterCellQuantilesDb', quantile(cells, [0.5 0.9 0.95 0.99])', 'afterCellsGe3Db', sum(cells >= 3), 'nCells', numel(cells));
end
