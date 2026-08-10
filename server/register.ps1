param(
  [Parameter(Mandatory = $true)][string]$Username,
  [Parameter(Mandatory = $true)][string]$Password,
  [switch]$Admin
)

$ErrorActionPreference = "Stop"
$adminFlag = if ($Admin) { "--admin" } else { "--no-admin" }

Write-Host "Ensuring @$Username`:localhost exists via MAS..."
# docker compose exec does not use the image ENTRYPOINT.
docker compose exec -T mas `
  /usr/local/bin/mas-cli --config /data/config.yaml manage register-user `
  --yes `
  --password $Password `
  $adminFlag `
  --ignore-password-complexity `
  $Username

if ($LASTEXITCODE -ne 0) {
  throw "Registration failed (the account may already exist)."
}
