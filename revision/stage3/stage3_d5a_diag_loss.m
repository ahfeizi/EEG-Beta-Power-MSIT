function T = stage3_d5a_diag_loss(outDir)
%STAGE3_D5A_DIAG_LOSS  Stimulus loss per notch setting a (S3a-D5a-diag (c)). Reads, for a = 2..6, the
%   outputs of stage3_raw_boundaries_d4e.py in <outDir>/notch_a<a>/ (run on the filter_halflengths.csv
%   written there by stage3_d5a_diag) and writes <outDir>/notch_loss.csv (refuses to overwrite).

f = fullfile(outDir, 'notch_loss.csv');
assert(exist(f, 'file') ~= 2, 'refusing to overwrite %s', f);
rows = {};
for a = 2:6
    nd = fullfile(outDir, sprintf('notch_a%d', a));
    H = sum(readtable(fullfile(nd, 'filter_halflengths.csv')).half_s);
    C = readtable(fullfile(nd, 'd4e_block_clipping.csv'), 'TextType', 'string');
    L = readtable(fullfile(nd, 'd4e_lost_stimuli.csv'), 'TextType', 'string');
    nStop = sum(startsWith(C.status, "STOP"));
    rows{end+1} = table(a, H, height(C), sum(C.status == "CLIPPED"), nStop, height(L), sum(L.block_first == 1), ...
        sum(L.first_in_miniblock == 1), numel(unique(L.subject)), 'VariableNames', {'a_hz', 'H_s', 'n_blocks', ...
        'n_blocks_clipped', 'n_blocks_stop', 'n_stimuli_lost', 'n_lost_block_first', 'n_lost_first_in_miniblock', ...
        'n_subjects'}); %#ok<AGROW>
end
T = vertcat(rows{:});
writetable(T, f);
disp(T);
end
