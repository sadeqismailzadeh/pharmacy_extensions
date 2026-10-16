<#
  Updater for unpacked Chrome extensions hosted in one GitHub repo.

  Git only:
    1. git already installed -> use it
    2. no git                -> download MinGit (official minimal Git for Windows,
                                no installer, no admin rights) into a private tools
                                folder and use that
    Then: fetch the latest commit and reset the working folder to it.

  Does NOT touch Chrome, the registry, or policies.
  After an update you must click "Reload" on each extension in chrome://extensions
  (Chrome offers no way for any script to do that for unpacked extensions).
#>
param(
  [switch]$OpenChrome   # open chrome://extensions when something changed
)

# ===================== EDIT THESE =====================
$Owner       = "OWNER"        # GitHub user/org
$Repo        = "REPO"         # repository name
$Branch      = "main"         # branch to track
$Extensions  = @("dana-checker", "tamin-calc")   # sub-folders that are extensions
# Fixed install location. Do NOT change it later: Chrome derives an unpacked
# extension's ID from its path, so a new path = a new extension (settings lost).
$InstallRoot = Join-Path $env:LOCALAPPDATA "InsuranceExtensions"
# ======================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoUrl   = "https://github.com/$Owner/$Repo.git"
$ToolsDir  = "$InstallRoot-tools"            # kept outside the repo folder on purpose
$MinGitDir = Join-Path $ToolsDir "mingit"

function Get-ExtVersion([string]$dir) {
  $m = Join-Path $dir "manifest.json"
  if (-not (Test-Path $m)) { return $null }
  try {
    $json = [IO.File]::ReadAllText($m, [Text.Encoding]::UTF8) | ConvertFrom-Json
    return [string]$json.version
  } catch { return "?" }
}

# ---------- MinGit: download / keep up to date ----------
function Ensure-MinGit {
  $gitExe  = Join-Path $MinGitDir "cmd\git.exe"
  $verFile = Join-Path $MinGitDir "version.txt"
  $have    = ""
  if (Test-Path $verFile) { $have = ([IO.File]::ReadAllText($verFile)).Trim() }

  try {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
             -Headers @{ "User-Agent" = "ext-updater" } -UseBasicParsing
  } catch {
    # offline / rate-limited: keep using what we have
    if (Test-Path $gitExe) { return $gitExe }
    throw
  }

  if ((Test-Path $gitExe) -and $have -eq $rel.tag_name) { return $gitExe }   # already current

  if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { $suffix = "arm64" }
  elseif ([Environment]::Is64BitOperatingSystem) { $suffix = "64-bit" }
  else { $suffix = "32-bit" }

  $asset = $rel.assets | Where-Object { $_.name -match ("^MinGit-[\d\.]+-" + $suffix + "\.zip$") } | Select-Object -First 1
  if (-not $asset) { throw "No MinGit $suffix zip found in release $($rel.tag_name)." }

  $tmp = Join-Path $env:TEMP ("mingit_" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $zip = Join-Path $tmp $asset.name

  Write-Host "Downloading $($asset.name) ($($rel.tag_name)) ..."
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing

  # integrity check (GitHub asset digest, else the hash listed in the release notes)
  $expected = $null
  if ($asset.PSObject.Properties.Name -contains "digest" -and $asset.digest -match "^sha256:([0-9a-fA-F]{64})$") {
    $expected = $Matches[1]
  } elseif ($rel.body -match ([regex]::Escape($asset.name) + "\s*\|?\s*([0-9a-fA-F]{64})")) {
    $expected = $Matches[1]
  }
  if ($expected) {
    $actual = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash
    if ($actual -ne $expected.ToUpper()) { throw "MinGit SHA256 mismatch - aborting." }
  } else {
    Write-Host "Warning: no published SHA256 found for MinGit; skipping hash check." -ForegroundColor Yellow
  }

  if (Test-Path $MinGitDir) { Remove-Item $MinGitDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $MinGitDir | Out-Null
  Expand-Archive -Path $zip -DestinationPath $MinGitDir -Force
  [IO.File]::WriteAllText($verFile, $rel.tag_name)
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

  if (-not (Test-Path $gitExe)) { throw "MinGit extracted but cmd\git.exe is missing." }
  return $gitExe
}

# ---------- git sync: always ends identical to origin/<branch> ----------
function Sync-WithGit([string]$git) {
  $base = @("-C", $InstallRoot, "-c", "core.autocrlf=false")

  if (-not (Test-Path (Join-Path $InstallRoot ".git"))) {
    & $git -C $InstallRoot init -q
    if ($LASTEXITCODE -ne 0) { throw "git init failed." }
    & $git -C $InstallRoot remote add origin $RepoUrl
  } else {
    & $git -C $InstallRoot remote set-url origin $RepoUrl
  }

  & $git @base fetch -q --depth 1 origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "git fetch failed (network, or repo/branch name wrong?)." }

  & $git @base reset -q --hard FETCH_HEAD
  if ($LASTEXITCODE -ne 0) { throw "git reset failed." }

  # remove stray files left over from older versions, only inside the extension folders
  & $git @base clean -fdq -- $Extensions
}

try {
  New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

  $before = @{}
  foreach ($e in $Extensions) { $before[$e] = Get-ExtVersion (Join-Path $InstallRoot $e) }

  # find git: system first, otherwise MinGit
  $sys = Get-Command git -ErrorAction SilentlyContinue
  if ($sys) { $git = $sys.Source }
  else      { $git = Ensure-MinGit }     # throws on failure

  Write-Host "Syncing with git ($git) ..."
  Sync-WithGit $git

  Write-Host ""
  $changed = $false
  foreach ($e in $Extensions) {
    $path = Join-Path $InstallRoot $e
    $old  = $before[$e]
    $new  = Get-ExtVersion $path
    if (-not $old)         { Write-Host "[NEW]        $e  ->  v$new"; $changed = $true }
    elseif ($old -ne $new) { Write-Host "[UPDATED]    $e  v$old -> v$new"; $changed = $true }
    else                   { Write-Host "[UP-TO-DATE] $e  v$new" }
    Write-Host "             Load unpacked path: $path"
  }

  Write-Host ""
  if ($changed) {
    Write-Host "Next step: open chrome://extensions and click Reload on the updated extension(s)."
    Write-Host "(First install: enable Developer mode, then Load unpacked and pick the paths above.)"
    if ($OpenChrome) { Start-Process "chrome" "chrome://extensions" }
  } else {
    Write-Host "Nothing to do. (If you pushed a change without bumping manifest.json version, reload anyway.)"
  }
}
catch {
  Write-Host ""
  Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
  exit 1
}
