function check_d50_cache()
% Post-crash integrity check of the D5-0 per-recording cache. Read-only: loads each .mat, checks
% variables, shapes, finiteness and labels; reads only .vhdr / channels.tsv text from the raw folder.
maxNumCompThreads(1);
repo = 'C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\github\eeg-beta-project';
addpath(repo); P = get_paths();
cacheDir = fullfile(P.outRoot, 'stage3', 'd5_0', 'per_recording');
L = dir(fullfile(cacheDir, '*.mat'));
fprintf('files: %d\n', numel(L));
nBad = 0;
for i = 1:numel(L)
    f = fullfile(cacheDir, L(i).name);
    [~, nm] = fileparts(f); parts = split(string(nm), "_"); s = char(parts(1)); task = char(parts(2));
    msg = {};
    try
        V = load(f);
    catch ME
        fprintf('%-14s LOAD FAILED: %s\n', nm, ME.message); nBad = nBad + 1; continue
    end
    need = {'res', 'F', 'd', 'f0s', 'nChunk'};
    miss = need(~isfield(V, need));
    if ~isempty(miss), fprintf('%-14s MISSING VARS: %s\n', nm, strjoin(miss, ',')); nBad = nBad + 1; continue; end
    R = V.res; nCh = numel(R.label);
    eegDir = fullfile(P.bidsRoot, s, 'eeg');
    txt = fileread(fullfile(eegDir, [s '_task-' task '_eeg.vhdr']));
    nV = str2double(regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once'));
    ct = readtable(fullfile(eegDir, [s '_task-' task '_channels.tsv']), 'FileType', 'text', ...
                   'Delimiter', '\t', 'TextType', 'string');
    nC = V.nChunk(1);
    if numel(V.F) ~= 244 || ~isequal(V.f0s, [50 100 150 200]), msg{end+1} = 'grid'; end
    if nCh ~= nV, msg{end+1} = sprintf('nCh %d vs vhdr %d', nCh, nV); end
    if any(R.label == "" | ismissing(R.label)), msg{end+1} = 'empty label'; end
    if numel(unique(R.label)) ~= nCh, msg{end+1} = 'duplicate labels'; end
    if ~isequal(R.label(:), ct.name(:)), msg{end+1} = 'labels ~= channels.tsv'; end
    if numel(V.nChunk) ~= ceil(nV / 16) || any(V.nChunk ~= nC) || nC < 1, msg{end+1} = 'nChunk'; end
    if ~isequal(size(R.avgP), [nCh 244]), msg{end+1} = 'avgP size'; end
    if ~all(isfinite(R.avgP(:))) || any(R.avgP(:) <= 0), msg{end+1} = 'avgP nonfinite/<=0'; end
    for fld = {'exc', 'fpk', 'amp'}
        X = R.(fld{1});
        if ~isequal(size(X, 1, 2, 3), [nCh 4 nC]), msg{end+1} = [fld{1} ' size']; end %#ok<AGROW>
        if ~all(isfinite(X(:))), msg{end+1} = sprintf('%s %d nonfinite', fld{1}, sum(~isfinite(X(:)))); end %#ok<AGROW>
    end
    if all(R.avgP(:) == 0) || all(R.exc(:) == 0), msg{end+1} = 'all zeros'; end
    if isempty(msg)
        st = 'OK';
    else
        st = strjoin(msg, '; '); nBad = nBad + 1;
    end
    fprintf('%-14s nCh %3d  chunks %3d  %s\n', nm, nCh, nC, st);
end
fprintf('SUMMARY: %d files, %d with problems\n', numel(L), nBad);
end
