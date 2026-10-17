function P = stage3_positions(subject, rawRoot, manifest, centering)
%STAGE3_POSITIONS  Individual electrode positions (S3a-D2-close) in the EEGLAB frame (mm).
%   P = stage3_positions(subject, rawRoot, manifest, centering) reads
%     <rawRoot>/sourcedata/<sub>/coords/<sub>_captrak.bvct   (digitised X/Y/Z, CapTrak RAS, mm), or, if absent,
%     <rawRoot>/sourcedata/<sub>/coords/<sub>_captrak.bvef   (integer spherical Theta/Phi/Radius;
%                                                            x = r sin t cos p, y = r sin t sin p, z = r cos t)
%   after checking the file against the verified manifest. Both are RAS (x right, y anterior, z up, mm;
%   S3a-D2-close). centering:
%     'spherefit'  subtract the least-squares sphere centre of the EEG electrodes (Nasion, LPA, RPA, GND
%                  excluded);
%     'origin'     keep the file's origin.
%   EEGLAB frame: X = y (anterior), Y = -x (left), Z = z.
%   Returns P.label (string), P.X/Y/Z (column vectors, mm, EEGLAB frame, after centring), P.source
%   ('bvct'/'bvef'), P.file (checked against the manifest), P.centre (RAS, mm, subtracted; [0 0 0] for 'origin'), P.radius
%   (fitted sphere radius, NaN for 'origin'), P.fiducials (struct with Nasion/LPA/RPA in the EEGLAB frame).

assert(any(strcmp(centering, {'spherefit', 'origin'})), 'stage3:pos', 'unknown centring %s', centering);
d = fullfile(char(rawRoot), 'sourcedata', char(subject), 'coords');
fb = fullfile(d, [char(subject) '_captrak.bvct']); fe = fullfile(d, [char(subject) '_captrak.bvef']);
if exist(fb, 'file') == 2
    f = fb; src = 'bvct';
    t = fileread(f);
    blk = regexp(t, '<CapTrakElectrodeList>(.*?)</CapTrakElectrodeList>', 'tokens', 'once');
    assert(~isempty(blk), 'stage3:pos', 'no CapTrakElectrodeList in %s', f);
    el = regexp(blk{1}, '<Name>([^<]*)</Name>\s*<X>([^<]*)</X>\s*<Y>([^<]*)</Y>\s*<Z>([^<]*)</Z>', 'tokens');
    names = string(cellfun(@(c) c{1}, el, 'uni', 0))';
    ras = cell2mat(cellfun(@(c) str2double(c(2:4)), el', 'uni', 0));
else
    assert(exist(fe, 'file') == 2, 'stage3:pos', 'no .bvct or .bvef for %s', subject);
    f = fe; src = 'bvef';
    t = fileread(f);
    el = regexp(t, '<Electrode>(.*?)</Electrode>', 'tokens');
    names = strings(numel(el), 1); ras = nan(numel(el), 3);
    for k = 1:numel(el)
        e = el{k}{1};
        names(k) = string(regexp(e, '<Name>([^<]*)</Name>', 'tokens', 'once'));
        th = str2double(regexp(e, '<Theta>([^<]*)</Theta>', 'tokens', 'once'));
        ph = str2double(regexp(e, '<Phi>([^<]*)</Phi>', 'tokens', 'once'));
        rr = str2double(regexp(e, '<Radius>([^<]*)</Radius>', 'tokens', 'once'));
        ras(k, :) = rr * [sind(th) * cosd(ph), sind(th) * sind(ph), cosd(th)];
    end
end
stage3_check_input(f, char(rawRoot), manifest);
assert(all(isfinite(ras(:))) && numel(unique(names)) == numel(names), 'stage3:pos', 'bad or duplicate entries in %s', f);
fid = ismember(names, ["Nasion", "LPA", "RPA"]);
eegPts = ~fid & names ~= "GND";
if strcmp(centering, 'spherefit')
    Q = ras(eegPts, :);
    sol = [2 * Q, ones(size(Q, 1), 1)] \ sum(Q .^ 2, 2);
    c = sol(1:3)'; r = sqrt(sol(4) + c * c');
else
    c = [0 0 0]; r = NaN;
end
ras = ras - c;
P.label = names(~fid);
P.X = ras(~fid, 2); P.Y = -ras(~fid, 1); P.Z = ras(~fid, 3);
P.source = src; P.file = f; P.centre = c; P.radius = r; P.centering = centering;
for n = ["Nasion", "LPA", "RPA"]
    k = find(names == n);
    if isscalar(k), P.fiducials.(char(n)) = [ras(k, 2), -ras(k, 1), ras(k, 3)]; else, P.fiducials.(char(n)) = [NaN NaN NaN]; end
end
end
