function K = r1_phase2_k3(D, covariates, opts)
%R1_PHASE2_K3 The decided K3(a) comparison (decision log §11k): M0 without RT, M1 with the K1.4(c) RT terms,
%   and the labelled non-Bauer product-of-coefficients bootstrap.
%   K = r1_phase2_k3(D, covariates, opts)
%   D           table from r1_phase2_prepare (already restricted to the analysed trials)
%   covariates  cellstr of covariates besides conflict, e.g. {'base_c','order_z'} (primary, K1.3(a)/K1.5);
%               {'base_c','order_z','mb_pos'} for the later-trials model
%   opts        dataKind (required), forceFail (synthetic only), B (bootstrap resamples, default 1000),
%               seed (default 20261117), conflictTerm (default 'nconf_c')
%   M0:  y   ~ conflict + covariates                 + (1 + conflict | subject)          drop: conflict
%   M1:  y   ~ conflict + covariates + rt_w + rt_cm  + (1 + conflict + rt_w | subject)   drop: rt_w, conflict
%   a:   lrt ~ conflict + covariates                 + (1 + conflict | subject)          drop: conflict
%   Reported (K3(a), descriptive, no categories): beta0, beta1 with Satterthwaite 95 % CIs, beta1 - beta0, the
%   within-cell RT slope b, and a*b with a participant-cluster percentile bootstrap CI. a*b omits the covariance
%   of random a and b slopes, so it is NOT the Bauer, Preacher & Gil (2006) indirect effect.
if ~isfield(opts, 'B'), opts.B = 1000; end
if ~isfield(opts, 'seed'), opts.seed = 20261117; end
if ~isfield(opts, 'conflictTerm'), opts.conflictTerm = 'nconf_c'; end
if ~isfield(opts, 'forceFail'), opts.forceFail = []; end
c = opts.conflictTerm;
fo = struct('dataKind', opts.dataKind, 'forceFail', opts.forceFail);

K.M0 = r1_phase2_fit(D, 'y', [{c}, covariates], {c}, {c}, fo);
K.M1 = r1_phase2_fit(D, 'y', [{c}, covariates, {'rt_w', 'rt_cm'}], {c, 'rt_w'}, {'rt_w', c}, fo);
K.A  = r1_phase2_fit(D, 'lrt', [{c}, covariates], {c}, {c}, fo);

K.beta0 = coefRow(K.M0.coef, c);
K.beta1 = coefRow(K.M1.coef, c);
K.b_rtw = coefRow(K.M1.coef, 'rt_w');
K.b_rtcm = coefRow(K.M1.coef, 'rt_cm');
K.a = coefRow(K.A.coef, c);
K.diff = K.beta1.Estimate - K.beta0.Estimate;
K.ab = K.a.Estimate * K.b_rtw.Estimate;

% participant-cluster bootstrap of a*b: each resample is estimated by the whole procedure, i.e. the full K1.6(a)
% simplification ladder of r1_phase2_fit runs inside every resample (§11l amendment 2), so the structure is chosen
% per resample, as in the main fits. The intercept-only warning is recorded per resample, not printed.
K.ab_boot = nan(opts.B, 1);
K.boot_failed = 0;
K.boot_level_A = nan(opts.B, 1);
K.boot_level_M1 = nan(opts.B, 1);
K.boot_fail_msgs = {};
if opts.B > 0
    rng(opts.seed, 'twister');
    subs = categories(D.subject);
    nS = numel(subs);
    rows = arrayfun(@(k) find(D.subject == subs{k}), 1:nS, 'UniformOutput', false);
    fb = struct('dataKind', opts.dataKind);       % no test hook inside the bootstrap
    wstate = warning('off', 'r1:interceptOnly');
    for r = 1:opts.B
        pick = randi(nS, nS, 1);
        parts = cell(nS, 1);
        for k = 1:nS
            P = D(rows{pick(k)}, :);
            P.subject = repmat(categorical("b" + k), height(P), 1);   % a drawn twice counts as two participants
            parts{k} = P;
        end
        Db = vertcat(parts{:});
        Db.subject = removecats(Db.subject);
        try
            Ab = r1_phase2_fit(Db, 'lrt', [{c}, covariates], {c}, {c}, fb);
            Mb = r1_phase2_fit(Db, 'y', [{c}, covariates, {'rt_w', 'rt_cm'}], {c, 'rt_w'}, {'rt_w', c}, fb);
            K.ab_boot(r) = coefRow(Ab.coef, c).Estimate * coefRow(Mb.coef, 'rt_w').Estimate;
            K.boot_level_A(r) = Ab.level;
            K.boot_level_M1(r) = Mb.level;
        catch ME
            K.boot_failed = K.boot_failed + 1;
            K.boot_fail_msgs{end + 1} = ME.message;
        end
    end
    warning(wstate);
    ok = ~isnan(K.ab_boot);
    K.ab_ci = prctile(K.ab_boot(ok), [2.5 97.5]);
    K.boot_n_ok = nnz(ok);
else
    K.ab_ci = [NaN NaN];
    K.boot_n_ok = 0;
end
K.label_ab = 'a*b: product of fixed effects, participant bootstrap; NOT the Bauer et al. (2006) estimator';
end


function r = coefRow(st, name)
i = find(strcmp(string(st.Name), name));
assert(numel(i) == 1, 'r1:k3', 'term %s not found', name);
r = st(i, :);
end
