% Synthetic only: default pop_eegfiltnew band-stop kernels at 500 Hz for 50/100/150/200 Hz, +/-2 Hz.
eeglab('nogui');
E = eeg_emptyset; E.srate = 500; E.nbchan = 1; E.trials = 1; E.pnts = 60000;
E.data = zeros(1, E.pnts); E.xmin = 0; E.xmax = (E.pnts-1)/E.srate; E = eeg_checkset(E);
B = 1; tot = 0;
for f0 = [50 100 150 200]
    [~, ~, b] = pop_eegfiltnew(E, 'locutoff', f0-2, 'hicutoff', f0+2, 'revfilt', 1);
    fprintf('notch %3d Hz: order %d, half-length %d samples = %.3f s\n', f0, numel(b)-1, (numel(b)-1)/2, (numel(b)-1)/2/500);
    tot = tot + (numel(b)-1)/2/500; B = conv(B, b);
end
fprintf('cascade of 4: summed half-length %.3f s (combined kernel order %d)\n', tot, numel(B)-1);
f = [13 20 30 45 47 48 49 50 51 52 53 55 60 90 95 97 98 100 102 103 105 145 150 155 195 200];
H1 = freqz(B, 1, f, 500);
fprintf('%6s %10s\n', 'Hz', 'gain dB');
for k = 1:numel(f), fprintf('%6g %10.3f\n', f(k), 20*log10(abs(H1(k)))); end
% the single 50 Hz notch alone (as in v1 task)
[~, ~, b50] = pop_eegfiltnew(E, 'locutoff', 48, 'hicutoff', 52, 'revfilt', 1);
g = freqz(b50, 1, [47 48 53 55], 500); fprintf('50-only notch: 47 %.3f, 48 %.3f, 53 %.3f, 55 %.3f dB\n', 20*log10(abs(g)));
