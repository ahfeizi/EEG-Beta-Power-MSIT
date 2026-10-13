function stage3_d5a_diag(d50BatchDir, bMergeFile, outDir)
%STAGE3_D5A_DIAG  Diagnostics before the notch-width choice of fallback (a) (S3a-D5a-diag). Descriptive only.
%   d50BatchDir: verified D5-0 batch (d5_0_2); bMergeFile: canonical (b) merge output (d5bm_1); outDir: new
%   folder (refused if it exists). No EEG data: only stored f0 +/- 3 Hz spectra and filter designs.
%   (a) line spectra: per kept channel, dB re its mean flank level (1.5 <= |f - f0| <= 3 Hz) of the
%       chunk-averaged PSD (0.1 Hz grid); per recording the median over kept channels; across recordings
%       the mean and 10/25/50/75/90th percentiles. Figures spectrum_f0_<f0>.png; tables line_peaks.csv
%       (grand-average and median spectra) and line_peaks_by_recording.csv.
%   (b) d5b_fail_cells.csv: per (b) test recording x f0, kept cells with after-excess >= 3 dB.
%   (c) notch_profiles.csv, notch_profile_f0_100.png and notch_a<a>/filter_halflengths.csv for
%       a = 2..6 (band edges f0 +/- a Hz, pop_eegfiltnew default design at 500 Hz). The stimulus loss per
%       a is added by stage3_d5a_diag_loss after stage3_raw_boundaries_d4e.py has run on each folder.

here = fileparts(mfilename('fullpath')); addpath(here);
assert(~exist(outDir, 'dir'), 'refusing to overwrite %s', outDir);
mkdir(outDir);
S = stage3_params();
f0s = [50 100 150 200]; d = (-30:30) / 10;
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pc = [10 25 50 75 90];
ink = [0.32 0.32 0.31]; c100 = [205 226 251] / 255; c250 = [134 182 239] / 255; c600 = [24 79 149] / 255;

% ---- (a) line spectra ------------------------------------------------------------------------------
batch = jsondecode(fileread(fullfile(d50BatchDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');
St = dir(fullfile(d50BatchDir, 'state', '*.json'));
nR = numel(St); rec = strings(nR, 1); spec = nan(nR, 4, numel(d));
for k = 1:nR
    st = jsondecode(fileread(fullfile(d50BatchDir, 'state', St(k).name)));
    assert(strcmp(st.status, 'verified'), '%s: status %s', St(k).name, st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', St(k).name);
    L = load(st.canonical.path); R = L.res;
    assert(isequal(L.f0s(:)', f0s) && isequal(L.d(:)', d), '%s: unexpected grid', St(k).name);
    rec(k) = erase(string(St(k).name), ".json");
    kept = ~ismember(R.label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
    for j = 1:4
        P = R.avgP(kept, (j - 1) * numel(d) + (1:numel(d)));
        spec(k, j, :) = median(10 * log10(P ./ mean(P(:, flank), 2)), 1);
    end
end
pkRows = {}; recRows = {};
for j = 1:4
    X = squeeze(spec(:, j, :));                           % recordings x bins
    G = mean(X, 1); Q = prctile(X, pc, 1);
    for v = ["grand_mean", "median"]
        if v == "grand_mean", y = G; else, y = Q(3, :); end
        p = peakInfo(y, d);
        pkRows{end+1} = table(f0s(j), v, p.gridHz, p.vertexHz, p.levelDb, p.wLoHz, p.wHiHz, p.widthHz, p.n2, p.second, ...
            'VariableNames', {'f0', 'spectrum', 'peak_offset_grid_hz', 'peak_offset_vertex_hz', 'peak_db_re_flank', ...
            'minus3db_lo_hz', 'minus3db_hi_hz', 'minus3db_width_hz', 'n_second_peaks', 'second_peaks'}); %#ok<AGROW>
    end
    for k = 1:nR
        p = peakInfo(X(k, :), d);
        recRows{end+1} = table(rec(k), f0s(j), p.vertexHz, p.levelDb, p.widthHz, p.n2, p.second, 'VariableNames', ...
            {'recording', 'f0', 'peak_offset_vertex_hz', 'peak_db_re_flank', 'minus3db_width_hz', 'n_second_peaks', 'second_peaks'}); %#ok<AGROW>
    end
    fig = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0 0 760 460], 'Color', 'w');
    ax = axes(fig); hold(ax, 'on');
    fill(ax, [d fliplr(d)], [Q(1, :) fliplr(Q(5, :))], c100, 'EdgeColor', 'none', 'DisplayName', '10-90th percentile');
    fill(ax, [d fliplr(d)], [Q(2, :) fliplr(Q(4, :))], c250, 'EdgeColor', 'none', 'DisplayName', '25-75th percentile');
    plot(ax, d, Q(3, :), '-', 'Color', c600, 'LineWidth', 2, 'DisplayName', 'median');
    plot(ax, d, G, '--', 'Color', ink, 'LineWidth', 1.5, 'DisplayName', 'grand mean');
    xline(ax, [-0.5 0.5], ':', 'Color', ink, 'HandleVisibility', 'off');
    yline(ax, 0, '-', 'Color', [0.8 0.8 0.8], 'HandleVisibility', 'off');
    set(ax, 'Box', 'off', 'XColor', ink, 'YColor', ink, 'FontSize', 11, 'XTick', -3:0.5:3, 'TickDir', 'out');
    xlabel(ax, sprintf('Offset from %d Hz (Hz)', f0s(j))); ylabel(ax, 'dB re mean flank level (1.5-3 Hz)');
    title(ax, sprintf('%d Hz: per-recording median over kept channels, %d recordings (d5\\_0\\_2)', f0s(j), nR), ...
        'FontWeight', 'normal', 'Color', ink);
    legend(ax, 'Location', 'northeast', 'Box', 'off', 'TextColor', ink);
    exportgraphics(fig, fullfile(outDir, sprintf('spectrum_f0_%d.png', f0s(j))), 'Resolution', 150);
    close(fig);
end
writetable(vertcat(pkRows{:}), fullfile(outDir, 'line_peaks.csv'));
byRec = vertcat(recRows{:});
writetable(byRec, fullfile(outDir, 'line_peaks_by_recording.csv'));
sumRows = cell(4, 1);
for j = 1:4
    r = byRec(byRec.f0 == f0s(j), :);
    sumRows{j} = table(f0s(j), height(r), median(r.peak_offset_vertex_hz), sum(abs(r.peak_offset_vertex_hz) > 0.5), ...
        median(r.minus3db_width_hz, 'omitnan'), sum(isnan(r.minus3db_width_hz)), sum(r.n_second_peaks > 0), ...
        'VariableNames', {'f0', 'n_recordings', 'median_peak_offset_hz', 'n_abs_offset_gt_0p5', ...
        'median_minus3db_width_hz', 'n_width_undefined', 'n_with_second_peak'});
end
writetable(vertcat(sumRows{:}), fullfile(outDir, 'line_peaks_by_recording_summary.csv'));

% ---- (b) where (b) failed ---------------------------------------------------------------------------
B = load(bMergeFile); rows = {};
for k = 1:numel(B.results)
    r = B.results(k); e = r.excessAfterDb(r.kept, :);
    n = sum(e >= 3, 1);
    rows{end+1} = table(r.subject, r.task, sum(r.kept), n(1), n(2), n(3), n(4), sum(n), 'VariableNames', ...
        {'subject', 'task', 'n_kept', 'n_ge3db_50', 'n_ge3db_100', 'n_ge3db_150', 'n_ge3db_200', 'n_ge3db_total'}); %#ok<AGROW>
end
Tb = vertcat(rows{:});
tot = table("all", "", sum(Tb.n_kept), sum(Tb.n_ge3db_50), sum(Tb.n_ge3db_100), sum(Tb.n_ge3db_150), sum(Tb.n_ge3db_200), ...
    sum(Tb.n_ge3db_total), 'VariableNames', Tb.Properties.VariableNames);
writetable([Tb; tot], fullfile(outDir, 'd5b_fail_cells.csv'));

% ---- (c) notch widths -------------------------------------------------------------------------------
fs = S.fsOut;
Z = eeg_emptyset; Z.srate = fs; Z.nbchan = 1; Z.trials = 1; Z.pnts = 120 * fs;
Z.data = zeros(1, Z.pnts); Z.xmin = 0; Z.xmax = (Z.pnts - 1) / fs; Z = eeg_checkset(Z);
A = 2:6; offs = [0 0.2 0.5 1 1.5 2 3 4]; fine = 0:0.001:8;
fBlind = [13:0.01:30, 55:0.01:95];
nRows = {}; prof = nan(numel(A), 2 * numel(fine) - 1);
for ia = 1:numel(A)
    a = A(ia); casc = 1; ord = nan(1, 4);
    for j = 1:4
        [~, ~, b] = pop_eegfiltnew(Z, 'locutoff', f0s(j) - a, 'hicutoff', f0s(j) + a, 'revfilt', 1);
        ord(j) = numel(b) - 1; casc = conv(casc, b);
    end
    [H, T] = stage3_filter_halflengths(S, 'a', a);
    nd = fullfile(outDir, sprintf('notch_a%d', a)); mkdir(nd);
    writetable(T, fullfile(nd, 'filter_halflengths.csv'));
    gB = 20 * log10(abs(freqz(casc, 1, fBlind, fs)));
    for j = 1:4
        g = 20 * log10(abs(freqz(casc, 1, f0s(j) + fine, fs)));
        gm = 20 * log10(abs(freqz(casc, 1, f0s(j) - fine, fs)));
        gw = max(g, gm);                                   % the weaker side at each offset
        if f0s(j) == 100, prof(ia, :) = [fliplr(gm(2:end)) g]; end
        go = interp1(fine, gw, offs);
        nRows{end+1} = table(a, f0s(j), ord(j), 3.3 / ord(j) * fs, a - 3.3 / ord(j) * fs, contig(fine, gw, -33), ...
            contig(fine, gw, -20), contig(fine, gw, -6), go(1), go(2), go(3), go(4), go(5), go(6), go(7), go(8), ...
            max(abs(gB(fBlind <= 30))), max(abs(gB(fBlind >= 55))), H, 'VariableNames', {'a_hz', 'f0', 'order', ...
            'transition_width_hz', 'stopband_halfwidth_hz', 'halfwidth_ge33db_hz', 'halfwidth_ge20db_hz', ...
            'halfwidth_minus6db_hz', 'gain_0', 'gain_0p2', 'gain_0p5', 'gain_1', 'gain_1p5', 'gain_2', 'gain_3', ...
            'gain_4', 'max_abs_gain_13_30_db', 'max_abs_gain_55_95_db', 'H_s'}); %#ok<AGROW>
    end
end
writetable(vertcat(nRows{:}), fullfile(outDir, 'notch_profiles.csv'));
fig = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0 0 760 460], 'Color', 'w');
ax = axes(fig); hold(ax, 'on');
catc = [42 120 214; 235 104 52; 27 175 122; 237 161 0; 232 123 164] / 255;   % categorical slots 1-5
x = [-fliplr(fine(2:end)) fine];
patch(ax, [-0.5 0.5 0.5 -0.5], [-70 -70 5 5], [0.94 0.94 0.93], 'EdgeColor', 'none', 'HandleVisibility', 'off');
for ia = 1:numel(A)
    plot(ax, x, max(prof(ia, :), -70), '-', 'Color', catc(ia, :), 'LineWidth', 2, 'DisplayName', sprintf('a = %d Hz', A(ia)));
end
yline(ax, [-33 -20 -6], ':', {'-33 dB', '-20 dB', '-6 dB'}, 'Color', ink, 'HandleVisibility', 'off', 'LabelHorizontalAlignment', 'left');
set(ax, 'Box', 'off', 'XColor', ink, 'YColor', ink, 'FontSize', 11, 'XLim', [-8 8], 'YLim', [-70 5], 'TickDir', 'out');
xlabel(ax, 'Offset from 100 Hz (Hz)'); ylabel(ax, 'Gain of the 4-notch cascade (dB)');
title(ax, 'Option (a), band edges f0 \pm a Hz, default pop\_eegfiltnew design at 500 Hz (shaded: \pm0.5 Hz)', ...
    'FontWeight', 'normal', 'Color', ink);
legend(ax, 'Location', 'southeast', 'Box', 'off', 'TextColor', ink);
exportgraphics(fig, fullfile(outDir, 'notch_profile_f0_100.png'), 'Resolution', 150);
close(fig);
fprintf('S3a-D5a-diag written to %s\n', outDir);
end

function w = contig(off, g, thr)
% largest offset such that the gain is <= thr at every offset from 0 to it (NaN if not even at 0)
i = find(g > thr, 1);
if isempty(i), w = off(end); elseif i == 1, w = NaN; else, w = off(i - 1); end
end

function p = peakInfo(y, d)
[m, i] = max(y);
p.gridHz = d(i); p.levelDb = m; p.vertexHz = d(i);
if i > 1 && i < numel(y)
    den = y(i - 1) - 2 * y(i) + y(i + 1);
    if den < 0
        dl = 0.5 * (y(i - 1) - y(i + 1)) / den;
        if abs(dl) <= 0.5, p.vertexHz = d(i) + dl * (d(2) - d(1)); end
    end
end
t = m - 3; lo = i; hi = i;
while lo > 1 && y(lo - 1) >= t, lo = lo - 1; end
while hi < numel(y) && y(hi + 1) >= t, hi = hi + 1; end
if lo == 1, p.wLoHz = NaN; else, p.wLoHz = d(lo - 1) + (t - y(lo - 1)) / (y(lo) - y(lo - 1)) * (d(lo) - d(lo - 1)); end
if hi == numel(y), p.wHiHz = NaN; else, p.wHiHz = d(hi) + (y(hi) - t) / (y(hi) - y(hi + 1)) * (d(hi + 1) - d(hi)); end
p.widthHz = p.wHiHz - p.wLoHz;
lm = find(islocalmax(y, 'MinProminence', 3) & y >= 3);
lm(lm == i) = [];
p.n2 = numel(lm);
p.second = string(strjoin(arrayfun(@(k) sprintf('%+.1f Hz %.1f dB', d(k), y(k)), lm, 'uni', 0), '; '));
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
