function p = config_local()
%CONFIG_LOCAL  Machine-specific paths. TEMPLATE -- placeholder paths only.
%   Copy this file to config_local.m (same folder, the repository root) and
%   replace the placeholders. config_local.m is gitignored and never committed.
%   Any field you leave out keeps the default from get_paths.m.

p.bidsRoot  = '/path/to/ds004621';               % raw OpenNeuro ds004621 (read-only)
p.derivRoot = '/path/to/v1/derivatives';         % existing v1 derivatives (read-only)
p.taskDeriv = '/path/to/v1/derivatives/MSIT';    % existing v1 MSIT+ derivatives (read-only)
p.outRoot   = '/path/to/new/outputs';            % all new outputs are written here
p.eegOutRoot = '/path/to/large/eeg/outputs';    % new continuous EEG files (needs tens of GB)
end
