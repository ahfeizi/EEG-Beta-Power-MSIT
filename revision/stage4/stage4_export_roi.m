function T = stage4_export_roi(subjects)
%STAGE4_EXPORT_ROI  Stage 4, §3.1.1 of docs/zenodo_preregistration_stage4.md: rebuild + rest D12 + ROI export.
%   T = stage4_export_roi()            all S1 bundles in <eegOutRoot>/stage3_part2/ (39 expected)
%   T = stage4_export_roi(subjects)    only these subjects, e.g. {'sub-01'}
%   Per subject:
%     1. EEG = stage3_p2_rebuild(P2, 'rest', 'beta', false)   (primary version; Other kept; S3a-close)
%     2. 2 s non-overlapping pseudo-epochs from the first sample of each rest block (rest_bK_start), up to
%        the block's last sample (rest_bK_end); the incomplete final segment of a block is "outside"
%     3. D12 with stage3_d12_trials: rejected if peak-to-peak > 150 uV on Fz, Cz or C4; an epoch crossing a
%        boundary or the data edge is "outside"; excluded if kept / (total - outside) < 0.5
%     4. the kept epochs of the 7 ROI channels (§3.3) are saved as contiguous runs of kept epochs, never
%        across a rejected epoch or a block boundary (§3.2), to <eegOutRoot>/stage4/roi/<sub>_rest_roi.mat
%        (-v7, readable by scipy.io.loadmat); data single, uV, channels x samples
%   Writes a manifest of the counts (manifest_roi_<timestamp>.tsv) next to the files and returns it as T.
%   OUTCOME-BLIND: no spectrum, power or other frequency-domain quantity is computed here.
%   Never overwrites: stops if an output file already exists.

here = fileparts(mfilename('fullpath'));
repo = fileparts(fileparts(here));
addpath(here, repo, fullfile(repo, 'revision', 'stage3'));   % get_paths.m, stage3_p2_rebuild, stage3_d12_trials
if ~exist('pop_interp', 'file'), eeglab('nogui'); end

roiLabels = {'C3', 'Cz', 'C4', 'FC1', 'FC2', 'CP1', 'CP2'};          % §3.3
d12Chans = {'Fz', 'Cz', 'C4'}; d12ThrUV = 150;                       % §3.1.1
epochSec = 2; minFracKept = 0.5;                                     % §3.1.1
version = 'beta'; rejectOther = false;                               % S3a-close

P = get_paths();
inDir = fullfile(P.eegOutRoot, 'stage3_part2');
outDir = fullfile(P.eegOutRoot, 'stage4', 'roi');
if ~exist(outDir, 'dir'), mkdir(outDir); end
f = dir(fullfile(inDir, 'sub-*_s3p2.mat'));
allSubs = erase({f.name}, '_s3p2.mat');
if nargin < 1 || isempty(subjects)
    subjects = allSubs;
    assert(numel(subjects) == 39, 'stage4:roi', '%d S1 bundles found, 39 expected', numel(subjects));
end
subjects = cellstr(subjects);
assert(all(ismember(subjects, allSubs)), 'stage4:roi', 'subject without an S1 bundle');

rows = cell(numel(subjects), 9);
for s = 1:numel(subjects)
    subject = subjects{s};
    outFile = fullfile(outDir, [subject '_rest_roi.mat']);
    assert(~exist(outFile, 'file'), 'stage4:roi', 'output exists, not overwritten: %s', outFile);
    S = load(fullfile(inDir, [subject '_s3p2.mat']), 'P2');
    EEG = stage3_p2_rebuild(S.P2, 'rest', version, rejectOther);
    clear S
    fs = EEG.srate;
    L = round(epochSec * fs);                                        % samples per pseudo-epoch
    assert(abs(L - epochSec * fs) < 1e-9, 'stage4:roi', 'epoch is not a whole number of samples');

    % block edges: <label>_start = first sample, <label>_end = last sample of the block (stage3_p1_compute_one)
    typ = string({EEG.event.type}); lat = [EEG.event.latency];
    bs = sort(lat(startsWith(typ, "rest_b") & endsWith(typ, "_start")));
    be = sort(lat(startsWith(typ, "rest_b") & endsWith(typ, "_end")));
    assert(~isempty(bs) && numel(bs) == numel(be) && all(be > bs) && all(bs(2:end) > be(1:end-1)), ...
        'stage4:roi', '%s: rest block markers', subject);
    on = []; blk = []; incomplete = [];
    for k = 1:numel(bs)
        o = bs(k):L:be(k);                                           % onsets every 2 s within block k
        on = [on, o]; blk = [blk, k * ones(size(o))]; incomplete = [incomplete, o + L - 1 > be(k)]; %#ok<AGROW>
    end
    incomplete = logical(incomplete);

    % D12 with the tested Stage-3 helper: one marker event per pseudo-epoch, appended in onset order
    E = EEG; n0 = numel(E.event);
    for k = 1:numel(on), E.event(n0 + k).type = 's4_pe'; E.event(n0 + k).latency = on(k); end
    [keep, R] = stage3_d12_trials(E, 's4_pe', [0 epochSec], d12Chans, d12ThrUV);
    clear E
    % the only epochs allowed to be outside are the incomplete final segments of the blocks
    assert(~any(keep & incomplete) && R.n_outside == sum(incomplete), 'stage4:roi', '%s: outside epochs', subject);
    excludedD12 = R.frac_kept < minFracKept;

    % contiguous runs of kept epochs, within each block
    [ok, ic] = ismember(roiLabels, {EEG.chanlocs.labels});
    assert(all(ok), 'stage4:roi', '%s: ROI channel missing', subject);
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
        assert(sum(runLenEpochs) == R.n_kept, 'stage4:roi', '%s: run lengths', subject);
    end
    nPseudoTotal = R.n_trials; nKept = R.n_kept; nOutside = R.n_outside;
    nRejected = R.n_rejected; fracKept = R.frac_kept;
    save(outFile, '-v7', 'subject', 'fs', 'roiLabels', 'runs', 'runLenEpochs', 'runBlock', 'nPseudoTotal', ...
        'nKept', 'nOutside', 'nRejected', 'fracKept', 'excludedD12', 'd12Chans', 'd12ThrUV', 'epochSec', ...
        'version', 'rejectOther');
    rl = sprintf('%d;', runLenEpochs); rl = rl(1:end - 1);
    rows(s, :) = {subject, fs, nPseudoTotal, nKept, nOutside, nRejected, fracKept, excludedD12, rl};
    fprintf('%s  total %d  kept %d  outside %d  rejected %d  excluded %d  runs %d\n', subject, nPseudoTotal, ...
        nKept, nOutside, nRejected, excludedD12, numel(runs));
end
T = cell2table(rows, 'VariableNames', {'subject', 'fs', 'n_pseudoepochs_total', 'n_pseudoepochs_kept', ...
    'n_outside', 'n_rejected', 'frac_kept', 'excluded_D12', 'run_lengths_epochs'});
stamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
writetable(T, fullfile(outDir, ['manifest_roi_' stamp '.tsv']), 'FileType', 'text', 'Delimiter', '\t');
end
