%% Stage 2, pass 1 (decision S2-1): compare rerun outputs with the original v1 files
% For every expected output of the rerun legacy scripts:
%   (i)   SHA-256 vs the original v1 file in derivRoot / taskDeriv (primary reference:
%         the true as-run bytes)
%   (ii)  SHA-256 vs legacy_v1/derivatives/ (CSVs only; stored byte-for-byte)
%   (iii) if (i) differs: CSV -> line-ending-insensitive comparison, then cell by cell
%         (numeric: max absolute and relative difference; text: exact);
%         PNG -> pixel comparison
% Verdicts (decision S2-1):
%   IDENTICAL            byte-identical to the original
%   FORMAT_OR_FP_ONLY    only line endings differ, or numeric differences <= 1e-10 relative
%   DIFFERENT            larger numeric difference, or different rows/columns/text
%   MISSING              the rerun produced no such file
% Output: <outRoot>/stage2/pass1_comparison.csv

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(repoRoot);
P = get_paths();
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');
outDir   = fullfile(P.outRoot, 'stage2');
legDeriv = fullfile(repoRoot, 'legacy_v1', 'derivatives');
relTol   = 1e-10;

% {file, location of the original ('rest' = derivRoot, 'msit' = taskDeriv), producing script}
expected = {
    'beta_avgpower_per_channel.csv',                    'rest', 'extract_beta_avgpower_per_channel'
    'beta_avgpower_heatmap_subject_x_channel.png',      'rest', 'extract_beta_avgpower_per_channel'
    'rest_control_band_power.csv',                      'rest', 'control_band_55_95_power_RS'
    'beta_distinct_channels_stats.csv',                 'rest', 'beta_channel_stats_emg_test'
    'beta_emg_contamination_test.csv',                  'rest', 'beta_channel_stats_emg_test'
    'beta_power_effect_sizes_rankbiserial.csv',         'msit', 'effect_size_rankbiserial'
    'Table2_with_effect_sizes.csv',                     'msit', 'effect_size_rankbiserial'
    'control_band_TOST_equivalence.csv',                'msit', 'tost_control_band_equivalence'
    'fig_control_band_TOST.png',                        'msit', 'tost_control_band_equivalence'
    'prestim_beta_conflict_specificity.csv',            'msit', 'conflict_specificity_prestim_beta'
    'fig_prestim_conflict_specificity.png',             'msit', 'conflict_specificity_prestim_beta'
    'trial_counts_per_condition.csv',                   'msit', 'trial_counts_per_condition'
    'nearEdge_sensitivity_analysis.csv',                'rest', 'sensitivity_nearedge_threshold'
    'fig_nearEdge_threshold_sensitivity.png',           'rest', 'sensitivity_nearedge_threshold'
    'msit_beta_condition_comparison_summary.csv',       'msit', 'statComparison_beta_power_MSIT_4Conds'
    'fig3_rest_vs_task_beta_and_control_CORRECTED.png', 'msit', 'figure3_corrected'
    };

rows = cell(size(expected, 1), 1);
for k = 1:size(expected, 1)
    [fname, loc, scr] = expected{k, :};
    if strcmp(loc, 'rest'), origDir = P.derivRoot; else, origDir = P.taskDeriv; end
    newF  = fullfile(rerunDir, fname);
    origF = fullfile(origDir, fname);
    legF  = fullfile(legDeriv, fname);
    [isCsv, sameLeg, nDiffCells, maxAbs, maxRel, detail] = deal(endsWith(fname, '.csv'), "", NaN, NaN, NaN, "");

    if ~isfile(newF)
        verdict = "MISSING"; sameOrig = "";
    else
        sameOrig = string(sha256(newF) == sha256(origF));
        if isCsv && isfile(legF), sameLeg = string(sha256(newF) == sha256(legF)); end
        if sameOrig == "true"
            verdict = "IDENTICAL";
        elseif isCsv
            [verdict, nDiffCells, maxAbs, maxRel, detail] = compare_csv(newF, origF, relTol);
        else
            [verdict, detail] = compare_png(newF, origF);
        end
    end
    rows{k} = table(string(scr), string(fname), string(verdict), sameOrig, sameLeg, ...
        nDiffCells, maxAbs, maxRel, string(detail), ...
        'VariableNames', {'script','file','verdict','sha256_equals_original', ...
        'sha256_equals_legacy_v1_derivatives','nDifferingCells','maxAbsDiff','maxRelDiff','detail'});
end
T = vertcat(rows{:});
writetable(T, fullfile(outDir, 'pass1_comparison.csv'));
disp(T(:, {'script','file','verdict','nDifferingCells','maxRelDiff','detail'}))
fprintf('Saved -> %s\n', fullfile(outDir, 'pass1_comparison.csv'));


function h = sha256(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r'); bytes = fread(fid, Inf, '*uint8'); fclose(fid);
md.update(bytes);
h = string(lower(reshape(dec2hex(typecast(md.digest(), 'uint8'))', 1, [])));
end

function [verdict, nDiff, maxAbs, maxRel, detail] = compare_csv(newF, origF, relTol)
nDiff = NaN; maxAbs = NaN; maxRel = NaN;
a = strrep(fileread(newF), sprintf('\r'), '');
b = strrep(fileread(origF), sprintf('\r'), '');
if strcmp(a, b)
    verdict = "FORMAT_OR_FP_ONLY"; detail = "line endings only"; nDiff = 0; return
end
A = readcell(newF, 'Delimiter', ',');
B = readcell(origF, 'Delimiter', ',');
if ~isequal(size(A), size(B))
    verdict = "DIFFERENT"; detail = sprintf('shape %s vs %s', mat2str(size(A)), mat2str(size(B))); return
end
nDiff = 0; maxAbs = 0; maxRel = 0; textDiff = 0;
for i = 1:numel(A)
    x = A{i}; y = B{i};
    if isa(x, 'missing') && isa(y, 'missing'), continue; end   % empty cell in both (isequal(missing,missing) is false)
    if isnumeric(x) && isnumeric(y)
        if isnan(x) && isnan(y), continue; end
        d = abs(double(x) - double(y));
        if d > 0
            nDiff = nDiff + 1;
            r = d / max(abs(double(x)), abs(double(y)));
            maxAbs = max(maxAbs, d); maxRel = max(maxRel, r);
        end
    elseif ~isequal(x, y)
        nDiff = nDiff + 1; textDiff = textDiff + 1;
    end
end
if textDiff == 0 && maxRel <= relTol
    verdict = "FORMAT_OR_FP_ONLY"; detail = sprintf('%d numeric cells differ, all <= %g relative', nDiff, relTol);
else
    verdict = "DIFFERENT"; detail = sprintf('%d cells differ (%d text)', nDiff, textDiff);
end
end

function [verdict, detail] = compare_png(newF, origF)
A = imread(newF); B = imread(origF);
if ~isequal(size(A), size(B))
    verdict = "DIFFERENT"; detail = sprintf('image size %s vs %s', mat2str(size(A)), mat2str(size(B))); return
end
d = abs(double(A) - double(B));
if max(d(:)) == 0
    verdict = "FORMAT_OR_FP_ONLY"; detail = "pixel-identical (file bytes differ)";
else
    verdict = "DIFFERENT"; detail = sprintf('%d pixel values differ, max %d', nnz(d), max(d(:)));
end
end
