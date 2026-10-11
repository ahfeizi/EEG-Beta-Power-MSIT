function ok = test_stage3_d5b_criterion(workDir)
%TEST_STAGE3_D5B_CRITERION  Synthetic test of stage3_d5b_null_set (S3a-D5b-null-amend1) and of
%   stage3_d5b_criterion (S3a-D5b-rb1). No EEG data.
%   1. null set: per task the fewest chunks wins (not the shortest duration); a chunk tie is broken by
%      the shorter duration; a full tie is refused; no overwrite.
%   2. criterion, null only: null_c1_valid true iff q95 <= 2 dB in both twins (2.0 exactly is valid);
%      cells > 3 dB counted over kept channels only; a null with other than one rest + one MSIT+ refused.
%   3. criterion, real: C1 (q95 < 3, 3.0 exactly fails), recording_pass = C1 && R-b2, b_passes needs a
%      valid null and every recording; descriptives max and cells > 3 dB; no overwrite.

here = fileparts(mfilename('fullpath')); addpath(here);
% ---- 1. null set
raw = fullfile(workDir, 'raw');
recs = {'sub-91', 'rest', 60, 100; 'sub-92', 'rest', 58, 120; 'sub-93', 'msit', 95, 200; ...
        'sub-94', 'msit', 93, 260; 'sub-95', 'msit', 93, 250};          % subject, task, n_chunks, duration (s)
nCh = 3; fs = 100;
rows = {}; chan = {};
for i = 1:size(recs, 1)
    s = recs{i, 1}; t = recs{i, 2}; d = fullfile(raw, s, 'eeg'); mkdir(d);
    base = sprintf('%s_task-%s_eeg', s, t);
    fid = fopen(fullfile(d, [base '.vhdr']), 'w');
    fprintf(fid, 'Brain Vision Data Exchange Header File Version 1.0\r\n[Common Infos]\r\nDataFile=%s.dat\r\nMarkerFile=%s.vmrk\r\nDataFormat=BINARY\r\nDataOrientation=VECTORIZED\r\nNumberOfChannels=%d\r\nSamplingInterval=%d\r\n[Binary Infos]\r\nBinaryFormat=IEEE_FLOAT_32\r\n', base, base, nCh, 1e6 / fs);
    fclose(fid);
    fid = fopen(fullfile(d, [base '.dat']), 'w'); fwrite(fid, zeros(nCh * recs{i, 4} * fs, 1, 'single'), 'float32'); fclose(fid);
    rows(end+1, :) = {s, t, 'synthetic', i}; %#ok<AGROW>
    for c = 1:nCh, chan(end+1, :) = {s, t, sprintf('C%d', c), recs{i, 3}}; end %#ok<AGROW>
end
ts = fullfile(workDir, 'test_set.csv');
writetable(cell2table(rows, 'VariableNames', {'subject', 'task', 'role', 'r2_rank'}), ts);
cc = fullfile(workDir, 'chan.csv');
writetable(cell2table(chan, 'VariableNames', {'subject', 'task', 'channel', 'n_chunks'}), cc);
T = stage3_d5b_null_set(ts, cc, raw, fullfile(workDir, 'null_set.csv'));
c1 = height(T) == 2 && isequal(T.subject, ["sub-92"; "sub-95"]) && isequal(T.task, ["rest"; "msit"]) ...
    && all(abs(T.duration_s - [120; 250]) < 1e-9);
noOver = false; try, stage3_d5b_null_set(ts, cc, raw, fullfile(workDir, 'null_set.csv')); catch, noOver = true; end
rows(5, :) = []; rows(end+1, :) = {'sub-96', 'msit', 'synthetic', 6};      % sub-94 twin: same chunks and duration
d = fullfile(raw, 'sub-96', 'eeg'); copyfile(fullfile(raw, 'sub-94', 'eeg'), d);
for e = {'.vhdr', '.dat'}
    movefile(fullfile(d, ['sub-94_task-msit_eeg' e{1}]), fullfile(d, ['sub-96_task-msit_eeg' e{1}]));
end
vf = fullfile(d, 'sub-96_task-msit_eeg.vhdr'); v = strrep(fileread(vf), 'sub-94', 'sub-96');
fid = fopen(vf, 'w'); fwrite(fid, v); fclose(fid);
for c = 1:nCh, chan(end+1, :) = {'sub-96', 'msit', sprintf('C%d', c), 93}; end %#ok<AGROW>
ts2 = fullfile(workDir, 'test_set_tie.csv'); cc2 = fullfile(workDir, 'chan_tie.csv');
writetable(cell2table(rows, 'VariableNames', {'subject', 'task', 'role', 'r2_rank'}), ts2);
writetable(cell2table(chan, 'VariableNames', {'subject', 'task', 'channel', 'n_chunks'}), cc2);
tie = false; try, stage3_d5b_null_set(ts2, cc2, raw, fullfile(workDir, 'null_set_tie.csv')); catch ME, tie = contains(ME.message, 'tie'); end
fprintf('1 null set: fewest chunks, tie-break by duration %d; no overwrite %d; full tie refused %d\n', c1, noOver, tie);

% ---- 2./3. criterion
nv = fullfile(workDir, 'null_valid.mat'); ni = fullfile(workDir, 'null_invalid.mat'); n3 = fullfile(workDir, 'null_three.mat');
mergeFile(nv, {'sub-92', 'rest', 1.0, 2.0, true; 'sub-95', 'msit', 1.5, 1.9, true});
mergeFile(ni, {'sub-92', 'rest', 1.0, 2.0, true; 'sub-95', 'msit', 1.5, 2.1, true});
mergeFile(n3, {'sub-92', 'rest', 1.0, 2.0, true; 'sub-95', 'msit', 1.5, 1.9, true; 'sub-91', 'rest', 1, 1, true});
A = stage3_d5b_criterion(nv, fullfile(workDir, 'nc_valid.csv'));
B = stage3_d5b_criterion(ni, fullfile(workDir, 'nc_invalid.csv'));
c2 = all(A.null_c1_valid) && all(~B.null_c1_valid) && isequal(B.null_q95_le_2db, [true; false]) ...
    && isequal(A.null_cells_gt3db, [3; 3]);
bad = false; try, stage3_d5b_criterion(n3, fullfile(workDir, 'nc_three.csv')); catch ME, bad = contains(ME.message, 'exactly one rest'); end
fprintf('2 null: validity %d; wrong null refused %d\n', c2, bad);
rf = fullfile(workDir, 'real.mat');
mergeFile(rf, {'sub-91', 'rest', 2.0, 2.9, true; 'sub-92', 'rest', 2.0, 3.0, true; 'sub-95', 'msit', 2.0, 2.5, false});
R = stage3_d5b_criterion(nv, fullfile(workDir, 'real_valid.csv'), rf);
c3 = isequal(R.C1_q95_lt3, [true; false; true]) && isequal(R.recording_pass, [true; false; false]) ...
    && all(~R.b_passes) && all(R.null_c1_valid) && isequal(R.real_cells_gt3db, [3; 3; 3]) && all(R.real_max_db == 9);
rp = fullfile(workDir, 'real_pass.mat');
mergeFile(rp, {'sub-91', 'rest', 2.0, 2.9, true; 'sub-95', 'msit', 2.0, 2.5, true});
P1 = stage3_d5b_criterion(nv, fullfile(workDir, 'real_pass_valid.csv'), rp);
P2 = stage3_d5b_criterion(ni, fullfile(workDir, 'real_pass_invalid.csv'), rp);
c4 = all(P1.b_passes) && all(~P2.b_passes);
noOver2 = false; try, stage3_d5b_criterion(nv, fullfile(workDir, 'real_valid.csv'), rf); catch, noOver2 = true; end
fprintf('3 real: C1 and recording pass %d; b_passes needs valid null %d; no overwrite %d\n', c3, c4, noOver2);
ok = c1 && noOver && tie && c2 && bad && c3 && c4 && noOver2;
if ok, fprintf('D5B CRITERION PASS\n'); else, fprintf('D5B CRITERION FAIL\n'); end
end

function mergeFile(f, spec)
% A stage3_d5b_merge-shaped file: per row subject, task, q50, q95, rb2. Each recording has 5 kept
% channels + 2 excluded (TP9/TP10, excess 50 dB) x 4 f0; three kept cells are set to 9 dB (> 3 dB).
results = struct([]); rows = {};
for i = 1:size(spec, 1)
    label = ["C1"; "C2"; "C3"; "C4"; "C5"; "TP9 LEFT EAR"; "TP10 RIGHT EAR"];
    kept = ~ismember(label, ["TP9 LEFT EAR", "TP10 RIGHT EAR"]);
    e = zeros(7, 4); e(~kept, :) = 50; e(1, 1:3) = 9;
    r = struct('subject', string(spec{i, 1}), 'task', string(spec{i, 2}), 'role', "synthetic", ...
        'label', label, 'kept', kept, 'excessAfterDb', e);
    if isempty(results), results = r; else, results(end+1) = r; end %#ok<AGROW>
    rows{end+1} = table(string(spec{i, 1}), string(spec{i, 2}), "synthetic", 1, 10, 20, false, spec{i, 5}, ...
        9, spec{i, 3}, spec{i, 4}, spec{i, 4}, 8, 3, 0.1, ...
        'VariableNames', {'subject', 'task', 'role', 'n_units', 'n_chunks', 'n_cells', 'rb1_committed_pass', 'rb2_pass', ...
        'max_excess_after_db', 'q50_after_db', 'q90_after_db', 'q95_after_db', 'q99_after_db', 'n_cells_ge3db', ...
        'max_abs_flank_change_db'}); %#ok<AGROW>
end
summary = vertcat(rows{:}); %#ok<NASGU>
save(f, 'results', 'summary');
end
