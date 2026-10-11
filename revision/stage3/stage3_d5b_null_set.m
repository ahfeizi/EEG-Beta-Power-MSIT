function T = stage3_d5b_null_set(testSetFile, chanCsv, rawRoot, outFile)
%STAGE3_D5B_NULL_SET  The two recordings whose noise-only twins form the R-b1 null (S3a-D5b-null-amend1):
%   per task (rest, msit), the test-set recording with the fewest D5-0 chunks (worst case: largest null
%   fluctuation); a tie is broken by the shorter duration, a remaining tie is an error.
%   testSetFile: <outRoot>/stage3/d5b/test_set.csv. chanCsv: the D5-0 v2 line_noise_by_channel.csv
%   (n_chunks, constant within a recording; the (b) test uses the same 10 s chunks). rawRoot: the
%   verified raw copy; only the .vhdr text and the .eeg file SIZE are read (duration), not its bytes.
%   Writes outFile (refuses to overwrite) with the test-set columns plus n_chunks and duration_s.

assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
S = readtable(testSetFile, 'TextType', 'string');
C = readtable(chanCsv, 'TextType', 'string', 'Delimiter', ',');
n = height(S); nChunks = nan(n, 1); dur = nan(n, 1);
for i = 1:n
    s = S.subject(i); task = S.task(i);
    c = unique(C.n_chunks(C.subject == s & C.task == task));
    assert(isscalar(c), '%s %s: n_chunks not unique in %s', s, task, chanCsv);
    nChunks(i) = c;
    d = fullfile(rawRoot, char(s), 'eeg'); base = char(s + "_task-" + task + "_eeg");
    vh = fileread(fullfile(d, [base '.vhdr']));
    assert(contains(vh, 'BinaryFormat=IEEE_FLOAT_32'), '%s: not float32', base);
    nCh = str2double(regexp(vh, 'NumberOfChannels=(\d+)', 'tokens', 'once'));
    si = str2double(regexp(vh, 'SamplingInterval=([\d.]+)', 'tokens', 'once'));   % microseconds
    df = regexp(vh, '^DataFile=([^\r\n]+)', 'tokens', 'once', 'lineanchors');
    info = dir(fullfile(d, strtrim(df{1})));
    assert(isscalar(info), '%s: data file not found', base);
    dur(i) = info.bytes / (4 * nCh) * si / 1e6;
end
S.n_chunks = nChunks; S.duration_s = dur;
pick = false(n, 1);
for task = ["rest", "msit"]
    idx = find(S.task == task);
    assert(~isempty(idx), 'no %s recording in the test set', task);
    cand = idx(S.n_chunks(idx) == min(S.n_chunks(idx)));
    cand = cand(S.duration_s(cand) == min(S.duration_s(cand)));
    assert(isscalar(cand), 'tie for the %s twin', task);
    pick(cand) = true;
end
T = S(pick, :);
writetable(T, outFile);
disp(S); fprintf('null twins:\n'); disp(T);
end
