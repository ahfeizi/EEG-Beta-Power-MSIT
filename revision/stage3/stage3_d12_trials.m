function [keep, R] = stage3_d12_trials(EEG, eventTypes, winSec, chans, thrUV)
%STAGE3_D12_TRIALS  D12 trial rejection (S3a-P2 item 7). Applied in Stage 5, once the analysis window is
%   fixed; Stage 3 only implements and tests it.
%   [keep, R] = stage3_d12_trials(EEG, eventTypes, winSec, chans, thrUV)
%     eventTypes  string/cellstr of the event types that define trials (or rest pseudo-epoch onsets)
%     winSec      [t0 t1] analysis window relative to the event (s), e.g. a 200 ms pre-stimulus window
%     chans       channel labels, default {'Fz', 'Cz', 'C4'}
%     thrUV       peak-to-peak threshold, default 150 (uV)
%   A trial is rejected if the broadband peak-to-peak amplitude (max - min of the time-domain samples) in
%   the window exceeds thrUV on any of the channels. A trial whose window crosses a boundary event or the
%   data edge is reported as 'outside' (not counted as kept). Returns keep (logical per trial) and R with
%   counts: n_trials, n_outside, n_rejected, n_kept, frac_kept. Counts only; no spectral quantity.
if nargin < 4 || isempty(chans), chans = {'Fz', 'Cz', 'C4'}; end
if nargin < 5 || isempty(thrUV), thrUV = 150; end
typ = string({EEG.event.type}); lat = [EEG.event.latency];
on = lat(ismember(typ, string(eventTypes)));
[ok, ic] = ismember(string(chans), string({EEG.chanlocs.labels}));
assert(all(ok), 'stage3:d12', 'channel not found');
bl = lat(typ == "boundary");
i0 = round(winSec(1) * EEG.srate); i1 = round(winSec(2) * EEG.srate) - 1;
keep = false(1, numel(on)); outside = false(1, numel(on)); rej = false(1, numel(on));
for k = 1:numel(on)
    a = round(on(k)) + i0; b = round(on(k)) + i1;
    if a < 1 || b > EEG.pnts || any(bl > a - 0.5 & bl < b + 0.5), outside(k) = true; continue; end
    x = double(EEG.data(ic, a:b));
    rej(k) = any(max(x, [], 2) - min(x, [], 2) > thrUV);
    keep(k) = ~rej(k);
end
R = struct('n_trials', numel(on), 'n_outside', sum(outside), 'n_rejected', sum(rej), 'n_kept', sum(keep), ...
    'frac_kept', sum(keep) / max(1, numel(on) - sum(outside)));
end
