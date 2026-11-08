function T = stage5_export_control_task(subjects)
%STAGE5_EXPORT_CONTROL_TASK  Stage 5: within-task CONTROL window export (decision log §10m).
%   T = stage5_export_control_task()            all S1 bundles in <eegOutRoot>/stage3_part2/ (39 expected)
%   T = stage5_export_control_task(subjects)    only these subjects, e.g. {'sub-01'}
%
%   `revision_plan.md` Stage 5 and audit items #5 and #6 ask for the pre-stimulus window to be compared
%   against a within-task control window of the SAME length, so rest and task share one spectral
%   estimator and the pre-stimulus elevation can be shown to be specific to the pre-stimulus moment
%   rather than a general within-task level.
%
%   THE WINDOW (§10m, decided by Amirhossein on 2026-11-08 and then fixed empirically by
%   stage5_iti_window_survey.py over all 39 subjects): 500 ms, CENTRED in the inter-mini-block interval,
%   on FIRST-IN-MINI-BLOCK trials that have a previous in-block trial. For a trial at onset t whose
%   previous in-block trial is at p, the free interval between the previous ACTIVE window and this
%   trial's BASELINE window is
%       [p + 1.0 s, t - 0.5 s)
%   and the control window is the central 500 ms of it. The survey measured, over 3960 such pairs:
%   it fits in 3960 of 3960, none falls outside its clipped block, clearance from the previous active
%   window is at least 733 ms, clearance to the upcoming onset at least 1233 ms, and the previous
%   response falls inside the window in 2 trials. A late ITI window was chosen over a post-response one
%   because the post-response interval is the beta-rebound (ERS) period §10g identified as the
%   contaminator of the later-trial baselines.
%
%   Per subject:
%     1. EEG = stage3_p2_rebuild(P2, 'msit', 'beta', false)   (primary version; Other kept; S3a-close)
%     2. condition markers inside the clipped task blocks and the S0-3 first-in-mini-block flag, by the
%        same code path as stage5_export_trials_task.m
%     3. the control window of every ELIGIBLE trial (first-in-mini-block, previous in-block trial present,
%        gap wide enough); a trial whose previous response falls inside its control window is rejected,
%        since that would put a movement artefact and the ERS peak into the control estimate
%     4. D12 with stage3_d12_trials on a marker placed at the window start, window [0, 0.5 s), the same
%        Fz/Cz/C4 150 uV peak-to-peak rule; a window crossing a boundary or the data edge is "outside"
%     5. per-condition 50 % rule over the eligible trials
%     6. the 7 ROI channels of the window of every usable trial go to
%        <eegOutRoot>/stage5/control/<sub>_msit_control.mat (-v7, readable by scipy.io.loadmat):
%        ctrl (7 x 250 x nUsable), single, uV. Metadata is written for ALL eligible trials, including
%        rejected ones, plus the three measured clearances per trial so the Python side can check them
%        against the survey.
%   Writes a manifest (manifest_control_<timestamp>.tsv) next to the files and returns it as T.
%
%   OUTCOME-BLIND: no spectrum, power or other frequency-domain quantity is computed here.
%   Never overwrites, and writes to its own directory, so the §10l trial export is untouched (rule 4).

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, repo, fullfile(repo, 'revision', 'stage3'));
if ~exist('pop_interp', 'file'), eeglab('nogui'); end

roiLabels = {'C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2'};          % same ROI as Stage 4 (§3.3)
d12Chans = {'Fz', 'Cz', 'C4'}; d12ThrUV = 150;                       % project-wide D12 artifact rule
baseWinSec = [-0.5 0]; actWinSec = [0 1.0];                          % the §10g windows, for the geometry
ctrlLenSec = 0.5;                                                    % §10m: same length as the baseline
minFracKept = 0.5;                                                   % per condition
condTypes = {'S  5', 'S  6', 'S  7', 'S  8'};                        % two spaces, as stored in the bundle
condNames = {'F0', 'FS', '00', 'S0'};
respTypes = {'S  1', 'S  2', 'S  3'};                                % checked directly in a real bundle
mbEndType = 'S 11';                                                  % "End of a mini-block"
version = 'beta'; rejectOther = false; cond = 'msit';                % S3a-close

P = get_paths();
inDir = fullfile(P.eegOutRoot, 'stage3_part2');
outDir = fullfile(P.eegOutRoot, 'stage5', 'control');
if ~exist(outDir, 'dir'), mkdir(outDir); end
f = dir(fullfile(inDir, 'sub-*_s3p2.mat'));
allSubs = erase({f.name}, '_s3p2.mat');
if nargin < 1 || isempty(subjects)
    subjects = allSubs;
    assert(numel(subjects) == 39, 'stage5:ct', '%d S1 bundles found, 39 expected', numel(subjects));
end
subjects = cellstr(subjects);
assert(all(ismember(subjects, allSubs)), 'stage5:ct', 'subject without an S1 bundle');

rows = cell(numel(subjects), 11);
for s = 1:numel(subjects)
    subject = subjects{s};
    outFile = fullfile(outDir, [subject '_msit_control.mat']);
    assert(~exist(outFile, 'file'), 'stage5:ct', 'output exists, not overwritten: %s', outFile);
    S = load(fullfile(inDir, [subject '_s3p2.mat']), 'P2');
    EEG = stage3_p2_rebuild(S.P2, cond, version, rejectOther);
    clear S
    fs = EEG.srate;
    nC = round(ctrlLenSec * fs);
    assert(nC == 250, 'stage5:ct', '%s: fs %g gives a %d-sample control window', subject, fs, nC);

    typ = string({EEG.event.type}); lat = [EEG.event.latency];
    bs = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_start")));
    be = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_end")));
    assert(~isempty(bs) && numel(bs) == numel(be) && all(be > bs) && all(bs(2:end) > be(1:end-1)), ...
        'stage5:ct', '%s: task block markers', subject);
    mbEnd = sort(lat(typ == string(mbEndType)));
    resp = sort(lat(ismember(typ, string(respTypes))));
    assert(numel(resp) > 100, 'stage5:ct', '%s: only %d response events', subject, numel(resp));

    % eligible trials: first-in-mini-block, with a previous in-block trial in the same block
    wa = []; ci = []; blk = []; prevOn = []; curOn = [];
    for k = 1:numel(bs)
        in = []; ic2 = [];
        for c = 1:numel(condTypes)
            l = lat(typ == string(condTypes{c}) & lat >= bs(k) & lat <= be(k));
            in = [in, l]; ic2 = [ic2, c * ones(size(l))];                       %#ok<AGROW>
        end
        [in, o] = sort(in); ic2 = ic2(o);
        for j = 2:numel(in)                                     % j = 1 has no previous in-block trial
            if ~any(mbEnd > in(j - 1) & mbEnd < in(j)), continue; end           % not first-in-mini-block
            gapLo = round(in(j - 1)) + round(actWinSec(2) * fs);
            gapHi = round(in(j)) + round(baseWinSec(1) * fs);
            if gapHi - gapLo < nC, continue; end                                % no room (survey: never)
            a = gapLo + floor((gapHi - gapLo - nC) / 2);
            wa = [wa, a]; ci = [ci, ic2(j)]; blk = [blk, k];                    %#ok<AGROW>
            prevOn = [prevOn, round(in(j - 1))]; curOn = [curOn, round(in(j))]; %#ok<AGROW>
        end
    end
    nTr = numel(wa);
    assert(nTr > 0, 'stage5:ct', '%s: no eligible control windows', subject);

    % measured clearances, so the survey's geometry can be checked against the exported data
    clearPrevActive = wa - (prevOn + round(actWinSec(2) * fs));
    clearNextOnset = curOn - (wa + nC - 1) - 1;
    clearPrevResp = nan(1, nTr); respInside = false(1, nTr);
    for k = 1:nTr
        r = resp(resp > prevOn(k) & resp < curOn(k));
        if ~isempty(r)
            clearPrevResp(k) = wa(k) - r(1);
            respInside(k) = r(1) >= wa(k) && r(1) <= wa(k) + nC - 1;
        end
    end

    % D12 on a marker at the window start, window [0, ctrlLenSec)
    E = EEG;
    E.event(strcmp({E.event.type}, 'boundary') & [E.event.latency] <= 1) = [];
    bnd = [E.event(strcmp({E.event.type}, 'boundary')).latency];
    n0 = numel(E.event);
    for k = 1:nTr, E.event(n0 + k).type = 's5_ct'; E.event(n0 + k).latency = wa(k); end
    [keepC, RC] = stage3_d12_trials(E, 's5_ct', [0 ctrlLenSec], d12Chans, d12ThrUV);
    clear E

    outC = false(1, nTr);
    for k = 1:nTr
        a = wa(k); b = a + nC - 1;
        outC(k) = a < 1 || b > EEG.pnts || any(bnd > a - 0.5 & bnd < b + 0.5);
    end
    assert(RC.n_outside == sum(outC), 'stage5:ct', ...
        '%s: outside mask disagrees with stage3_d12_trials (%d vs %d)', subject, sum(outC), RC.n_outside);
    rejC = ~keepC & ~outC;                                   % failed the 150 uV test, not outside
    usable = keepC & ~outC & ~respInside;                    % §10m: a response inside the window rejects

    % per-condition 50 % rule, over the eligible trials
    fracCond = nan(1, numel(condTypes)); nCond = zeros(1, numel(condTypes));
    nKeptCond = zeros(1, numel(condTypes));
    for c = 1:numel(condTypes)
        m = ci == c;
        nCond(c) = sum(m); nKeptCond(c) = sum(usable & m);
        fracCond(c) = nKeptCond(c) / max(1, sum(m & ~outC));
    end
    excludedD12 = any(fracCond < minFracKept);

    [ok, ichan] = ismember(roiLabels, {EEG.chanlocs.labels});
    assert(all(ok), 'stage5:ct', '%s: ROI channel missing', subject);
    idx = find(usable);
    ctrl = zeros(numel(roiLabels), nC, numel(idx), 'single');
    if ~excludedD12
        for j = 1:numel(idx)
            a = wa(idx(j));
            ctrl(:, :, j) = single(EEG.data(ichan, a : a + nC - 1));
        end
    else
        ctrl = zeros(numel(roiLabels), nC, 0, 'single');
        idx = [];
    end

    trialWindowStart = wa(:); trialCond = ci(:); trialBlock = blk(:);
    trialPrevOnset = prevOn(:); trialOnset = curOn(:);
    trialClearPrevActive = clearPrevActive(:); trialClearNextOnset = clearNextOnset(:);
    trialClearPrevResp = clearPrevResp(:); trialRespInside = double(respInside(:));
    trialOutside = double(outC(:)); trialRej = double(rejC(:));
    trialUsable = double(usable(:)); trialExported = zeros(nTr, 1); trialExported(idx) = 1:numel(idx);

    save(outFile, '-v7', 'subject', 'cond', 'fs', 'roiLabels', 'condNames', 'ctrlLenSec', ...
        'baseWinSec', 'actWinSec', 'ctrl', 'trialWindowStart', 'trialCond', 'trialBlock', ...
        'trialPrevOnset', 'trialOnset', 'trialClearPrevActive', 'trialClearNextOnset', ...
        'trialClearPrevResp', 'trialRespInside', 'trialOutside', 'trialRej', 'trialUsable', ...
        'trialExported', 'nCond', 'nKeptCond', 'fracCond', 'excludedD12', 'd12Chans', 'd12ThrUV', ...
        'minFracKept', 'version', 'rejectOther', 'mbEndType', 'respTypes');

    fc = sprintf('%.4f;', fracCond); fc = fc(1:end - 1);
    nc = sprintf('%d;', nCond); nc = nc(1:end - 1);
    kc = sprintf('%d;', nKeptCond); kc = kc(1:end - 1);
    rows(s, :) = {subject, fs, numel(bs), nTr, sum(usable), sum(outC), sum(rejC), sum(respInside), ...
        min(clearPrevActive) / fs * 1000, double(excludedD12), [nc ' | ' kc ' | ' fc]};
    fprintf(['%s  blocks %d  eligible %d  usable %d  outside %d  rej %d  respInside %d  ' ...
        'minClearPrevActive %.0f ms  excluded %d\n'], subject, numel(bs), nTr, sum(usable), sum(outC), ...
        sum(rejC), sum(respInside), min(clearPrevActive) / fs * 1000, excludedD12);
end
T = cell2table(rows, 'VariableNames', {'subject', 'fs', 'n_blocks', 'n_eligible', 'n_usable', ...
    'n_outside', 'n_rejected', 'n_response_inside', 'min_clear_prev_active_ms', 'excluded_D12', ...
    'per_condition_total_kept_frac'});
stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
writetable(T, fullfile(outDir, ['manifest_control_' stamp '.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
