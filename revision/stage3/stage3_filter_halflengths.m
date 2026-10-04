function [H, T] = stage3_filter_halflengths(S)
%STAGE3_FILTER_HALFLENGTHS  Filter-edge half-length H for decision S3a-D4e.
%   [H, T] = stage3_filter_halflengths(S) designs every filter that the pipeline applies to the
%   continuous data before cropping, with the installed EEGLAB code and the parameters in S
%   (from stage3_params), and returns:
%     T  one row per filter: name, design rate (Hz), order, half-length (samples at the design
%        rate) and half-length (s);
%     H  sum of the half-lengths (s). The filters run in cascade, so a sample is free of every
%        filter's edge padding only if it lies at least the SUM of the half-lengths from an edge.
%   No real data are used. D5 adds its filter(s) here, so H follows automatically.

if ~exist('pop_eegfiltnew', 'file'), eeglab('nogui'); end   % EEGLAB + plugins on the path

name = strings(0, 1); fsDesign = []; order = []; half = [];

% 1) High-pass (S3a-D4a) at fsRaw. pop_eegfiltnew returns the kernel b it applies; it is called
%    on a synthetic zero-valued dataset only to obtain b with the installed default design.
E = eeg_emptyset;
E.srate = S.fsRaw; E.nbchan = 1; E.trials = 1;
E.pnts = 120 * S.fsRaw;                           % 120 s: longer than any kernel considered here
E.data = zeros(1, E.pnts); E.xmin = 0; E.xmax = (E.pnts - 1) / E.srate;
E = eeg_checkset(E);
[~, ~, b] = pop_eegfiltnew(E, 'locutoff', S.hpEdge);
name(end+1, 1) = sprintf("high-pass %.3g Hz (pop_eegfiltnew)", S.hpEdge);
fsDesign(end+1, 1) = S.fsRaw; order(end+1, 1) = numel(b) - 1; half(end+1, 1) = (numel(b) - 1) / 2;

% 2) Anti-aliasing filter inside pop_resample (fsRaw -> fsOut). Its kernel is built in a local
%    function (myresample) that cannot be called, so the three design lines are reproduced here.
%    Guard: stop if the installed pop_resample.m no longer contains exactly these lines.
src = fileread(which('pop_resample'));
need = {'[p,q] = rat(freq/EEG.srate, 1e-12);', 'nyq = 1 / max([p q]);', ...
        'df = df * nyq;', 'm = pop_firwsord(''kaiser'', 2, df, 0.002);', ...
        'if nargin < 4 || isempty(df)', 'df = 0.2;'};
for k = 1:numel(need)
    if ~contains(src, need{k})
        error('stage3:resampleChanged', 'pop_resample.m no longer contains "%s"; re-check the design.', need{k});
    end
end
[p, q] = rat(S.fsOut / S.fsRaw, 1e-12);
df = 0.2 * (1 / max([p q]));                      % default df = 0.2, scaled by the Nyquist factor
m = pop_firwsord('kaiser', 2, df, 0.002);
name(end+1, 1) = "anti-aliasing (pop_resample, Kaiser)";
fsDesign(end+1, 1) = p * S.fsRaw;                % the kernel runs at the upsampled rate p*fsRaw
order(end+1, 1) = m; half(end+1, 1) = m / 2;

% 3) Line-noise removal (S3a-D5): to be added once D5 is decided.

T = table(name, fsDesign, order, half, half ./ fsDesign, ...
    'VariableNames', {'filter', 'design_rate_hz', 'order', 'half_samples', 'half_s'});
H = sum(T.half_s);
end
