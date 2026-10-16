%% Stage 3a / decision S3a-D4e-4: does the installed EEGLAB keep raw boundaries intact?
% Synthetic data only (no raw EEG). Runs the D4 steps that precede cropping -- high-pass
% (pop_eegfiltnew) then resampling (pop_resample) -- on a dataset with boundary events placed as
% pop_loadbv places them (integer latency = first sample of the new segment, duplicates included)
% and checks:
%   1. pop_resample splits at the boundaries: each new boundary latency equals the start of its
%      resampled segment, computed independently as 1 + sum(ceil(segment length * p / q)).
%   2. Non-boundary event latencies keep their time relative to their segment start.
%   3. Neither filter leaks across a boundary: channel 1 is a different constant in each segment
%      (DC jumps of up to 1500 uV, like the raw offsets); any leak would leave a transient.
%   4. Data and events stay aligned: channel 2 is a 10 Hz sine of the ORIGINAL time; after both
%      steps it must still match sin(2*pi*10*t) at the remapped times (away from segment edges).
% Prints PASS/FAIL per check and stops with an error on any FAIL.

if ~exist('pop_eegfiltnew', 'file'), eeglab('nogui'); end
here = fileparts(mfilename('fullpath')); addpath(here);
S = stage3_params();
H = stage3_filter_halflengths(S, 'none');   % this test covers high-pass + resample only

% ---- synthetic recording: three segments, odd and even lengths ------------------------------
fs = S.fsRaw;
segStart = [1 10002 20004];                         % boundary latencies (pop_loadbv convention)
N = 30001;                                          % segment lengths 10001, 10002, 9998
segLen = diff([segStart N + 1]);
tOrig = zeros(1, N);                                % original recording time of every sample (s)
offs  = [0 1000 -500];                              % uV, a different DC level per segment
ch1 = zeros(1, N);
for k = 1:3
    idx = segStart(k):segStart(k) + segLen(k) - 1;
    tOrig(idx) = (idx - 1) / fs;                    % continuous clock (gaps of zero length)
    ch1(idx) = offs(k);
end
ch2 = sin(2 * pi * 10 * tOrig);

E = eeg_emptyset;
E.srate = fs; E.nbchan = 2; E.trials = 1; E.pnts = N;
E.data = [ch1; ch2]; E.xmin = 0; E.xmax = (N - 1) / fs;
stim = [5001 15002 25004];                          % even offsets from each segment start
E.event = struct('type', {'boundary', 'boundary', 'boundary', 'boundary', 'S 7', 'S 7', 'S 7'}, ...
                 'latency', {1, 10002, 20004, 20004, stim(1), stim(2), stim(3)}, ...
                 'duration', {NaN, NaN, NaN, NaN, 0, 0, 0});   % 20004 twice: New Segment + Stimulus/boundary
E = eeg_checkset(E, 'eventconsistency');

E = pop_eegfiltnew(E, 'locutoff', S.hpEdge);
E = pop_resample(E, S.fsOut);

[p, q] = rat(S.fsOut / S.fsRaw, 1e-12);
newStart = cumsum([1 ceil(segLen(1:2) * p / q)]);  % independent expectation
newLen   = ceil(segLen * p / q);
fail = false;
report = @(ok, msg) fprintf('%s  %s\n', ternary(ok, 'PASS', 'FAIL'), msg);

% ---- check 1: boundary latencies --------------------------------------------------------------
isB = strcmp({E.event.type}, 'boundary');
bl = unique([E.event(isB).latency]);
bl = bl(bl > 1);
ok = isequal(bl, newStart(2:3)) && E.pnts == sum(newLen);
report(ok, sprintf('1 boundaries at %s (expected %s); pnts %d (expected %d)', ...
    mat2str(bl), mat2str(newStart(2:3)), E.pnts, sum(newLen))); fail = fail || ~ok;

% ---- check 2: event latencies relative to segment start ----------------------------------------
sl = [E.event(strcmp({E.event.type}, 'S 7')).latency];
expSl = (stim - segStart) * p / q + newStart;
ok = isequal(sl, expSl);
report(ok, sprintf('2 stimulus latencies %s (expected %s)', mat2str(sl), mat2str(expSl))); fail = fail || ~ok;

% ---- check 3: no leak across boundaries ---------------------------------------------------------
% Reference: each segment processed ALONE (its own dataset, no boundaries) with the same two steps.
% If both functions split at the boundaries, the joint result equals the per-segment results.
dev = 0;
for k = 1:3
    idx = segStart(k):segStart(k) + segLen(k) - 1;
    R = eeg_emptyset;
    R.srate = fs; R.nbchan = 2; R.trials = 1; R.pnts = segLen(k);
    R.data = [ch1(idx); ch2(idx)]; R.xmin = 0; R.xmax = (R.pnts - 1) / fs;
    R = eeg_checkset(R);
    R = pop_resample(pop_eegfiltnew(R, 'locutoff', S.hpEdge), S.fsOut);
    J = E.data(:, newStart(k):newStart(k) + newLen(k) - 1);
    if ~isequal(size(R.data), size(J)), dev = Inf; break; end
    dev = max(dev, max(abs(R.data(:) - J(:))));
end
ok = dev < 1e-9;                                    % uV; numerical precision only
report(ok, sprintf('3 max |joint - per-segment| = %.3g uV (threshold 1e-9; DC jumps up to 1500 uV)', dev)); fail = fail || ~ok;

% ---- check 4: data/event alignment (channel 2), samples >= H from every segment edge ------------
tNew = zeros(1, E.pnts); keep = false(1, E.pnts); G = ceil(H * S.fsOut);
for k = 1:3
    idx = newStart(k):newStart(k) + newLen(k) - 1;
    tNew(idx) = (segStart(k) - 1) / fs + (idx - newStart(k)) / S.fsOut;   % original time of each new sample
    keep(idx(1 + G:end - G)) = true;
end
err = max(abs(E.data(2, keep) - sin(2 * pi * 10 * tNew(keep))));
ok = err < 0.01;
report(ok, sprintf('4 max |sine error| at >= H from edges = %.3g (threshold 0.01)', err)); fail = fail || ~ok;

fprintf('H used for check 4: %.4f s (%d samples at %d Hz)\n', H, G, S.fsOut);
if fail, error('stage3:boundaryCheck', 'At least one boundary check failed.'); end

function out = ternary(c, a, b)
if c, out = a; else, out = b; end
end
