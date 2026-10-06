function [h, txt] = stage3_log_entry(logFile, id)
%STAGE3_LOG_ENTRY  Text and SHA-256 of one decision-log entry, located by its exact heading line.
%   [h, txt] = stage3_log_entry(logFile, id) finds the single line that starts with "## <id> "
%   followed by a non-space character (the "·" separator), so that "S3a-D5-0" does not match
%   "S3a-D5-0-exc". It takes the text from that heading to the next line starting with "## "
%   (exclusive) or to the end of the file, removes CR, and returns the lower-case hex SHA-256 of
%   its UTF-8 bytes. It errors unless exactly one heading line matches.
%   The text rule and the hash are those of the original entryHash in stage3_d5_0_line_noise.m;
%   only the locator differs (decision log, S3a-D5-0-amend1).

raw = fileread(logFile);
a = regexp(raw, ['^## ' regexptranslate('escape', id) ' \S'], 'lineanchors');
assert(numel(a) == 1, 'stage3_log_entry:locator', ...
    'entry "%s": %d heading lines match, expected exactly 1', id, numel(a));
rest = raw(a:end);
b = regexp(rest(3:end), '\n## ', 'once');                 % next level-2 heading
if ~isempty(b), rest = rest(1:b + 1); end
rest = strrep(rest, sprintf('\r'), '');                    % hash independent of LF/CRLF checkout
md = java.security.MessageDigest.getInstance('SHA-256');
d = typecast(md.digest(uint8(unicode2native(rest, 'UTF-8'))), 'uint8');
h = lower(reshape(dec2hex(d, 2)', 1, []));
txt = rest;
end
