%% ---- trial-count summary per condition (for Conflict Specificity reporting) ----
% Addresses reviewer request: report the number of trials per condition
% (00, S0, F0, FS) that went into the pre-stimulus power averages used in
% the conflict-specificity (Friedman / Page's L) analysis, so statistical
% power can be assessed. Uses the nEpochs column already saved by
% msit_beta_erd_by_condition.m -- no new EEG processing needed.

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)
taskDeriv = P.taskDeriv;                                           % [path] v1 MSIT+ derivatives (read-only)
T = readtable(fullfile(taskDeriv, 'msit_beta_erd_by_condition.csv'));

conditions = {'00','S0','F0','FS'};
channels   = {'Fz','Cz','C4'};

fprintf('==== Trial counts per condition (nEpochs), pooled across channels ====\n');
fprintf('(nEpochs should be identical across channels for the same subject/condition,\n');
fprintf(' since it reflects how many MSIT+ trials of that type the subject completed)\n\n');

summary = table();
for k = 1:numel(conditions)
    rows = strcmp(T.condition, conditions{k}) & strcmp(T.channel, 'Fz');  % Fz as representative
    n = T.nEpochs(rows);
    fprintf('%s: mean=%.1f, SD=%.1f, range=[%d, %d], n subjects=%d\n', ...
        conditions{k}, mean(n), std(n), min(n), max(n), numel(n));
    summary = [summary; table(conditions(k), mean(n), std(n), min(n), max(n), numel(n), ...
        'VariableNames', {'condition','meanTrials','sdTrials','minTrials','maxTrials','nSubjects'})]; %#ok<AGROW>
end

disp(summary)
outFile = fullfile(rerunDir, 'trial_counts_per_condition.csv');   % [path]
writetable(summary, outFile);
fprintf('\nSaved -> %s\n', outFile);

% sanity check: confirm nEpochs is indeed identical across channels per subject/condition
fprintf('\n==== Sanity check: does nEpochs vary across channels for the same subject/condition? ====\n');
mismatch = 0;
subjects = unique(T.subject);
for s = 1:numel(subjects)
    for k = 1:numel(conditions)
        rows = strcmp(T.subject, subjects{s}) & strcmp(T.condition, conditions{k});
        vals = unique(T.nEpochs(rows));
        if numel(vals) > 1
            mismatch = mismatch + 1;
            fprintf('  MISMATCH: %s, %s -> nEpochs = %s\n', subjects{s}, conditions{k}, mat2str(vals'));
        end
    end
end
if mismatch == 0
    fprintf('  OK: nEpochs is consistent across channels for every subject/condition.\n');
else
    fprintf('  %d mismatches found -- investigate before reporting.\n', mismatch);
end
