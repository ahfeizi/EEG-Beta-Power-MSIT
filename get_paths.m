function p = get_paths()
%GET_PATHS  Local data/output paths for every script in this repository.
%   p = get_paths() returns a struct with four fields:
%     p.bidsRoot   raw OpenNeuro ds004621 dataset (BIDS)            -- read-only
%     p.derivRoot  existing v1 derivatives (per-subject .set, CSV)  -- read-only
%     p.taskDeriv  existing v1 MSIT+ derivatives                    -- read-only
%     p.outRoot    where ALL new outputs are written
%   Defaults point inside this repository. If config_local.m exists in the
%   repository root (it is gitignored), each field it defines overrides the
%   default. Copy config_local_example.m to config_local.m and edit it.
%
%   Scripts never write to derivRoot or taskDeriv; every output goes under outRoot.

here = fileparts(mfilename('fullpath'));          % repository root (this file lives there)

% defaults: the layout of the public repository
p.bidsRoot  = fullfile(here, 'raw_data', 'ds004621');
p.derivRoot = fullfile(here, 'legacy_v1', 'derivatives');
p.taskDeriv = p.derivRoot;                        % in the repo, v1 task CSVs sit in the same folder
p.outRoot   = fullfile(here, 'outputs');          % gitignored

% local override
if exist(fullfile(here, 'config_local.m'), 'file') == 2
    q = config_local();
    f = fieldnames(q);
    for k = 1:numel(f)
        if ~isfield(p, f{k})
            error('get_paths:unknownField', 'config_local.m defines unknown field "%s".', f{k});
        end
        p.(f{k}) = q.(f{k});
    end
end

if ~exist(p.outRoot, 'dir'), mkdir(p.outRoot); end
end
