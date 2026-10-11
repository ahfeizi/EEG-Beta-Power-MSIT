function stage3_d4e4_assemble(params, outFile)
%STAGE3_D4E4_ASSEMBLE  S3a-D4e-4-test decision rules from the canonical outputs of a verified D4e-4
%   batch (S3a-D4e-4-asm), as a runner job function. params: sourceBatchDir, blockTable, rawRoot,
%   manifest (common). Reads only canonical out.mat files (each hash-checked against its state file)
%   and, for the test P predictor check, the subjects' .bvct (checked against the manifest).
%
%   Test N (sub-13, sub-41, sub-42), per k in {4, 6, 8} (k = 6 primary):
%     reference A (primary): s(U) over unaffected labels none of whose k neighbours is affected; for
%       these s_vhdr(U) == s_tsv(U) (asserted), as the entry states for the reference;
%     reference B (sensitivity): s_H(U) over all unaffected labels, under each H separately;
%     p5 = prctile(reference, 5) (MATLAB default method);
%     H meets the rule in a recording if (i) every affected label has s_H(L) >= p5 and (ii) under the
%       other hypothesis at least one affected label has s(L) < p5;
%     per subject: H supported if exactly one H meets the rule in both rest and MSIT+; otherwise ambiguous.
%   Test P (84 recordings): smallest 5 eigenvalues (dB re median), deficient dimensions (< -60 dB),
%     average-reference ratio (max over chunks; exported average-referenced if all < 1e-4),
%     near-perfectly predicted channels (1 - R^2 < 1e-4) with their 6 largest standardised weights
%     and how many of those predictors are among the channel's 6 nearest labels (subject's .bvct;
%     NaN for subjects without a .bvct, decision pending); sub-13/41/42 under both labellings.
%   OUTCOME-BLIND: only the stored 1-10 Hz time-domain statistics are read.

here = fileparts(mfilename('fullpath'));
addpath(here);
srcDir = char(params.sourceBatchDir);
batch = jsondecode(fileread(fullfile(srcDir, 'batch.json')));
assert(strcmp(batch.mode, 'Batch') && strcmp(batch.status, 'DONE'), 'source batch is not a finished Batch-mode run');
B = readtable(char(params.blockTable), 'TextType', 'string');
recs = unique(B.subject + "_" + B.task, 'stable');
assert(numel(dir(fullfile(srcDir, 'state', '*.json'))) == numel(recs), 'state files and block table differ');
kList = [4 6 8];
L = cell(numel(recs), 1); srcSha = strings(numel(recs), 1);
for r = 1:numel(recs)
    st = jsondecode(fileread(fullfile(srcDir, 'state', char(recs(r) + ".json"))));
    assert(strcmp(st.status, 'verified'), '%s: status %s', recs(r), st.status);
    assert(strcmp(sha256File(st.canonical.path), st.canonical.sha256), '%s: canonical output does not match its SHA-256', recs(r));
    L{r} = load(st.canonical.path); srcSha(r) = string(st.canonical.sha256);
end
sources = table(recs, srcSha, 'VariableNames', {'recording', 'sha256'});
isN = cellfun(@(x) logical(x.info.testN), L);
nSubjects = unique(string(cellfun(@(x) char(x.info.subject), L(isN), 'uni', 0)), 'stable')';   % sub-13/41/42 in the real batch

% ---- test N --------------------------------------------------------------------------------
NS = {}; ND = {};
for s = nSubjects
    meets = struct();
    for task = ["rest", "msit"]
        A = L{recs == s + "_" + task};
        R = A.Nres; aff = find(R.affected); nL = numel(R.labels);
        for kk = 1:numel(kList)
            k = kList(kk);
            nbAff = any(ismember(R.neighbours(:, 1:k), aff), 2);
            refA = ~R.affected & ~nbAff;
            assert(isequal(R.sVhdr(refA, kk), R.sTsv(refA, kk)), 'reference A not identical under both hypotheses');
            refB = ~R.affected;
            p5A = prctile(R.sTsv(refA, kk), 5);
            p5BV = prctile(R.sVhdr(refB, kk), 5); p5BT = prctile(R.sTsv(refB, kk), 5);
            mA = [all(R.sVhdr(aff, kk) >= p5A) && any(R.sTsv(aff, kk) < p5A), ...
                  all(R.sTsv(aff, kk) >= p5A) && any(R.sVhdr(aff, kk) < p5A)];          % [vhdr tsv]
            mB = [all(R.sVhdr(aff, kk) >= p5BV) && any(R.sTsv(aff, kk) < p5BT), ...
                  all(R.sTsv(aff, kk) >= p5BT) && any(R.sVhdr(aff, kk) < p5BV)];
            meets.(char(task)).A(kk, :) = mA; meets.(char(task)).B(kk, :) = mB;
            NS{end+1} = table(repmat(s, nL, 1), repmat(task, nL, 1), repmat(k, nL, 1), R.labels, ...
                double(R.affected), double(refA), R.sVhdr(:, kk), R.sTsv(:, kk), repmat(p5A, nL, 1), ...
                repmat(p5BV, nL, 1), repmat(p5BT, nL, 1), 'VariableNames', {'subject', 'task', 'k', 'label', ...
                'affected', 'in_reference_A', 's_vhdr', 's_tsv', 'p5_ref_A', 'p5_ref_B_vhdr', 'p5_ref_B_tsv'}); %#ok<AGROW>
            ND{end+1} = table(s, task, k, numel(aff), sum(refA), p5A, min(R.sVhdr(aff, kk)), min(R.sTsv(aff, kk)), ...
                sum(R.sVhdr(aff, kk) < p5A), sum(R.sTsv(aff, kk) < p5A), mA(1), mA(2), mB(1), mB(2), ...
                'VariableNames', {'subject', 'task', 'k', 'n_affected', 'n_reference_A', 'p5_ref_A', ...
                'min_s_vhdr_affected', 'min_s_tsv_affected', 'n_affected_below_p5_vhdr', 'n_affected_below_p5_tsv', ...
                'refA_vhdr_meets', 'refA_tsv_meets', 'refB_vhdr_meets', 'refB_tsv_meets'}); %#ok<AGROW>
        end
    end
end
neighbourScores = vertcat(NS{:}); nByRecording = vertcat(ND{:});
D = {};
for s = nSubjects
    for kk = 1:numel(kList)
        for ref = ["A", "B"]
            sub = nByRecording(nByRecording.subject == s & nByRecording.k == kList(kk), :);
            mr = [sub{sub.task == "rest", "ref" + ref + "_vhdr_meets"}, sub{sub.task == "rest", "ref" + ref + "_tsv_meets"}];
            mm = [sub{sub.task == "msit", "ref" + ref + "_vhdr_meets"}, sub{sub.task == "msit", "ref" + ref + "_tsv_meets"}];
            both = mr & mm;
            if isequal(both, [true false]) && isequal(mr, mm), out = "H_vhdr supported";
            elseif isequal(both, [false true]) && isequal(mr, mm), out = "H_tsv supported";
            else, out = "ambiguous"; end
            D{end+1} = table(s, kList(kk), ref, mr(1), mr(2), mm(1), mm(2), out, 'VariableNames', ...
                {'subject', 'k', 'reference', 'rest_vhdr_meets', 'rest_tsv_meets', 'msit_vhdr_meets', 'msit_tsv_meets', 'outcome'}); %#ok<AGROW>
        end
    end
end
nDecisions = vertcat(D{:});

% ---- test P --------------------------------------------------------------------------------
PR = {}; PC = {}; PP = {};
pos = containers.Map();
for r = 1:numel(recs)
    A = L{r}; I = A.info; P = A.P;
    s = I.subject; task = I.task;
    vlabK = I.vhdrLabels(I.keptColumns); tlabK = I.tsvLabels(I.keptColumns);
    nn = []; nnLabels = strings(0, 1);
    bv = fullfile(char(params.rawRoot), 'sourcedata', char(s), 'coords', [char(s) '_captrak.bvct']);
    if ~isKey(pos, char(s)) && exist(bv, 'file') == 2
        stage3_check_input(bv, char(params.rawRoot), params.manifest);
        [pn, pxyz] = readCapTrak(bv); pos(char(s)) = {pn, pxyz};
    end
    if isKey(pos, char(s))
        q = pos(char(s)); [okp, ip] = ismember(tlabK, q{1}); assert(all(okp));
        xyz = q{2}(ip, :);
        Dd = sqrt(sum((permute(xyz, [1 3 2]) - permute(xyz, [3 1 2])) .^ 2, 3)); Dd(logical(eye(numel(tlabK)))) = Inf;
        [~, o] = sort(Dd, 2, 'ascend'); nn = o(:, 1:6); nnLabels = tlabK;  % 6 nearest, as label indices into tlabK
    end
    npc = find(P.nearPerfect);
    PR{end+1} = table(s, task, numel(I.keptColumns), I.nChunk, P.nDeficient, P.eigRelDbSmallest5(:)', ...
        max(P.avgRefRatio125), double(P.exportedAvgRef125), max(P.avgRefRatio127), P.rcond, numel(npc), ...
        strjoin(tlabK(npc), ';'), double(ismember(s, nSubjects)), 'VariableNames', {'subject', 'task', 'n_channels', ...
        'n_chunks', 'n_deficient_lt_m60db', 'eig_rel_db_smallest5', 'avgref_ratio125_max', 'exported_avgref125', ...
        'avgref_ratio127_max_additional', 'rcond_cov', 'n_near_perfect', 'near_perfect_labels_tsv', 'labels_provisional'}); %#ok<AGROW>
    PC{end+1} = table(repmat(s, numel(tlabK), 1), repmat(task, numel(tlabK), 1), (1:numel(tlabK))', tlabK, vlabK, ...
        P.oneMinusR2, double(P.nearPerfect), 'VariableNames', {'subject', 'task', 'column', 'label_tsv', 'label_vhdr', ...
        'one_minus_r2', 'near_perfect'}); %#ok<AGROW>
    for c = npc(:)'
        for H = ["tsv", "vhdr"]
            if H == "vhdr" && ~ismember(s, nSubjects), continue; end
            lab = tlabK; if H == "vhdr", lab = vlabK; end
            predLab = lab(P.top6Col(c, :));
            nNb = NaN;
            if ~isempty(nn)
                ci = find(nnLabels == lab(c));
                nNb = sum(ismember(predLab, nnLabels(nn(ci, :))));
            end
            PP{end+1} = table(s, task, H, c, lab(c), P.oneMinusR2(c), strjoin(predLab, ';'), ...
                string(strjoin(compose('%.4f', P.top6W(c, :)), ';')), nNb, 'VariableNames', {'subject', 'task', 'labelling', ...
                'column', 'label', 'one_minus_r2', 'top6_predictors', 'top6_std_weights', 'n_top6_among_6_nearest'}); %#ok<AGROW>
        end
    end
end
rankByRecording = vertcat(PR{:}); predByChannel = vertcat(PC{:});
if isempty(PP), nearPerfectPredictors = table(); else, nearPerfectPredictors = vertcat(PP{:}); end
logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md');
entryHashes = strings(0, 1);
for id = ["S3a-D4e-4-test", "S3a-D4e-4-test-approval", "S3a-D4e-4-asm"]
    entryHashes(end+1, 1) = sprintf('SHA-256 of the %s log entry: %s', id, stage3_log_entry(logFile, char(id))); %#ok<AGROW>
end
sourceBatch = struct('dir', string(srcDir), 'batchJsonSha256', string(sha256File(fullfile(srcDir, 'batch.json'))));
save(outFile, 'neighbourScores', 'nByRecording', 'nDecisions', 'rankByRecording', 'predByChannel', ...
    'nearPerfectPredictors', 'entryHashes', 'sources', 'sourceBatch');
disp(nDecisions(nDecisions.k == 6, :));
end

function [names, xyz] = readCapTrak(f)
t = fileread(f);
blk = regexp(t, '<CapTrakElectrodeList>(.*?)</CapTrakElectrodeList>', 'tokens', 'once');
assert(~isempty(blk), 'no CapTrakElectrodeList in %s', f);
el = regexp(blk{1}, '<CapTrakElectrode>(.*?)</CapTrakElectrode>', 'tokens');
names = strings(numel(el), 1); xyz = nan(numel(el), 3); ax = 'XYZ';
for k = 1:numel(el)
    e = el{k}{1};
    names(k) = string(regexp(e, '<Name>([^<]*)</Name>', 'tokens', 'once'));
    for a = 1:3
        v = regexp(e, sprintf('<%s>([^<]*)</%s>', ax(a), ax(a)), 'tokens', 'once');
        xyz(k, a) = str2double(v{1});
    end
end
end

function h = sha256File(f)
md = java.security.MessageDigest.getInstance('SHA-256');
fid = fopen(f, 'r');
assert(fid > 0, 'cannot open %s', f);
c = onCleanup(@() fclose(fid));
while true
    x = fread(fid, 16 * 2^20, '*uint8');
    if isempty(x), break; end
    md.update(typecast(x, 'int8'));
end
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
