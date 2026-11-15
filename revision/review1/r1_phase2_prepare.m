function D = r1_phase2_prepare(T)
%R1_PHASE2_PREPARE Build the Phase 2 model variables from a trial table (decision log §11k, K1).
%   D = r1_phase2_prepare(T)
%   T: one row per trial of the analysed set, with columns
%     subject (string/char/categorical), cond ('00','S0','F0','FS'), active_power, baseline_power (linear,
%     uV^2/Hz, 13-30 Hz ROI band power), rt_ms, trial_index (position in the session), mb_pos (1-4, position
%     within the mini-block), correct (logical).
%   The same function is used for synthetic and real data, so the validation exercises the real code path.
%   Variables built (all from the rows of T only, so a subset such as first-in-mini-block trials is centred on
%   itself):
%     y        log10 active-window band power                                   (K1.1 outcome)
%     base_c   log10 baseline band power, centred at its grand mean             (K1.3 covariate)
%     nconf_c  number of conflict sources (00 = 0, S0/F0 = 1, FS = 2) minus 1, i.e. -1/0/1   (K1.2(a), K1.6)
%     simon, flanker   0/1 indicators for the 2 x 2 secondary coding         (K1.2(c))
%     lrt      natural log of RT in seconds (transform: Claude's call, logged in the validation report)
%     rt_cm    participant x condition cell mean of lrt, centred at the grand mean of the cell means (K1.4(c))
%     rt_w     lrt minus its cell mean: the within-cell deviation, zero mean in every cell        (K1.4(c))
%     order_z  trial_index z-scored within participant                           (K1.5)
%     mb_pos   carried as a categorical-free numeric covariate for the later-trials model (K1.3)
%     acc      double(correct), for the K4a model
assert(all(ismember({'subject','cond','active_power','baseline_power','rt_ms','trial_index','mb_pos','correct'}, ...
    T.Properties.VariableNames)), 'r1:prep', 'missing columns');
assert(all(T.active_power > 0) && all(T.baseline_power > 0), 'r1:prep', 'non-positive band power');
assert(all(T.rt_ms > 0), 'r1:prep', 'non-positive RT');
cond = string(T.cond);
assert(all(ismember(cond, ["00","S0","F0","FS"])), 'r1:prep', 'unexpected condition label');

D = table();
D.subject = categorical(string(T.subject));
D.cond = categorical(cond, ["00","S0","F0","FS"]);
D.y = log10(T.active_power);
lb = log10(T.baseline_power);
D.base_c = lb - mean(lb);
n = zeros(height(T), 1);
n(cond == "S0" | cond == "F0") = 1;
n(cond == "FS") = 2;
D.nconf_c = n - 1;
D.simon = double(cond == "S0" | cond == "FS");
D.flanker = double(cond == "F0" | cond == "FS");
D.lrt = log(T.rt_ms / 1000);
[g, ~, ~] = findgroups(D.subject, D.cond);
cm = splitapply(@mean, D.lrt, g);
D.rt_cm_raw = cm(g);
D.rt_w = D.lrt - D.rt_cm_raw;
D.rt_cm = D.rt_cm_raw - mean(cm);
gs = findgroups(D.subject);
mu = splitapply(@mean, T.trial_index, gs);
sd = splitapply(@std, T.trial_index, gs);
assert(all(sd > 0), 'r1:prep', 'a participant has a single trial');
D.order_z = (T.trial_index - mu(gs)) ./ sd(gs);
D.mb_pos = double(T.mb_pos);
D.acc = double(T.correct);
D.rt_ms = double(T.rt_ms);

% construction checks: centring and coding are exactly as specified
assert(all(ismember(D.nconf_c, [-1 0 1])), 'r1:prep', 'conflict coding');
assert(max(abs(splitapply(@mean, D.rt_w, g))) < 1e-12, 'r1:prep', 'within-cell RT deviation not centred');
end
