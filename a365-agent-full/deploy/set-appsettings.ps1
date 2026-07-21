# Copyright (c) Microsoft. All rights reserved.
# Re-push backend/.env into an existing Container App (non-secret keys as env vars,
# sensitive keys as Container Apps secrets). Use after `a365 setup all` fills the
# blueprint auth values, or whenever .env changes.
#
# Usage (from a365-agent-full/):
#   ./deploy/set-appsettings.ps1 -ResourceGroup rg-a365-full -AppName a365-full-demo

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppName,
    [string]$BackendPath = "$PSScriptRoot/../backend"
)
$ErrorActionPreference = "Stop"

$envFile = Join-Path (Split-Path $BackendPath -Parent) ".env"
if (-not (Test-Path $envFile)) { throw "Missing $envFile." }

$secretKeys = @(
    "AZURE_OPENAI_API_KEY",
    "CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET",
    "BEARER_TOKEN"
)
$envArgs = @(); $secretArgs = @(); $secretRefs = @()
foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#") -or -not $t.Contains("=")) { continue }
    $k, $v = $t -split "=", 2
    $v = $v.Trim('"')
    if ($v -eq "") { continue }
    if ($secretKeys -contains $k) {
        $sname = $k.ToLower().Replace("_", "-").Replace(".", "-")
        $secretArgs += "$sname=$v"; $secretRefs += "$k=secretref:$sname"
    } else { $envArgs += "$k=$v" }
}

if ($secretArgs.Count -gt 0) {
    Write-Host "==> Setting $($secretArgs.Count) secret(s)" -ForegroundColor Cyan
    az containerapp secret set --name $AppName --resource-group $ResourceGroup --secrets @secretArgs --only-show-errors | Out-Null
}
Write-Host "==> Setting $($envArgs.Count + $secretRefs.Count) env var(s)" -ForegroundColor Cyan
az containerapp update --name $AppName --resource-group $ResourceGroup --set-env-vars ($envArgs + $secretRefs) --only-show-errors | Out-Null

Write-Host "==> Restarting the latest revision" -ForegroundColor Cyan
$rev = az containerapp revision list --name $AppName --resource-group $ResourceGroup --query "[0].name" -o tsv
az containerapp revision restart --name $AppName --resource-group $ResourceGroup --revision $rev --only-show-errors | Out-Null
Write-Host "==> Done." -ForegroundColor Green
