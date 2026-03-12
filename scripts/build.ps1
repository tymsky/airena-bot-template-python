# build.ps1 - Package bot into a single Linux binary using Nuitka (via Docker).
#
# Produces a single-file Linux ELF binary that can be shared and used with match.ps1.
# The build runs inside a Docker container so no local compiler or Nuitka install is needed.
#
# Prerequisites:
#   - Docker Desktop (Linux containers)
#
# Usage:
#   .\scripts\build.ps1                    # build dist/bot from main.py
#   .\scripts\build.ps1 -Script my_bot.py  # build from a different entry script
#   .\scripts\build.ps1 -OutputName mybot  # custom output filename

[CmdletBinding()]
param(
    [string]$Script = "main.py",
    [string]$OutputName = "bot"
)

$ErrorActionPreference = "Stop"

# ---------- Resolve paths ----------
$BotRoot = (Resolve-Path "$PSScriptRoot\..").Path
$EntryScript = Join-Path $BotRoot $Script
$DistDir = Join-Path $BotRoot "dist"

if (-not (Test-Path $EntryScript)) {
    Write-Host "[ERROR] Entry script not found: $EntryScript" -ForegroundColor Red
    exit 1
}

# ---------- Check Docker ----------
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[ERROR] Docker is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker daemon is not running." -ForegroundColor Red
    exit 1
}

# ---------- Display config ----------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " AiRENA Bot Packager (Nuitka/Docker)"    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Entry:  $Script"
Write-Host "[INFO] Output: dist/$OutputName"
Write-Host ""

# ---------- Ensure dist dir exists ----------
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

# ---------- Build inside Docker ----------
Write-Host "[STEP] Building with Nuitka --onefile inside Docker..." -ForegroundColor Cyan
Write-Host "       This may take a few minutes on the first run." -ForegroundColor Yellow
Write-Host ""

$dockerBotRoot = $BotRoot -replace '\\', '/'
$dockerDistDir = $DistDir -replace '\\', '/'

# Build the bash command as a semicolon-joined string to avoid
# Windows CRLF line-ending issues with PowerShell here-strings.
$buildCmd = @(
    "set -e",
    "echo '[build] Installing build tools...'",
    "apt-get update -qq && apt-get install -y -qq gcc patchelf ccache > /dev/null 2>&1",
    "echo '[build] Installing Nuitka and bot dependencies...'",
    "pip install --quiet nuitka ordered-set",
    "if [ -f /src/requirements.txt ]; then pip install --quiet -r /src/requirements.txt; fi",
    "echo '[build] Copying source...'",
    "cp -r /src /build",
    "cd /build",
    "echo '[build] Compiling with Nuitka --onefile...'",
    "python -m nuitka --onefile --output-filename=$OutputName --output-dir=/out --assume-yes-for-downloads --follow-imports --remove-output $Script",
    "cp /out/$OutputName /dist/$OutputName",
    "chmod +x /dist/$OutputName",
    "echo '[build] Done.'"
) -join " && "

docker run --rm `
    -v "${dockerBotRoot}:/src:ro" `
    -v "${dockerDistDir}:/dist" `
    python:3.11-slim `
    bash -c $buildCmd

$buildExitCode = $LASTEXITCODE

if ($buildExitCode -ne 0) {
    Write-Host "[ERROR] Build failed with exit code $buildExitCode." -ForegroundColor Red
    exit $buildExitCode
}

# ---------- Verify output ----------
$outputBin = Join-Path $DistDir $OutputName
if (-not (Test-Path $outputBin)) {
    Write-Host "[ERROR] Expected output not found: $outputBin" -ForegroundColor Red
    exit 1
}

$fileSize = (Get-Item $outputBin).Length
$fileSizeMB = [math]::Round($fileSize / 1MB, 1)

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Build complete!"                         -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "[INFO] Output: $outputBin"
Write-Host "[INFO] Size:   $fileSizeMB MB"
Write-Host "[INFO] Format: Linux ELF binary (single file)"
Write-Host ""
Write-Host "Run a match:"
Write-Host "  .\scripts\match.ps1 -Bot1 dist/$OutputName -Bot2 ..\rival\dist\bot"
Write-Host ""
