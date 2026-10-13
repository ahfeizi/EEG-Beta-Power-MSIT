function out = stage3_d5a_r3_recheck(sourceBatchDir, outDir)
%STAGE3_D5A_R3_RECHECK  R3 re-examination for fallback (a) (S3a-D5a-R3). No EEG data: reads the
%   verified canonical D5-0 outputs of sourceBatchDir (d5_0_2), each hash-checked against its state file.
%   Cell = one 10 s chunk x kept channel (TP9/TP10 excluded, as in stage3_d5_0_assemble) x f0 whose own
%   chunk excess (res.exc) is >= 10 dB; its offset is |res.fpk - f0| (guarded peak, S3a-D5-0-amend2).
%   Writes to outDir (refuses to overwrite):
%     r3_pooled.csv          per f0: n cells, n recordings with >= 1 cell, median, p95, p99, max |offset|
%     r3_by_recording.csv    per recording x f0: n cells, median, p99, max |offset|
%     r3_harmonic.csv        per k = 2..4: signed offset at k*50 vs at 50 Hz, per recording x chunk
%                            (median over kept channels whose cells qualify at both f0): n pairs,
%                            slope through the origin, Pearson r, median ratio (descriptive)
%     r3_decision.txt        decision rule of S3a-D5a-R3: p99 <= 0.2 Hz at every f0 -> keep the +/-2 Hz notch
%   Percentiles: MATLAB prctile (default method).

assert(~exist(outDir, 'dir'), 'refusing to overwrite %s', outDir);
thr = 10; lim = 0.2; f0s = [50 100 150 200];
batch = jsondecode(fileread(fullfile(sourceBatchDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');
S = dir(fullfile(sourceBatchDir, 'state', '*.json'));
pooled = cell(1, 4); recRows = {}; harm = cell(1, 3);
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(sourceBatchDir, 'state', S(k).name)));
    assert(strcmp(st.status, 'verified'), '%s: status %s', S(k).name, st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', S(k).name);
    L = load(st.canonical.path); R = L.res;
    assert(isequal(L.f0s(:)', f0s), '%s: unexpected f0s', S(k).name);
    id = erase(string(S(k).name), ".json");
    kept = ~ismember(R.label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
    exc = R.exc(kept, :, 1:L.nChunk); fpk = R.fpk(kept, :, 1:L.nChunk);
    so = nan(size(fpk));                                  % signed offset of qualifying cells
    for j = 1:4
        q = squeeze(exc(:, j, :) >= thr);
        o = squeeze(fpk(:, j, :)) - f0s(j);
        so(:, j, :) = reshape(o .* (q ./ q), size(so(:, j, :)));   % NaN where not qualifying
        a = abs(o(q));
        pooled{j} = [pooled{j}; a(:)];
        if isempty(a), m = [NaN NaN NaN]; else, m = [median(a) prctile(a, 99) max(a)]; end
        recRows{end+1} = table(id, f0s(j), numel(a), m(1), m(2), m(3), 'VariableNames', ...
            {'recording', 'f0', 'n_cells', 'median_abs_offset_hz', 'p99_abs_offset_hz', 'max_abs_offset_hz'}); %#ok<AGROW>
    end
    for h = 2:4                                           % per chunk: median over channels qualifying at both
        both = ~isnan(so(:, 1, :)) & ~isnan(so(:, h, :));
        for c = 1:size(so, 3)
            b = both(:, 1, c);
            if any(b), harm{h - 1}(end+1, :) = [median(so(b, 1, c)) median(so(b, h, c))]; end
        end
    end
end
byRec = vertcat(recRows{:});
pRows = cell(4, 1); pass = true(1, 4);
for j = 1:4
    a = pooled{j};
    nr = sum(byRec.f0 == f0s(j) & byRec.n_cells > 0);
    if isempty(a), v = nan(1, 4); else, v = [median(a) prctile(a, 95) prctile(a, 99) max(a)]; end
    pass(j) = ~isnan(v(3)) && v(3) <= lim;
    pRows{j} = table(f0s(j), numel(a), nr, v(1), v(2), v(3), v(4), pass(j), 'VariableNames', ...
        {'f0', 'n_cells', 'n_recordings', 'median_abs_offset_hz', 'p95_abs_offset_hz', 'p99_abs_offset_hz', ...
        'max_abs_offset_hz', 'p99_le_0p2hz'});
end
pooledT = vertcat(pRows{:});
hRows = cell(3, 1);
for h = 2:4
    x = harm{h - 1};
    if isempty(x), x = zeros(0, 2); end
    slope = (x(:, 1)' * x(:, 2)) / (x(:, 1)' * x(:, 1));
    if size(x, 1) > 2, r = corr(x(:, 1), x(:, 2)); else, r = NaN; end
    nz = abs(x(:, 1)) >= 0.05;                            % ratio only where the 50 Hz offset is >= half a grid step
    hRows{h - 1} = table(h, size(x, 1), slope, r, median(x(nz, 2) ./ x(nz, 1)), sum(nz), 'VariableNames', ...
        {'harmonic_k', 'n_recording_chunks', 'slope_through_origin', 'pearson_r', 'median_ratio', 'n_ratio'});
end
harmT = vertcat(hRows{:});
mkdir(outDir);
writetable(pooledT, fullfile(outDir, 'r3_pooled.csv'));
writetable(byRec, fullfile(outDir, 'r3_by_recording.csv'));
writetable(harmT, fullfile(outDir, 'r3_harmonic.csv'));
if all(pass), verdict = 'KEEP the +/-2 Hz notch (p99 <= 0.2 Hz at every f0)';
else, verdict = sprintf('STOP and report to Amirhossein (p99 > 0.2 Hz at f0 = %s Hz)', mat2str(f0s(~pass))); end
fid = fopen(fullfile(outDir, 'r3_decision.txt'), 'w');
fprintf(fid, 'S3a-D5a-R3 re-examination; source %s (batch.json SHA-256 %s), %d recordings\n', ...
    sourceBatchDir, sha256File(fullfile(sourceBatchDir, 'batch.json')), numel(S));
fprintf(fid, 'cell = chunk x kept channel x f0 with chunk excess >= %g dB; offset = |fpk - f0|\n', thr);
for j = 1:4
    fprintf(fid, '%3d Hz: n %d (%d recordings); median %.4f, p95 %.4f, p99 %.4f, max %.4f Hz -> p99 <= %.1f: %d\n', ...
        f0s(j), pooledT.n_cells(j), pooledT.n_recordings(j), pooledT.median_abs_offset_hz(j), pooledT.p95_abs_offset_hz(j), ...
        pooledT.p99_abs_offset_hz(j), pooledT.max_abs_offset_hz(j), lim, pass(j));
end
fprintf(fid, 'DECISION: %s\n', verdict);
fclose(fid);
fprintf('%s', fileread(fullfile(outDir, 'r3_decision.txt')));
disp(harmT);
out = struct('pooled', pooledT, 'byRecording', byRec, 'harmonic', harmT, 'pass', all(pass));
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
