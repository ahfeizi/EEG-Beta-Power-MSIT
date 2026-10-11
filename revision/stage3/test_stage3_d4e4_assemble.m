function ok = test_stage3_d4e4_assemble(workDir, labelsTsv)
%TEST_STAGE3_D4E4_ASSEMBLE  Synthetic test of stage3_d4e4_assemble + stage3_d4e4_export (S3a-D4e-4-asm).
%   Per-recording outputs from test_stage3_d4e4_compute_one (synthetic; sub-13 has its .vhdr labels
%   121/124 swapped and data in channels.tsv order, so H_tsv is true; sub-01 has an exactly
%   interpolated channel 50). Each is used for rest and (relabelled) MSIT+.
%   Pass: sub-13 -> "H_tsv supported" (k = 6, reference A); sub-01 channel 50 near-perfectly predicted;
%   sub-01 has no .bvct but an integer-rounded .bvef (built here from the synthetic positions of the
%   sub-13 .bvct, S3a-D4e-4-asm-amend1) -> neighbour counts computed, position_source "bvef"; tampered input refused; export
%   writes all files and refuses to overwrite.

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(fileparts(fileparts(here)), 'revision', 'infra'));
ok0 = test_stage3_d4e4_compute_one(workDir, labelsTsv);
% integer-rounded spherical .bvef for sub-01 from the synthetic positions (same for both subjects)
t = fileread(fullfile(workDir, 'raw', 'sourcedata', 'sub-13', 'coords', 'sub-13_captrak.bvct'));
blk = regexp(t, '<CapTrakElectrodeList>(.*?)</CapTrakElectrodeList>', 'tokens', 'once');
el = regexp(blk{1}, '<Name>([^<]*)</Name>\s*<X>([^<]*)</X>\s*<Y>([^<]*)</Y>\s*<Z>([^<]*)</Z>', 'tokens');
bd = fullfile(workDir, 'raw', 'sourcedata', 'sub-01', 'coords'); mkdir(bd);
bf = fullfile(bd, 'sub-01_captrak.bvef');
fid = fopen(bf, 'w'); fprintf(fid, '<?xml version="1.0"?>\n<Electrodes defaults="false">\n');
for k = 1:numel(el)
    v = str2double(el{k}(2:4)); rr = norm(v);
    fprintf(fid, '  <Electrode>\n    <Name>%s</Name>\n    <Theta>%d</Theta>\n    <Phi>%d</Phi>\n    <Radius>%d</Radius>\n  </Electrode>\n', ...
        el{k}{1}, round(acosd(v(3) / rr)), round(atan2d(v(2), v(1))), round(rr));
end
fprintf(fid, '</Electrodes>\n'); fclose(fid);
fid = fopen(fullfile(workDir, 'manifest.tsv'), 'a'); fi = dir(bf);
fprintf(fid, '%s\t%d\t%s\n', 'sourcedata/sub-01/coords/sub-01_captrak.bvef', fi.bytes, sha256File(bf)); fclose(fid);
clear stage3_check_input   % its persistent manifest cache (filled by the compute test above) predates this row
src = fullfile(workDir, 'srcbatch'); mkdir(fullfile(src, 'state'));
fid = fopen(fullfile(src, 'batch.json'), 'w'); fwrite(fid, jsonencode(struct('mode', 'Batch', 'status', 'DONE'))); fclose(fid);
pairs = {'sub-01', 'sub-01_rest.mat'; 'sub-13', 'sub-13_rest_a.mat'};
rows = {};
for i = 1:2
    for task = ["rest", "msit"]
        A = load(fullfile(workDir, pairs{i, 2}));
        A.info.task = task;
        f = fullfile(workDir, sprintf('%s_%s_src.mat', pairs{i, 1}, task));
        save(f, '-struct', 'A');
        id = sprintf('%s_%s', pairs{i, 1}, task);
        fid = fopen(fullfile(src, 'state', [id '.json']), 'w');
        fwrite(fid, jsonencode(struct('status', 'verified', 'canonical', struct('path', f, 'sha256', sha256File(f))))); fclose(fid);
        rows(end+1, :) = {pairs{i, 1}, char(task), 'unchanged', 5, 45}; %#ok<AGROW>
    end
end
bt = fullfile(workDir, 'asm_blocks.csv');
writetable(cell2table(rows, 'VariableNames', {'subject', 'task', 'status', 'new_start_s', 'new_end_s'}), bt);
params = struct('sourceBatchDir', src, 'blockTable', bt, 'rawRoot', fullfile(workDir, 'raw'), 'manifest', fullfile(workDir, 'manifest.tsv'));
out = fullfile(workDir, 'd4e4_asm.mat');
stage3_d4e4_assemble(params, out);
R = load(out);
dec = R.nDecisions(R.nDecisions.subject == "sub-13" & R.nDecisions.k == 6 & R.nDecisions.reference == "A", :);
c1 = ok0 && height(dec) == 1 && dec.outcome == "H_tsv supported";
fprintf('sub-13 k=6 reference A: %s -> %d\n', dec.outcome, c1);
pc = R.predByChannel(R.predByChannel.subject == "sub-01" & R.predByChannel.task == "rest", :);
pp = R.nearPerfectPredictors;
ct = readtable(labelsTsv, 'FileType', 'text', 'Delimiter', '\t', 'TextType', 'string');
c2 = pc.near_perfect(pc.label_tsv == ct.name(50)) == 1;                        % raw channel 50 (interpolated)
s01 = pp(pp.subject == "sub-01", :);
c3 = height(s01) > 0 && all(~isnan(s01.n_top6_among_6_nearest)) && all(s01.position_source == "bvef");
fprintf('sub-01 channel 50 near-perfect: %d; sub-01 neighbour counts from .bvef %s: %d\n', c2, mat2str(s01.n_top6_among_6_nearest'), c3);
tampered = fullfile(workDir, 'sub-13_msit_src.mat'); fid = fopen(tampered, 'a'); fwrite(fid, uint8(1)); fclose(fid);
refused = false;
try, stage3_d4e4_assemble(params, fullfile(workDir, 'x.mat')); catch ME, refused = contains(ME.message, 'SHA-256'); end
exp = fullfile(workDir, 'export');
stage3_d4e4_export(out, sha256File(out), exp, 'synthetic');
names = {'neighbour_scores.csv', 'rank_predictability_by_recording.csv', 'predictability_by_channel.csv', ...
         'test_n_by_recording.csv', 'test_n_decisions.csv', 'near_perfect_predictors.csv', 'run_info.txt'};
c4 = all(cellfun(@(n) exist(fullfile(exp, n), 'file') == 2, names));
noOver = false; try, stage3_d4e4_export(out, sha256File(out), exp, 'synthetic'); catch, noOver = true; end
fprintf('tampered input refused: %d; export files: %d; no overwrite: %d\n', refused, c4, noOver);
ok = c1 && c2 && c3 && refused && c4 && noOver;
if ok, fprintf('D4E4 ASSEMBLY PASS\n'); else, fprintf('D4E4 ASSEMBLY FAIL\n'); end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); x = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(typecast(x, 'int8'));
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
