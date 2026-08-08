# Start the local Synapse + MatrixRTC stack and create demo accounts.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root "server"
Set-Location $server

function New-Secret([int]$Bytes = 32) {
  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
  return [Convert]::ToBase64String($buffer)
}

$envFile = Join-Path $server ".env"
if (-not (Test-Path $envFile)) {
  @(
    "POSTGRES_PASSWORD=$(New-Secret)"
    "SYNAPSE_REGISTRATION_SECRET=$(New-Secret)"
    "TURN_SHARED_SECRET=$(New-Secret)"
    "LIVEKIT_KEY=local-$([Guid]::NewGuid().ToString('N'))"
    "LIVEKIT_SECRET=$(New-Secret)"
  ) | Set-Content -Path $envFile -Encoding ASCII
  Write-Host "==> Generated gitignored server/.env"
}

Write-Host "==> Validating and starting Synapse + MatrixRTC..."
docker compose config --quiet
docker compose up -d

$ready = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
  try {
    Invoke-RestMethod -Uri "http://localhost:8008/health" -TimeoutSec 2 | Out-Null
    $ready = $true
    break
  } catch {
    Start-Sleep -Seconds 2
  }
}
if (-not $ready) {
  docker compose ps
  throw "Synapse did not become ready."
}

function Ensure-User($name, $pass) {
  try {
    & .\register.ps1 -Username $name -Password $pass | Out-Null
    Write-Host "Registered @$name:localhost"
  } catch {
    Write-Host "Skip @$name:localhost (maybe already exists)"
  }
}

Ensure-User "alice" "alice-pass"
Ensure-User "bob" "bob-pass"
Ensure-User "bot" "bot-pass"

Write-Host ""
Write-Host "Homeserver:  http://localhost:8008"
Write-Host "Element Call: http://localhost:8081"
Write-Host "LiveKit JWT:  http://localhost:8082"
Write-Host "Bot:        cd bot; npm start"
Write-Host "Client:     .\bin\highlife_client.exe"
