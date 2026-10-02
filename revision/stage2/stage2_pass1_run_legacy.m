%% Stage 2, pass 1 (decision S2-1): rerun legacy_v1 scripts UNCHANGED, then compare outputs
% Each legacy script runs in its own workspace (run_one below) and writes to
% <outRoot>/legacy_v1_rerun/ (its own rerunDir). Inputs are read from the v1
% derivatives (read-only), so every script is tested link by link against the
% exact v1 inputs it used. Then stage2_pass1_compare runs.
%
% Output: <outRoot>/stage2/pass1_run_log.csv (one row per script: ok / error, seconds)

repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % revision/stage2/<this> -> repository root
addpath(repoRoot);
P = get_paths();
outDir = fullfile(P.outRoot, 'stage2');
if ~exist(outDir, 'dir'), mkdir(outDir); end

scripts = {
    'feature_extraction/extract_beta_avgpower_per_channel.m'   % .set -> rest beta power (Table 2, Fig 3)
    'feature_extraction/control_band_55_95_power_RS.m'         % .set -> rest control-band power
    'statistics/beta_channel_stats_emg_test.m'                 % channel screening + EMG test
    'statistics/effect_size_rankbiserial.m'                    % Table 2 beta
    'statistics/tost_control_band_equivalence.m'               % Table 2 control band + S1
    'statistics/conflict_specificity_prestim_beta.m'           % conflict stats + S3
    'statistics/trial_counts_per_condition.m'                  % trial counts
    'statistics/sensitivity_nearedge_threshold.m'              % Table 1 counts + S2
    'exploratory/statComparison_beta_power_MSIT_4Conds.m'      % whole-epoch Friedman (finding B)
    'figures/figure3_corrected.m'                              % Figure 3
    };

logRows = cell(numel(scripts), 1);
for k = 1:numel(scripts)
    f = fullfile(repoRoot, 'legacy_v1', scripts{k});
    fprintf('\n===== [%d/%d] %s =====\n', k, numel(scripts), scripts{k});
    [ok, msg, secs] = run_one(f);
    logRows{k} = table(string(scripts{k}), ok, string(msg), secs, ...
        'VariableNames', {'script','ok','error','seconds'});
    close all force
end
logT = vertcat(logRows{:});
writetable(logT, fullfile(outDir, 'pass1_run_log.csv'));
disp(logT)

stage2_pass1_compare;   % comparison against the original v1 files


function [ok, msg, secs] = run_one(scriptPath)
% Runs one script in this function's own workspace, so scripts cannot see each other's variables.
t = tic; ok = true; msg = "";
try
    run(scriptPath);
catch ME
    ok = false; msg = string(ME.message);
    fprintf(2, 'FAILED: %s\n', ME.message);
end
secs = toc(t);
end
