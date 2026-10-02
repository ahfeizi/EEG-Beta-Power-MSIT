%% ---- extract IBF/amplitude via FOOOF/specparam, robust to 'fixed' vs 'knee' aperiodic mode ----
% Run this script TWICE: once with settings.aperiodic_mode = 'fixed', once with
% settings.aperiodic_mode = 'knee'. Output filename is set automatically to match
% (beta_features_full42_fixed.csv / beta_features_full42_knee.csv), corresponding
% to methods 3 and 4 in Table 1 of the manuscript.
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
% [path] as run: addpath(<local fooof_mat folder>) -- see README, "FOOOF / Python setup"
freq_range = [3, 40];
betaBand   = [13, 30];     % canonical beta range (matches manuscript Methods)

settings = struct();
settings.aperiodic_mode    = 'knee';   % <-- TOGGLE: 'fixed' or 'knee' (run once for each)
settings.peak_width_limits = [1, 8];
settings.max_n_peaks       = 6;
settings.min_peak_height   = 0.05;
settings.peak_threshold    = 2.0;
settings.verbose           = false;

results = table();

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    EEG = pop_loadset('filename', setFile);

    data = double(EEG.data);
    if ndims(data) == 3
        data = reshape(data, size(data,1), []);
    end
    fs = EEG.srate;
    win = round(2.0 * fs);
    ov  = round(win * 0.5);
    [pxx, f] = pwelch(data', hann(win), ov, win, fs);
    psd = mean(pxx, 2);

    sel = f >= freq_range(1) & f <= freq_range(2);
    fx  = f(sel);  py = psd(sel);

    fr = fooof(f, psd, freq_range, settings, false);

    ap = fr.aperiodic_params;
    if strcmpi(settings.aperiodic_mode, 'knee')
        ap_curve = ap(1) - log10(ap(2) + fx.^ap(3));
    else
        ap_curve = ap(1) - ap(2) .* log10(fx);
    end
    residual = log10(py) - ap_curve;

    bIdx = fx >= betaBand(1) & fx <= betaBand(2);
    bf   = fx(bIdx);
    bres = residual(bIdx);
    bpow = py(bIdx);

    [maxRes, idxMax] = max(bres);
    ibf         = bf(idxMax);
    ampResidual = maxRes;
    ampRawPower = bpow(idxMax);
    isEdge = (ibf <= betaBand(1)+0.5) || (ibf >= betaBand(2)-0.5);

    results = [results; table({subject}, ibf, ampResidual, ampRawPower, isEdge, fr.r_squared, ...
        'VariableNames', {'subject','IBF_Hz','amp_residual','amp_rawPower','nearEdge','r2'})]; %#ok<AGROW>

    fprintf('%s: IBF=%.2f Hz  amp(resid)=%.3f  amp(raw)=%.4f  nearEdge=%d  r2=%.4f\n', ...
        subject, ibf, ampResidual, ampRawPower, isEdge, fr.r_squared);
end

disp(results)

outFile = fullfile(rerunDir, sprintf('beta_features_full42_%s.csv', lower(settings.aperiodic_mode)));   % [path]
writetable(results, outFile);
fprintf('Saved: %s\n', outFile);
