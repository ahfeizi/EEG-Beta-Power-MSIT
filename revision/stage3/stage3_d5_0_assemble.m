function stage3_d5_0_assemble(params, outFile)
%STAGE3_D5_0_ASSEMBLE  D5-0 assembly (S3a-D5-0 rules R1-R3) from the canonical outputs of a verified
%   A/B batch, as a runner job function (S3a-D5-0-asm). Job function: stage3_d5_0_assemble(params, outFile).
%   params: sourceBatchDir (e.g. <EegOutRoot>\stage3_runs\d5_0_1), blockTable (common).
%   Reads ONLY the canonical out.mat of every recording of the source batch, each checked against
%   the SHA-256 recorded in its state file before it is loaded. The source batch must be DONE with
%   every recording verified.
%   The arithmetic is copied unchanged from stage3_d5_0_line_noise.m lines 116-150 (tables) and
%   152-188 (anti-aliasing gain, R1-R3), with three changes that do not alter any value:
%     - R1 is labelled report-only (S3a-D5-opt, open point (i), decision (i-1));
%     - the R2 ranking is reported in full, and the D14 replacement step is reported as pending
%       (the D14 test subjects are not chosen yet);
%     - lines go into the variable runInfo (no timestamp: A and B must be identical); the export
%       step (stage3_d5_0_export) writes the CSVs and run_info.txt.
%   Added (derived only from the same tables): rulesByRecording, one row per recording.
%   Outcome-blind: only the f0 +/- 3 Hz grid of the per-recording outputs is read (asserted).
%   Equivalence with the script's assembly on synthetic data: test_stage3_d5_0_assemble.m.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
srcDir = char(params.sourceBatchDir);
batch = jsondecode(fileread(fullfile(srcDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');

% ---- recordings: block-table order, as the script ----------------------------------------------
B = readtable(char(params.blockTable), 'TextType', 'string');
recs = unique(B.subject + "_" + B.task, 'stable');
stFiles = dir(fullfile(srcDir, 'state', '*.json'));
assert(numel(stFiles) == numel(recs), 'source batch has %d state files, block table %d recordings', numel(stFiles), numel(recs));

% ---- canonical outputs, hash-checked, loaded once -----------------------------------------------
srcId = strings(numel(recs), 1); srcPath = strings(numel(recs), 1); srcSha = strings(numel(recs), 1);
srcReplica = strings(numel(recs), 1); srcStatus = strings(numel(recs), 1); srcFlags = strings(numel(recs), 1);
L = cell(numel(recs), 1);
for r = 1:numel(recs)
    stf = fullfile(srcDir, 'state', char(recs(r) + ".json"));
    assert(exist(stf, 'file') == 2, 'no state file for %s', recs(r));
    st = jsondecode(fileread(stf));
    assert(strcmp(st.status, 'verified'), '%s: status %s (only verified recordings are assembled)', recs(r), st.status);
    p = char(st.canonical.path);
    assert(strcmp(sha256File(p), char(st.canonical.sha256)), '%s: canonical output does not match its recorded SHA-256', recs(r));
    L{r} = load(p);
    srcId(r) = recs(r); srcPath(r) = string(p); srcSha(r) = string(st.canonical.sha256);
    srcReplica(r) = string(st.canonical.replica); srcStatus(r) = string(st.status);
    srcFlags(r) = strjoin(string(st.flags), ';');
end
sources = table(srcId, srcStatus, srcReplica, srcPath, srcSha, srcFlags, ...
    'VariableNames', {'recording', 'status', 'canonical_replica', 'path', 'sha256', 'flags'});

% ---- grid and constants, as the script (lines 26-36) --------------------------------------------
F = L{1}.F; d = L{1}.d; f0s = L{1}.f0s;
for r = 2:numel(recs), assert(isequal(L{r}.F, F) && isequal(L{r}.d, d) && isequal(L{r}.f0s, f0s), 'grid differs'); end
assert(isequal(f0s, [50 100 150 200]) && isequal(d, (-30:30) / 10), 'unexpected grid');
assert(~any(F >= 13 & F <= 30) && ~any(F >= 55 & F <= 95), 'outcome-blind: forbidden band in grid');
flank = abs(d) >= 1.5 - 1e-9 & abs(d) <= 3 + 1e-9;
pkwin = find(abs(d) <= 0.5 + 1e-9);
chunkLen = 10;
provisionalLabels = ["sub-13", "sub-41", "sub-42"];       % S3a-D5-0-exc
detDb = 6;

% ---- assemble: stage3_d5_0_line_noise.m lines 116-150, unchanged -------------------------------
rowsC = {}; rowsR = {};
for r = 1:numel(recs)
    parts = split(recs(r), "_"); s = parts(1); task = parts(2);
    R = L{r}.res; nCh = numel(R.label);
    [excA, fpkA] = stage3_d5_0_linepeaks(R.avgP, F, d, f0s, flank, pkwin);   % chunk-averaged PSD
    kept = ~ismember(R.label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
    prov = double(ismember(s, provisionalLabels));          % S3a-D5-0-exc flag
    for j = 1:4
        e = squeeze(R.exc(:, j, :)); fp = squeeze(R.fpk(:, j, :)); a = squeeze(R.amp(:, j, :));
        det = e >= detDb;
        fpD = fp; fpD(~det) = NaN;
        nDet = sum(det, 2);
        fsd = std(fpD, 0, 2, 'omitnan'); frg = max(fpD, [], 2) - min(fpD, [], 2);
        fsd(nDet < 2) = NaN; frg(nDet < 2) = NaN;
        off = max(abs(fpD - f0s(j)), [], 2);                 % NaN if no detected chunk
        cv = std(a, 0, 2) ./ mean(a, 2);
        T = table(repmat(s, nCh, 1), repmat(task, nCh, 1), R.label, double(kept), repmat(f0s(j), nCh, 1), ...
            repmat(size(e, 2), nCh, 1), nDet, excA(:, j), fpkA(:, j), median(e, 2), max(e, [], 2), cv, ...
            fsd, frg, off, repmat(prov, nCh, 1), 'VariableNames', {'subject', 'task', 'channel', 'kept', 'f0', 'n_chunks', ...
            'n_chunks_det6db', 'excess_db', 'peak_freq_hz', 'chunk_excess_median_db', 'chunk_excess_max_db', ...
            'amp_cv', 'freq_sd_det_hz', 'freq_range_det_hz', 'max_abs_offset_det_hz', 'labels_provisional'});
        rowsC{end+1} = T; %#ok<AGROW>
        k = kept;
        rowsR{end+1} = table(s, task, f0s(j), sum(k), median(excA(k, j)), max(excA(k, j)), ...
            sum(excA(k, j) >= 3), median(cv(k), 'omitnan'), max(frg(k)), max(off(k)), ...
            max(excA(~k, j)), prov, 'VariableNames', {'subject', 'task', 'f0', 'n_kept_channels', ...
            'excess_db_median_kept', 'excess_db_max_kept', 'n_kept_excess_ge3db', 'amp_cv_median_kept', ...
            'freq_range_det_max_kept_hz', 'max_abs_offset_det_kept_hz', 'excess_db_max_tp9_tp10', 'labels_provisional'}); %#ok<AGROW>
    end
end
TC = vertcat(rowsC{:}); TR = vertcat(rowsR{:});

% ---- rules R1-R3: script lines 152-188 (values unchanged; see header for the reporting changes) --
logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md');
runInfo = strings(0, 1);
add = @(varargin) sprintf(varargin{:});
ids = ["S3a-D5-0", "S3a-D5-opt", "S3a-INF-1"];            % S3a-D5-0-amend1: the three hashes of run_info.txt
for id = ids
    runInfo(end+1, 1) = add('SHA-256 of the %s log entry as read by this script: %s', id, stage3_log_entry(logFile, char(id)));
end
for id = ["S3a-D5-0-amend1", "S3a-D5-0-exc", "S3a-D5-0-asm", "S3a-D5-0-amend2"]   % additionally recorded (not required by amend1)
    runInfo(end+1, 1) = add('SHA-256 of the %s log entry (additional): %s', id, stage3_log_entry(logFile, char(id)));
end
runInfo(end+1, 1) = add('Recordings: %d; chunk %d s; grid f0 +/- 3 Hz in 0.1 Hz steps', numel(recs), chunkLen);
[p, q] = rat(S.fsOut / S.fsRaw, 1e-12);
m = pop_firwsord('kaiser', 2, 0.2 / max([p q]), 0.002);
bAA = firws(m, 0.9 / max([p q]), windows('kaiser', m + 1, 5));
fg = [147 150 153 197 200 203];
aaGainDb = 20 * log10(abs(freqz(bAA, 1, fg, p * S.fsRaw)));
runInfo(end+1, 1) = add('Anti-aliasing gain (pop_resample design, dB): %s', ...
    strjoin(arrayfun(@(f, v) sprintf('%g Hz %.3f', f, v), fg, aaGainDb, 'uni', 0), ', '));
r1max = nan(1, 4);
for j = 1:4
    k = TC.kept == 1 & TC.f0 == f0s(j);
    mx = max(TC.excess_db(k));
    r1max(j) = mx;
    runInfo(end+1, 1) = add('R1 %3d Hz: max excess over all kept channels x recordings = %.2f dB -> %s (report-only, S3a-D5-opt (i-1))', ...
        f0s(j), mx, ternary(mx < 3, 'ABSENT', 'present'));
end
sev = groupsummary(TR, {'subject', 'task'}, 'max', 'excess_db_median_kept');
sev = sortrows(sev, 'max_excess_db_median_kept', 'descend');
runInfo(end+1, 1) = "R2 severity S = max over f0 of median kept-channel excess; full ranking:";
for i = 1:height(sev)
    runInfo(end+1, 1) = add('  %2d. %s %s  S = %.2f dB', i, sev.subject(i), sev.task(i), sev.max_excess_db_median_kept(i)); %#ok<AGROW>
end
nW = min(3, height(sev));
runInfo(end+1, 1) = add('R2 worst set before the D14 replacement step: ranks 1-%d (%s). The step "if a worst recording belongs to a D14 test subject, the next one in rank is taken" is PENDING: the D14 test subjects are not chosen.', ...
    nW, strjoin(sev.subject(1:nW) + " " + sev.task(1:nW), ', '));
off = TC.max_abs_offset_det_hz(TC.kept == 1);
r3max = max(off);
runInfo(end+1, 1) = add('R3 largest |peak - f0| in any detected chunk (kept channels): %.3f Hz -> %s', r3max, ...
    ternary(r3max > 0.5, 'RE-EXAMINE notch width', 'within 0.5 Hz'));

% ---- per-recording rule outcomes (derived from TR only) -----------------------------------------
[g, rs, rt] = findgroups(TR.subject, TR.task);
nRec = max(g);
rulesByRecording = table(rs, rt, 'VariableNames', {'subject', 'task'});
rulesByRecording.severity_S_db = splitapply(@max, TR.excess_db_median_kept, g);
[~, ord] = sort(rulesByRecording.severity_S_db, 'descend');
rk = zeros(nRec, 1); rk(ord) = 1:nRec;
rulesByRecording.r2_rank = rk;
for j = 1:4
    sel = TR.f0 == f0s(j);
    v = nan(nRec, 1); v(g(sel)) = TR.excess_db_max_kept(sel);
    rulesByRecording.(sprintf('r1_max_kept_excess_db_%d', f0s(j))) = v;
    n3 = nan(nRec, 1); n3(g(sel)) = TR.n_kept_excess_ge3db(sel);
    rulesByRecording.(sprintf('r1_n_kept_ge3db_%d', f0s(j))) = n3;
end
rulesByRecording.r3_max_abs_offset_det_kept_hz = splitapply(@(x) max(x), TR.max_abs_offset_det_kept_hz, g);
rulesByRecording.r3_gt_0p5hz = double(rulesByRecording.r3_max_abs_offset_det_kept_hz > 0.5);
rulesByRecording.labels_provisional = splitapply(@max, TR.labels_provisional, g);
[~, io] = ismember(rulesByRecording.subject + "_" + rulesByRecording.task, recs);
rulesByRecording = sortrows(addvars(rulesByRecording, io, 'NewVariableNames', 'rec_order'), 'rec_order');
rulesByRecording.rec_order = [];

rules = struct('r1_max_excess_db', r1max, 'r1_absent', r1max < 3, 'r1_report_only', true, ...
    'r2_ranking', sev, 'r2_d14_step_pending', true, 'r3_max_abs_offset_hz', r3max, 'r3_reexamine', r3max > 0.5);
entryHashes = runInfo(1:7);
sourceBatch = struct('dir', string(srcDir), 'batchJsonSha256', string(sha256File(fullfile(srcDir, 'batch.json'))));
save(outFile, 'TC', 'TR', 'rulesByRecording', 'rules', 'runInfo', 'entryHashes', 'aaGainDb', 'sources', 'sourceBatch');
fprintf('%s\n', runInfo{:});
end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
