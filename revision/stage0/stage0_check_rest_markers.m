%% Stage 0 / decision S0-2: do the rest markers (S12/S10/S11) survive in the existing _rest_clean.set files?
% Read-only. Loads ONLY the small header variables of each .set (event, urevent, srate,
% pnts, trials, xmin, nbchan, chanlocs, icaweights) -- never the EEG data matrix.
% Also records, for audit item #15, the number of ICA components actually stored and
% whether Fz / Cz / C4 were among the interpolated channels (from full_qc_summary.csv).
%
% Outputs (new files only, in <outRoot>/stage0/):
%   rest_markers_in_clean_sets.csv   one row per subject
%   rest_markers_log.txt             full console log

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % revision/stage0/<this> -> repository root
addpath(repoRoot);                                                  % for get_paths.m
P = get_paths();                                                    % local paths: config_local.m or repo defaults
restRoot = P.derivRoot;                                             % v1 derivatives, read-only
rawRoot  = P.bidsRoot;                                              % raw dataset, read-only
outDir   = fullfile(P.outRoot, 'stage0');
if ~exist(outDir, 'dir'), mkdir(outDir); end
diary(fullfile(outDir, 'rest_markers_log.txt')); diary on

subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
markers   = {'S 12', 'S 10', 'S 11'};
keyChans  = {'Fz', 'Cz', 'C4'};
qc        = readtable(fullfile(restRoot, 'full_qc_summary.csv'), 'TextType', 'string');
vars      = {'event','urevent','srate','pnts','trials','xmin','nbchan','chanlocs','icaweights'};

rows = cell(numel(subjects), 1);
for i = 1:numel(subjects)
    s   = subjects{i};
    f   = fullfile(restRoot, s, [s '_rest_clean.set']);
    S   = load(f, '-mat', vars{:});          % -mat: .set is a MAT file; data matrix not requested

    % normalise marker labels: BrainVision writes 'S 12' but sub-20 has 'S  12' (two spaces)
    norm = @(t) regexprep(strtrim(char(string(t))), '\s+', ' ');
    evT  = cellfun(norm, {S.event.type},   'uni', 0);
    urT  = cellfun(norm, {S.urevent.type}, 'uni', 0);
    if i == 1
        fprintf('event fields:   %s\n', strjoin(fieldnames(S.event)', ', '));
        fprintf('urevent fields: %s\n', strjoin(fieldnames(S.urevent)', ', '));
    end
    [uT, ~, k] = unique(evT);  evSummary = strjoin(compose('%s x%d', string(uT(:)), accumarray(k, 1)), '; ');
    [uU, ~, k] = unique(urT);  urSummary = strjoin(compose('%s x%d', string(uU(:)), accumarray(k, 1)), '; ');

    % latencies (s) of the rest markers in urevent (continuous time, after resampling to S.srate)
    urLat = [S.urevent.latency];
    m = ismember(urT, markers);
    urMarkerSeq = strjoin(urT(m), ' | ');
    urMarkerSec = (urLat(m) - 1) / S.srate;

    % same markers in events.tsv (raw, v1.0.3 copy on E:)
    ev  = readtable(fullfile(rawRoot, s, 'eeg', [s '_task-rest_events.tsv']), ...
                    'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    tsvT = cellfun(norm, cellstr(ev.event_type), 'uni', 0);
    mt   = ismember(tsvT, markers);
    tsvSeq = strjoin(tsvT(mt), ' | ');
    tsvSec = ev.onset(mt)';
    sameSeq = strcmp(urMarkerSeq, tsvSeq);
    if sameSeq && ~isempty(tsvSec)
        maxAbsDiffSec = max(abs(urMarkerSec - tsvSec));
    else
        maxAbsDiffSec = NaN;
    end

    % ICA dimensionality and interpolated key channels
    nIC   = size(S.icaweights, 1);
    q     = qc(qc.subject == s, :);
    bad   = split(strtrim(q.badChans(1)))';
    interpKey = strjoin(keyChans(ismember(keyChans, bad)), ' ');

    fprintf('%s | trials=%d | urevent markers: %s | events.tsv: %s | same=%d | maxAbsDiff=%.4f s | nIC=%d nbchan=%d nBadChan=%d | interpolated key chans: %s\n', ...
        s, S.trials, urMarkerSeq, tsvSeq, sameSeq, maxAbsDiffSec, nIC, S.nbchan, q.nBadChan(1), interpKey);

    rows{i} = table(string(s), S.srate, S.trials, string(evSummary), string(urSummary), ...
        string(urMarkerSeq), string(mat2str(round(urMarkerSec, 3))), string(tsvSeq), ...
        string(mat2str(round(tsvSec, 3))), sameSeq, maxAbsDiffSec, nIC, S.nbchan, q.nBadChan(1), ...
        S.nbchan - 1 - q.nBadChan(1), string(interpKey), ...
        'VariableNames', {'subject','srate','nEpochs','eventTypes','ureventTypes', ...
        'ureventMarkerSeq','ureventMarkerSec','tsvMarkerSeq','tsvMarkerSec','sameMarkerSeq', ...
        'maxAbsLatencyDiffSec','nICAcomponents','nbchan','nBadChan','nbchanMinus1MinusBad','interpolatedKeyChans'});
end

T = vertcat(rows{:});
writetable(T, fullfile(outDir, 'rest_markers_in_clean_sets.csv'));
fprintf('\nSaved -> %s\n', fullfile(outDir, 'rest_markers_in_clean_sets.csv'));
diary off
