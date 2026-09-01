function run_triage(cfg)
    fprintf('\n==== TRIAGE: scanning all %d subjects ====\n', numel(cfg.allSubjects));
    rows = struct([]);
    for i = 1:numel(cfg.allSubjects)
        subject = cfg.allSubjects{i};
        try
            hits = dir(fullfile(cfg.bidsRoot, subject, '**', ['*' cfg.taskLabel '*.vhdr']));
            assert(~isempty(hits), 'no .vhdr');
            EEG = pop_loadbv(hits(1).folder, hits(1).name);
            EEG = pop_select(EEG, 'chantype', 'EEG');
            EEG = pop_eegfiltnew(EEG, 'locutoff', 1.0);   % cheap HP to kill drift

            d = EEG.data;                                 % chan x time
            robustAmp = prctile(abs(d(:)), 99.9);         % ignores single spikes
            maxAmp    = max(abs(d(:)));
            chanRMS   = sqrt(mean(d.^2, 2));
            nLoudChan = sum(chanRMS > 5 * median(chanRMS));  % grossly noisy chans

            rows(end+1).subject   = subject;              %#ok<AGROW>
            rows(end).srate       = EEG.srate;
            rows(end).nchan       = EEG.nbchan;
            rows(end).robustAmpUV = round(robustAmp);
            rows(end).maxAmpUV    = round(maxAmp);
            rows(end).nLoudChan   = nLoudChan;
            rows(end).ampFlag     = robustAmp > cfg.ampFlagUV;
            fprintf('  %-8s  robustAmp=%8.0f uV  loudChans=%2d  %s\n', ...
                subject, robustAmp, nLoudChan, ternary(robustAmp>cfg.ampFlagUV,'<-- FLAG',''));
        catch ME
            fprintf('  %-8s  ERROR: %s\n', subject, ME.message);
        end
    end

    T = struct2table(rows);
    T = sortrows(T, 'robustAmpUV', 'descend');   % dirtiest first
    outFile = fullfile(cfg.derivRoot, 'triage_summary.csv');
    writetable(T, outFile);
    fprintf('\nTriage table -> %s\n', outFile);
    fprintf(['NEXT: open it, then pick cfg.pilotSubjects spanning the range\n' ...
             '      (top = dirty, middle = medium, bottom = clean), include a flagged one.\n']);
end

