function stage3_p1_compute_one(params, outFile)
%STAGE3_P1_COMPUTE_ONE  Stage 3 part 1 (D1-D5) for one recording, as a runner job function (S3a-P1).
%   params: subject, task, plus rawRoot, manifest, blockTable (common); optional groupSize (default 16),
%   logFile (decision log, default docs/decision_log.md of this repository).
%   Steps, in the committed order:
%     inputs   every raw file read is checked against the verified manifest (S3a-D1-amend);
%     D4e-4    pop_loadbv; labels equal channels.tsv (types from channels.tsv); sample-exact event check:
%              the non-boundary events (code 'Stimulus') equal the events.tsv rows (latency = onset x 1000,
%              same whitespace-normalised event_type), as multisets; the empty-type 'Time 0' marker is
%              the only other non-boundary event allowed, and it is removed (count stored);
%              sub-13/41/42 are refused (stop-on-mismatch in force, S3a-D4e-4-asm-amend1);
%     D3a      rest, all but sub-25: S10 = S12(1) + 300 s within 0.01 s (events.tsv);
%     D2a      TP9 LEFT EAR / TP10 RIGHT EAR dropped (125 channels); positions from the
%              standard-10-5-cap385 template (S3a-D2; D2a/D2b in force, S3a-D2-reopen). D2b (FCz) is
%              applied at re-referencing, after D6, not here;
%     D4a      high-pass 0.5 Hz at 1000 Hz (pop_eegfiltnew);
%     D4c      pop_resample to 500 Hz;
%     D5       four band-stop filters f0 +/- S.notchA Hz (S3a-D5-final), in cascade at 500 Hz;
%     D3/D3e/D4e  crop to the clipped blocks of params.blockTable (pop_select 'point'; raw latency of a
%              block edge = round(new_*_s x 1000), then ceil/floor at 500 Hz, as in the D5 tests);
%              block identity events <label>_start/_end; EEG.etc.restBlocks / taskBlocks (D3d, D3e-4,
%              D4e-3).
%   Channels are processed in groups (every step is per channel; events are asserted identical between
%   groups). Output: variable EEG (data single), loadable by pop_loadset. OUTCOME-BLIND: no spectrum or
%   power is computed.

here = fileparts(mfilename('fullpath'));
addpath(here);
S = stage3_params();
if ~exist('pop_loadbv', 'file'), eeglab('nogui'); end
[H, HT] = stage3_filter_halflengths(S);
s = char(params.subject); task = char(params.task);
assert(~ismember(string(s), ["sub-13", "sub-41", "sub-42"]), 'stage3:p1', ...
    '%s: D4e-4 stop-on-mismatch in force (S3a-D4e-4-asm-amend1)', s);
if isfield(params, 'logFile') && ~isempty(params.logFile), logFile = char(params.logFile);
else, logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md'); end
drop = ["TP9 LEFT EAR", "TP10 RIGHT EAR"];

% ---- inputs ---------------------------------------------------------------------------------
rawRoot = char(params.rawRoot);
eegDir = fullfile(rawRoot, s, 'eeg'); base = [s '_task-' task]; hdr = [base '_eeg.vhdr'];
inputs = strings(0, 1);
chk = @(f) stage3_check_input(f, rawRoot, params.manifest);
vh = fullfile(eegDir, hdr); chk(vh); inputs(end+1) = vh;
txt = fileread(vh);
for key = ["DataFile", "MarkerFile"]
    tok = regexp(txt, "^" + key + "=([^\r\n]+)", 'tokens', 'once', 'lineanchors');
    f = fullfile(eegDir, strtrim(tok{1})); chk(f); inputs(end+1) = f; %#ok<AGROW>
end
ctFile = fullfile(eegDir, [base '_channels.tsv']); chk(ctFile); inputs(end+1) = ctFile;
evFile = fullfile(eegDir, [base '_events.tsv']); chk(evFile); inputs(end+1) = evFile;
ct = readtable(ctFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
ev = readtable(evFile, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
nCh = str2double(regexp(txt, 'NumberOfChannels=(\d+)', 'tokens', 'once'));
assert(height(ct) == nCh, 'stage3:p1', 'channels.tsv and .vhdr disagree on the channel count');
keep = find(~ismember(ct.name, drop))';
assert(numel(keep) == nCh - 2, 'stage3:p1', 'TP9/TP10 not found exactly once');
B = readtable(char(params.blockTable), 'TextType', 'string');
bk = B(B.subject == s & B.task == task, :);
assert(height(bk) >= 1 && all(ismember(bk.status, ["unchanged", "CLIPPED"])), 'stage3:p1', '%s %s: block table status', s, task);
tpl = fullfile(fileparts(which('dipfitdefs')), 'standard_BESA', 'standard-10-5-cap385.elp');
assert(exist(tpl, 'file') == 2, 'stage3:p1', 'template %s not found', tpl);

% ---- D3a consistency check (rest) -----------------------------------------------------------
evType = regexprep(strtrim(ev.event_type), '\s+', ' ');
if strcmp(task, 'rest') && ~strcmp(s, 'sub-25')
    s12 = ev.onset(evType == "S 12"); s10 = ev.onset(evType == "S 10");
    assert(isscalar(s10) && numel(s12) >= 1 && abs(s10 - (s12(1) + 300)) <= 0.01, 'stage3:p1', '%s: D3a S10 check failed', s);
end

% ---- per channel group: load, checks, filters, crop ------------------------------------------
gs = 16; if isfield(params, 'groupSize') && ~isempty(params.groupSize), gs = double(params.groupSize); end
groups = arrayfun(@(g) keep(g:min(g + gs - 1, numel(keep))), 1:gs:numel(keep), 'uni', 0);
Xs = cell(1, numel(groups)); locs = cell(1, numel(groups)); E1 = []; kern = {}; nTime0 = NaN; edges500 = [];
for gi = 1:numel(groups)
    chans = groups{gi};
    EEG = pop_loadbv(eegDir, hdr, [], chans);
    lab = string({EEG.chanlocs.labels});
    assert(isequal(lab(:), ct.name(chans)), 'stage3:p1', 'channel labels differ from channels.tsv');
    % sample-exact event check (D4e-4)
    typ = string({EEG.event.type}); code = string({EEG.event.code}); lat = [EEG.event.latency];
    isB = typ == "boundary";
    isT0 = ~isB & strlength(strtrim(typ)) == 0;
    assert(all(code(isT0) == "Time 0"), 'stage3:p1', 'an empty-type event that is not Time 0');
    st = ~isB & ~isT0;
    assert(all(code(st) == "Stimulus"), 'stage3:p1', 'a non-boundary event whose code is not Stimulus');
    A = sortrows(table(lat(st)', regexprep(strtrim(typ(st)'), '\s+', ' '), 'VariableNames', {'lat', 'type'}));
    R = sortrows(table(round(ev.onset * S.fsRaw), evType, 'VariableNames', {'lat', 'type'}));
    assert(isequal(A.lat, R.lat) && isequal(A.type, R.type), 'stage3:p1', '%s %s: events differ from events.tsv', s, task);
    if gi == 1, nTime0 = sum(isT0); else, assert(sum(isT0) == nTime0); end
    EEG.event(isT0) = [];
    if isfield(EEG.event, 'urevent'), EEG.event = rmfield(EEG.event, 'urevent'); end
    EEG.urevent = [];
    for k = 1:height(bk)                                   % block edges as marker events (raw samples)
        EEG.event(end+1).type = sprintf('p1bs%02d', k); EEG.event(end).latency = round(bk.new_start_s(k) * S.fsRaw);
        EEG.event(end+1).type = sprintf('p1be%02d', k); EEG.event(end).latency = round(bk.new_end_s(k) * S.fsRaw);
    end
    EEG = eeg_checkset(EEG, 'eventconsistency');
    EEG = pop_eegfiltnew(EEG, 'locutoff', S.hpEdge);       % D4a
    EEG = pop_resample(EEG, S.fsOut);                      % D4c
    kg = cell(1, numel(S.lineFreqs));
    for j = 1:numel(S.lineFreqs)                           % D5, option (a)
        [EEG, ~, kg{j}] = pop_eegfiltnew(EEG, 'locutoff', S.lineFreqs(j) - S.notchA, ...
            'hicutoff', S.lineFreqs(j) + S.notchA, 'revfilt', 1);
    end
    if isempty(kern), kern = kg; else, assert(isequal(kern, kg), 'stage3:p1', 'notch kernels differ between groups'); end
    typ = {EEG.event.type};
    ed = nan(height(bk), 2);
    for k = 1:height(bk)
        a = [EEG.event(strcmp(typ, sprintf('p1bs%02d', k))).latency];
        e = [EEG.event(strcmp(typ, sprintf('p1be%02d', k))).latency];
        assert(isscalar(a) && isscalar(e), 'stage3:p1', 'block %d marker lost', k);
        ed(k, :) = [ceil(a), floor(e)];
        EEG.event(strcmp(typ, sprintf('p1bs%02d', k))).latency = ed(k, 1);   % exactly on the kept edge samples
        EEG.event(strcmp(typ, sprintf('p1be%02d', k))).latency = ed(k, 2);
    end
    assert(all(ed(:, 2) > ed(:, 1)) && all(ed(2:end, 1) > ed(1:end-1, 2)), 'stage3:p1', 'block edges not increasing');
    bl = [EEG.event(strcmp(typ, 'boundary')).latency];     % D4e: no raw boundary inside a kept block
    assert(~any(any(bl(:)' > ed(:, 1) & bl(:)' <= ed(:, 2))), 'stage3:p1', 'raw boundary inside a clipped block');
    if isempty(edges500), edges500 = ed; else, assert(isequal(edges500, ed), 'stage3:p1', 'block edges differ between groups'); end
    EEG = pop_select(EEG, 'point', ed);                   % D3/D3e crop
    Xs{gi} = single(EEG.data); locs{gi} = EEG.chanlocs;
    ev1 = rmfield(EEG.event, intersect(fieldnames(EEG.event), {'urevent'}));
    if gi == 1, E1 = EEG; E1.data = []; evRef = ev1; else, assert(isequaln(ev1, evRef), 'stage3:p1', 'events differ between groups'); end
    clear EEG
end
order = cellfun(@numel, kern) - 1;
assert(isequal(order(:), HT.order(3:end)), 'stage3:p1', 'notch orders differ from stage3_filter_halflengths');

% ---- assemble, block identity, channel info --------------------------------------------------
EEG = E1;
EEG.data = vertcat(Xs{:}); clear Xs
EEG.chanlocs = [locs{:}]; EEG.nbchan = size(EEG.data, 1); EEG.urchanlocs = [];
for c = 1:EEG.nbchan, EEG.chanlocs(c).type = char(ct.type(keep(c))); end
lens = ed(:, 2) - ed(:, 1) + 1; off = [0; cumsum(lens(1:end-1))];
typ = {EEG.event.type};
for k = 1:height(bk)
    ia = find(strcmp(typ, sprintf('p1bs%02d', k))); ie = find(strcmp(typ, sprintf('p1be%02d', k)));
    assert(isscalar(ia) && isscalar(ie) && EEG.event(ia).latency == off(k) + 1 && EEG.event(ie).latency == off(k) + lens(k), ...
        'stage3:p1', 'block %d edges after cropping', k);
    EEG.event(ia).type = char(bk.block(k) + "_start"); EEG.event(ie).type = char(bk.block(k) + "_end");
end
EEG = pop_chanedit(EEG, 'lookup', tpl);                    % S3a-D2 template positions
assert(all(arrayfun(@(c) isnumeric(c.X) && isscalar(c.X) && ~isnan(c.X), EEG.chanlocs)), 'stage3:p1', 'a channel without template position');
txtc = @(x) cellstr(fillmissing(string(x), 'constant', ""));
blocks = struct('label', txtc(bk.block), 'orig_start_s', num2cell(bk.start_s), 'orig_end_s', num2cell(bk.end_s), ...
    'orig_dur_s', num2cell(bk.dur_s), 'clip_start_s', num2cell(bk.clip_start_s), 'clip_start_reason', txtc(bk.clip_start_reason), ...
    'clip_end_s', num2cell(bk.clip_end_s), 'clip_end_reason', txtc(bk.clip_end_reason), 'new_start_s', num2cell(bk.new_start_s), ...
    'new_end_s', num2cell(bk.new_end_s), 'new_dur_s', num2cell(bk.new_dur_s), 'status', txtc(bk.status), ...
    'samples_500hz_uncropped', num2cell(ed, 2), 'samples_cropped', num2cell([off + 1, off + lens], 2));
if strcmp(task, 'rest')
    [blocks.sub25_flag] = deal(strcmp(s, 'sub-25'));     % D3c
    EEG.etc.restBlocks = blocks;
else
    nS = num2cell(bk.n_stim); sp = num2cell(bk.split_10s);
    sb = num2cell(bk.stim_before_new_start); sa = num2cell(bk.stim_after_new_end);
    [blocks.n_stim] = nS{:}; [blocks.split_10s] = sp{:};
    [blocks.stim_before_new_start] = sb{:}; [blocks.stim_after_new_end] = sa{:};
    EEG.etc.taskBlocks = blocks;
end
ids = {'S3a-D1', 'S3a-D1-amend', 'S3a-D2', 'S3a-D3', 'S3a-D3e', 'S3a-D4', 'S3a-D4e', 'S3a-D5-final', 'S3a-D5-integ', 'S3a-P1'};
lh = cellfun(@(i) stage3_log_entry(logFile, i), ids, 'uni', 0);
inSha = arrayfun(@(f) string(sha256File(char(f))), inputs);
EEG.etc.stage3 = struct('part', 1, 'subject', s, 'task', task, 'H_s', H, 'filters', table2struct(HT), ...
    'notchA_hz', S.notchA, 'lineFreqs_hz', S.lineFreqs, 'droppedChannels', {cellstr(drop)}, 'removedTime0Events', nTime0, ...
    'template', tpl, 'blockTableSha256', sha256File(char(params.blockTable)), ...
    'inputs', struct('file', cellstr(inputs(:)), 'sha256', cellstr(inSha(:))), ...
    'logEntries', struct('id', ids, 'sha256', lh));
EEG.setname = [base '_s3p1']; EEG.filename = ''; EEG.filepath = ''; EEG.datfile = '';
EEG = eeg_checkset(EEG, 'eventconsistency');
EEG.data = single(EEG.data);                               % float32, as pop_saveset writes (S3a-D1-amend)
save(outFile, 'EEG', '-v7');
fprintf('%s %s: %d channels, %d samples at %d Hz in %d blocks; H %.3f s; %d Time 0 marker(s) removed\n', ...
    s, task, EEG.nbchan, EEG.pnts, EEG.srate, height(bk), H, nTime0);
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
