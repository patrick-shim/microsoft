# refresh-mail-token.ps1
# Acquire a WorkIQ Mail MCP bearer token and write it into .env (BEARER_TOKEN=).
#
# The agent's MCP tool service uses BEARER_TOKEN (local mode, USE_AGENTIC_AUTH=false)
# to authenticate to the Mail MCP server as the signed-in user. This token is
# short-lived (~1 hour) — re-run this script and restart the agent when it expires.
#
# Usage:   .\refresh-mail-token.ps1
#
# The token is written straight into .env (which is gitignored) and never printed.

$ErrorActionPreference = 'Stop'

$envPath = Join-Path $PSScriptRoot '.env'
if (-not (Test-Path $envPath)) { throw "Missing .env at $envPath" }

if (-not (Get-Command a365 -ErrorAction SilentlyContinue)) {
    throw "a365 CLI not found. Install: dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli"
}

Write-Host "Requesting Mail MCP token (scope: McpServers.Mail.All)..."
Write-Host "A Windows sign-in dialog may appear — complete it if prompted (check the taskbar for a hidden window)."

# --output raw prints the token; auth progress goes to stderr. Extract the JWT
# defensively in case any non-token lines land on stdout.
$raw = & a365 develop get-token --scopes McpServers.Mail.All --output raw
if ($LASTEXITCODE -ne 0) { throw "a365 develop get-token failed (exit $LASTEXITCODE)." }

$text = [string]::Join("`n", $raw) -replace "`r", ''
$jwt = [regex]::Matches($text, '[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+') |
    ForEach-Object { $_.Value } | Sort-Object Length -Descending | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($jwt)) { throw "Could not extract a bearer token from the CLI output." }

# Replace the BEARER_TOKEN= line in .env (add it if absent).
$lines = Get-Content $envPath
if ($lines -match '^BEARER_TOKEN=') {
    $lines = $lines -replace '^BEARER_TOKEN=.*', "BEARER_TOKEN=$jwt"
} else {
    $lines += "BEARER_TOKEN=$jwt"
}
Set-Content -Path $envPath -Value $lines -Encoding UTF8

Write-Host "OK — BEARER_TOKEN updated in .env (token length $($jwt.Length))."
Write-Host "Restart the agent so it picks up the new token:  .venv\Scripts\python.exe start_with_generic_host.py"
