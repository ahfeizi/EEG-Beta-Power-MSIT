function EEG = stage3_p2_rebuild(P2, cond, version, rejectOther)
%STAGE3_P2_REBUILD  Rebuild one analysed version from the S1 bundle (S3a-P2 items 4-6; S3a-P2-impl).
%   EEG = stage3_p2_rebuild(P2, cond, version, rejectOther)
%     cond         'rest' or 'msit'
%     version      'beta' (all non-brain classes removed at p >= 0.8; primary for beta),
%                  'emg'  (all non-brain classes except Muscle; primary for the EMG control-band test),
%                  'none' (no component removed)
%     rejectOther  true/false: whether the class Other counts as non-brain (S3a-P2 flagged point i).
%                  REQUIRED (no default) until Amirhossein decides it; ignored for 'none'.
%   Steps: component removal (pop_subcomp) -> spherical-spline interpolation of the D6 channels with the
%   individual centred positions (pop_interp 'spherical', P2.fullChanlocs, 126 channels incl. FCz) -> average
%   reference over the full montage (R1). Deterministic. Returns double data; records the version, the
%   removed channels and the rejected components in EEG.etc.stage3.

assert(any(strcmp(cond, {'rest', 'msit'})), 'stage3:p2r', 'unknown condition %s', cond);
EEG = P2.(cond);
EEG.data = double(EEG.data);
switch version
    case 'none', rej = [];
    case {'beta', 'emg'}
        assert(nargin >= 4 && islogical(rejectOther) && isscalar(rejectOther), 'stage3:p2r', ...
            'rejectOther (true/false) must be given: the Other class is not decided (S3a-P2)');
        if rejectOther, rej = P2.lists.([version '_withOther']); else, rej = P2.lists.([version '_withoutOther']); end
    otherwise
        error('stage3:p2r', 'unknown version %s', version);
end
if ~isempty(rej), EEG = pop_subcomp(EEG, rej, 0); end
EEG.icaact = [];
EEG = pop_interp(EEG, P2.fullChanlocs, 'spherical');
assert(isequal({EEG.chanlocs.labels}, {P2.fullChanlocs.labels}), 'stage3:p2r', 'montage after interpolation');
EEG = pop_reref(EEG, []);
EEG.etc.stage3.version = version;
if strcmp(version, 'none'), EEG.etc.stage3.rejectOther = []; else, EEG.etc.stage3.rejectOther = rejectOther; end
EEG.etc.stage3.rejectedComponents = rej;
EEG.etc.stage3.removedChannels = P2.removedChannels;
EEG.etc.stage3.interpolatedChannels = P2.removedChannels;
end
