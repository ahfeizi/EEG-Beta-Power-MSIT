%% ---- labeled scalp maps: distinct channels + 6-channel verdict ----
% Produces two figures with every electrode plotted at its scalp position,
% labeled with its name, and colored by category, so results can be read
% at a glance instead of from a long table.

derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder

%% ---- load channel locations (from any one preprocessed subject) ----
sampleSet = fullfile(derivRoot, 'sub-01', 'sub-01_rest_clean.set');
[ALLEEG, EEG, CURRENTSET] = eeglab;
EEG = pop_loadset('filename', sampleSet);
chanlocs = EEG.chanlocs;

labels = {chanlocs.labels}';
Th = [chanlocs.theta]';
Rd = [chanlocs.radius]';
[x0, y0] = pol2cart(Th/180*pi, Rd);   % standard EEGLAB polar-to-cartesian projection
x = -y0;
y = x0;

%% ---- load statistical tables ----
Tdist = readtable(fullfile(derivRoot, 'beta_distinct_channels_stats.csv'));
Temg  = readtable(fullfile(derivRoot, 'beta_emg_contamination_test.csv'));

% match order to chanlocs
[~, idxD] = ismember(labels, Tdist.channel);
[~, idxE] = ismember(labels, Temg.channel);

meanZ    = nan(size(labels)); meanZ(idxD>0)    = Tdist.meanZscore(idxD(idxD>0));
distinct = false(size(labels)); distinct(idxD>0) = logical(Tdist.distinct_FDR05(idxD(idxD>0)));
emgR     = nan(size(labels)); emgR(idxE>0)     = Temg.betaVsControlBand_r(idxE(idxE>0));
emgFlag  = false(size(labels)); emgFlag(idxE>0) = logical(Temg.likelyEMG_contaminated(idxE(idxE>0)));

%% ---- FIGURE A: distinct-channel categories, all electrodes ----
catHigh = distinct & meanZ > 0;    % significantly above whole-head average
catLow  = distinct & meanZ < 0;    % significantly below whole-head average
catNS   = ~distinct;               % not significant

colHigh = [0.80 0.20 0.20];   % red
colLow  = [0.20 0.40 0.80];   % blue
colNS   = [0.65 0.65 0.65];   % gray

figure('Color','w','Position',[50 50 900 900]);
hold on; axis equal off;

% head outline
th = linspace(0, 2*pi, 200);
plot(0.5*cos(th), 0.5*sin(th), 'k-', 'LineWidth', 1.5);
plot([-0.05 0 0.05], [0.5 0.56 0.5], 'k-', 'LineWidth', 1.5);   % nose
plot([-0.52 -0.5], [0.05 0.05], 'k-', 'LineWidth', 1.5);        % left ear tick
plot([0.5 0.52], [0.05 0.05], 'k-', 'LineWidth', 1.5);          % right ear tick

scatter(x(catNS), y(catNS), 40, colNS, 'filled', 'MarkerFaceAlpha', 0.6);
scatter(x(catLow), y(catLow), 55, colLow, 'filled');
scatter(x(catHigh), y(catHigh), 55, colHigh, 'filled');

for i = find(catLow | catHigh)'
    text(x(i), y(i)+0.018, labels{i}, 'FontSize', 6, 'HorizontalAlignment','center', ...
        'FontWeight','bold');
end

title('Beta power vs. whole-head average (FDR<.05)', 'FontSize', 13);
legend([scatter(nan,nan,55,colHigh,'filled'), scatter(nan,nan,55,colLow,'filled'), ...
        scatter(nan,nan,40,colNS,'filled')], ...
    {'Significantly ABOVE average', 'Significantly BELOW average', 'Not significant'}, ...
    'Location','southoutside', 'Orientation','horizontal', 'Box','off');

exportgraphics(gcf, fullfile(derivRoot, 'scalpmap_distinct_channels.png'), 'Resolution', 220);

%% ---- FIGURE B: verdict for the 6 candidate channels ----
candidates = {'Fz','Cz','C4','C3','F3','F4'};
verdict = struct('clean', {{'Fz','Cz','C4'}}, ...
                  'ambiguous', {{'C3'}}, ...
                  'contaminated', {{'F3','F4'}});

colClean = [0.20 0.60 0.30];    % green
colAmbig = [0.90 0.60 0.10];    % orange
colCont  = [0.80 0.20 0.20];    % red
colOther = [0.85 0.85 0.85];    % light gray (all other channels, context only)

figure('Color','w','Position',[50 50 900 900]);
hold on; axis equal off;
plot(0.5*cos(th), 0.5*sin(th), 'k-', 'LineWidth', 1.5);
plot([-0.05 0 0.05], [0.5 0.56 0.5], 'k-', 'LineWidth', 1.5);
plot([-0.52 -0.5], [0.05 0.05], 'k-', 'LineWidth', 1.5);
plot([0.5 0.52], [0.05 0.05], 'k-', 'LineWidth', 1.5);

isCand = ismember(labels, candidates);
scatter(x(~isCand), y(~isCand), 25, colOther, 'filled');

for i = find(isCand)'
    lab = labels{i};
    if ismember(lab, verdict.clean)
        c = colClean;
    elseif ismember(lab, verdict.ambiguous)
        c = colAmbig;
    else
        c = colCont;
    end
    scatter(x(i), y(i), 140, c, 'filled', 'MarkerEdgeColor','k', 'LineWidth',1.2);
    text(x(i), y(i)+0.035, lab, 'FontSize', 11, 'HorizontalAlignment','center', ...
        'FontWeight','bold');
end

title('Candidate channel verdict (combined tests)', 'FontSize', 13);
legend([scatter(nan,nan,140,colClean,'filled'), scatter(nan,nan,140,colAmbig,'filled'), ...
        scatter(nan,nan,140,colCont,'filled')], ...
    {'Clean (Fz, Cz, C4)', 'Ambiguous (C3)', 'EMG-contaminated (F3, F4)'}, ...
    'Location','southoutside', 'Orientation','vertical', 'Box','off');

exportgraphics(gcf, fullfile(derivRoot, 'scalpmap_candidate_verdict.png'), 'Resolution', 220);

fprintf('Saved:\n  scalpmap_distinct_channels.png\n  scalpmap_candidate_verdict.png\n');
