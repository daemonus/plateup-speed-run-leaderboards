<#
.SYNOPSIS
    Runs the PlateUp leaderboard scraper into a local clone of the data repo, then commits and
    pushes any changes. Intended to be run on a schedule (Task Scheduler) while Steam is running.

.DESCRIPTION
    The scraper is a pure data producer (it writes the scrubbed JSON to --public). This wrapper
    handles the "publish" step so the tool itself stays free of git/credentials:

        1. Optionally fast-forward the local clone so it's in sync.
        2. Run the scraper, writing the scrubbed JSON into <RepoPath>\<SubDir>.
        3. Rebuild index.json from the weeks/ + archive/ folders.
        4. Commit + push only if something actually changed (no empty commits).

    Auth uses your machine's normal git setup (Git Credential Manager or an SSH/deploy key on the
    clone). No secrets live in this script or the tool.

.PARAMETER RepoPath
    Path to the local clone of the leaderboard data repo.

.PARAMETER Branch
    Branch to push to. Default: main.

.PARAMETER SubDir
    Folder within the repo to write the scrubbed JSON into. Default: weeks.

.PARAMETER ArchiveDir
    Optional local folder for the full CSV (includes SteamID). Kept out of the repo; never published.

.PARAMETER ScraperExe
    Path to the built LeaderboardScraper.exe. Defaults to the Release build next to this script;
    pass this explicitly when the script lives in the data repo, away from the tool's build output.

.PARAMETER Week
    Absolute week number to scrape. Omit (or pass a negative value) for the current week.

.PARAMETER NoNames
    Skip persona-name resolution (faster).

.PARAMETER NoPush
    Commit locally but do not push (dry run).

.EXAMPLE
    .\publish-leaderboard.ps1 -RepoPath D:\repos\plateup-leaderboard-data

.EXAMPLE
    .\publish-leaderboard.ps1 -RepoPath D:\repos\plateup-leaderboard-data -Week 67 -NoPush
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepoPath,
    [string] $Branch = 'main',
    [string] $SubDir = 'weeks',
    [string] $ArchiveDir,
    [string] $ScraperExe = "",
    [int]    $Week = -1,
    [switch] $NoNames,
    [switch] $NoPush
)

$ErrorActionPreference = 'Stop'

# Steam and git both write progress to stderr; don't let that abort the script on PS 7+.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-Step($msg) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $msg" }

# ---- Validate inputs --------------------------------------------------------
if (-not (Test-Path $ScraperExe)) {
    throw "Scraper exe not found at '$ScraperExe'. Pass -ScraperExe, or build it (dotnet build -c Release)."
}
if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    throw "'$RepoPath' is not a git repository (no .git folder). Clone the data repo there first."
}

$publicDir = Join-Path $RepoPath $SubDir

# ---- 1. Sync the clone ------------------------------------------------------
Write-Step "Fast-forwarding '$RepoPath' ($Branch)..."
git -C $RepoPath pull --ff-only origin $Branch
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git pull --ff-only failed (diverged or offline); continuing with the local state."
}

# ---- 2. Run the scraper -----------------------------------------------------
# Only the scrubbed JSON (--public) goes into the repo; the full CSV (--archive) stays local.
$scraperArgs = @('--public', $publicDir)
if ($ArchiveDir) { $scraperArgs += @('--archive', $ArchiveDir) }
if ($Week -ge 0) { $scraperArgs += @('--week', $Week) }
if ($NoNames)    { $scraperArgs += '--no-names' }

Write-Step "Running scraper: $ScraperExe $($scraperArgs -join ' ')"
& $ScraperExe @scraperArgs
$scraperExit = $LASTEXITCODE
if ($scraperExit -ne 0) {
    throw "Scraper exited $scraperExit; not committing."
}

# ---- 3. Rebuild the manifest ------------------------------------------------
Write-Step "Rebuilding index.json..."
& $ScraperExe --build-index $RepoPath
if ($LASTEXITCODE -ne 0) {
    throw "Index build failed; not committing."
}

# ---- 4. Commit only if something changed ------------------------------------
git -C $RepoPath add -A
git -C $RepoPath diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Step "No changes to commit. Done."
    exit 0
}

$msg = "leaderboard update: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm')) UTC"
Write-Step "Committing: $msg"
git -C $RepoPath commit -m $msg
if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

# ---- 5. Push ----------------------------------------------------------------
if ($NoPush) {
    Write-Step "Committed locally (-NoPush set); skipping push."
    exit 0
}

Write-Step "Pushing to origin/$Branch..."
git -C $RepoPath push origin $Branch
if ($LASTEXITCODE -ne 0) { throw "git push failed." }

Write-Step "Done."
