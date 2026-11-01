function T = stage5_export_roi_task(subjects)
%STAGE5_EXPORT_ROI_TASK  Stage 5 Track B: rebuild + task D12 + ROI export of the MSIT+ task blocks.
%   T = stage5_export_roi_task()            all S1 bundles in <eegOutRoot>/stage3_part2/ (39 expected)
%   T = stage5_export_roi_task(subjects)    only these subjects, e.g. {'sub-01'}
%
%   Track B asks whether a discrete beta peak is present during the task period overall
%   (condition-collapsed). It therefore mirrors the Stage-4 rest architecture as closely as the data
%   allow: the same 7-channel ROI, the same 2 s non-overlapping pseudo-epochs, the same D12 rule, the
%   same contiguous-run export format. It is NOT trial-locked; per-condition peak detection is out of
%   scope (S5-trackB-scope in docs/decision_log.md §10).
%   Per subject:
%     1. EEG = stage3_p2_rebuild(P2, 'msit', 'beta', false)   (primary version; Other kept; S3a-close)
%     2. 2 s non-overlapping pseudo-epochs from the first sample of each task block (task_bK_start), up
%        to the block's last sample (task_bK_end); the incomplete final segment of a block is "outside"
%     3. D12 with stage3_d12_trials: rejected if peak-to-peak > 150 uV on Fz, Cz or C4; an epoch crossing
%        a boundary or the data edge is "outside"; excluded if kept / (total - outside) < 0.5
%     4. the kept epochs of the 7 ROI channels are saved as contiguous runs of kept epochs, never across
%        a rejected epoch or a block boundary, to <eegOutRoot>/stage5/roi/<sub>_msit_roi.mat
%        (-v7, readable by scipy.io.loadmat); data single, uV, channels x samples
%   Writes a manifest of the counts (manifest_roi_task_<timestamp>.tsv) next to the files, returns it as T.
%
%   Differences from revision/stage4/stage4_export_roi.m (which is frozen at tag S4-prereg-frozen and
%   deposited on Zenodo, DOI 10.5281/zenodo.23843194, and is therefore NOT edited):
%     - cond 'msit' instead of 'rest'; block markers task_bK_start / task_bK_end;
%     - task blocks are many (12 for 36 subjects, 9 for sub-21, 13 for sub-29, 14 for sub-23) and short
%       (~78-92 s), so far more pseudo-epochs and far more block tails than rest;
%     - the leading-boundary fix of §5 is applied here as well: the same two boundary events at latency
%       0.5 and 1.0 are present in every one of the 39 msit bundles (confirmed by reading
%       P2.msit.event directly), so without it pseudo-epoch 1 of block 1 would count as "outside".
%   Everything else (ROI, epoch length, D12 channels/threshold, 50% rule, run export) is unchanged, so
%   rest and task PSDs are estimated by the identical shared Python pipeline (stage4_core.py).
%
%   OUTCOME-BLIND: no spectrum, power or other frequency-domain quantity is computed here.
%   Never overwrites: stops if an output file already exists.

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, repo, fullfile(repo, 'revision', 'stage3'));   % get_paths.m, stage3_p2_rebuild, stage3_d12_trials
if ~exist('pop_interp', 'file'), eeglab('nogui'); end

roiLabels = {'C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2'};          % same ROI as Stage 4 (§3.3)
d12Chans = {'Fz', 'Cz', 'C4'}; d12ThrUV = 150;                       % project-wide D12 artifact rule
epochSec = 2; minFracKept = 0.5;                                     % same as Stage 4 rest
version = 'beta'; rejectOther = false;                               % S3a-close
cond = 'msit';

P = get_paths();
inDir = fullfile(P.eegOutRoot, 'stage3_part2');
outDir = fullfile(P.eegOutRoot, 'stage5', 'roi');
if ~exist(outDir, 'dir'), mkdir(outDir); end
f = dir(fullfile(inDir, 'sub-*_s3p2.mat'));
allSubs = erase({f.name}, '_s3p2.mat');
if nargin < 1 || isempty(subjects)
    subjects = allSubs;
    assert(numel(subjects) == 39, 'stage5:roi', '%d S1 bundles found, 39 expected', numel(subjects));
end
subjects = cellstr(subjects);
assert(all(ismember(subjects, allSubs)), 'stage5:roi', 'subject without an S1 bundle');

rows = cell(numel(subjects), 10);
for s = 1:numel(subjects)
    subject = subjects{s};
    outFile = fullfile(outDir, [subject '_msit_roi.mat']);
    assert(~exist(outFile, 'file'), 'stage5:roi', 'output exists, not overwritten: %s', outFile);
    S = load(fullfile(inDir, [subject '_s3p2.mat']), 'P2');
    EEG = stage3_p2_rebuild(S.P2, cond, version, rejectOther);
    clear S
    fs = EEG.srate;
    L = round(epochSec * fs);                                        % samples per pseudo-epoch
    assert(abs(L - epochSec * fs) < 1e-9, 'stage5:roi', 'epoch is not a whole number of samples');

    % block edges: <label>_start = first sample, <label>_end = last sample of the block
    % (stage3_p1_compute_one; task blocks are S3a-D3e: first stimulus - 1 s .. last event + 1.5 s)
    typ = string({EEG.event.type}); lat = [EEG.event.latency];
    bs = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_start")));
    be = sort(lat(startsWith(typ, "task_b") & endsWith(typ, "_end")));
    assert(~isempty(bs) && numel(bs) == numel(be) && all(be > bs) && all(bs(2:end) > be(1:end-1)), ...
        'stage5:roi', '%s: task block markers', subject);
    on = []; blk = []; incomplete = [];
    for k = 1:numel(bs)
        o = bs(k):L:be(k);                                           % onsets every 2 s within block k
        on = [on, o]; blk = [blk, k * ones(size(o))]; incomplete = [incomplete, o + L - 1 > be(k)]; %#ok<AGROW>
    end
    incomplete = logical(incomplete);

    % D12 with the tested Stage-3 helper: one marker event per pseudo-epoch, appended in onset order.
    % §5 boundary fix, re-applied here for the task path: a boundary at latency <= 1 lies at or before
    % the first sample and separates no data (artefact of the Stage-3 cropping). It is removed from the
    % helper's input copy only; the helper and its assert are unchanged. Without this, pseudo-epoch 1 of
    % block 1 (whose onset is the first sample) would be reported "outside" in every subject.
    E = EEG;
    E.event(strcmp({E.event.type}, 'boundary') & [E.event.latency] <= 1) = [];
    n0 = numel(E.event);
    for k = 1:numel(on), E.event(n0 + k).type = 's5_pe'; E.event(n0 + k).latency = on(k); end
    [keep, R] = stage3_d12_trials(E, 's5_pe', [0 epochSec], d12Chans, d12ThrUV);
    clear E
    % the only epochs allowed to be outside are the incomplete final segments of the blocks
    assert(~any(keep & incomplete) && R.n_outside == sum(incomplete), 'stage5:roi', '%s: outside epochs', subject);
    excludedD12 = R.frac_kept < minFracKept;

    % contiguous runs of kept epochs, within each block
    [ok, ic] = ismember(roiLabels, {EEG.chanlocs.labels});
    assert(all(ok), 'stage5:roi', '%s: ROI channel missing', subject);
    runs = {}; runLenEpochs = []; runBlock = [];
    if ~excludedD12
        for k = 1:numel(bs)
            kk = keep & blk == k;
            d = diff([0, kk, 0]); r0 = find(d == 1); r1 = find(d == -1) - 1;   % first/last epoch of each run
            for j = 1:numel(r0)
                a = on(r0(j)); b = on(r1(j)) + L - 1;
                runs{end + 1} = single(EEG.data(ic, a:b));                     %#ok<AGROW>
                runLenEpochs(end + 1) = r1(j) - r0(j) + 1;                     %#ok<AGROW>
                runBlock(end + 1) = k;                                         %#ok<AGROW>
            end
        end
        assert(sum(runLenEpochs) == R.n_kept, 'stage5:roi', '%s: run lengths', subject);
    end
    nBlocks = numel(bs);
    nPseudoTotal = R.n_trials; nKept = R.n_kept; nOutside = R.n_outside;
    nRejected = R.n_rejected; fracKept = R.frac_kept;
    save(outFile, '-v7', 'subject', 'cond', 'fs', 'roiLabels', 'runs', 'runLenEpochs', 'runBlock', ...
        'nBlocks', 'nPseudoTotal', 'nKept', 'nOutside', 'nRejected', 'fracKept', 'excludedD12', ...
        'd12Chans', 'd12ThrUV', 'epochSec', 'version', 'rejectOther');
    rl = sprintf('%d;', runLenEpochs); rl = rl(1:end - 1);
    rows(s, :) = {subject, fs, nBlocks, nPseudoTotal, nKept, nOutside, nRejected, fracKept, excludedD12, rl};
    fprintf('%s  blocks %d  total %d  kept %d  outside %d  rejected %d  excluded %d  runs %d\n', subject, ...
        nBlocks, nPseudoTotal, nKept, nOutside, nRejected, excludedD12, numel(runs));
end
T = cell2table(rows, 'VariableNames', {'subject', 'fs', 'n_blocks', 'n_pseudoepochs_total', ...
    'n_pseudoepochs_kept', 'n_outside', 'n_rejected', 'frac_kept', 'excluded_D12', 'run_lengths_epochs'});
stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
writetable(T, fullfile(outDir, ['manifest_roi_task_' stamp '.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
