<#
================================================================================
  update-extensions.ps1  -  updater for unpacked Chrome extensions on GitHub
================================================================================

  WHAT THIS SCRIPT DOES
  ---------------------
  Keeps a local copy of your GitHub repository (which contains one or more
  unpacked Chrome extensions) in a fixed folder on the user's PC, and brings it
  up to date with the latest commit on GitHub.

  HOW IT GETS GIT
  ---------------
    1. If git is already installed on the PC, it uses that.
    2. If not, it downloads "MinGit" (the official minimal Git for Windows
       build, a plain zip: no installer, no admin rights) into a private tools
       folder and uses that instead.

  WHAT IT DOES NOT DO
  -------------------
  It never touches Chrome itself, the registry, or any policy. It only updates
  files in a normal folder. That is why Chrome shows no security warning.

  WHAT THE USER MUST DO AFTER AN UPDATE
  -------------------------------------
  Open chrome://extensions and click the "Reload" button on each updated
  extension. Chrome gives no way for any script to do this for unpacked
  extensions.

  FIRST-TIME SETUP FOR A USER
  ---------------------------
  Run the script once. It prints the folder paths. Then in chrome://extensions:
  turn on "Developer mode", click "Load unpacked", and pick each printed path.
#>

# -----------------------------------------------------------------------------
# Command-line switch.
#   -OpenChrome : when something changed, open chrome://extensions for the user.
# update.bat passes this switch. A scheduled task can leave it off to stay quiet.
# -----------------------------------------------------------------------------
param(
  [switch]$OpenChrome
)

# ===================== SETTINGS: EDIT THESE =====================

# GitHub account (user or organization) that owns the repository.
$Owner       = "OWNER"

# Repository name. The repo must be PUBLIC (no login is used).
$Repo        = "REPO"

# Branch to follow. Users always get the newest commit of this branch.
$Branch      = "main"

# Folders INSIDE the repo that are extensions (each must contain manifest.json).
# Used for the version report and for cleaning leftover files.
$Extensions  = @("dana-checker", "tamin-calc")

# Where the repo is stored on the user's PC.
# WARNING: do not change this after users installed the extensions. Chrome builds
# an unpacked extension's ID from its folder path, so a new path means a NEW
# extension and the old one's saved settings are lost.
$InstallRoot = Join-Path $env:LOCALAPPDATA "InsuranceExtensions"

# ================================================================

# Stop the script immediately on any error, so the catch block at the bottom
# can show a clear message instead of continuing in a broken state.
$ErrorActionPreference = "Stop"

# Old Windows PowerShell (5.1) may default to outdated TLS. GitHub requires
# TLS 1.2, so force it for all downloads below.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Derived values (computed from the settings above, no need to edit):
$RepoUrl   = "https://github.com/$Owner/$Repo.git"   # address git will fetch from
$ToolsDir  = "$InstallRoot-tools"                    # private tools folder; kept OUTSIDE the repo folder
                                                     # so downloaded git never shows up as "untracked files"
$MinGitDir = Join-Path $ToolsDir "mingit"            # where MinGit gets extracted


# -----------------------------------------------------------------------------
# Get-ExtVersion
#   Reads the "version" field from <folder>\manifest.json.
#   Returns:  the version string, $null if the folder/manifest does not exist
#             (e.g. first install), or "?" if the manifest cannot be parsed.
#   Used only to tell the user "NEW / UPDATED / UP-TO-DATE" at the end.
# -----------------------------------------------------------------------------
function Get-ExtVersion([string]$dir) {
  $m = Join-Path $dir "manifest.json"
  if (-not (Test-Path $m)) { return $null }
  try {
    # Read as UTF-8 explicitly: the manifests contain Persian text, and
    # PowerShell 5.1 would otherwise guess the wrong encoding.
    $json = [IO.File]::ReadAllText($m, [Text.Encoding]::UTF8) | ConvertFrom-Json
    return [string]$json.version
  } catch { return "?" }
}


# -----------------------------------------------------------------------------
# Ensure-MinGit
#   Makes sure a working copy of MinGit exists in $MinGitDir and is current.
#   Returns the full path to git.exe. Throws an error if that is impossible.
#   Only called when the PC has no git of its own.
# -----------------------------------------------------------------------------
function Ensure-MinGit {
  $gitExe  = Join-Path $MinGitDir "cmd\git.exe"        # the executable we want
  $verFile = Join-Path $MinGitDir "version.txt"        # remembers which release is installed

  # Which MinGit release do we already have? (empty text if none)
  $have = ""
  if (Test-Path $verFile) { $have = ([IO.File]::ReadAllText($verFile)).Trim() }

  # Ask GitHub what the latest Git for Windows release is.
  # (GitHub's API rejects requests without a User-Agent header, hence the header.)
  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
             -Headers @{ "User-Agent" = "ext-updater" } -UseBasicParsing
  } catch {
    # No internet, or GitHub rate limit hit. If we already have a MinGit from an
    # earlier run, just keep using it; otherwise we cannot continue.
    if (Test-Path $gitExe) { return $gitExe }
    throw
  }

  # Already have exactly the latest release? Nothing to download.
  if ((Test-Path $gitExe) -and $have -eq $rel.tag_name) { return $gitExe }

  # Choose the MinGit build that matches this PC's CPU:
  #   ARM64 PC -> "arm64",  normal 64-bit PC -> "64-bit",  old 32-bit PC -> "32-bit"
  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { $suffix = "arm64" }
  elseif ([Environment]::Is64BitOperatingSystem) { $suffix = "64-bit" }
  else { $suffix = "32-bit" }

  # Find the right file among the release's downloads. The pattern accepts
  # "MinGit-<version>-<suffix>.zip" and so skips the experimental "busybox" variants.
  $asset = $rel.assets | Where-Object { $_.name -match ("^MinGit-[\d\.]+-" + $suffix + "\.zip$") } | Select-Object -First 1
  if (-not $asset) { throw "No MinGit $suffix zip found in release $($rel.tag_name)." }

  # Download into a unique temporary folder.
  $tmp = Join-Path $env:TEMP ("mingit_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp $asset.name

  Write-Host "Downloading $($asset.name) ($($rel.tag_name)) ..."
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

  # --- Integrity check: make sure the download was not corrupted or tampered with.
  # First choice: the SHA256 that GitHub attaches to the file ("digest" field).
  # Second choice: the SHA256 printed in the release notes next to the file name.
  $expected = $null
  if ($asset.PSObject.Properties.Name -contains "digest" -and $asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
    $expected = $Matches[1]
  } elseif ($rel.body -match ([regex]::Escape($asset.name) + "\s*\|?\s*([0-9a-fA-F]{64})")) {
    $expected = $Matches[1]
  }
  if ($expected) {
    # Compute the real hash of the downloaded file and compare.
    $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
    if ($actual -ne $expected.ToUpper()) { throw "MinGit SHA256 mismatch - aborting." }
  } else {
    # No published hash found: continue, but tell the user the check was skipped.
    Write-Host "Warning: no published SHA256 found for MinGit; skipping hash check." -ForegroundColor Yellow
  }

  # Replace any older MinGit with the new one.
  if (Test-Path $MinGitDir) { Remove-Item $MinGitDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $MinGitDir | Out-Null
  Expand-Archive -Path $zip -DestinationPath $MinGitDir -Force

  # Remember which release we installed (checked on the next run, see above).
  [IO.File]::WriteAllText($verFile, $rel.tag_name)

  # Delete the temporary download.
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

  # Final sanity check, then hand back the path.
  if (-not (Test-Path $gitExe)) { throw "MinGit extracted but cmd\git.exe is missing." }
  return $gitExe
}


# -----------------------------------------------------------------------------
# Sync-WithGit
#   Makes $InstallRoot identical to the latest commit of $Branch on GitHub.
#   Works for BOTH the first install and every later update.
#
#   Why "fetch + reset --hard" instead of "git pull"?
#   "pull" can fail with merge conflicts if files changed locally. "reset --hard"
#   always forces the folder to match GitHub exactly, so it cannot get stuck.
#   "--depth 1" downloads only the newest snapshot, not the whole history.
#
#   Note on "$LASTEXITCODE": PowerShell stores the exit code of the last external
#   program there. 0 means success, anything else means git reported a failure.
# -----------------------------------------------------------------------------
function Sync-WithGit([string]$git) {
  # Options used with every git call below:
  #   -C <folder>             run git as if started inside $InstallRoot
  #   -c core.autocrlf=false  do not rewrite line endings; keep files byte-identical to GitHub
  $base = @("-C", $InstallRoot, "-c", "core.autocrlf=false")

  if (-not (Test-Path (Join-Path $InstallRoot ".git"))) {
    # First run: the folder is not a git repository yet. Turn it into one and
    # tell it where GitHub is ("origin"). This also works if the folder already
    # contains files.
    & $git -C $InstallRoot init -q
    if ($LASTEXITCODE -ne 0) { throw "git init failed." }
    & $git -C $InstallRoot remote add origin $RepoUrl
  } else {
    # Later runs: make sure "origin" still points at the address in the settings
    # (in case $Owner or $Repo were changed).
    & $git -C $InstallRoot remote set-url origin $RepoUrl
  }

  # Download the newest snapshot of the branch (quiet, no history).
  & $git @base fetch -q --depth 1 origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "git fetch failed (network, or repo/branch name wrong?)." }

  # Force every tracked file to match what was just downloaded.
  # FETCH_HEAD = "the commit fetch just retrieved".
  & $git @base reset -q --hard FETCH_HEAD
  if ($LASTEXITCODE -ne 0) { throw "git reset failed." }

  # Delete leftover files that no longer exist on GitHub (e.g. a file you removed
  # in a newer version). "clean" is limited to the extension folders only.
  & $git @base clean -fdq -- $Extensions
}


# =============================================================================
# MAIN PROGRAM
# Everything is inside try/catch: any error jumps to the catch block at the end,
# which prints it in red and exits with code 1.
# =============================================================================
try {
  # Make sure the install folder exists (does nothing if it already does).
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

  # Remember the version of every extension BEFORE updating, so we can show
  # "v1.1 -> v1.2" afterwards. ($null means "not installed yet".)
  $before = @{}
  foreach ($e in $Extensions) { $before[$e] = Get-ExtVersion (Join-Path $InstallRoot $e) }

  # Find git: use the system's git if there is one, otherwise get MinGit.
  $sys = Get-Command git -ErrorAction SilentlyContinue
  if ($sys) { $git = $sys.Source }
  else      { $git = Ensure-MinGit }          # throws an error if this fails

  # Do the actual update.
  Write-Host "Syncing with git ($git) ..."
  Sync-WithGit $git

  # ---- Report -----------------------------------------------------------------
  Write-Host ""
  $changed = $false
  foreach ($e in $Extensions) {
    $path = Join-Path $InstallRoot $e
    $old  = $before[$e]                       # version before the update
    $new  = Get-ExtVersion $path              # version after the update

    if (-not $old)         { Write-Host "[NEW]        $e  ->  v$new"; $changed = $true }       # first install
    elseif ($old -ne $new) { Write-Host "[UPDATED]    $e  v$old -> v$new"; $changed = $true }  # version number changed
    else                   { Write-Host "[UP-TO-DATE] $e  v$new" }                             # same version

    # Always print the folder, because this is what "Load unpacked" needs.
    Write-Host "             Load unpacked path: $path"
  }

  # ---- Tell the user what to do next -----------------------------------------
  Write-Host ""
  if ($changed) {
    Write-Host "Next step: open chrome://extensions and click Reload on the updated extension(s)."
    Write-Host "(First install: enable Developer mode, then Load unpacked and pick the paths above.)"
    if ($OpenChrome) { Start-Process "chrome" "chrome://extensions" }
  } else {
    # The version check only compares manifest.json "version". If you change code
    # but forget to raise the version number, the files still update on disk, but
    # this message appears anyway - so remind the user.
    Write-Host "Nothing to do. (If you pushed a change without bumping manifest.json version, reload anyway.)"
  }
}
catch {
  # Any error above lands here: show the message in red and return exit code 1
  # (so Task Scheduler or other callers can detect the failure).
  Write-Host ""
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}