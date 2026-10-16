function S = stage3_params()
%STAGE3_PARAMS  Approved Stage 3 preprocessing parameters (single source; see docs/decision_log.md).
%   S = stage3_params() returns a struct. Every field cites the decision that fixed it.
%   The pipeline and the Stage 3 helper scripts read their settings from here only.

S.fsRaw  = 1000;   % Hz, raw sampling rate (all 84 .vhdr: SamplingInterval = 1000 us; S3a-D4e)
S.fsOut  = 500;    % Hz, target rate (S3a-D1)
S.hpEdge = 0.5;    % Hz, high-pass passband edge, pop_eegfiltnew defaults, applied at fsRaw (S3a-D4a)
S.lineFreqs = [50 100 150 200];   % Hz, line frequencies F_L (S3a-D4b, S3a-D5-opt (i-1))
S.notchA = 3;      % Hz, D5 = option (a): pop_eegfiltnew band-stop f0 +/- notchA, revfilt 1, default design,
                   % at fsOut, one filter per f0 in cascade (S3a-D5-final; width S3a-D5a-width)
% S3a-D4c order: high-pass (fsRaw) -> resample (fsOut) -> line noise (D5) -> crop (D3, D3e).
% S3a-D4e: H = sum of the half-lengths of every filter applied before cropping;
% computed by stage3_filter_halflengths(S), never hard-coded.
end
