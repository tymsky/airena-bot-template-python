# match.ps1 - Run a headless 1v1 bot-vs-bot match via Docker.
#
# Accepts two pre-built bot binaries (produced by build.ps1) and runs
# them against each other in the runtime Docker container.
#
# Prerequisites:
#   - Docker Desktop (Linux containers)
#   - Both bots built via: .\scripts\build.ps1
#
# Usage:
#   .\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot
#   .\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot -Map "a-nuclear-winter"
#   .\scripts\match.ps1 -Bot1 dist\bot -Bot2 ..\rival\dist\bot -Ticks 6000 -Seed 99

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Bot1,

    [Parameter(Mandatory=$true)]
    [string]$Bot2,

    [string]$Mod,
    [string]$Image,
    [string]$Map,
    [int]$Ticks = 0,
    [string]$Faction,
    [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = "Stop"

# ---------- Resolve paths ----------
$BotRoot = (Resolve-Path "$PSScriptRoot\..").Path

# Resolve Bot1
if (-not [System.IO.Path]::IsPathRooted($Bot1)) {
    $Bot1 = Join-Path (Get-Location) $Bot1
}
if (-not (Test-Path $Bot1)) {
    Write-Host "[ERROR] Bot1 binary not found: $Bot1" -ForegroundColor Red
    Write-Host "        Build it first: .\scripts\build.ps1" -ForegroundColor Red
    exit 3
}
$Bot1 = (Resolve-Path $Bot1).Path

# Resolve Bot2
if (-not [System.IO.Path]::IsPathRooted($Bot2)) {
    $Bot2 = Join-Path (Get-Location) $Bot2
}
if (-not (Test-Path $Bot2)) {
    Write-Host "[ERROR] Bot2 binary not found: $Bot2" -ForegroundColor Red
    exit 3
}
$Bot2 = (Resolve-Path $Bot2).Path

# ---------- Load runtime config ----------
$runtimeConfigPath = "$BotRoot\airena.runtime.json"
$cfg = @{
    mod             = "ra"
    image           = "ghcr.io/tymsky/airena-openra-headless:latest"
    map             = "a-nuclear-winter"
    ticks           = 6000
    bot_faction     = ""
    timeout_seconds = 300
}

if (Test-Path $runtimeConfigPath) {
    $fileCfg = Get-Content $runtimeConfigPath -Raw | ConvertFrom-Json
    if ($fileCfg.mod)             { $cfg.mod             = $fileCfg.mod }
    if ($fileCfg.image)           { $cfg.image           = $fileCfg.image }
    if ($fileCfg.map)             { $cfg.map             = $fileCfg.map }
    if ($fileCfg.ticks)           { $cfg.ticks           = $fileCfg.ticks }
    if ($fileCfg.bot_faction)     { $cfg.bot_faction     = $fileCfg.bot_faction }
    if ($fileCfg.timeout_seconds) { $cfg.timeout_seconds = $fileCfg.timeout_seconds }
}

# CLI overrides
if ($Mod)                  { $cfg.mod             = $Mod }
if ($Image)                { $cfg.image           = $Image }
if ($Map)                  { $cfg.map             = $Map }
if ($Ticks -gt 0)          { $cfg.ticks           = $Ticks }
if ($Faction)              { $cfg.bot_faction     = $Faction }
if ($TimeoutSeconds -gt 0) { $cfg.timeout_seconds = $TimeoutSeconds }

# ---------- Check Docker ----------
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "[ERROR] Docker is not installed or not in PATH." -ForegroundColor Red
    exit 3
}

$null = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Docker daemon is not running." -ForegroundColor Red
    exit 3
}

# ---------- Check image ----------
$ErrorActionPreference = "Continue"
$null = docker image inspect $cfg.image 2>&1
$ErrorActionPreference = "Stop"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] Docker image '$($cfg.image)' not found locally." -ForegroundColor Yellow
    Write-Host "[INFO] Pulling image..." -ForegroundColor Cyan
    docker pull $cfg.image
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to pull image '$($cfg.image)'." -ForegroundColor Red
        exit 3
    }
}

# ---------- Prepare output ----------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutDir = "$BotRoot\artifacts\match-$timestamp"
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$matchId = "match-$timestamp"

# ---------- Display config ----------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " AiRENA Match (Bot vs Bot / Docker)"    -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Mod:        $($cfg.mod)"
Write-Host "[INFO] Image:      $($cfg.image)"
Write-Host "[INFO] Map:        $($cfg.map)"
Write-Host "[INFO] Ticks:      $($cfg.ticks)"
Write-Host "[INFO] Timeout:    $($cfg.timeout_seconds)s"
Write-Host "[INFO] Bot1:       $Bot1"
Write-Host "[INFO] Bot2:       $Bot2"
Write-Host "[INFO] Output:     $OutDir"
Write-Host ""

# ---------- Convert paths for Docker ----------
$dockerBot1    = $Bot1 -replace '\\', '/'
$dockerBot2    = $Bot2 -replace '\\', '/'
$dockerOutDir  = $OutDir -replace '\\', '/'

$bot1Name = [System.IO.Path]::GetFileName($Bot1)
$bot2Name = [System.IO.Path]::GetFileName($Bot2)

# ---------- Run container ----------
Write-Host "[STEP] Starting Docker container (bot-vs-bot)..." -ForegroundColor Cyan

$factionArgs = @()
if ($cfg.bot_faction) {
    $factionArgs = @("--bot-faction", $cfg.bot_faction)
}

docker run --rm `
    -v "${dockerBot1}:/bots/bot1/${bot1Name}:ro" `
    -v "${dockerBot2}:/bots/bot2/${bot2Name}:ro" `
    -v "${dockerOutDir}:/artifacts/${matchId}" `
    $cfg.image `
    --match-id $matchId `
    --mod $cfg.mod `
    --map $cfg.map `
    --ticks $cfg.ticks `
    --timeout $cfg.timeout_seconds `
    --bot-bin "/bots/bot1/$bot1Name" `
    --bot2-bin "/bots/bot2/$bot2Name" `
    @factionArgs

$exitCode = $LASTEXITCODE

# ---------- Summary ----------
Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "[DONE] Match completed." -ForegroundColor Green
    Write-Host "       Artifacts: $OutDir" -ForegroundColor Green

    $resultFile = "$OutDir\result.json"
    if (Test-Path $resultFile) {
        Write-Host ""
        $result = Get-Content $resultFile -Raw | ConvertFrom-Json
        Write-Host "  Winner:   Player $($result.winner)" -ForegroundColor Yellow
        Write-Host "  Reason:   $($result.reason)" -ForegroundColor Yellow
        Write-Host "  Duration: $($result.duration_ticks) ticks" -ForegroundColor Yellow
    }
} elseif ($exitCode -eq 2) {
    Write-Host "[DONE] Match timed out after $($cfg.timeout_seconds)s." -ForegroundColor Red
    Write-Host "       Partial artifacts may be in: $OutDir" -ForegroundColor Red
} else {
    Write-Host "[DONE] Match failed with exit code $exitCode." -ForegroundColor Red
    Write-Host "       Artifacts: $OutDir" -ForegroundColor Red
}

exit $exitCode
