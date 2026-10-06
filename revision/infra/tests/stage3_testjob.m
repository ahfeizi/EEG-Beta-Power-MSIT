function stage3_testjob(params, outFile)
%STAGE3_TESTJOB  Synthetic job function for the runner tests only (no data). params.mode:
%   'ok'            deterministic result (y = x * x', x = rand(50) from the worker's seeded RNG),
%                   after params.sleepS seconds
%   'error'         injected worker error
%   'slow_save'     saves its output, prints PARTIAL_SAVED, then waits params.sleepS seconds before
%                   returning (the worker renames the file only afterwards), on attempt
%                   params.slowOnAttempt only; used to kill the process mid-save
%   'replica_diff'  like 'ok', but y(1) + 1 on the replicas listed in params.diffReplicas
sleepS = 0; if isfield(params, 'sleepS'), sleepS = double(params.sleepS); end
x = rand(50);
y = x * x';
switch params.mode
    case 'ok'
        pause(sleepS);
        save(outFile, 'y');
    case 'error'
        error('stage3:test', 'injected worker error');
    case 'slow_save'
        save(outFile, 'y');
        if double(params.attempt) == double(params.slowOnAttempt)
            fprintf('PARTIAL_SAVED\n');
            pause(sleepS);
        end
    case 'replica_diff'
        if any(strcmp(params.replica, cellstr(params.diffReplicas))), y(1) = y(1) + 1; end
        save(outFile, 'y');
    otherwise
        error('stage3:test', 'unknown test mode %s', params.mode);
end
end
