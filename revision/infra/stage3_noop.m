function stage3_noop(params, outFile)
%STAGE3_NOOP  Job function that only produces a tiny output file; used by the batch pre-check to
%   obtain the current environment fingerprint through the normal worker (stage3_job).
jobFunc = params.jobFunc;                                  %#ok<NASGU> recorded for the record only
save(outFile, 'jobFunc');
end
