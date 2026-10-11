function stage3_d5b_merge(params, outFile)
%STAGE3_D5B_MERGE  Merge the verified unit outputs of a chunked (b) residual-test batch (S3a-D5b-amend1)
%   into one result per recording, identical in content to stage3_d5b_compute_one's unsplit 'res'
%   (same stage3_d5b_rules). Runner job function. params: sourceBatchDir.
%   Every unit's canonical output is hash-checked against its state file. Per recording the units
%   must cover channels 1..nChannelsTotal exactly once, with identical grid, segments, chunk positions
%   and line-noise parameters. Saves: results (struct array, one per recording), summary (table).

srcDir = char(params.sourceBatchDir);
batch = jsondecode(fileread(fullfile(srcDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');
S = dir(fullfile(srcDir, 'state', '*.json'));
U = cell(numel(S), 1); sha = strings(numel(S), 1); ids = strings(numel(S), 1);
for k = 1:numel(S)
    st = jsondecode(fileread(fullfile(srcDir, 'state', S(k).name)));
    assert(strcmp(st.status, 'verified'), '%s: status %s', S(k).name, st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', S(k).name);
    L = load(st.canonical.path); U{k} = L.unit; sha(k) = string(st.canonical.sha256); ids(k) = erase(string(S(k).name), ".json");
end
sources = table(ids, sha, 'VariableNames', {'unit', 'sha256'});
recKey = cellfun(@(u) char(u.subject + "_" + u.task), U, 'uni', 0);
recs = unique(string(recKey), 'stable');
results = struct([]); rows = {};
for r = 1:numel(recs)
    sel = find(string(recKey) == recs(r));
    first = cellfun(@(u) u.chans(1), U(sel));
    [~, o] = sort(first); sel = sel(o);
    u1 = U{sel(1)}; nCh = u1.nChannelsTotal;
    covered = cell2mat(cellfun(@(u) u.chans(:)', U(sel)', 'uni', 0));
    assert(isequal(covered, 1:nCh), '%s: units do not cover channels 1..%d exactly once', recs(r), nCh);
    for k = sel(:)'
        u = U{k};
        assert(isequal(u.F, u1.F) && isequal(u.segments, u1.segments) && isequal(u.chunkStarts, u1.chunkStarts) ...
            && u.nChunk == u1.nChunk && isequal(u.lineNoise, u1.lineNoise) && u.nChannelsTotal == nCh, '%s: units disagree', recs(r));
    end
    label = vertcat(U{sel}); label = vertcat(label.label);
    avgB = cell2mat(cellfun(@(u) u.avgPBefore, U(sel), 'uni', 0));
    avgA = cell2mat(cellfun(@(u) u.avgPAfter, U(sel), 'uni', 0));
    chunkExcA = cell2mat(cellfun(@(u) u.chunkExcessAfterDb, U(sel), 'uni', 0));
    res = stage3_d5b_rules(avgB, avgA, chunkExcA, label);
    res.subject = u1.subject; res.task = u1.task; res.role = u1.role;
    res.F = u1.F; res.f0s = [50 100 150 200]; res.avgPBefore = avgB; res.avgPAfter = avgA; res.nChunk = u1.nChunk;
    res.chunkStarts = u1.chunkStarts; res.segments = u1.segments; res.lineNoise = u1.lineNoise;
    if isempty(results), results = res; else, results(end+1) = res; end %#ok<AGROW>
    q = res.afterCellQuantilesDb;
    rows{end+1} = table(res.subject, res.task, res.role, numel(sel), res.nChunk, res.nCells, res.rb1Pass, res.rb2Pass, ...
        res.maxExcessAfterKeptDb, q(1), q(2), q(3), q(4), res.afterCellsGe3Db, res.maxAbsFlankChangeKeptDb, ...
        'VariableNames', {'subject', 'task', 'role', 'n_units', 'n_chunks', 'n_cells', 'rb1_committed_pass', 'rb2_pass', ...
        'max_excess_after_db', 'q50_after_db', 'q90_after_db', 'q95_after_db', 'q99_after_db', 'n_cells_ge3db', ...
        'max_abs_flank_change_db'}); %#ok<AGROW>
end
summary = vertcat(rows{:});
sourceBatch = struct('dir', string(srcDir), 'batchJsonSha256', string(sha256File(fullfile(srcDir, 'batch.json'))));
save(outFile, 'results', 'summary', 'sources', 'sourceBatch');
disp(summary);
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
