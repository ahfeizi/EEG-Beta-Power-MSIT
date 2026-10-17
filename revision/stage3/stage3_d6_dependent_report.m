function T = stage3_d6_dependent_report(predTable, nppTable, outFile)
%STAGE3_D6_DEPENDENT_REPORT  Descriptive report for the dependent channels of S3a-D6-amend1 (does not change
%   the rule). For every channel-recording with 1 - R^2 < S.d6.r2Thr in predTable (test P,
%   predictability_by_channel.csv; channels.tsv labels), the predictor check of test P from nppTable
%   (near_perfect_predictors.csv): the 6 largest standardised predictors and how many of them are among
%   the channel's 6 nearest sites (adjacent electrodes: possible gel bridges). sub-42 is left out
%   (excluded, S3a-D6). For sub-13/41 the channels.tsv labelling is used. Writes outFile (never overwrites).

here = fileparts(mfilename('fullpath')); addpath(here);
S = stage3_params();
assert(exist(outFile, 'file') ~= 2, 'refusing to overwrite %s', outFile);
P = readtable(predTable, 'FileType', 'text', 'Delimiter', ',', 'ReadVariableNames', true, 'TextType', 'string');
N = readtable(nppTable, 'FileType', 'text', 'Delimiter', ',', 'ReadVariableNames', true, 'TextType', 'string');   % ';' inside cells
P = P(P.one_minus_r2 < S.d6.r2Thr & P.subject ~= "sub-42", :);
if ismember('labelling', N.Properties.VariableNames)
    N = N(ismissing(N.labelling) | N.labelling == "" | N.labelling == "tsv", :);
end
n = height(P); top = strings(n, 1); nAdj = nan(n, 1); src = strings(n, 1);
for k = 1:n
    r = N(N.subject == P.subject(k) & N.task == P.task(k) & N.label == P.label_tsv(k), :);
    assert(height(r) == 1, '%s %s %s: %d predictor rows', P.subject(k), P.task(k), P.label_tsv(k), height(r));
    top(k) = r.top6_predictors; nAdj(k) = r.n_top6_among_6_nearest; src(k) = r.position_source;
end
T = table(P.subject, P.task, P.label_tsv, P.one_minus_r2, top, nAdj, src, 'VariableNames', ...
    {'subject', 'task', 'label', 'one_minus_r2', 'top6_predictors', 'n_top6_among_6_nearest', 'position_source'});
T = sortrows(T, {'subject', 'task', 'label'});
writetable(T, outFile);
G = groupsummary(T, 'subject', {'min', 'max'}, 'n_top6_among_6_nearest');
disp(G);
fprintf('%d channel-recordings in %d subjects; n_top6_among_6_nearest: 0 in %d, >= 3 in %d\n', height(T), ...
    numel(unique(T.subject)), sum(T.n_top6_among_6_nearest == 0), sum(T.n_top6_among_6_nearest >= 3));
end
