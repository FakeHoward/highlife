param(
  [Parameter(Mandatory = $true)][string]$Username,
  [Parameter(Mandatory = $true)][string]$Password,
  [switch]$Admin
)

$ErrorActionPreference = "Stop"
$adminFlag = if ($Admin) { "--admin" } else { "--no-admin" }

Write-Host "Ensuring @$Username`:localhost exists..."
docker compose exec -T synapse register_new_matrix_user `
  --config /data/homeserver.yaml `
  --user $Username `
  --password $Password `
  $adminFlag `
  http://127.0.0.1:8008

if ($LASTEXITCODE -ne 0) {
  throw "Registration failed (the account may already exist)."
}
