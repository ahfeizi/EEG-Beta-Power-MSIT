function r1_fig1_curves(outCsv)
%R1_FIG1_CURVES Review round 1 (decision log §11i): write the detrended curves that Figure 1 plots.
%   r1_fig1_curves(outCsv)
%   Reproduces the computation of plot_all_subjects_spectrum_grid.m (project root) line for line, without
%   plotting: v1 Rest_Output\sub-XX\sub-XX_rest_clean.set, pwelch with a 2 s Hann window and 50 % overlap on
%   every channel, PSD averaged over channels, log10 power on 2-40 Hz detrended by a linear fit in log-log
%   coordinates that excludes 7-13 Hz, kept on the 5-40 Hz display range. Writes one row per subject x bin
%   (subject, f, detr). Reads the v1 derivatives only; never overwrites.
if exist(outCsv, 'file'), error('r1:fig1', 'output exists, not overwritten: %s', outCsv); end
if ~exist('pop_loadset', 'file'), eeglab('nogui'); end
P = get_paths();
derivRoot = P.derivRoot;                       % = the plotting script's hard-coded Rest_Output path
displayRange = [5, 40]; fitRange = [2, 40]; alphaMask = [7, 13];
epochLen = 2.0; pweOverlap = 50;
fid = fopen(outCsv, 'w'); fprintf(fid, 'subject,f,detr\n');
for i = 1:42
    subject = sprintf('sub-%02d', i);
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    if ~exist(setFile, 'file'), fprintf('%s: SKIPPED (no file)\n', subject); continue, end
    EEG = pop_loadset('filename', setFile);
    data = double(EEG.data);
    if ndims(data) == 3, data = reshape(data, size(data, 1), []); end
    fs = EEG.srate; win = round(epochLen * fs); ov = round(win * pweOverlap / 100);
    [pxx, f] = pwelch(data', hann(win), ov, win, fs);
    psd = mean(pxx, 2);
    sel = f >= fitRange(1) & f <= fitRange(2) & f > 0;
    fx = f(sel); ly = log10(psd(sel)); lx = log10(fx);
    fitMask = ~(fx >= alphaMask(1) & fx <= alphaMask(2));
    p = polyfit(lx(fitMask), ly(fitMask), 1);
    detr = ly - polyval(p, lx);
    k = fx >= displayRange(1) & fx <= displayRange(2);
    C = [repmat({subject}, 1, nnz(k)); num2cell(fx(k)'); num2cell(detr(k)')];
    fprintf(fid, '%s,%.6f,%.10g\n', C{:});
    fprintf('%s: %d bins\n', subject, nnz(k));
end
fclose(fid);
end
