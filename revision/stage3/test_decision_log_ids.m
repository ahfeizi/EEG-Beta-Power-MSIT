function ok = test_decision_log_ids(logFile)
%TEST_DECISION_LOG_IDS  Every entry ID in the decision log resolves to exactly one heading line.
%   ok = test_decision_log_ids() checks docs/decision_log.md; test_decision_log_ids(logFile) checks
%   another copy. A level-2 heading is a line starting with "## "; its ID is the first word after
%   "## ". The test fails if any level-2 heading has no ID followed by a separator, or if any ID
%   does not resolve to exactly one heading through stage3_log_entry (S3a-D5-0-amend1).

here = fileparts(mfilename('fullpath'));
addpath(here);
if nargin < 1, logFile = fullfile(fileparts(fileparts(here)), 'docs', 'decision_log.md'); end
raw = fileread(logFile);
heads = regexp(raw, '^## [^\n]*', 'match', 'lineanchors');
tok = regexp(raw, '^## (\S+) \S', 'tokens', 'lineanchors');
ids = cellfun(@(c) c{1}, tok, 'UniformOutput', false);
fprintf('level-2 headings: %d; with an ID and separator: %d; distinct IDs: %d\n', ...
    numel(heads), numel(ids), numel(unique(ids)));
nFail = 0;
for k = 1:numel(ids)
    try
        stage3_log_entry(logFile, ids{k});
    catch ME
        nFail = nFail + 1;
        fprintf('FAIL %s: %s\n', ids{k}, ME.message);
    end
end
sep = regexp(raw, '^## S3a-D5-0 (\S)', 'tokens', 'once', 'lineanchors');
if ~isempty(sep), fprintf('separator after "S3a-D5-0" decoded as U+%04X\n', double(sep{1})); end
ok = nFail == 0 && numel(heads) == numel(ids);
if ok, fprintf('PASS: all %d IDs resolve to exactly one heading\n', numel(ids));
else, fprintf('FAIL: %d IDs do not resolve; %d headings without an ID\n', nFail, numel(heads) - numel(ids)); end
end
