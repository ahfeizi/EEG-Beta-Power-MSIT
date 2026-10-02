%% ---- control-band (55-95 Hz) power for RESTING STATE (fast, files already clean) ----
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
subjects = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
targetChans = {'Fz','Cz','C4'};
controlBand = [55, 95];
epochLen = 2.0; pweOverlap = 50;

[ALLEEG, EEG, CURRENTSET] = eeglab;
results = table();

for i = 1:numel(subjects)
    subject = subjects{i};
    setFile = fullfile(derivRoot, subject, [subject '_rest_clean.set']);
    if ~exist(setFile, 'file'), continue; end
    EEG = pop_loadset('filename', setFile);
    labels = {EEG.chanlocs.labels};
    fs = EEG.srate; win = round(epochLen*fs); ov = round(win*pweOverlap/100);

    for ch = 1:numel(targetChans)
        idx = find(strcmpi(labels, targetChans{ch}));
        if isempty(idx), continue; end
        data = double(squeeze(EEG.data(idx(1),:,:))); data = data(:);
        [pxx, f] = pwelch(data, hann(win), ov, win, fs);
        cIdx = f >= controlBand(1) & f <= controlBand(2);
        controlPow = mean(pxx(cIdx));
        results = [results; table({subject}, {targetChans{ch}}, controlPow, ...
            'VariableNames', {'subject','channel','restControlPower'})]; %#ok<AGROW>
    end
    fprintf('%s done\n', subject);
end
writetable(results, fullfile(rerunDir, 'rest_control_band_power.csv'));   % [path]