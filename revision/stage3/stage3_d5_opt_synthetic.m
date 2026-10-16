function stage3_d5_opt_synthetic(outDir)
%STAGE3_D5_OPT_SYNTHETIC  Synthetic calibrations for decision S3a-D5-opt (docs/decision_log.md,
%   "Synthetic calibrations", logged before this ran). Filter design and synthetic signals only:
%   no EEG file is read.
%   stage3_d5_opt_synthetic(outDir) writes results.mat (struct R, no time stamps), three CSV tables
%   and run_info.txt (time stamps, environment) to outDir. It is run twice in separate processes;
%   the two R structs must be isequaln before any value is reported.
%
%   A    gain of the option (a) / (a') band-stop cascades at f0 and f0 +/- 0.1, 0.2, 0.5, 1.0 Hz
%   i4   default pop_eegfiltnew low-pass designs for option (i-4) and their H cost
%   B    rise of 55-60 / 90-95 Hz band power, under a 0.2 s Hann estimator, caused by a residual
%        line at 50 or 100 Hz whose expected D5-0 excess is X dB

maxNumCompThreads(2);
rng(1, 'twister');                                         % SEED_GLOBAL (S3a-INF-1)
here = fileparts(mfilename('fullpath'));
addpath(here);
if ~exist('pop_eegfiltnew', 'file'), eeglab('nogui'); end
if ~exist(outDir, 'dir'), mkdir(outDir); end
S = stage3_params();
fs = S.fsOut;                                              % 500 Hz

% zero-valued synthetic dataset, used only to obtain the installed default kernels
Z = eeg_emptyset; Z.srate = fs; Z.nbchan = 1; Z.trials = 1; Z.pnts = 120 * fs;
Z.data = zeros(1, Z.pnts); Z.xmin = 0; Z.xmax = (Z.pnts - 1) / fs; Z = eeg_checkset(Z);

% ---- A: attenuation of the (a) and (a') cascades near the line -------------------------------
f0s = [50 100 150 200];
b = cell(1, 4);
for k = 1:4
    [~, ~, b{k}] = pop_eegfiltnew(Z, 'locutoff', f0s(k) - 2, 'hicutoff', f0s(k) + 2, 'revfilt', 1);
end
casc.a = 1; for k = 1:4, casc.a = conv(casc.a, b{k}); end   % option (a): 4 notches
casc.a1 = conv(b{1}, b{2});                                  % option (a'): 50 and 100 Hz
offs = [-1 -0.5 -0.2 -0.1 0 0.1 0.2 0.5 1];
opt = strings(0, 1); f0c = []; offc = []; gdb = [];
for name = ["a", "a1"]
    for f0 = [50 100]
        g = 20 * log10(abs(freqz(casc.(name), 1, f0 + offs, fs)));
        opt = [opt; repmat(name, numel(offs), 1)]; f0c = [f0c; repmat(f0, numel(offs), 1)]; %#ok<AGROW>
        offc = [offc; offs(:)]; gdb = [gdb; g(:)];          %#ok<AGROW>
    end
end
opt(opt == "a1") = "a_prime";
R.A = table(opt, f0c, offc, f0c + offc, gdb, 'VariableNames', ...
    {'option', 'f0_hz', 'offset_hz', 'freq_hz', 'gain_db'});
R.notchOrder = cellfun(@numel, b) - 1;

% ---- i4: default low-pass designs and their H cost --------------------------------------------
[H0, T0] = stage3_filter_halflengths(S, 'none');           % pre-D5 H                   % current H (high-pass + anti-aliasing)
lpE = 100;
for E = 147:-1:101                                          % largest integer edge with stop-band < 148 Hz
    [~, ~, bl] = pop_eegfiltnew(Z, 'hicutoff', E);
    df = 3.3 / (numel(bl) - 1) * fs;                        % pop_eegfiltnew.m:242 (Hamming)
    if E + df < 148, lpE(end+1) = E; break; end              %#ok<AGROW>
end
rows = zeros(numel(lpE), 9);
for i = 1:numel(lpE)
    [~, ~, bl] = pop_eegfiltnew(Z, 'hicutoff', lpE(i));
    ord = numel(bl) - 1; df = 3.3 / ord * fs; half = ord / 2;
    g = 20 * log10(abs(freqz(bl, 1, [150 200], fs)));
    rows(i, :) = [lpE(i), ord, df, lpE(i) + df / 2, lpE(i) + df, half, half / fs, g];
end
R.i4 = array2table(rows, 'VariableNames', {'passband_edge_hz', 'order', 'transition_hz', ...
    'cutoff_6db_hz', 'stopband_edge_hz', 'half_samples', 'half_s', 'gain_150_db', 'gain_200_db'});
R.i4.H_with_b_s = H0 + R.i4.half_s;                         % (b): no notch contribution
R.i4.H_with_a_prime_s = H0 + sum(R.notchOrder(1:2)) / 2 / fs + R.i4.half_s;
R.H0 = H0; R.H0_table = T0;

% ---- B: leakage of a residual line into the control-band edges -------------------------------
N0 = 1;                                                     % one-sided background PSD at f0 (uV^2/Hz)
w10 = hann(10 * fs);                                        % D5-0 estimator: 10 s Hann
PsUnit = sum(w10)^2 / (2 * fs * sum(w10 .^ 2));             % PSD at the peak bin of a unit-amplitude line
Xs = [1 2 3 6 10 15 20 30];
aOf = @(X) sqrt((10 .^ (X / 10) - 1) * N0 / PsUnit);        % expected D5-0 excess = X dB (white floor)
L = 100; w = hann(L); U = sum(w .^ 2);                      % Stage 5: 0.2 s Hann, 100 samples
nfftList = [256 100];                                       % v1 pwelch default; no zero-padding
bands = [55 60; 90 95];
lines = [50 100];
alphas = [0 1 2];                                           % background ~ (f0/f)^alpha, = N0 at f0
n = (0:L-1)';
rowsB = [];
for q = 1:numel(nfftList)
    fb = (0:floor(nfftList(q) / 2))' * fs / nfftList(q);
    Wm = @(nu) abs(sum(w .* exp(-1i * 2 * pi * n * nu(:)' / fs), 1)).^2;   % |W(nu)|^2
    for li = 1:2
        f0 = lines(li);
        for bi = 1:2
            kb = fb >= bands(bi, 1) & fb <= bands(bi, 2);
            leakUnit = mean(2 / (fs * U) * (1 / 4) * (Wm(fb(kb) - f0) + Wm(fb(kb) + f0)));  % per a^2
            for al = alphas
                Nb = mean(N0 * (f0 ./ fb(kb)) .^ al);           % background at the bins (approximation for alpha > 0)
                for X = Xs
                    rise = 10 * log10(1 + aOf(X)^2 * leakUnit / Nb);
                    rowsB = [rowsB; nfftList(q), f0, bands(bi, :), al, X, rise, NaN]; %#ok<AGROW>
                end
            end
        end
    end
end
% Monte Carlo check (white background, primary and variant estimator)
nTr = 20000;
sig = sqrt(N0 * fs / 2);                                    % white noise with one-sided PSD N0
noise = sig * randn(L, nTr);
ph = 2 * pi * rand(1, nTr);
for q = 1:numel(nfftList)
    [P0, fb] = pwelch(noise, w, [], nfftList(q), fs);
    for li = 1:2
        f0 = lines(li);
        s = cos(2 * pi * f0 * n / fs + ph);
        for X = Xs
            P1 = pwelch(noise + aOf(X) * s, w, [], nfftList(q), fs);
            for bi = 1:2
                kb = fb >= bands(bi, 1) & fb <= bands(bi, 2);
                mc = 10 * log10(mean(P1(kb, :), 'all') / mean(P0(kb, :), 'all'));
                r = rowsB(:, 1) == nfftList(q) & rowsB(:, 2) == f0 & rowsB(:, 3) == bands(bi, 1) & ...
                    rowsB(:, 5) == 0 & rowsB(:, 6) == X;
                rowsB(r, 8) = mc;
            end
        end
    end
end
R.B = array2table(rowsB, 'VariableNames', {'nfft', 'line_hz', 'band_lo_hz', 'band_hi_hz', ...
    'background_alpha', 'X_db', 'rise_db_expected', 'rise_db_montecarlo'});
R.B_binFreqs = struct('nfft256', (0:128)' * fs / 256, 'nfft100', (0:50)' * fs / 100);
R.B_amplitude = table(Xs(:), aOf(Xs(:)), 'VariableNames', {'X_db', 'amplitude_uV'});
R.B_PsUnit = PsUnit;

% proposal rule (S3a-D5-opt): largest X in {1,2,3,6} with rise <= 0.5 dB in both bands, both lines,
% white background, primary estimator (nfft 256), expected value
P = R.B(R.B.nfft == 256 & R.B.background_alpha == 0 & ismember(R.B.X_db, [1 2 3 6]), :);
ok = arrayfun(@(X) all(P.rise_db_expected(P.X_db == X) <= 0.5), [1 2 3 6]);
cand = [1 2 3 6];
R.proposal_X_db = max([cand(ok), -Inf]);

% ---- outputs ----------------------------------------------------------------------------------
save(fullfile(outDir, 'results.mat'), 'R');
writetable(R.A, fullfile(outDir, 'table_A_attenuation.csv'));
writetable(R.i4, fullfile(outDir, 'table_i4_lowpass.csv'));
writetable(R.B, fullfile(outDir, 'table_B_leakage.csv'));
fid = fopen(fullfile(outDir, 'run_info.txt'), 'w');
fprintf(fid, 'stage3_d5_opt_synthetic finished %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'MATLAB %s | %s | threads %d | MKL_CBWR=%s\n', version, version('-blas'), maxNumCompThreads, getenv('MKL_CBWR'));
fprintf(fid, 'pop_eegfiltnew: %s\npop_resample: %s\n', which('pop_eegfiltnew'), which('pop_resample'));
fclose(fid);
fprintf('DONE %s\n', outDir);
end
