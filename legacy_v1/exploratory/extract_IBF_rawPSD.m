%% ========================================================================
%  extract_IBF_rawPSD.m
% ========================================================================

clear;
clc;
close all;

%% ------------------------------------------------------------------------
% PATHS
% -------------------------------------------------------------------------

cfg.derivRoot = fullfile(pwd, 'derivatives');   % <-- EDIT if needed: your local output/derivatives folder

cfg.subjects = arrayfun(@(x)sprintf('sub-%02d',x),1:42,'uni',0);

cfg.channels = {'Fz','Cz','F3','F4','C3','C4'};

cfg.betaBand = [13 30];

cfg.windowSec = 2;

cfg.overlap = 0.50;

cfg.nfft = [];

cfg.saveFigure = fullfile(cfg.derivRoot,'PSD_Fz_AllSubjects.png');

cfg.saveCSV = fullfile(cfg.derivRoot,'IBF_features_rawPSD.csv');

%% ------------------------------------------------------------------------
% TABLE
% -------------------------------------------------------------------------

varNames = {'Subject'};

for k=1:numel(cfg.channels)

    ch = cfg.channels{k};

    varNames = [varNames,...
        {[ch '_IBF']},...
        {[ch '_AMP']},...
        {[ch '_PeakDetected']}];

end

Result = cell(numel(cfg.subjects),length(varNames));

%% ------------------------------------------------------------------------
% FIGURE
% -------------------------------------------------------------------------

fig = figure(...
    'Color','w',...
    'Position',[40 40 1500 900]);

tiledlayout(6,7,...
    'TileSpacing','compact',...
    'Padding','compact');

%% ------------------------------------------------------------------------
% SUBJECT LOOP
% -------------------------------------------------------------------------

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    fprintf('%s\n',subject);

    Result{s,1}=subject;

    setFile = fullfile(...
        cfg.derivRoot,...
        subject,...
        [subject '_rest_clean.set']);

    assert(exist(setFile,'file')==2,...
    'SET file not found:\n%s',setFile);

    EEG = pop_loadset(setFile);

    fs = EEG.srate;

    win = round(cfg.windowSec*fs);

    overlap = round(win*cfg.overlap);

    %% --------------------------------------------------------------------
    % CHANNEL LOOP
    % ---------------------------------------------------------------------

    for c=1:numel(cfg.channels)

        chName = cfg.channels{c};

        idx = find(strcmpi({EEG.chanlocs.labels},chName));

        if isempty(idx)

            Result{s,3*(c-1)+2}=NaN;
            Result{s,3*(c-1)+3}=NaN;
            Result{s,3*(c-1)+4}=false;

            continue

        end

        x = double(EEG.data(idx,:));

        if isempty(cfg.nfft)

            nfft = max(256,2^nextpow2(win));

        else

            nfft = cfg.nfft;

        end

        [Pxx,f] = pwelch(...
            x,...
            hann(win),...
            overlap,...
            nfft,...
            fs);

        betaIdx = ...
            f>=cfg.betaBand(1) & ...
            f<=cfg.betaBand(2);

        fb = f(betaIdx);

        pb = Pxx(betaIdx);

        [pks,locs] = findpeaks(pb);

        if isempty(pks)

            [amp,ii] = max(pb);

            ibf = fb(ii);

            peakFlag = false;

        else

            [amp,id] = max(pks);

            ibf = fb(locs(id));

            peakFlag = true;

        end

        Result{s,3*(c-1)+2}=ibf;

        Result{s,3*(c-1)+3}=amp;

        Result{s,3*(c-1)+4}=peakFlag;

        %% ---------------------------------------------------------------
        % Fz PANEL
        % ---------------------------------------------------------------

        if strcmpi(chName,'Fz')

            nexttile

            hold on

            yl = [min(Pxx(Pxx>0)) max(Pxx)];

            patch(...
                [cfg.betaBand(1) cfg.betaBand(2) cfg.betaBand(2) cfg.betaBand(1)],...
                [yl(1) yl(1) yl(2) yl(2)],...
                [0.92 0.92 0.92],...
                'EdgeColor','none',...
                'FaceAlpha',0.5);

            loglog(f,Pxx,'b','LineWidth',1);

            if peakFlag

                loglog(ibf,amp,...
                    'rv',...
                    'MarkerFaceColor','r',...
                    'MarkerSize',5);

            else

                loglog(ibf,amp,...
                    'ko',...
                    'MarkerFaceColor','y',...
                    'MarkerSize',5);

            end

            xlim([1 45])

            grid on

            title(subject,'Interpreter','none','FontSize',8)

        end

    end

end

%% ------------------------------------------------------------------------
% TABLE
% -------------------------------------------------------------------------

T = cell2table(Result,'VariableNames',varNames);

writetable(T,cfg.saveCSV);

%% ------------------------------------------------------------------------
% SAVE FIGURE
% -------------------------------------------------------------------------

exportgraphics(fig,cfg.saveFigure,'Resolution',300);

close(fig);

%% ------------------------------------------------------------------------
% SCATTER : Fz
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.Fz_IBF;

flag = T.Fz_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('Fz');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_Fz_scatter.png'),...
    'Resolution',300);

close(fig2);

%% ------------------------------------------------------------------------
% SCATTER : Cz
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.Cz_IBF;

flag = T.Cz_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('Cz');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_Cz_scatter.png'),...
    'Resolution',300);

close(fig2);

%% ------------------------------------------------------------------------
% SCATTER : F3
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.F3_IBF;

flag = T.F3_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('F3');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_F3_scatter.png'),...
    'Resolution',300);

close(fig2);

%% ------------------------------------------------------------------------
% SCATTER : F4
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.F4_IBF;

flag = T.F4_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('F4');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_F4_scatter.png'),...
    'Resolution',300);

close(fig2);

%% ------------------------------------------------------------------------
% SCATTER : C3
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.C3_IBF;

flag = T.C3_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('C3');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_C3_scatter.png'),...
    'Resolution',300);

close(fig2);

%% ------------------------------------------------------------------------
% SCATTER : C4
% -------------------------------------------------------------------------

fig2 = figure(...
    'Color','w',...
    'Position',[200 150 1100 450]);

hold on

ibf = T.C4_IBF;

flag = T.C4_PeakDetected;

scatter(find(flag),...
    ibf(flag),...
    70,...
    'b',...
    'filled');

scatter(find(~flag),...
    ibf(~flag),...
    70,...
    'r',...
    'filled');

yline(cfg.betaBand(1),'--k');

yline(cfg.betaBand(2),'--k');

xlabel('Subject');

ylabel('Beta frequency (Hz)');

title('C4');

ylim([cfg.betaBand(1)-2 cfg.betaBand(2)+2]);

grid on

exportgraphics(...
    fig2,...
    fullfile(cfg.derivRoot,'IBF_C4_scatter.png'),...
    'Resolution',300);

close(fig2);

disp('Done.');

%% ------------------------------------------------------------------------
% ROI AVERAGE (OPTIONAL)
% -------------------------------------------------------------------------

ROI_IBF = nan(height(T),1);
ROI_AMP = nan(height(T),1);

for i = 1:height(T)

    x = [
        T.Fz_IBF(i)
        T.Cz_IBF(i)
        T.F3_IBF(i)
        T.F4_IBF(i)
        T.C3_IBF(i)
        T.C4_IBF(i)
        ];

    y = [
        T.Fz_AMP(i)
        T.Cz_AMP(i)
        T.F3_AMP(i)
        T.F4_AMP(i)
        T.C3_AMP(i)
        T.C4_AMP(i)
        ];

    ROI_IBF(i) = mean(x,'omitnan');
    ROI_AMP(i) = mean(y,'omitnan');

end

T.ROI_IBF = ROI_IBF;
T.ROI_AMP = ROI_AMP;

writetable(T,cfg.saveCSV);

%% ------------------------------------------------------------------------
% SUMMARY
% -------------------------------------------------------------------------

fprintf('\n');
fprintf('=============================================\n');
fprintf('Subjects processed : %d\n',height(T));
fprintf('Output table       : %s\n',cfg.saveCSV);
fprintf('PSD figure         : %s\n',cfg.saveFigure);
fprintf('=============================================\n');

%% ------------------------------------------------------------------------
% MISSING CHANNEL REPORT
% -------------------------------------------------------------------------

fprintf('\nChecking channel availability...\n');

for c = 1:numel(cfg.channels)

    ch = cfg.channels{c};

    miss = isnan(T.(sprintf('%s_IBF',ch)));

    fprintf('%s : %d missing\n',ch,sum(miss));

end

%% ------------------------------------------------------------------------
% BETA EDGE REPORT
% -------------------------------------------------------------------------

fprintf('\nBeta edge frequencies\n');

for c = 1:numel(cfg.channels)

    ch = cfg.channels{c};

    f = T.(sprintf('%s_IBF',ch));

    n13 = sum(abs(f-13)<1e-6);

    n30 = sum(abs(f-30)<1e-6);

    fprintf('%s   13Hz=%2d   30Hz=%2d\n',ch,n13,n30);

end

%% ------------------------------------------------------------------------
% SAVE MATLAB DATA
% -------------------------------------------------------------------------

save(fullfile(cfg.derivRoot,'IBF_rawPSD_results.mat'),...
    'T',...
    'cfg');

disp('Finished.')

%% ------------------------------------------------------------------------
% CHANNEL SUMMARY
% -------------------------------------------------------------------------

ChannelSummary = table();

ChannelSummary.Channel = cfg.channels';

MeanIBF = zeros(numel(cfg.channels),1);
StdIBF  = zeros(numel(cfg.channels),1);

MeanAMP = zeros(numel(cfg.channels),1);
StdAMP  = zeros(numel(cfg.channels),1);

NPeak   = zeros(numel(cfg.channels),1);

for c = 1:numel(cfg.channels)

    ch = cfg.channels{c};

    ibf = T.(sprintf('%s_IBF',ch));

    amp = T.(sprintf('%s_AMP',ch));

    det = T.(sprintf('%s_PeakDetected',ch));

    MeanIBF(c) = mean(ibf,'omitnan');
    StdIBF(c)  = std(ibf,'omitnan');

    MeanAMP(c) = mean(amp,'omitnan');
    StdAMP(c)  = std(amp,'omitnan');

    NPeak(c) = sum(det);

end

ChannelSummary.MeanIBF = MeanIBF;
ChannelSummary.StdIBF  = StdIBF;

ChannelSummary.MeanAmplitude = MeanAMP;
ChannelSummary.StdAmplitude  = StdAMP;

ChannelSummary.NDetectedPeaks = NPeak;

writetable(ChannelSummary,...
    fullfile(cfg.derivRoot,'ChannelSummary.csv'));

%% ------------------------------------------------------------------------
% HISTOGRAMS
% -------------------------------------------------------------------------

for c = 1:numel(cfg.channels)

    ch = cfg.channels{c};

    figure('Color','w');

    histogram(T.(sprintf('%s_IBF',ch)),...
        'BinWidth',1);

    xlabel('Frequency (Hz)');

    ylabel('Count');

    title(ch);

    grid on

    exportgraphics(gcf,...
        fullfile(cfg.derivRoot,...
        sprintf('%s_IBF_histogram.png',ch)),...
        'Resolution',300);

    close(gcf);

end

%% ------------------------------------------------------------------------
% END
% -------------------------------------------------------------------------

disp('---------------------------------------')
disp('RAW PSD FEATURE EXTRACTION COMPLETED')
disp('---------------------------------------')

%% ------------------------------------------------------------------------
% SUBJECT-WISE QC REPORT
% -------------------------------------------------------------------------

SubjectSummary = table();

SubjectSummary.Subject = T.Subject;

SubjectSummary.Fz = T.Fz_IBF;
SubjectSummary.Cz = T.Cz_IBF;
SubjectSummary.F3 = T.F3_IBF;
SubjectSummary.F4 = T.F4_IBF;
SubjectSummary.C3 = T.C3_IBF;
SubjectSummary.C4 = T.C4_IBF;

SubjectSummary.NDetected = ...
    double(T.Fz_PeakDetected) + ...
    double(T.Cz_PeakDetected) + ...
    double(T.F3_PeakDetected) + ...
    double(T.F4_PeakDetected) + ...
    double(T.C3_PeakDetected) + ...
    double(T.C4_PeakDetected);

SubjectSummary.Edge13 = ...
    double(abs(T.Fz_IBF-13)<eps) + ...
    double(abs(T.Cz_IBF-13)<eps) + ...
    double(abs(T.F3_IBF-13)<eps) + ...
    double(abs(T.F4_IBF-13)<eps) + ...
    double(abs(T.C3_IBF-13)<eps) + ...
    double(abs(T.C4_IBF-13)<eps);

SubjectSummary.Edge30 = ...
    double(abs(T.Fz_IBF-30)<eps) + ...
    double(abs(T.Cz_IBF-30)<eps) + ...
    double(abs(T.F3_IBF-30)<eps) + ...
    double(abs(T.F4_IBF-30)<eps) + ...
    double(abs(T.C3_IBF-30)<eps) + ...
    double(abs(T.C4_IBF-30)<eps);

writetable(SubjectSummary,...
    fullfile(cfg.derivRoot,'SubjectSummary.csv'));

%% ------------------------------------------------------------------------
% SAVE FIG FILE
% -------------------------------------------------------------------------

savefig(fig,...
    fullfile(cfg.derivRoot,'PSD_Fz_AllSubjects.fig'));

%% ------------------------------------------------------------------------
% EXPORT PSD CURVES
% -------------------------------------------------------------------------

PSD = struct();

PSD.Subjects = cfg.subjects;

PSD.Frequency = f;

save(fullfile(cfg.derivRoot,'PSD_Metadata.mat'),'PSD','-v7.3');

%% ------------------------------------------------------------------------
% FINISHED
% -------------------------------------------------------------------------

beep

%% ------------------------------------------------------------------------
% SAVE INDIVIDUAL PSD (Fz)
% -------------------------------------------------------------------------

PSD_Fz = cell(numel(cfg.subjects),1);

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    setFile = fullfile(...
        cfg.derivRoot,...
        subject,...
        [subject '_rest_clean.set']);

    EEG = pop_loadset(setFile);

    idx = find(strcmpi({EEG.chanlocs.labels},'Fz'));

    if isempty(idx)
        continue
    end

    x = double(EEG.data(idx,:));

    fs = EEG.srate;

    win = round(cfg.windowSec*fs);

    overlap = round(win*cfg.overlap);

    if isempty(cfg.nfft)
        nfft = max(256,2^nextpow2(win));
    else
        nfft = cfg.nfft;
    end

    [Pxx,f] = pwelch(...
        x,...
        hann(win),...
        overlap,...
        nfft,...
        fs);

    PSD_Fz{s}.Subject = subject;
    PSD_Fz{s}.Frequency = f;
    PSD_Fz{s}.PSD = Pxx;

end

save(fullfile(cfg.derivRoot,'PSD_Fz_AllSubjects.mat'),'PSD_Fz','-v7.3');

%% ------------------------------------------------------------------------
% SAVE INDIVIDUAL PSD (ALL CHANNELS)
% -------------------------------------------------------------------------

PSD_All = struct();

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    setFile = fullfile(...
        cfg.derivRoot,...
        subject,...
        [subject '_rest_clean.set']);

    EEG = pop_loadset(setFile);

    fs = EEG.srate;

    win = round(cfg.windowSec*fs);

    overlap = round(win*cfg.overlap);

    if isempty(cfg.nfft)
        nfft = max(256,2^nextpow2(win));
    else
        nfft = cfg.nfft;
    end

    PSD_All(s).Subject = subject;

    for c = 1:numel(cfg.channels)

        idx = find(strcmpi({EEG.chanlocs.labels},cfg.channels{c}));

        if isempty(idx)
            continue
        end

        x = double(EEG.data(idx,:));

        [Pxx,f] = pwelch(...
            x,...
            hann(win),...
            overlap,...
            nfft,...
            fs);

        PSD_All(s).(cfg.channels{c}).Frequency = f;
        PSD_All(s).(cfg.channels{c}).PSD = Pxx;

    end

end

save(fullfile(cfg.derivRoot,'PSD_AllChannels.mat'),'PSD_All','-v7.3');

%% ------------------------------------------------------------------------
% PEAK TABLE
% -------------------------------------------------------------------------

PeakTable = table();

PeakTable.Subject = T.Subject;

for c = 1:numel(cfg.channels)

    ch = cfg.channels{c};

    PeakTable.(sprintf('%s_Frequency',ch)) = T.(sprintf('%s_IBF',ch));
    PeakTable.(sprintf('%s_Amplitude',ch)) = T.(sprintf('%s_AMP',ch));
    PeakTable.(sprintf('%s_Detected',ch)) = T.(sprintf('%s_PeakDetected',ch));

end

writetable(PeakTable,...
    fullfile(cfg.derivRoot,'PeakTable.csv'));

%% ------------------------------------------------------------------------
% CHANNEL PRESENCE CHECK
% -------------------------------------------------------------------------

MissingChannels = {};

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    setFile = fullfile(...
        cfg.derivRoot,...
        subject,...
        [subject '_rest_clean.set']);

    EEG = pop_loadset(setFile);

    labels = {EEG.chanlocs.labels};

    for c = 1:numel(cfg.channels)

        if ~ismember(cfg.channels{c},labels)

            MissingChannels(end+1,:) = {subject,cfg.channels{c}};

        end

    end

end

if ~isempty(MissingChannels)

    MissingTable = cell2table(MissingChannels,...
        'VariableNames',{'Subject','Channel'});

    writetable(MissingTable,...
        fullfile(cfg.derivRoot,'MissingChannels.csv'));

end

%% ------------------------------------------------------------------------
% PARAMETERS
% -------------------------------------------------------------------------

Parameters = struct();

Parameters.betaBand = cfg.betaBand;
Parameters.windowSec = cfg.windowSec;
Parameters.overlap = cfg.overlap;
Parameters.channels = cfg.channels;
Parameters.derivRoot = cfg.derivRoot;

save(fullfile(cfg.derivRoot,'Parameters.mat'),'Parameters');

%% ------------------------------------------------------------------------
% EXPORT PER-SUBJECT FIGURES
% -------------------------------------------------------------------------

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    setFile = fullfile( ...
        cfg.derivRoot, ...
        subject, ...
        [subject '_rest_clean.set']);

    if ~exist(setFile,'file')
        continue
    end

    EEG = pop_loadset(setFile);

    fs = EEG.srate;

    win = round(cfg.windowSec*fs);

    overlap = round(win*cfg.overlap);

    if isempty(cfg.nfft)
        nfft = max(256,2^nextpow2(win));
    else
        nfft = cfg.nfft;
    end

    idx = find(strcmpi({EEG.chanlocs.labels},'Fz'));

    if isempty(idx)
        continue
    end

    x = double(EEG.data(idx,:));

    [Pxx,f] = pwelch( ...
        x, ...
        hann(win), ...
        overlap, ...
        nfft, ...
        fs);

    figure('Visible','off','Color','w');

    hold on

    yl = [min(Pxx(Pxx>0)) max(Pxx)];

    patch( ...
        [cfg.betaBand(1) cfg.betaBand(2) cfg.betaBand(2) cfg.betaBand(1)], ...
        [yl(1) yl(1) yl(2) yl(2)], ...
        [0.92 0.92 0.92], ...
        'EdgeColor','none', ...
        'FaceAlpha',0.5);

    loglog(f,Pxx,'k','LineWidth',1.2);

    betaIdx = f>=cfg.betaBand(1) & f<=cfg.betaBand(2);

    fb = f(betaIdx);

    pb = Pxx(betaIdx);

    [pks,locs] = findpeaks(pb);

    if isempty(pks)

        [amp,id] = max(pb);

        ibf = fb(id);

    else

        [amp,id] = max(pks);

        ibf = fb(locs(id));

    end

    loglog(ibf,amp,'ro','MarkerFaceColor','r');

    xlabel('Frequency (Hz)');
    ylabel('PSD');
    title(subject,'Interpreter','none');

    grid on

    exportgraphics( ...
        gcf, ...
        fullfile(cfg.derivRoot,subject,[subject '_Fz_PSD.png']), ...
        'Resolution',300);

    close(gcf);

end

%% ------------------------------------------------------------------------
% FINISH
% -------------------------------------------------------------------------

disp(' ');
disp('==========================================');
disp('        FEATURE EXTRACTION FINISHED');
disp('==========================================');
disp(' ');

%% ------------------------------------------------------------------------
% VALIDATION
% -------------------------------------------------------------------------

assert(exist(cfg.derivRoot,'dir')~=0,...
    'Output directory not found.');

assert(~isempty(cfg.subjects),...
    'No subjects specified.');

assert(numel(cfg.betaBand)==2,...
    'Invalid beta band.');

assert(cfg.betaBand(1)<cfg.betaBand(2),...
    'Invalid beta band.');

assert(cfg.windowSec>0,...
    'Window length must be positive.');

%% ------------------------------------------------------------------------
% LOG FILE
% -------------------------------------------------------------------------

logFile = fullfile(cfg.derivRoot,'extract_IBF_log.txt');

fid = fopen(logFile,'w');

fprintf(fid,'Raw PSD feature extraction\n');
fprintf(fid,'\n');
fprintf(fid,'Subjects : %d\n',numel(cfg.subjects));
fprintf(fid,'Channels : ');

for k=1:numel(cfg.channels)
    fprintf(fid,'%s ',cfg.channels{k});
end

fprintf(fid,'\n');
fprintf(fid,'Beta band : %.1f - %.1f Hz\n',...
    cfg.betaBand(1),cfg.betaBand(2));

fprintf(fid,'Window : %.2f sec\n',cfg.windowSec);

fprintf(fid,'Overlap : %.2f %%\n',100*cfg.overlap);

fprintf(fid,'\n');

for s=1:height(T)

    fprintf(fid,...
        '%s\tFz=%5.2f\tCz=%5.2f\tF3=%5.2f\tF4=%5.2f\tC3=%5.2f\tC4=%5.2f\n',...
        T.Subject{s},...
        T.Fz_IBF(s),...
        T.Cz_IBF(s),...
        T.F3_IBF(s),...
        T.F4_IBF(s),...
        T.C3_IBF(s),...
        T.C4_IBF(s));

end

fclose(fid);

%% ------------------------------------------------------------------------
% SAVE CONFIG
% -------------------------------------------------------------------------

cfg.creationDate = datestr(now);

save(fullfile(cfg.derivRoot,'extract_IBF_config.mat'),'cfg');

%% ------------------------------------------------------------------------
% CLEANUP
% -------------------------------------------------------------------------

clear amp
clear ibf
clear betaIdx
clear fb
clear pb
clear pks
clear locs
clear idx
clear x
clear fs
clear win
clear overlap
clear nfft

disp('Done.')

%% ------------------------------------------------------------------------
% ROI PSD (MEAN OF CHANNELS)
% -------------------------------------------------------------------------

ROI_PSD = cell(numel(cfg.subjects),1);

for s = 1:numel(cfg.subjects)

    subject = cfg.subjects{s};

    setFile = fullfile( ...
        cfg.derivRoot,...
        subject,...
        [subject '_rest_clean.set']);

    if ~exist(setFile,'file')
        continue
    end

    EEG = pop_loadset(setFile);

    fs = EEG.srate;

    win = round(cfg.windowSec*fs);

    overlap = round(cfg.overlap*win);

    if isempty(cfg.nfft)
        nfft = max(256,2^nextpow2(win));
    else
        nfft = cfg.nfft;
    end

    PSDmat = [];

    for c = 1:numel(cfg.channels)

        idx = find(strcmpi({EEG.chanlocs.labels},cfg.channels{c}));

        if isempty(idx)
            continue
        end

        x = double(EEG.data(idx,:));

        [Pxx,f] = pwelch( ...
            x,...
            hann(win),...
            overlap,...
            nfft,...
            fs);

        PSDmat(:,end+1) = Pxx;

    end

    if isempty(PSDmat)
        continue
    end

    ROI_PSD{s}.Subject = subject;
    ROI_PSD{s}.Frequency = f;
    ROI_PSD{s}.PSD = mean(PSDmat,2,'omitnan');

end

save(fullfile(cfg.derivRoot,'ROI_PSD.mat'),'ROI_PSD','-v7.3');

%% ------------------------------------------------------------------------
% ROI FIGURE
% -------------------------------------------------------------------------

figure('Color','w');

hold on

for s = 1:numel(ROI_PSD)

    if isempty(ROI_PSD{s})
        continue
    end

    loglog( ...
        ROI_PSD{s}.Frequency,...
        ROI_PSD{s}.PSD);

end

grid on

xlabel('Frequency (Hz)');
ylabel('PSD');

title('ROI PSD');

exportgraphics( ...
    gcf,...
    fullfile(cfg.derivRoot,'ROI_PSD.png'),...
    'Resolution',300);

close(gcf);

%% ------------------------------------------------------------------------
% ROI PEAK SUMMARY
% -------------------------------------------------------------------------

ROI_Table = table();

ROI_Table.Subject = cfg.subjects';

ROI_IBF = nan(numel(cfg.subjects),1);
ROI_AMP = nan(numel(cfg.subjects),1);

for s = 1:numel(cfg.subjects)

    if isempty(ROI_PSD{s})
        continue
    end

    f = ROI_PSD{s}.Frequency;
    p = ROI_PSD{s}.PSD;

    idx = f>=cfg.betaBand(1) & f<=cfg.betaBand(2);

    fb = f(idx);
    pb = p(idx);

    [pk,lc] = findpeaks(pb);

    if isempty(pk)

        [ROI_AMP(s),ii] = max(pb);
        ROI_IBF(s) = fb(ii);

    else

        [ROI_AMP(s),ii] = max(pk);
        ROI_IBF(s) = fb(lc(ii));

    end

end

ROI_Table.IBF = ROI_IBF;
ROI_Table.Amplitude = ROI_AMP;

writetable(ROI_Table,...
    fullfile(cfg.derivRoot,'ROI_IBF.csv'));

%% ------------------------------------------------------------------------
% ROI SCATTER
% -------------------------------------------------------------------------

figure('Color','w');

scatter(1:numel(cfg.subjects),...
    ROI_IBF,...
    60,...
    'filled');

hold on

yline(cfg.betaBand(1),'--k');
yline(cfg.betaBand(2),'--k');

xlabel('Subject');
ylabel('IBF (Hz)');
title('ROI Beta Peak');

grid on

exportgraphics(gcf,...
    fullfile(cfg.derivRoot,'ROI_IBF.png'),...
    'Resolution',300);

close(gcf);

%% ------------------------------------------------------------------------
% FINAL SAVE
% -------------------------------------------------------------------------

save(fullfile(cfg.derivRoot,'Workspace_IBF.mat'));

%% ------------------------------------------------------------------------
% PSD QC REPORT
% -------------------------------------------------------------------------

QC = table();

QC.Subject = cfg.subjects';

QC.Fz_Peak = T.Fz_PeakDetected;
QC.Cz_Peak = T.Cz_PeakDetected;
QC.F3_Peak = T.F3_PeakDetected;
QC.F4_Peak = T.F4_PeakDetected;
QC.C3_Peak = T.C3_PeakDetected;
QC.C4_Peak = T.C4_PeakDetected;

QC.TotalDetected = ...
      double(QC.Fz_Peak) ...
    + double(QC.Cz_Peak) ...
    + double(QC.F3_Peak) ...
    + double(QC.F4_Peak) ...
    + double(QC.C3_Peak) ...
    + double(QC.C4_Peak);

writetable(QC,...
    fullfile(cfg.derivRoot,'QC_Report.csv'));

%% ------------------------------------------------------------------------
% EXPORT EXCEL
% -------------------------------------------------------------------------

xlsFile = fullfile(cfg.derivRoot,'IBF_Results.xlsx');

writetable(T,xlsFile,'Sheet','Features');

writetable(ChannelSummary,xlsFile,'Sheet','ChannelSummary');

writetable(ROI_Table,xlsFile,'Sheet','ROI');

writetable(QC,xlsFile,'Sheet','QC');

%% ------------------------------------------------------------------------
% SAVE ALL VARIABLES
% -------------------------------------------------------------------------

save(fullfile(cfg.derivRoot,'IBF_Project.mat'),...
    'T',...
    'ROI_Table',...
    'ChannelSummary',...
    'QC',...
    'cfg',...
    'PSD_All',...
    'PSD_Fz',...
    'ROI_PSD',...
    '-v7.3');

%% ------------------------------------------------------------------------
% CLOSE
% -------------------------------------------------------------------------

close all force

clearvars -except ...
    T ...
    ROI_Table ...
    ChannelSummary ...
    QC ...
    cfg

disp('Finished')

