<#
.SYNOPSIS
    Sets up and starts the Chama Ledger stack on Windows.

.DESCRIPTION
    Runs the make targets as plain commands: checks the prerequisites, starts the docker-compose
    Postgres, applies migrations, then opens the API and the Vite dev server in their own windows.
    The environment is set for the docker Postgres and for the LAN address so a phone on the same
    Wi-Fi can reach the API.

.PARAMETER Ip
    LAN address clients use to reach the API. Default: 192.168.100.11

.PARAMETER Port
    API port. Default: 8080

.PARAMETER CheckOnly
    Verify the prerequisites and print the plan without starting anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
    [string]$Ip = '192.168.100.11',
    [int]$Port = 8080,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$origin = "http://${Ip}:${Port}"
$databaseUrl = 'postgres://chama:chama@localhost:5434/chama?sslmode=disable'

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        if ($CheckOnly) {
            Write-Host "    missing: $Name ($Hint)" -ForegroundColor Yellow
            return $false
        }
        throw "$Name was not found. $Hint"
    }
    Write-Host "    ok: $Name" -ForegroundColor DarkGray
    return $true
}

function Wait-ForHealth([string]$Url, [int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -lt 500) { return $true }
        } catch {
            # Not listening yet.
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

Set-Location $root
Write-Host "Chama Ledger setup: root $root, API $origin" -ForegroundColor Green

Write-Step 'Checking prerequisites'
$ready = $true
if (-not (Test-Command 'go' 'Install Go 1.26+ from https://go.dev/dl/')) { $ready = $false }
if (-not (Test-Command 'docker' 'Install Docker Desktop and start it')) { $ready = $false }
if (-not (Test-Command 'npm' 'Install Node 20+ from https://nodejs.org/')) { $ready = $false }

if ($CheckOnly) {
    Write-Step 'Plan'
    Write-Host '    1. docker compose up -d db        (Postgres 15 on host port 5434, container chama-db)'
    Write-Host '    2. go run ./cmd/migrate up        (from backend/, with DATABASE_URL set)'
    Write-Host "    3. go run ./cmd/server            (http://${Ip}:${Port})"
    Write-Host "    4. npm run dev -- --host 0.0.0.0  (http://${Ip}:5173, proxies /api to localhost:${Port})"
    Write-Host ''
    if (-not $ready) {
        Write-Host 'Some prerequisites are missing; install them before running without -CheckOnly.' -ForegroundColor Yellow
    }
    return
}

# The API reads the process environment only; child processes inherit these.
$env:APP_ENV = 'development'
$env:HTTP_ADDR = ":$Port"
$env:PUBLIC_BASE_URL = $origin
$env:DATABASE_URL = $databaseUrl
$env:SMS_PROVIDER = 'console'
if (-not $env:PAYMENTS_PROVIDER) { $env:PAYMENTS_PROVIDER = 'mock' }

Write-Step 'Starting Postgres'
docker compose up -d db
if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }

$deadline = (Get-Date).AddSeconds(90)
$status = ''
while ((Get-Date) -lt $deadline) {
    $status = (docker inspect --format '{{.State.Health.Status}}' chama-db 2>$null)
    if ($status -eq 'healthy') { break }
    Start-Sleep -Seconds 2
}
if ($status -ne 'healthy') {
    throw "Postgres did not become healthy (status: '$status'). Run 'docker compose logs db' to see why."
}
Write-Host '    Postgres healthy on localhost:5434' -ForegroundColor DarkGray

Write-Step 'Applying migrations'
Push-Location (Join-Path $root 'backend')
try {
    go run ./cmd/migrate up
    if ($LASTEXITCODE -ne 0) { throw 'Migrations failed; check DATABASE_URL and the Postgres logs.' }
} finally {
    Pop-Location
}

if (-not (Test-Path (Join-Path $root 'web/node_modules'))) {
    Write-Step 'Installing web dependencies'
    Push-Location (Join-Path $root 'web')
    try {
        npm install
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed.' }
    } finally {
        Pop-Location
    }
}

Write-Step "Starting the API on $origin"
$apiWindow = "`$host.UI.RawUI.WindowTitle = 'chama api'; go run ./cmd/server"
Start-Process -FilePath 'powershell.exe' -WorkingDirectory (Join-Path $root 'backend') `
    -ArgumentList '-NoExit', '-NoProfile', '-Command', $apiWindow | Out-Null

if (-not (Wait-ForHealth "$origin/healthz" 90)) {
    throw "The API did not answer $origin/healthz. Check the 'chama api' window for the startup error."
}
Write-Host "    API ready: $origin/healthz" -ForegroundColor DarkGray

Write-Step "Starting the web dashboard on http://${Ip}:5173"
$webWindow = "`$host.UI.RawUI.WindowTitle = 'chama web'; npm run dev -- --host 0.0.0.0"
Start-Process -FilePath 'powershell.exe' -WorkingDirectory (Join-Path $root 'web') `
    -ArgumentList '-NoExit', '-NoProfile', '-Command', $webWindow | Out-Null

Write-Host ''
Write-Host 'Stack is running.' -ForegroundColor Green
Write-Host "    API          $origin"
Write-Host "    API docs     $origin/api/v1/meta"
Write-Host "    Dashboard    http://${Ip}:5173"
Write-Host ''
Write-Host 'Next steps'
Write-Host "    Mobile:  cd mobile; flutter run --dart-define=API_BASE_URL=$origin"
Write-Host "    Seed:    `$env:DEMO_PHONE='0712991122'; `$env:DEMO_PIN='4826'; `$env:DEMO_API='$origin/api/v1'; node scripts/seed-demo.mjs"
Write-Host ''
Write-Host "If a phone cannot connect, allow inbound TCP $Port on both Private and Public networks"
Write-Host '(elevated PowerShell):'
Write-Host "    New-NetFirewallRule -DisplayName 'chama-api $Port' -Direction Inbound -LocalPort $Port -Protocol TCP -Action Allow"
Write-Host ''
Write-Host 'Stop the background services with: docker compose down   (API and web: close their windows)'
