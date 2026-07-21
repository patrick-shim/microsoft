# Copyright (c) Microsoft. All rights reserved.
# Register the deployed messaging endpoint with the agent blueprint (Teams Graph routing).
# `--m365` is MANDATORY for an AI Teammate — without it the CLI skips the Teams Graph
# re-registration and Teams keeps routing to the old endpoint.
#
# Run from backend/ (where a365.config.json / a365.generated.config.json live):
#   ../deploy/set-endpoint.ps1 -Endpoint https://<fqdn>/api/messages

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Endpoint
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path "a365.config.json")) {
    throw "Run this from the backend/ directory (a365.config.json not found in $(Get-Location))."
}
if ($Endpoint -notmatch "^https://.*/api/messages$") {
    throw "Endpoint must be an HTTPS URL ending in /api/messages. Got: $Endpoint"
}

Write-Host "==> a365 setup blueprint --update-endpoint $Endpoint --m365" -ForegroundColor Cyan
a365 setup blueprint --update-endpoint $Endpoint --m365

Write-Host ""
Write-Host "==> Verify the blueprint now points at the new endpoint:" -ForegroundColor Green
$cfg = Get-Content a365.generated.config.json | ConvertFrom-Json
Write-Host "    messagingEndpoint = $($cfg.messagingEndpoint)"
Write-Host "    Dev Portal:         https://dev.teams.microsoft.com/tools/agent-blueprint/$($cfg.agentBlueprintId)/configuration"
