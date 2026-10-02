%% ---- merged scalp map: distinct-power colors + verdict halo for 6 candidates ----
repoRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));   % [path] legacy_v1/<folder>/<this> -> repository root
addpath(repoRoot);  P = get_paths();                                  % [path] config_local.m or repo defaults (get_paths.m)
rerunDir = fullfile(P.outRoot, 'legacy_v1_rerun');                    % [path] a rerun writes here, never over v1 derivatives
if ~exist(rerunDir, 'dir'); mkdir(rerunDir); end                      % [path]
derivRoot = P.derivRoot;                                           % [path] v1 derivatives (read-only)

%% ---- load channel locations ----
sampleSet = fullfile(derivRoot, 'sub-01', 'sub-01_rest_clean.set');
[ALLEEG, EEG, CURRENTSET] = eeglab;
EEG = pop_loadset('filename', sampleSet);
chanlocs = EEG.chanlocs;

labels = {chanlocs.labels}';
Th = [chanlocs.theta]';
Rd = [chanlocs.radius]';
[x0, y0] = pol2cart(Th/180*pi, Rd);
x = -y0;
y = x0;

%% ---- load statistical tables ----
Tdist = readtable(fullfile(derivRoot, 'beta_distinct_channels_stats.csv'));
Temg  = readtable(fullfile(derivRoot, 'beta_emg_contamination_test.csv'));

[~, idxD] = ismember(labels, Tdist.channel);
meanZ    = nan(size(labels)); meanZ(idxD>0)    = Tdist.meanZscore(idxD(idxD>0));
distinct = false(size(labels)); distinct(idxD>0) = logical(Tdist.distinct_FDR05(idxD(idxD>0)));

catHigh = distinct & meanZ > 0;
catLow  = distinct & meanZ < 0;
catNS   = ~distinct;

colHigh = [0.80 0.20 0.20];   % red
colLow  = [0.20 0.40 0.80];   % blue
colNS   = [0.65 0.65 0.65];   % gray

%% ---- candidate verdict ----
candidates = {'Fz','Cz','C4','C3','F3','F4'};
cleanSet = {'Fz','Cz','C4'};
ambigSet = {'C3'};
contSet  = {'F3','F4'};

colClean = [0.20 0.60 0.30];    % green
colAmbig = [0.90 0.60 0.10];    % orange
colCont  = [0.80 0.20 0.20];    % red (verdict red -- distinguishable by context/size from stat-red)

isCand = ismember(labels, candidates);

%% ---- figure ----
figure('Color','w','Position',[50 50 1000 1050]);
hold on; axis equal off;

th = linspace(0, 2*pi, 200);
plot(0.5*cos(th), 0.5*sin(th), 'k-', 'LineWidth', 1.5);
plot([-0.05 0 0.05], [0.5 0.56 0.5], 'k-', 'LineWidth', 1.5);
plot([-0.52 -0.5], [0.05 0.05], 'k-', 'LineWidth', 1.5);
plot([0.5 0.52], [0.05 0.05], 'k-', 'LineWidth', 1.5);

% --- non-candidate channels: small dots, colored by distinct-test category ---
nonCand = ~isCand;
scatter(x(nonCand & catNS), y(nonCand & catNS), 35, colNS, 'filled', 'MarkerFaceAlpha', 0.6);
scatter(x(nonCand & catLow), y(nonCand & catLow), 45, colLow, 'filled');
scatter(x(nonCand & catHigh), y(nonCand & catHigh), 45, colHigh, 'filled');
for i = find(nonCand & (catLow | catHigh))'
    text(x(i), y(i)+0.016, labels{i}, 'FontSize', 6, 'HorizontalAlignment','center');
end

% --- candidate channels: verdict halo (large, underneath) + stat-colored dot (on top) ---
for i = find(isCand)'
    lab = labels{i};
    if ismember(lab, cleanSet), vc = colClean;
    elseif ismember(lab, ambigSet), vc = colAmbig;
    else, vc = colCont;
    end

    if catHigh(i), sc = colHigh;
    elseif catLow(i), sc = colLow;
    else, sc = colNS;
    end

    scatter(x(i), y(i), 420, vc, 'filled');                                  % verdict halo
    scatter(x(i), y(i), 130, sc, 'filled', 'MarkerEdgeColor','k', 'LineWidth',1.5);  % stat dot on top
    text(x(i), y(i)+0.05, lab, 'FontSize', 13, 'HorizontalAlignment','center', ...
        'FontWeight','bold');
end

title('Beta power topography: whole-head statistics + candidate-channel verdict', 'FontSize', 13);

% --- combined legend ---
h1 = scatter(nan,nan,45,colHigh,'filled');
h2 = scatter(nan,nan,45,colLow,'filled');
h3 = scatter(nan,nan,35,colNS,'filled');
h4 = scatter(nan,nan,300,colClean,'filled');
h5 = scatter(nan,nan,300,colAmbig,'filled');
h6 = scatter(nan,nan,300,colCont,'filled');
legend([h1 h2 h3 h4 h5 h6], ...
    {'Power significantly ABOVE average','Power significantly BELOW average','Not significant', ...
     'Verdict: clean (Fz, Cz, C4)', 'Verdict: ambiguous (C3)', 'Verdict: EMG-contaminated (F3, F4)'}, ...
    'Location','southoutside', 'NumColumns', 2, 'Box','off', 'FontSize', 9);

exportgraphics(gcf, fullfile(rerunDir, 'scalpmap_merged.png'), 'Resolution', 220);   % [path]
fprintf('Saved -> scalpmap_merged.png\n');
