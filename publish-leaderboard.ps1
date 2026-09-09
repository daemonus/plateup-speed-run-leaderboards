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
    Optional folder for the full CSV (includes SteamID) + identities.json. Never goes in the PUBLIC
    repo. If this folder is itself a git clone (e.g. the private plateup-speed-run-leaderboards-private
    repo), it is also committed and pushed after the scrape so the identity map gets version history.
    Because these files contain Steam IDs, that repo MUST be private.

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

# Stage everything in a repo and commit + push only when something actually changed (no empty
# commits). Used for both the public and the private repos.
function Publish-Repo {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $RepoBranch,
        [Parameter(Mandatory)] [string] $Message,
        [string] $Label = 'repo',
        [switch] $SkipPush
    )

    git -C $Path add -A
    git -C $Path diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
        Write-Step "[$Label] No changes to commit."
        return
    }

    Write-Step "[$Label] Committing: $Message"
    git -C $Path commit -m $Message
    if ($LASTEXITCODE -ne 0) { throw "[$Label] git commit failed." }

    if ($SkipPush) {
        Write-Step "[$Label] Committed locally (-NoPush set); skipping push."
        return
    }

    Write-Step "[$Label] Pushing to origin/$RepoBranch..."
    git -C $Path push origin $RepoBranch
    if ($LASTEXITCODE -ne 0) { throw "[$Label] git push failed." }
}

# ---- Validate inputs --------------------------------------------------------
if (-not (Test-Path $ScraperExe)) {
    throw "Scraper exe not found at '$ScraperExe'. Pass -ScraperExe, or build it (dotnet build -c Release)."
}
if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    throw "'$RepoPath' is not a git repository (no .git folder). Clone the data repo there first."
}
$publicDir = Join-Path $RepoPath $SubDir

# When the archive folder is itself a git clone (the private repo), we also commit + push it.
$archiveIsRepo = $ArchiveDir -and (Test-Path (Join-Path $ArchiveDir '.git'))

# ---- 1. Sync the clone ------------------------------------------------------
Write-Step "Fast-forwarding '$RepoPath' ($Branch)..."
git -C $RepoPath pull --ff-only origin $Branch
if ($LASTEXITCODE -ne 0) {
    Write-Warning "git pull --ff-only failed (diverged or offline); continuing with the local state."
}

if ($archiveIsRepo) {
    Write-Step "Fast-forwarding '$ArchiveDir' ($Branch)..."
    git -C $ArchiveDir pull --ff-only origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git pull --ff-only failed for the archive repo; continuing with the local state."
    }
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

# ---- 4. Commit + push each repo (only when it actually changed) -------------
$stamp = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm')

Publish-Repo -Path $RepoPath -RepoBranch $Branch `
    -Message "leaderboard update: $stamp UTC" -Label 'public' -SkipPush:$NoPush

if ($archiveIsRepo) {
    Publish-Repo -Path $ArchiveDir -RepoBranch $Branch `
        -Message "leaderboard backup: $stamp UTC" -Label 'archive' -SkipPush:$NoPush
}

Write-Step "Done."
