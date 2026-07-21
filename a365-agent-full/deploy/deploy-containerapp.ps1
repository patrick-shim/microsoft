# Copyright (c) Microsoft. All rights reserved.
# Provision + deploy the AI Teammate to Azure Container Apps.
#
# Prereqs: az CLI logged in (`az login`), a subscription with Contributor, and
#          backend/.env populated (at least the Azure OpenAI keys). The blueprint
#          auth values are pushed later by set-appsettings.ps1 once a365 setup runs.
#
# Usage (from a365-agent-full/):
#   ./deploy/deploy-containerapp.ps1 -ResourceGroup rg-a365-full -Location eastus `
#       -AcrName a365fullacr -AppName a365-full-demo
#
# Prints the messaging endpoint (https://<fqdn>/api/messages) at the end — feed it
# to ./deploy/set-endpoint.ps1.

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [string]$Location = "eastus",
    [Parameter(Mandatory)] [string]$AcrName,
    [Parameter(Mandatory)] [string]$AppName,
    [string]$EnvName = "$AppName-env",
    [string]$ImageTag = "latest",
    [string]$BackendPath = "$PSScriptRoot/../backend"
)

$ErrorActionPreference = "Stop"
$image = "$AcrName.azurecr.io/$AppName`:$ImageTag"

Write-Host "==> Ensuring the containerapp extension is present" -ForegroundColor Cyan
az extension add --name containerapp --upgrade --only-show-errors | Out-Null
# Register required resource providers and WAIT — a fresh subscription has none of these,
# and creation fails if they aren't Registered yet (registration is async).
foreach ($ns in @("Microsoft.App", "Microsoft.OperationalInsights", "Microsoft.ContainerRegistry", "Microsoft.Network", "Microsoft.ContainerInstance")) {
    Write-Host "==> Registering resource provider $ns"
    az provider register --namespace $ns --wait --only-show-errors | Out-Null
}

Write-Host "==> Resource group $ResourceGroup ($Location)" -ForegroundColor Cyan
az group create --name $ResourceGroup --location $Location --only-show-errors | Out-Null

Write-Host "==> Azure Container Registry $AcrName" -ForegroundColor Cyan
az acr create --resource-group $ResourceGroup --name $AcrName --sku Basic --admin-enabled true --only-show-errors | Out-Null

Write-Host "==> Building image in ACR from $BackendPath/Dockerfile" -ForegroundColor Cyan
# az acr build runs the Docker build server-side — no local Docker daemon needed.
az acr build --registry $AcrName --image "$AppName`:$ImageTag" $BackendPath

Write-Host "==> Container Apps environment $EnvName" -ForegroundColor Cyan
# --logs-destination none avoids the auto-created Log Analytics workspace (a fragile
# dependency on fresh subscriptions). Live logs still work via `az containerapp logs show`.
az containerapp env create --name $EnvName --resource-group $ResourceGroup --location $Location `
    --logs-destination none --only-show-errors | Out-Null

# ── Parse the project-root .env (a365-agent-full/.env) into env vars and secrets ──────
$envFile = Join-Path (Split-Path $BackendPath -Parent) ".env"
if (-not (Test-Path $envFile)) { throw "Missing $envFile — copy .env.example to .env and fill it first." }

$secretKeys = @(
    "AZURE_OPENAI_API_KEY",
    "CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTSECRET",
    "BEARER_TOKEN"
)
$envArgs = @()
$secretArgs = @()
$secretRefs = @()

foreach ($line in Get-Content $envFile) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#") -or -not $t.Contains("=")) { continue }
    $k, $v = $t -split "=", 2
    $v = $v.Trim('"')
    if ($v -eq "") { continue }
    if ($secretKeys -contains $k) {
        $sname = $k.ToLower().Replace("_", "-").Replace(".", "-")
        $secretArgs += "$sname=$v"
        $secretRefs += "$k=secretref:$sname"
    } else {
        $envArgs += "$k=$v"
    }
}

Write-Host "==> Creating/updating container app $AppName (external ingress :3978)" -ForegroundColor Cyan
$acrCreds = az acr credential show --name $AcrName | ConvertFrom-Json

$exists = az containerapp show --name $AppName --resource-group $ResourceGroup --only-show-errors 2>$null
if ($exists) {
    az containerapp update --name $AppName --resource-group $ResourceGroup --image $image `
        --set-env-vars @envArgs --only-show-errors | Out-Null
} else {
    az containerapp create `
        --name $AppName --resource-group $ResourceGroup --environment $EnvName `
        --image $image --target-port 3978 --ingress external `
        --min-replicas 0 --max-replicas 3 `
        --system-assigned `
        --registry-server "$AcrName.azurecr.io" `
        --registry-username $acrCreds.username `
        --registry-password $acrCreds.passwords[0].value `
        --only-show-errors | Out-Null
}

if ($secretArgs.Count -gt 0) {
    az containerapp secret set --name $AppName --resource-group $ResourceGroup --secrets @secretArgs --only-show-errors | Out-Null
}
$allEnv = $envArgs + $secretRefs
az containerapp update --name $AppName --resource-group $ResourceGroup --set-env-vars @allEnv --only-show-errors | Out-Null

$fqdn = az containerapp show --name $AppName --resource-group $ResourceGroup --query properties.configuration.ingress.fqdn -o tsv
$endpoint = "https://$fqdn/api/messages"

Write-Host ""
Write-Host "==> Deployed." -ForegroundColor Green
Write-Host "    FQDN:              $fqdn"
Write-Host "    Messaging endpoint: $endpoint"
Write-Host "    Health check:       https://$fqdn/api/health"
Write-Host ""
Write-Host "Next: register this endpoint with the blueprint:" -ForegroundColor Yellow
Write-Host "    ./deploy/set-endpoint.ps1 -Endpoint `"$endpoint`""
