# a365-agent-purview — the slim demo + Microsoft Purview DLP

This is [`../a365-agent-slim`](../a365-agent-slim) with **Microsoft Purview Data Loss Prevention**
added. Same local agent (Azure OpenAI chat, WorkIQ Mail, Agent 365 observability), but every
**prompt** is now evaluated against your tenant's Purview DLP policies and **blocked inline** when it
contains sensitive data — and each interaction is logged in Purview (Audit, Communication Compliance,
Insider Risk, eDiscovery).

> **New here?** Read the [root README](../README.md) and [`../a365-agent-slim`](../a365-agent-slim/README.md)
> first — this project assumes you know the slim demo.
>
> **Docs & packages:** the [root README → References](../README.md#references--further-reading) lists the
> official Microsoft Learn docs and packages for Agent Framework, Agent 365, and **Microsoft Purview**
> (DLP, DSPM for AI, IRM, `agent-framework-purview`).

---

## What it does

```
        You: "My resident registration number is 900101-1234567."
                          │
                          ▼   PROMPT evaluated by Purview
        ┌───────────────────────────────────────────────┐
        │  PurviewPolicyMiddleware (agent_framework)     │
        │    → Microsoft Graph processContent            │──► Purview DLP (your tenant's policies)
        └───────────────────────────────────────────────┘
                          │
             blocked? ────┼── yes ──►  "🛑 blocked by a Purview DLP policy"  (model never sees it)
                          │
                          ▼   no
                    Azure OpenAI (gpt-5) ──► Agent: "<the answer>"
```

The check is an Agent Framework **middleware** (`agent-framework-purview`, imports as
`agent_framework.microsoft`). The wiring is one call in [`agent_purview.py`](agent_purview.py) —
`_build_purview_middleware()` builds a `PurviewPolicyMiddleware` and passes it to
`client.as_agent(..., middleware=[...])`.

> **Prompt vs response:** the middleware evaluates both, but on the **Application** enforcement plane
> (custom apps) Purview currently supports **blocking prompts** (`UploadText`) only — response
> blocking (`DownloadText`) isn't available yet, so this demo is **prompt-level DLP**.

---

## Prerequisites

- Everything the slim demo needs (Python 3.11+, `uv`, `az login`, an Azure OpenAI/Foundry deployment).
- **Microsoft 365 E5** + **pay-as-you-go billing** linked in Purview — these AI data-security APIs are
  **metered**; without billing you get HTTP **402** (the agent then degrades gracefully and doesn't block).
- An **Entra app registration** for Purview (its client id → `PURVIEW_CLIENT_APP_ID`) with delegated
  Graph permissions (admin-consented).
- A **DLP policy** on the **Application** enforcement plane, scoped to that app.

---

## Setup (the exact working flow)

### 1. Register the Purview Entra app + grant Graph permissions

Run in your terminal (creates the app, its SP, and admin-consents the three delegated Graph scopes —
GUIDs are Microsoft Graph's `ProtectionScopes.Compute.All`, `Content.Process.All`, `ContentActivity.Write`):

```powershell
@'
[{ "resourceAppId": "00000003-0000-0000-c000-000000000000",
   "resourceAccess": [
     { "id": "98f5a27a-539a-48bc-a597-f78e9e1e76bf", "type": "Scope" },
     { "id": "7e2467d1-f874-46bb-828e-24cb06b29d3f", "type": "Scope" },
     { "id": "948caae6-152a-48cd-a746-4844af30e8e9", "type": "Scope" }
]}]
'@ | Set-Content -Path perms.json -Encoding UTF8

az ad app create --display-name "a365-purview-dlp" `
  --public-client-redirect-uris "http://localhost" `
  --required-resource-accesses "@perms.json" --is-fallback-public-client true | Out-Null
$appId = az ad app list --display-name "a365-purview-dlp" --query "[0].appId" -o tsv
az ad sp create --id $appId | Out-Null
az ad app permission admin-consent --id $appId        # requires Global Admin
Remove-Item perms.json
Write-Host "PURVIEW_CLIENT_APP_ID = $appId"            # -> put in .env, and reuse below
```

### 2. Onboard the app in Purview + set up billing

In the [Purview portal](https://purview.microsoft.com):
- **Settings → Billing** → set up **pay-as-you-go** (required for custom-app policies).
- **DSPM for AI** → [Recommendations/Policies](https://purview.microsoft.com/purviewforai/recommendations)
  → enable **"Secure interactions from enterprise apps (preview)"** → status **On**. This puts your app's
  prompts/responses in scope for processing.

### 3. Create the DLP policy + rule (Security & Compliance PowerShell)

The standard DLP *location wizard* does **not** cover custom SDK apps — you must use the **Application**
enforcement plane with the app itself as the location. This is the flow that works:

```powershell
Connect-IPPSSession -UserPrincipalName <you>@<tenant>.onmicrosoft.com   # opens a sign-in

$myEntraAppId   = $appId          # the a365-purview-dlp client id from step 1
$myEntraAppName = "a365-purview-dlp"
# Location = THIS app (LocationType Individual, LocationSource Entra), all users:
$locations = "[{`"Workload`":`"Applications`",`"Location`":`"$myEntraAppId`",`"LocationDisplayName`":`"$myEntraAppName`",`"LocationSource`":`"Entra`",`"LocationType`":`"Individual`",`"Inclusions`":[{`"Type`":`"Tenant`",`"Identity`":`"All`"}]}]"

New-DlpCompliancePolicy -Name "Block sensitive PII in AI apps" -Mode Enable `
  -Locations $locations -EnforcementPlanes @("Application")

# Rule: block the PROMPT when it contains any of these SITs (add/remove as you like).
New-DlpComplianceRule -Name "Block PII - AI" -Policy "Block sensitive PII in AI apps" `
  -ContentContainsSensitiveInformation @(
    @{ Name = "Credit Card Number" },
    @{ Name = "South Korea Resident Registration Number" },
    @{ Name = "South Korea Passport Number" },
    @{ Name = "South Korea Driver's License Number" }
  ) `
  -RestrictAccess @(@{ setting = "UploadText"; value = "Block" }) `
  -GenerateAlert $true -NotifyUser @("<you>@<tenant>.onmicrosoft.com")
```

Gotchas we actually hit (so you don't):
- `-EnforcementPlanes @("Application")` is **rejected** with the Copilot location GUID — the location must
  be **your app id** with `LocationType:"Individual"`. ("Application" replaced the deprecated "Entra" plane.)
- Only **`UploadText`** (prompt) is a valid `-RestrictAccess` action here; `DownloadText` (response) errors.
- The `Set-`/`Get-DlpComplianceRule` cmdlets vanish when the **IPPS session times out** — just
  `Connect-IPPSSession` again. To add SITs later: `Set-DlpComplianceRule -Identity "Block PII - AI" -ContentContainsSensitiveInformation @(...)`.

### 4. Configure and run

```powershell
cd a365-agent-purview
copy .env.sample .env
# Fill: AZURE_OPENAI_* (gpt-5), PURVIEW_CLIENT_APP_ID = $appId, and the A365 observability values
#       (reuse the a365-agent-slim blueprint, or provision your own).
uv sync --link-mode=copy                 # --link-mode=copy avoids a OneDrive hardlink error
.venv\Scripts\python.exe agent_purview.py -m "My resident registration number is 900101-1234567."
```

Start-up shows `🛡️ Purview DLP ON …`. The **first run opens a browser** to sign in to the Purview app;
after that the token is cached (see below) and it's silent. After policy propagation (a few minutes) a
prompt containing any configured SIT comes back **🛑 blocked by a Purview DLP policy**; normal prompts
answer as usual.

---

## Sign-in: once, not every time

`_build_purview_middleware()` uses `InteractiveBrowserCredential` with **token-cache persistence**
(`TokenCachePersistenceOptions`), so the browser sign-in happens on the **first run only** — the token is
cached in the Windows Credential Manager and refreshed silently afterward.

**Fully headless (no popup ever):** switch to `CertificateCredential` (app-only) — upload a cert to the
`a365-purview-dlp` app, grant the **application** versions of the three Graph permissions, and pass
`user_id` explicitly (set `PURVIEW_DEFAULT_USER_ID`). See the `agent-framework-purview` sample's
`PURVIEW_USE_CERT_AUTH` path.

---

## Configuration reference (`.env`)

Purview-specific keys (the rest are inherited from the slim demo — see [`.env.sample`](.env.sample)):

| Key | What it is |
|---|---|
| `PURVIEW_CLIENT_APP_ID` | Client id of the `a365-purview-dlp` app. **Empty = DLP off** (runs like slim). |
| `PURVIEW_APP_NAME` | Display name Purview logs under. |
| `PURVIEW_DEFAULT_USER_ID` | Optional explicit user GUID — only needed for app-only/cert auth. |

The middleware uses `ignore_exceptions=True` / `ignore_payment_required=True`, so if Purview is
unreachable or unlicensed the agent keeps chatting (logs a warning) instead of failing. Flip those off in
`_build_purview_middleware()` for strict enforcement.

---

## Two signal planes: observability vs. Purview risk

This agent emits to **two independent planes**. Understanding the split matters, because a **blocked**
prompt shows up in one and not the other:

| Plane | Carried by | Identity it's keyed to | Where you see it |
|---|---|---|---|
| **A365 observability** | OpenTelemetry spans exported to A365 (`…/otlp/…/traces`) | the A365 blueprint / agentic id (`AGENT365_ACTIVITY_AGENT_ID`) | admin center → Agents → **Activity** |
| **Purview data-security / risk** | the middleware's Graph `processContent` calls | the **Purview app** (`PURVIEW_CLIENT_APP_ID`; shown in Purview as `Entra - <appId>`) | Purview → **DSPM for AI** / **IRM** (Risky Agent) |

Key consequences:

- **When DLP blocks a prompt, the LLM never runs** (the middleware terminates first), so there are
  **no genAI spans** to export — the exporter logs `No eligible genAI spans to export; nothing exported.`
  That is expected, **not** a failure.
- **The block is still recorded**: the middleware's `processContent` call (HTTP 200) sends the prompt +
  the sensitive-info-type match + the DLP verdict to Purview. **That** is the signal that feeds
  **DSPM for AI** and the **IRM `RiskyAgents`** policy — i.e. how the agent gets flagged as risky.
- So the **Risky Agent** flag rides the **Purview plane** (the `Entra - <appId>` identity =
  `a365-purview-dlp`), **not** the OTel observability export. The two planes are decoupled and use
  different app identities by design. Seeing `Entra - <your PURVIEW_CLIENT_APP_ID>` in Purview is
  correct. Risk/IRM views are batch-computed — allow a few hours.

### Diagnosing the observability export (`A365_OBS_DEBUG`)

The per-turn `📡 activity exported` line prints unconditionally and is **not** proof of success. To
see what the A365 exporter actually did — eligible spans, the export URL, and the **HTTP status**
(200 = shipped; 401/403 = the agent lacks the Observability `OtelWrite` grant; `No eligible genAI
spans` = nothing produced) — set the env var:

```powershell
$env:A365_OBS_DEBUG="1"
.venv\Scripts\python.exe agent_purview.py -m "How many unread emails do I have?"
$env:A365_OBS_DEBUG=""
```

A healthy export logs `HTTP 200 success …` with the A365 sinks (`flashpoint` / `sentinel` / `esp`)
reporting `"status":"sent"`. The admin-center Activity view then lags 15–90 min behind that.

### Understanding which policy fired (block detail + `PURVIEW_DEBUG`)

When a prompt is blocked, the agent appends a **traceable detail** to the message:

```
🛑 Your message was blocked by a Microsoft Purview data-loss-prevention policy.
   ↳ Purview: app='a365-purview-dlp' · action=block · correlationId=<guid>@AF
```

**Important:** Purview's inline `processContent` API returns only the **action** (`block`) and a
**correlation id** — **not** the rule / policy / SIT *name*. To see exactly *which rule and which
sensitive-info-type* fired, resolve that correlation id in **Purview → Data Loss Prevention →
Activity explorer** (or **Audit**), filtered to the `a365-purview-dlp` app — the matching event
lists the policy, rule, and SITs. DLP alerts (from the rule's `GenerateAlert`) name the rule directly.

To see **what's effective vs. what isn't** across prompts, set `PURVIEW_DEBUG=1` — it prints *every*
evaluation, including prompts that are **allowed**:

```powershell
$env:PURVIEW_DEBUG="1"
.venv\Scripts\python.exe agent_purview.py -m "my amex is 3746-640358-02207"
$env:PURVIEW_DEBUG=""
```
```
🔎 Purview eval: blocked=True · [action=blockAccess/restriction=block] · scopeState=... · correlationId=...@AF
```

`blocked=False` on a prompt you *expected* to catch means your DLP policy/SIT didn't match it —
tune the rule (SITs / thresholds / confidence) as in the [setup section](#3-create-the-dlp-policy--rule-security--compliance-powershell).

---

## How this relates to the other samples

- [`a365-agent-slim`](../a365-agent-slim) — the base (chat + Mail + observability).
- [`a365-agent-full`](../a365-agent-full) — the real Teams AI Teammate. Purview also governs Agent 365 AI
  Teammates at the platform level; this middleware approach is for **custom / self-hosted** agent code
  where you want DLP inside your own runtime.

Secrets (`.env`, `a365.generated.config.json`) are gitignored and never committed.
