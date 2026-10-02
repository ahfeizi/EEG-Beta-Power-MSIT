%% Stage 0 / decision S0-3: response-to-next-stimulus interval (RSI) in MSIT+ -- descriptive only
% Read-only input: raw *_task-msit_events.tsv (small text files). No EEG is loaded.
% For every stimulus: how long before its onset was the most recent button press?
% This tells us where the pre-stimulus window (-0.2..0 s) sits relative to the previous
% movement (post-movement beta rebound, audit item #6). No inferential statistics.
%
% Definitions (fixed in docs/decision_log.md, entry S0-3):
%   RSI              = stimulus onset - onset of the most recent preceding response (s)
%   firstInMiniBlock = a block marker (S 10/S 11/S 12) lies between the previous stimulus
%                      and this one, or the stimulus is the first of the run
%   prevTrialResp    = the previous stimulus (same mini-block) received >= 1 response before
%                      this stimulus; if false, the "most recent response" belongs to an older trial
%   RT               = first response after this stimulus and before the next stimulus/marker
%   SOA              = onset - previous stimulus onset (NaN for first-in-mini-block)
%   insideWindow     = RSI <= 0.2 s, i.e. the press itself falls inside the -0.2..0 s window
%
% Outputs (new files, <outRoot>/stage0/):
%   rsi_per_trial.csv, rsi_summary_per_subject.csv, rsi_summary_pooled.txt

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % revision/stage0/<this> -> repository root
addpath(repoRoot);                                                  % for get_paths.m
P = get_paths();                                                    % local paths: config_local.m or repo defaults
rawRoot = P.bidsRoot;                                               % raw dataset, read-only
outDir  = fullfile(P.outRoot, 'stage0');
if ~exist(outDir, 'dir'), mkdir(outDir); end

subjects  = arrayfun(@(i) sprintf('sub-%02d', i), 1:42, 'uni', 0);
condMap   = containers.Map({'S 5','S 6','S 7','S 8'}, {'F0','FS','00','S0'});   % task-msit_events.json
blockMark = {'S 10','S 11','S 12'};
normType  = @(t) regexprep(strtrim(char(t)), '\s+', ' ');   % 'S  5' -> 'S 5'

perTrial = cell(numel(subjects), 1);
for i = 1:numel(subjects)
    s  = subjects{i};
    ev = readtable(fullfile(rawRoot, s, 'eeg', [s '_task-msit_events.tsv']), ...
                   'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
    typ   = arrayfun(@(t) string(normType(t)), ev.event_type);
    ttype = ev.trial_type;
    onset = ev.onset;
    isStim = ttype == "stimulus";
    isResp = ttype == "response";
    isMark = ismember(typ, string(blockMark));

    stimIdx = find(isStim);
    n = numel(stimIdx);
    [cond, firstInMB, prevResp, rsi, rt, soa, nResp, inside] = deal(strings(n,1), false(n,1), ...
        false(n,1), nan(n,1), nan(n,1), nan(n,1), zeros(n,1), false(n,1));
    for k = 1:n
        j = stimIdx(k);
        cond(k) = condMap(char(typ(j)));

        % first in mini-block = first stimulus of the run, or a block marker (S 10/11/12) lies
        % between the previous stimulus and this one. (Two files contain an 'empty' n/a event
        % before the first stimulus, so "previous non-response event" is not a safe test.)
        if k == 1
            firstInMB(k) = true;
        else
            firstInMB(k) = any(isMark(stimIdx(k-1)+1:j-1));
        end

        % most recent response before this stimulus
        lastR = find(isResp(1:j-1), 1, 'last');
        if ~isempty(lastR)
            rsi(k) = onset(j) - onset(lastR);
            inside(k) = rsi(k) <= 0.2;
        end
        % did the previous stimulus (if within the same mini-block) get a response before this one?
        if ~firstInMB(k)
            pj = stimIdx(k-1);
            prevResp(k) = any(isResp(pj+1:j-1));
            soa(k) = onset(j) - onset(pj);
        end
        % own RT and number of responses until the next stimulus/marker
        nxt = find(isStim(j+1:end) | isMark(j+1:end), 1, 'first');
        if isempty(nxt), stop = numel(onset); else, stop = j + nxt - 1; end
        r = find(isResp(j+1:stop)) + j;
        nResp(k) = numel(r);
        if ~isempty(r), rt(k) = onset(r(1)) - onset(j); end
    end
    perTrial{i} = table(repmat(string(s), n, 1), (1:n)', cond, onset(stimIdx), firstInMB, ...
        prevResp, rsi, inside, rt, nResp, soa, ...
        'VariableNames', {'subject','stimIndex','condition','onset','firstInMiniBlock', ...
        'prevTrialResponded','RSI','respInsideWindow','RT','nResponses','SOA'});
end
T = vertcat(perTrial{:});
writetable(T, fullfile(outDir, 'rsi_per_trial.csv'));

% ---- per-subject descriptive summary --------------------------------------------------
% "Within" trials = not first in mini-block AND the previous trial was answered, so the RSI
% measures the gap after the previous trial's own button press.
edges = [0 0.5 1.0 1.5 Inf];
S = table();
for i = 1:numel(subjects)
    t = T(T.subject == subjects{i}, :);
    w = t(~t.firstInMiniBlock & t.prevTrialResponded, :);
    f = t(t.firstInMiniBlock, :);
    q  = prctile(w.RSI, [25 50 75]);
    pb = histcounts(w.RSI, edges) / height(w);
    S = [S; table(string(subjects{i}), height(t), height(w), height(f), ...
        sum(~t.firstInMiniBlock & ~t.prevTrialResponded), ...
        q(2), q(1), q(3), min(w.RSI), max(w.RSI), ...
        pb(1), pb(2), pb(3), pb(4), sum(w.respInsideWindow), ...
        median(f.RSI, 'omitnan'), median(t.RT, 'omitnan'), sum(isnan(t.RT)), median(w.SOA), ...
        'VariableNames', {'subject','nStim','nWithin','nFirstInMiniBlock','nPrevTrialNoResponse', ...
        'RSI_median','RSI_q25','RSI_q75','RSI_min','RSI_max', ...
        'prop_0_0p5','prop_0p5_1p0','prop_1p0_1p5','prop_gt1p5','nRespInsideWindow', ...
        'RSI_median_firstInMB','RT_median','nNoResponse','SOA_median'})]; %#ok<AGROW>
end
writetable(S, fullfile(outDir, 'rsi_summary_per_subject.csv'));

% ---- pooled descriptive summary --------------------------------------------------------
w  = T(~T.firstInMiniBlock & T.prevTrialResponded, :);
pp = [5 10 25 50 75 90 95];
fid = fopen(fullfile(outDir, 'rsi_summary_pooled.txt'), 'w');
fprintf(fid, 'MSIT+ response-to-next-stimulus interval (RSI), descriptive only (decision S0-3)\n');
fprintf(fid, 'Stimuli total: %d (42 subjects)\n', height(T));
fprintf(fid, 'Within-mini-block stimuli with an answered previous trial ("within"): %d\n', height(w));
fprintf(fid, 'First-in-mini-block stimuli: %d\n', sum(T.firstInMiniBlock));
fprintf(fid, 'Within-mini-block stimuli whose previous trial had no response before them: %d\n', ...
    sum(~T.firstInMiniBlock & ~T.prevTrialResponded));
fprintf(fid, '\nRSI percentiles (s), within trials pooled:\n');
fprintf(fid, '  P%-3d = %.3f\n', [pp; prctile(w.RSI, pp)]);
pb = histcounts(w.RSI, edges);
fprintf(fid, '\nRSI bins, within trials pooled (count, proportion):\n');
lbl = {'0-0.5 s','0.5-1.0 s','1.0-1.5 s','>1.5 s'};
for b = 1:4, fprintf(fid, '  %-10s %6d  %.3f\n', lbl{b}, pb(b), pb(b)/height(w)); end
fprintf(fid, '\nResponses falling inside the -0.2..0 s window (RSI <= 0.2 s), all stimuli: %d\n', sum(T.respInsideWindow));
fprintf(fid, 'Per-subject median RSI (within): min %.3f, median %.3f, max %.3f s\n', ...
    min(S.RSI_median), median(S.RSI_median), max(S.RSI_median));
fprintf(fid, '\nRT percentiles (s), all answered stimuli:\n');
fprintf(fid, '  P%-3d = %.3f\n', [pp; prctile(T.RT(~isnan(T.RT)), pp)]);
fprintf(fid, 'Stimuli without any response before the next stimulus/marker: %d\n', sum(isnan(T.RT)));
fprintf(fid, 'Stimuli with >1 response: %d\n', sum(T.nResponses > 1));
fprintf(fid, '\nSOA percentiles (s), within-mini-block stimuli:\n');
fprintf(fid, '  P%-3d = %.3f\n', [pp; prctile(T.SOA(~isnan(T.SOA)), pp)]);
fclose(fid);
type(fullfile(outDir, 'rsi_summary_pooled.txt'));
