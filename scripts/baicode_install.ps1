#Requires -Version 5.1
<#
.SYNOPSIS
    BAI code installer for Windows.

.DESCRIPTION
    Downloads the BAI code wheel manifest, detects the current platform and
    Python version, then installs the matching wheel via pip.

.PARAMETER NoVenv
    Skip the virtual environment creation prompt.
    Also honoured when the environment variable BAI_NO_VENV is set to "1".

.NOTES
    Requires: PowerShell 5.1+, Python 3.10+

    If script execution is blocked by the execution policy, run once:
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#>
[CmdletBinding()]
param(
    [switch]$NoVenv
)

Set-StrictMode -Version Latest

$MANIFEST_URL = "https://download.bankofai.io/download/baicode_release_whls.txt"
$VENV_DIR     = ".venv"

# ── helpers ─────────────────────────────────────────────────────────────────

function Write-Info {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Write-Err {
    param([string]$Message)
    [Console]::Error.WriteLine("Error: $Message")
}

function Exit-WithError {
    param([string]$Message)
    Write-Err $Message
    exit 1
}

# ── fetch manifest ───────────────────────────────────────────────────────────

function Get-Manifest {
    Write-Info "Fetching package manifest..."
    try {
        $response = Invoke-WebRequest -Uri $MANIFEST_URL -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        return $response.Content
    }
    catch {
        Exit-WithError ("Failed to download manifest from: $MANIFEST_URL`n" +
                        "Please check your network connection.`n" +
                        "Details: $($_.Exception.Message)")
    }
}

# ── manifest parsing ─────────────────────────────────────────────────────────
# Returns an array of [PSCustomObject]@{ Url = ... } entries
# from the first [vX.Y.Z] segment (or all lines if no segment headers).
# Each line may optionally contain a " | sha256:..." field which is ignored.

function Get-CandidateEntries {
    param([string]$Content)

    $lines     = ($Content -replace "`r`n", "`n") -split "`n"
    $hasHeader = $false
    $inSeg     = $false
    $done      = $false
    $segEntries = @()
    $nohEntries = @()

    foreach ($line in $lines) {
        if ($done) { break }
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[v[^\]]*\]') {
            $hasHeader = $true
            if ($inSeg) { $done = $true } else { $inSeg = $true }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith('#'))               { continue }

        # Extract URL only; ignore optional " | sha256:..." suffix
        $parts = $trimmed -split '\s*\|\s*', 2
        $url   = $parts[0].Trim()
        $entry = [PSCustomObject]@{ Url = $url }

        if ($inSeg)              { $segEntries += $entry }
        elseif (-not $hasHeader) { $nohEntries += $entry }
    }

    if ($hasHeader) { return $segEntries }
    else            { return $nohEntries }
}

# ── platform detection ────────────────────────────────────────────────────────

function Get-PlatformTag {
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        "AMD64" { return "win_amd64" }
        default {
            Exit-WithError "Unsupported architecture: $arch (only AMD64/x86_64 is supported)"
        }
    }
}

# ── python detection ──────────────────────────────────────────────────────────

function Get-PythonInfo {
    $candidates = @("python", "python3", "py")
    foreach ($cmd in $candidates) {
        try {
            $verOutput = & $cmd --version 2>&1
            if ($verOutput -match "Python (\d+)\.(\d+)") {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 10)) {
                    return @{
                        Cmd = $cmd
                        Ver = "$major.$minor"
                        Tag = "cp$major$minor"
                    }
                }
            }
        }
        catch { continue }
    }
    Exit-WithError ("Python 3.10+ is required but not found.`n" +
                    "Please install from: https://www.python.org/downloads/")
}

# ── wheel matching ────────────────────────────────────────────────────────────
# Returns the matching entry object { Url }

function Find-WheelEntry {
    param(
        [object[]]$Entries,
        [string]$PythonTag,
        [string]$PlatformTag
    )

    $matched = @()
    foreach ($entry in $Entries) {
        $fname = Split-Path $entry.Url -Leaf
        if ($fname -notlike "*-$PythonTag-*") { continue }
        if ($fname -notlike "*$PlatformTag*")  { continue }
        $matched += $entry
    }

    if ($matched.Count -eq 0) {
        Write-Err "No matching wheel found."
        Write-Host "  Python tag : $PythonTag"
        Write-Host "  Platform   : $PlatformTag"
        Write-Host "  Available wheels:"
        foreach ($e in $Entries) { Write-Host "    $(Split-Path $e.Url -Leaf)" }
        exit 1
    }
    if ($matched.Count -gt 1) {
        Write-Host "Warning: Multiple matching wheels found, using first." -ForegroundColor Yellow
    }
    return $matched[0]
}

# ── venv setup ────────────────────────────────────────────────────────────────
# Returns the path to the venv python.exe, or $null if venv was not created.

function Invoke-VenvSetup {
    param(
        [string]$PythonCmd,
        [bool]$SkipPrompt
    )

    if ($SkipPrompt -or $env:BAI_NO_VENV -eq "1") { return $null }

    $answer = Read-Host "Create a virtual environment at $VENV_DIR? [y/N]"
    if ($answer -match '^[yY](es)?$') {
        Write-Info "Creating virtual environment at $VENV_DIR ..."
        & $PythonCmd -m venv $VENV_DIR
        if ($LASTEXITCODE -ne 0) {
            Exit-WithError "Failed to create virtual environment."
        }

        $venvPython = Join-Path $VENV_DIR "Scripts\python.exe"

        # Ensure pip is available inside the venv (may be absent on Debian/Ubuntu).
        $venvPip = Join-Path $VENV_DIR "Scripts\pip.exe"
        if (-not (Test-Path $venvPip)) {
            Write-Info "pip not found in venv, bootstrapping via ensurepip..."
            & $venvPython -m ensurepip --upgrade
            if ($LASTEXITCODE -ne 0) {
                Exit-WithError "Failed to bootstrap pip in virtual environment."
            }
        }

        Write-Info "Virtual environment created."
        return $venvPython
    }
    return $null
}

# ── install ───────────────────────────────────────────────────────────────────

function Install-Wheel {
    param(
        [object]$Entry,
        [string]$PythonCmd,
        [string]$VenvPython   # may be empty string / $null
    )

    $fname     = Split-Path $Entry.Url -Leaf
    $pipPython = if ($VenvPython) { $VenvPython } else { $PythonCmd }

    Write-Info "Installing: $fname"
    & $pipPython -m pip install $Entry.Url
    if ($LASTEXITCODE -ne 0) {
        Exit-WithError "Installation failed. See pip output above."
    }

    Write-Host "`nInstallation complete!" -ForegroundColor Green
    if ($VenvPython) {
        Write-Host "BAI code installed into $VENV_DIR"
        Write-Host "🚀 To activate in future sessions:"
        Write-Host "     .\$VENV_DIR\Scripts\Activate.ps1"
    }
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host "  Next steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  🚀 Set your API key:" -ForegroundColor Cyan
    Write-Host "       `$env:BAI_API_KEY = `"sk-...`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ✨ Try BAI code at once:" -ForegroundColor Cyan
    Write-Host "       baicode" -ForegroundColor Cyan
    Write-Host "==============================================" -ForegroundColor Cyan
}

# ── main ──────────────────────────────────────────────────────────────────────

$manifest        = Get-Manifest
$platformTag     = Get-PlatformTag
$pyInfo          = Get-PythonInfo

Write-Info "Python $($pyInfo.Ver) ($($pyInfo.Tag)) | Platform: $platformTag"

$candidateEntries = Get-CandidateEntries -Content $manifest
$wheelEntry       = Find-WheelEntry -Entries $candidateEntries -PythonTag $pyInfo.Tag -PlatformTag $platformTag

Write-Info "Matched: $(Split-Path $wheelEntry.Url -Leaf)"

$venvPython       = Invoke-VenvSetup -PythonCmd $pyInfo.Cmd -SkipPrompt $NoVenv.IsPresent
Install-Wheel     -Entry $wheelEntry -PythonCmd $pyInfo.Cmd -VenvPython $venvPython
