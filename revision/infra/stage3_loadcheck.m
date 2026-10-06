function stage3_loadcheck(listFile, outJson)
%STAGE3_LOADCHECK  Q9 rule of S3a-INF-1 sec. 5: check that each MAT file listed (one path per line)
%   loads. Writes outJson: an array of {file, loads, message}.
files = strtrim(splitlines(string(fileread(listFile))));
files = files(files ~= "");
R = struct('file', {}, 'loads', {}, 'message', {});
for k = 1:numel(files)
    try
        load(files(k)); %#ok<LOAD>
        R(end+1) = struct('file', char(files(k)), 'loads', true, 'message', ''); %#ok<AGROW>
    catch ME
        R(end+1) = struct('file', char(files(k)), 'loads', false, 'message', ME.message); %#ok<AGROW>
    end
end
fid = fopen(outJson, 'w', 'n', 'UTF-8'); fwrite(fid, jsonencode(R), 'char'); fclose(fid);
end
