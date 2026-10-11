function stage3_d5b_null_make(srcRawRoot, testSetFile, dstRoot, seedBase)
%STAGE3_D5B_NULL_MAKE  Noise-only twins of the (b) test recordings for the R-b1 null calibration
%   (S3a-D5b-null). For each row of testSetFile (subject, task):
%     - the real .vhdr and .vmrk text and channels.tsv are copied unchanged (same channel count,
%       labels, duration, raw boundaries/"New Segment" markers; the D4e block table applies as is);
%     - the .eeg is replaced by seeded white Gaussian noise (10 uV, IEEE float32, VECTORIZED, as the
%       header states) with exactly the real file size. The real .eeg bytes are NOT read (only its size).
%   Writes <dstRoot>/raw/<sub>/eeg/... and <dstRoot>/manifest.tsv (relpath, size, sha256), which the
%   job checks inputs against. seedBase + row index seeds each recording (rng twister). Refuses to
%   overwrite an existing <dstRoot>/raw.

T = readtable(testSetFile, 'TextType', 'string');
raw = fullfile(dstRoot, 'raw');
assert(~exist(raw, 'dir'), 'refusing to overwrite %s', raw);
for i = 1:height(T)
    s = char(T.subject(i)); task = char(T.task(i));
    src = fullfile(srcRawRoot, s, 'eeg'); dst = fullfile(raw, s, 'eeg'); mkdir(dst);
    base = [s '_task-' task];
    vh = fileread(fullfile(src, [base '_eeg.vhdr']));
    need = {'DataFormat=BINARY', 'DataOrientation=VECTORIZED', 'BinaryFormat=IEEE_FLOAT_32'};
    for k = 1:numel(need), assert(contains(vh, need{k}), '%s: header lacks %s', base, need{k}); end
    tok = regexp(vh, 'NumberOfChannels=(\d+)', 'tokens', 'once'); nCh = str2double(tok{1});
    df = regexp(vh, '^DataFile=([^\r\n]+)', 'tokens', 'once', 'lineanchors'); df = strtrim(df{1});
    mf = regexp(vh, '^MarkerFile=([^\r\n]+)', 'tokens', 'once', 'lineanchors'); mf = strtrim(mf{1});
    copyfile(fullfile(src, [base '_eeg.vhdr']), dst);
    copyfile(fullfile(src, mf), dst);
    copyfile(fullfile(src, [base '_channels.tsv']), dst);
    info = dir(fullfile(src, df));
    nSamp = info.bytes / (4 * nCh);
    assert(nSamp == round(nSamp), '%s: file size is not a whole number of samples', base);
    rng(seedBase + i, 'twister');
    fid = fopen(fullfile(dst, df), 'w', 'ieee-le');
    for c = 1:nCh                                          % VECTORIZED: channel after channel
        fwrite(fid, single(10 * randn(nSamp, 1)), 'float32');
    end
    fclose(fid);
    info2 = dir(fullfile(dst, df));
    assert(info2.bytes == info.bytes, '%s: noise file size differs', base);
    fprintf('%s: %d channels x %d samples of noise (seed %d)\n', base, nCh, nSamp, seedBase + i);
end
L = dir(fullfile(raw, '**', '*')); L = L(~[L.isdir]);
fid = fopen(fullfile(dstRoot, 'manifest.tsv'), 'w');
fprintf(fid, 'relpath\tsize\tsha256\n');
for k = 1:numel(L)
    f = fullfile(L(k).folder, L(k).name);
    fprintf(fid, '%s\t%d\t%s\n', strrep(f(numel(raw) + 2:end), '\', '/'), L(k).bytes, sha256File(f));
end
fclose(fid);
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
