function T = r1_phase2_synth_generate(P, seed)
%R1_PHASE2_SYNTH_GENERATE Synthetic first-in-mini-block trial table for the K1.7 validation (decision log §11l).
%   The outcome is generated from the variables r1_phase2_prepare builds, so M1 is correctly specified.
rng(seed, 'twister');
conds = ["00", "S0", "F0", "FS"]; nc = [-1 0 0 1];
nT = 4 * P.nPer; rowsAll = cell(P.nS, 1);
for i = 1:P.nS
    v0 = P.sd_v0 * randn; va = P.sd_va * randn; mb = P.b0 + P.sd_base_subj * randn;
    ci = repelem(1:4, P.nPer)'; ci = ci(randperm(nT));
    ecell = P.sd_cell * randn(4, 1);
    lrt = P.r0 + v0 + (P.a + va) * nc(ci)' + ecell(ci) + P.sd_trial * randn(nT, 1);
    base = mb + P.sd_base_trial * randn(nT, 1);
    R = table();
    R.subject = repmat("s" + i, nT, 1); R.cond = conds(ci)';
    R.trial_index = sort(randperm(P.nSession, nT))'; R.mb_pos = ones(nT, 1); R.correct = true(nT, 1);
    R.rt_ms = 1000 * exp(lrt); R.baseline_power = 10 .^ base; R.active_power = ones(nT, 1);
    R.u0 = repmat(P.sd_u0 * randn, nT, 1); R.uc = repmat(P.sd_uc * randn, nT, 1); R.ub = repmat(P.sd_ub * randn, nT, 1);
    rowsAll{i} = R;
end
T = vertcat(rowsAll{:});
D = r1_phase2_prepare(T);                     % the model variables, built exactly as for real data
y = P.b0 + T.u0 + (P.cp + T.uc) .* D.nconf_c + P.gamma * log10(T.baseline_power) + P.delta * D.order_z ...
    + (P.b + T.ub) .* D.rt_w + P.b * D.rt_cm + P.sd_res * randn(height(T), 1);
T.active_power = 10 .^ y;
T = removevars(T, {'u0', 'uc', 'ub'});
end
