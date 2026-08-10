param(
  [Parameter(Mandatory = $true)][string]$Username,
  [Parameter(Mandatory = $true)][string]$Password,
  [switch]$Admin
)

$ErrorActionPreference = "Stop"
$adminFlag = if ($Admin) { "--admin" } else { "--no-admin" }

Write-Host "Ensuring @$Username`:localhost exists via MAS..."
# Image ENTRYPOINT is mas-cli.
docker compose exec -T mas `
  --config /data/config.yaml manage register-user `
  --yes `
  --username $Username `
  --password $Password `
  $adminFlag `
  --ignore-password-complexity

if ($LASTEXITCODE -ne 0) {
  throw "Registration failed (the account may already exist)."
}
