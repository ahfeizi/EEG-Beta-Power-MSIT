# runner_config.psd1 -- configuration of the S3a-INF-1 runner. Every value cites its decision.
# Its SHA-256 is recorded in every job fingerprint and every batch summary. ASCII only.
@{
    # ---- paths (S3a-D1-amend; S3a-INF-1 sec. 1)
    MatlabExe        = 'C:\Program Files\MATLAB\R2022b\bin\win64\MATLAB.exe'    # direct launch: PID = computing process
    EegOutRoot       = 'D:\Revision_EEG'                                        # replicas, state, journal: <EegOutRoot>\stage3_runs\<BatchId>
    OutRoot          = 'C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output'   # summary copies: <OutRoot>\stage3\runs
    RawRoot          = 'D:\Revision_Raw\ds004621'                               # verified raw copy; E: is not read by jobs
    VerifiedManifest = 'C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output\stage3\raw_copy\verified_manifest.tsv'
    BlockTable       = 'C:\Users\Amirhossein\Desktop\Prof. Nasrabadi\Revision_Output\stage3\d4e_block_clipping.csv'
    ExtraMatlabPaths = @()

    # ---- process configuration (S3a-INF-1 sec. 1, sec. 2)
    Threads    = 2
    MklCbwr    = 'AUTO'
    SeedGlobal = 1
    # per-step seed constants: none needed yet (D5-0 and the burn-in reseed with SeedGlobal);
    # functions that reseed internally (recorded, not set by us):
    InternalSeeds = @{ clean_channels = "rng('default')"; picard = '5489'; runica = "rand('state',0) with 'reset_randomseed','no'"; iclabel = "rng('default'), then rng('shuffle')" }
    StepSeeds     = @{}

    # ---- gates between jobs (S3a-INF-1 sec. 6; thermal monitoring removed by S3a-INF-1-amend1)
    CooldownS               = 30                        # fixed cool-down before every job (S3a-D5b-cooldown; was 120)
    PollS                   = 2
    ProcessorStateMaxPct    = 85                        # AC and DC, pre-check 2 (S3a-INF-1 sec. 6, ladder rule)
    HardwareChangeNotBefore = '2026-10-06T19:40:46'     # S3a-HW-1: paste replaced before the ladder's first row

    # ---- attempts, timeouts, acceptance, stop rule, disk (S3a-INF-1 sec. 4, 6, 8; clar1; amend1)
    MaxAttemptsPerReplica    = 5                        # amend1: crashes are expected (BurnIn mode: 1)
    AcceptanceMinCompleted   = 9                        # amend1: completed MSIT+ replicas of 11 needed for PASS
    MaxQuarantinedRecordings = 3                        # amend1: the batch stops at >= 3 quarantined recordings
    BurnInIterations       = 436                         # fixed N, S3a-INF-1-clar1 (calibration 2026-10-07)
    BurnInIterationSeconds = 8.25                        # calibrated s per iteration; timeout 3 x 436 x 8.25 = 10791 s
    AcceptanceTimeoutS    = 1800                        # acceptance and burn-in calibration jobs (clar1)
    CompareTimeoutS       = 900
    DiskMinFreeGB_EegOut  = 15
    DiskOutputFactor      = 3
    DiskMinFreeGB_OutRoot = 5

    # ---- synthetic tests only; must stay $false for real runs
    TestMode     = $false
    TestTimeoutS = @{}
}
