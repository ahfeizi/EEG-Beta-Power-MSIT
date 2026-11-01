function T = stage5_export_trials_task(subjects)
%STAGE5_EXPORT_TRIALS_TASK  Stage 5 Track A: rebuild + per-trial D12 + two-window ROI export (§10b, §10g).
%   T = stage5_export_trials_task()            all S1 bundles in <eegOutRoot>/stage3_part2/ (39 expected)
%   T = stage5_export_trials_task(subjects)    only these subjects, e.g. {'sub-01'}
%
%   Track A compares band-average beta power across the four MSIT+ conditions. Each trial contributes two
%   windows relative to its condition-marker onset t (decision log §10b, §10g):
%       baseline  [t - 0.5, t)   s  -> 250 samples at 500 Hz
%       active    [t,       t+1) s  -> 500 samples
%   ERD% = (baseline - active) / baseline * 100 is computed later, in Python, from these time series.
%   Per subject:
%     1. EEG = stage3_p2_rebuild(P2, 'msit', 'beta', false)   (primary version; Other kept; S3a-close)
%     2. condition markers inside the clipped task blocks; the event types in the rebuilt bundle are
%        'S  5' = F0, 'S  6' = FS, 'S  7' = 00, 'S  8' = S0 (two spaces; checked directly in the bundle,
%        and matching task-msit_events.json / Dzianok et al. 2022 Table 3)
%     3. first-in-mini-block flag, Stage-0 (S0-3) definition. 'S 11' ("End of a mini-block") survives the
%        Stage-3 cropping inside blocks; 'S 10'/'S 12' do not, because they lie between blocks -- so the
%        first trial of a block is flagged first-in-mini-block, which is what those markers would have
%        given. Verified against the independent events.tsv count in the Python step.
%     4. D12 twice with stage3_d12_trials, once per window (same Fz/Cz/C4, 150 uV peak-to-peak rule).
%        §10g: a trial is usable only if BOTH windows pass -- ERD% needs both sides, so a trial failing
%        on either side is rejected whole. A window crossing a boundary or the data edge is "outside".
%        The §5/§10c leading-boundary fix is applied on the helper's input copy only.
%     5. per-condition 50 % rule: a subject is excluded if, in any condition, kept/(total - outside) < 0.5
%     6. the 7 ROI channels of the two windows of every usable trial are saved to
%        <eegOutRoot>/stage5/trials/<sub>_msit_trials.mat (-v7, readable by scipy.io.loadmat):
%        base (7 x 250 x nUsable) and act (7 x 500 x nUsable), single, uV. Metadata is written for ALL
%        in-block trials, including rejected ones, so the bookkeeping is complete and checkable.
%   Writes a manifest (manifest_trials_<timestamp>.tsv) next to the files and returns it as T.
%
%   OUTCOME-BLIND: no spectrum, power or other frequency-domain quantity is computed here.
%   Never overwrites: stops if an output file already exists.

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, repo, fullfile(repo, 'revision', 'stage3'));   % get_paths.m, stage3_p2_rebuild, stage3_d12_trials
if ~exist('pop_interp', 'file'), eeglab('nogui'); end

roiLabels = {'C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2'};          % same ROI as Stage 4 (§3.3)
d12Chans = {'Fz', 'Cz', 'C4'}; d12ThrUV = 150;                       % project-wide D12 artifact rule
baseWinSec = [-0.5 0]; actWinSec = [0 1.0];                          % §10g / §10b
minFracKept = 0.5;                                                   % per condition
condTypes = {'S  5', 'S  6', 'S  7', 'S  8'};                        % two spaces, as stored in the bundle
condNames = {'F0', 'FS', '00', 'S0'};
mbEndType = 'S 11';                                                  % "End of a mini-block"
version = 'beta'; rejectOther = false; cond = 'msit';                % S3a-close

P = get_paths();
inDir = fullfile(P.eegOutRoot, 'stage3_part2');
outDir = fullfile(P.eegOutRoot, 'stage5', 'trials');
if ~exist(outDir, 'dir'), mkdir(outDir); end
f = dir(fullfile(inDir, 'sub-*_s3p2.mat'));
allSubs = erase({f.name}, '_s3p2.mat');
if nargin < 1 || isempty(subjects)
    subjects = allSubs;
    assert(numel(subjects) == 39, 'stage5:tr', '%d S1 bundles found, 39 expected', numel(subjects));
end
subjects = cellstr(subjects);
assert(all(ismember(subjects, allSubs)), 'stage5:tr', 'subject without an S1 bundle');

rows = cell(numel(subjects), 11);
for s = 1:numel(subjects)
    subject = subjects{s};
    outFile = fullfile(outDir, [subject '_msit_trials.mat']);
    assert(~exist(outFile, 'file'), 'stage5:tr', 'output exists, not overwritten: %s', outFile);
    S = load(fullfile(inDir, [subject '_s3p2.mat']), 'P2');
    EEG = stage3_p2_rebuild(S.P2, cond, version, rejectOther);
    clear S
    fs = EEG.srate;
    nB = round(diff(baseWinSec) * fs); nA = round(diff(actWinSec) * fs);        % 250 and 500
    assert(nB == 250 && nA == 500, 'stage5:tr', '%s: fs %g gives windows of %d/%d samples', subject, fs, nB, nA);

    typ = string({EEG.event.type}); lat = [EEG.event.latency];
    bs = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_start")));
    be = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_end")));
    assert(~isempty(bs) && numel(bs) == numel(be) && all(be > bs) && all(bs(2:end) > be(1:end-1)), ...
        'stage5:tr', '%s: task block markers', subject);
    mbEnd = sort(lat(typ == string(mbEndType)));

    % condition markers inside the clipped blocks, in time order, block by block
    on = []; ci = []; blk = []; fimb = [];
    for k = 1:numel(bs)
        in = []; ic2 = [];
        for c = 1:numel(condTypes)
            l = lat(typ == string(condTypes{c}) & lat >= bs(k) & lat <= be(k));
            in = [in, l]; ic2 = [ic2, c * ones(size(l))];                       %#ok<AGROW>
        end
        [in, o] = sort(in); ic2 = ic2(o);
        % S0-3: first stimulus of the block, or an 'S 11' between the previous stimulus and this one
        ff = false(size(in));
        for j = 1:numel(in)
            if j == 1
                ff(j) = true;
            else
                ff(j) = any(mbEnd > in(j - 1) & mbEnd < in(j));
            end
        end
        on = [on, in]; ci = [ci, ic2]; blk = [blk, k * ones(size(in))]; fimb = [fimb, ff]; %#ok<AGROW>
    end
    nTr = numel(on);
    assert(nTr > 0, 'stage5:tr', '%s: no in-block condition markers', subject);

    % D12, once per window, with the tested Stage-3 helper. One marker event per trial, appended in the
    % order above, so the helper returns its results in that same order (it preserves EEG.event order).
    % §5/§10c: a boundary at latency <= 1 lies at or before the first sample and separates no data.
    E = EEG;
    E.event(strcmp({E.event.type}, 'boundary') & [E.event.latency] <= 1) = [];
    bnd = [E.event(strcmp({E.event.type}, 'boundary')).latency];
    n0 = numel(E.event);
    for k = 1:nTr, E.event(n0 + k).type = 's5_tr'; E.event(n0 + k).latency = on(k); end
    [keepB, RB] = stage3_d12_trials(E, 's5_tr', baseWinSec, d12Chans, d12ThrUV);
    [keepA, RA] = stage3_d12_trials(E, 's5_tr', actWinSec, d12Chans, d12ThrUV);
    clear E

    % my own "outside" masks, with the helper's rule, asserted against the helper's own counts
    i0B = round(baseWinSec(1) * fs); i1B = round(baseWinSec(2) * fs) - 1;
    i0A = round(actWinSec(1) * fs);  i1A = round(actWinSec(2) * fs) - 1;
    outB = false(1, nTr); outA = false(1, nTr);
    for k = 1:nTr
        t = round(on(k));
        aB = t + i0B; bB = t + i1B; aA = t + i0A; bA = t + i1A;
        outB(k) = aB < 1 || bB > EEG.pnts || any(bnd > aB - 0.5 & bnd < bB + 0.5);
        outA(k) = aA < 1 || bA > EEG.pnts || any(bnd > aA - 0.5 & bnd < bA + 0.5);
    end
    assert(RB.n_outside == sum(outB) && RA.n_outside == sum(outA), 'stage5:tr', ...
        '%s: outside masks disagree with stage3_d12_trials (%d/%d vs %d/%d)', subject, ...
        sum(outB), RB.n_outside, sum(outA), RA.n_outside);
    rejB = ~keepB & ~outB; rejA = ~keepA & ~outA;        % failed the 150 uV test, not outside
    usable = keepB & keepA;                              % §10g: both windows must pass
    outside = outB | outA;

    % per-condition 50 % rule
    fracCond = nan(1, numel(condTypes)); nCond = zeros(1, numel(condTypes)); nKeptCond = zeros(1, numel(condTypes));
    for c = 1:numel(condTypes)
        m = ci == c;
        nCond(c) = sum(m); nKeptCond(c) = sum(usable & m);
        fracCond(c) = nKeptCond(c) / max(1, sum(m & ~outside));
    end
    excludedD12 = any(fracCond < minFracKept);

    % ROI time series of the usable trials
    [ok, ichan] = ismember(roiLabels, {EEG.chanlocs.labels});
    assert(all(ok), 'stage5:tr', '%s: ROI channel missing', subject);
    idx = find(usable);
    base = zeros(numel(roiLabels), nB, numel(idx), 'single');
    act = zeros(numel(roiLabels), nA, numel(idx), 'single');
    if ~excludedD12
        for j = 1:numel(idx)
            t = round(on(idx(j)));
            base(:, :, j) = single(EEG.data(ichan, t + i0B : t + i1B));
            act(:, :, j) = single(EEG.data(ichan, t + i0A : t + i1A));
        end
    else
        base = zeros(numel(roiLabels), nB, 0, 'single'); act = zeros(numel(roiLabels), nA, 0, 'single');
        idx = [];
    end

    % metadata for EVERY in-block trial (usable or not), so the bookkeeping is complete
    trialLatency = on(:); trialCond = ci(:); trialBlock = blk(:);
    trialFirstInMiniblock = double(fimb(:));
    trialOutsideBase = double(outB(:)); trialOutsideAct = double(outA(:));
    trialRejBase = double(rejB(:)); trialRejAct = double(rejA(:));
    trialUsable = double(usable(:)); trialExported = zeros(nTr, 1); trialExported(idx) = 1:numel(idx);

    save(outFile, '-v7', 'subject', 'cond', 'fs', 'roiLabels', 'condNames', 'baseWinSec', 'actWinSec', ...
        'base', 'act', 'trialLatency', 'trialCond', 'trialBlock', 'trialFirstInMiniblock', ...
        'trialOutsideBase', 'trialOutsideAct', 'trialRejBase', 'trialRejAct', 'trialUsable', ...
        'trialExported', 'nCond', 'nKeptCond', 'fracCond', 'excludedD12', 'd12Chans', 'd12ThrUV', ...
        'minFracKept', 'version', 'rejectOther', 'mbEndType');

    fc = sprintf('%.4f;', fracCond); fc = fc(1:end - 1);
    nc = sprintf('%d;', nCond); nc = nc(1:end - 1);
    kc = sprintf('%d;', nKeptCond); kc = kc(1:end - 1);
    rows(s, :) = {subject, fs, numel(bs), nTr, sum(usable), sum(outside), sum(rejB), sum(rejA), ...
        sum(fimb), double(excludedD12), [nc ' | ' kc ' | ' fc]};
    fprintf('%s  blocks %d  trials %d  usable %d  outside %d  rejB %d  rejA %d  firstMB %d  excluded %d\n', ...
        subject, numel(bs), nTr, sum(usable), sum(outside), sum(rejB), sum(rejA), sum(fimb), excludedD12);
end
T = cell2table(rows, 'VariableNames', {'subject', 'fs', 'n_blocks', 'n_trials_in_blocks', 'n_usable', ...
    'n_outside', 'n_rejected_baseline', 'n_rejected_active', 'n_first_in_miniblock', 'excluded_D12', ...
    'per_condition_total_kept_frac'});
stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
writetable(T, fullfile(outDir, ['manifest_trials_' stamp '.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
