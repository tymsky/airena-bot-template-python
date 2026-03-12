# smoke.ps1 - Run a headless smoke test via Docker.
#
# The bot repo is mounted into a pre-built runtime image that contains
# OpenRA, ArenaHost, and all match infrastructure. No local core repo,
# OpenRA install, or workspace config is needed.
#
# Prerequisites:
#   - Docker Desktop (Linux containers)
#   - Python 3.10+ (for local development)
#
# Usage:
#   .\scripts\smoke.ps1                                          # defaults from airena.runtime.json
#   .\scripts\smoke.ps1 -Ticks 1500                              # override settings
#   .\scripts\smoke.ps1 -Faction soviet                          # play as Soviet
#   .\scripts\smoke.ps1 -Faction allied                          # play as Allied
#   .\scripts\smoke.ps1 -Script my_bot.py                        # use a different entry script
#   .\scripts\smoke.ps1 -Image ghcr.io/tymsky/airena-openra-headless:latest

[CmdletBinding()]
param(
    [string]$Image,
    [string]$Map,
    [int]$Ticks = 0,
    [string]$OpponentAi,
    [string]$Faction,
    [int]$TimeoutSeconds = 0,
    [string]$Script = "main.py"
)

$ErrorActionPreference = "Stop"

# ---------- Resolve paths ----------
$BotRoot = (Resolve-Path "$PSScriptRoot\..").Path

# ---------- Load runtime config ----------
$runtimeConfigPath = "$BotRoot\airena.runtime.json"
$cfg = @{
    image           = "ghcr.io/tymsky/airena-openra-headless:latest"
    map             = "a-nuclear-winter"
    ticks           = 6000
    opponent_ai     = "normal"
    bot_faction     = ""
    timeout_seconds = 300
}

if (Test-Path $runtimeConfigPath) {
    $fileCfg = Get-Content $runtimeConfigPath -Raw | ConvertFrom-Json
    if ($fileCfg.image)           { $cfg.image           = $fileCfg.image }
    if ($fileCfg.map)             { $cfg.map             = $fileCfg.map }
    if ($fileCfg.ticks)           { $cfg.ticks           = $fileCfg.ticks }
    if ($fileCfg.opponent_ai)     { $cfg.opponent_ai     = $fileCfg.opponent_ai }
    if ($fileCfg.bot_faction)     { $cfg.bot_faction     = $fileCfg.bot_faction }
    if ($fileCfg.timeout_seconds) { $cfg.timeout_seconds = $fileCfg.timeout_seconds }
}

# CLI parameters override config file
if ($Image)                    { $cfg.image           = $Image }
if ($Map)                      { $cfg.map             = $Map }
if ($Ticks -gt 0)              { $cfg.ticks           = $Ticks }
if ($OpponentAi)               { $cfg.opponent_ai     = $OpponentAi }
if ($Faction)                  { $cfg.bot_faction     = $Faction }
if ($TimeoutSeconds -gt 0)     { $cfg.timeout_seconds = $TimeoutSeconds }

# ---------- Verify entry script exists ----------
$botScriptPath = "$BotRoot\$Script"
if (-not (Test-Path $botScriptPath)) {
    Write-Host "[ERROR] Bot script not found: $botScriptPath" -ForegroundColor Red
    exit 3
}

# ---------- Check Docker ----------
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[ERROR] Docker is not installed or not in PATH." -ForegroundColor Red
    Write-Host "        Install Docker Desktop: https://www.docker.com/products/docker-desktop" -ForegroundColor Red
    exit 3
}

$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker daemon is not running." -ForegroundColor Red
    Write-Host "        Start Docker Desktop and try again." -ForegroundColor Red
    exit 3
}

# ---------- Check image exists ----------
$null = docker image inspect $cfg.image 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] Docker image '$($cfg.image)' not found locally." -ForegroundColor Yellow
    Write-Host "[INFO] Pulling image..." -ForegroundColor Cyan
    docker pull $cfg.image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to pull image '$($cfg.image)'." -ForegroundColor Red
        Write-Host "        Check the image name in airena.runtime.json or use -Image to override." -ForegroundColor Red
        exit 3
    }
}

# ---------- Prepare output directory ----------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = "$BotRoot\artifacts\smoke-$timestamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# ---------- Generate match ID ----------
$matchId = "smoke-$timestamp"

# ---------- Display config ----------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " AiRENA Smoke Test (Headless/Docker)"   -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Image:    $($cfg.image)"
Write-Host "[INFO] Map:      $($cfg.map)"
Write-Host "[INFO] Ticks:    $($cfg.ticks)"
Write-Host "[INFO] Faction:  $(if ($cfg.bot_faction) { $cfg.bot_faction } else { 'random' })"
Write-Host "[INFO] Opponent: $($cfg.opponent_ai)"
Write-Host "[INFO] Timeout:  $($cfg.timeout_seconds)s"
Write-Host "[INFO] Script:   $Script"
Write-Host "[INFO] Output:   $OutDir"
Write-Host ""

# ---------- Convert Windows paths to Docker-compatible paths ----------
$dockerBotRoot = $BotRoot -replace '\\', '/'
$dockerOutDir = $OutDir -replace '\\', '/'

# ---------- Run container ----------
# The runtime image has airena-sdk pre-installed from PyPI.
# The entrypoint installs /bot/requirements.txt if present (for bot-specific deps).
Write-Host "[STEP] Starting Docker container..." -ForegroundColor Cyan

$factionArgs = @()
if ($cfg.bot_faction) {
    $factionArgs = @("--bot-faction", $cfg.bot_faction)
}

docker run --rm `
    -v "${dockerBotRoot}:/bot:ro" `
    -v "${dockerOutDir}:/artifacts/${matchId}" `
    $cfg.image `
    --match-id $matchId `
    --map $cfg.map `
    --ticks $cfg.ticks `
    --ai-type $cfg.opponent_ai `
    --timeout $cfg.timeout_seconds `
    --bot-script "/bot/$Script" `
    @factionArgs

$exitCode = $LASTEXITCODE

# ---------- Summary ----------
Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "[DONE] Smoke test passed." -ForegroundColor Green
    Write-Host "       Artifacts: $OutDir" -ForegroundColor Green
} elseif ($exitCode -eq 2) {
    Write-Host "[DONE] Smoke test timed out after $($cfg.timeout_seconds)s." -ForegroundColor Red
    Write-Host "       Partial artifacts may be in: $OutDir" -ForegroundColor Red
} else {
    Write-Host "[DONE] Smoke test failed with exit code $exitCode." -ForegroundColor Red
    Write-Host "       Artifacts: $OutDir" -ForegroundColor Red
}

exit $exitCode
