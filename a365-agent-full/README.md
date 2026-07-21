# a365-agent-full — a real, Teams-demoable Agent 365 AI Teammate

This is the **production-shaped** sibling of [`../a365-agent-slim`](../a365-agent-slim). Where
slim is one script that chats locally and exports observability (but bypasses the Bot Framework,
so it can never run in Teams), **this project runs the real hosting layer** and is meant to be
onboarded end-to-end and used inside Microsoft Teams and Copilot.

It is a **Microsoft Agent 365 AI Teammate** that:

1. **Chats** via an Azure OpenAI model through **Microsoft Agent Framework** (`ChatAgent`).
2. **Acts on Microsoft 365** — Mail, Teams, SharePoint, OneDrive — through **WorkIQ MCP tools**,
   using the agent's **own Agentic User identity** (not the caller's token).
3. **Reports everything** to Agent 365 as **observability** activities visible in the Microsoft
   admin center and Microsoft Defender.
4. **Runs as a container** on **Azure Container Apps**, reachable by Teams at `/api/messages`.

> New to Agent 365? Read [`../a365-agent-slim/README.md`](../a365-agent-slim/README.md) §1 first — it
> explains Entra, tenant, Blueprint, MCP, observability, and the FMI token chain in plain English.

---

## Repository layout

```
a365-agent-full/
├─ backend/                 ← the a365 project dir (run a365 / uv / docker from here)
│  ├─ host_agent_server.py  ← aiohttp host: /api/messages + /api/health, notifications
│  ├─ agent.py              ← MyAgent: Agent Framework + WorkIQ + observability scopes
│  ├─ agent_interface.py    ← abstract contract the host talks to
│  ├─ observability_bootstrap.py  ← use_microsoft_opentelemetry() — imported first
│  ├─ turn_context_utils.py ← caller identity / UPN resolution
│  ├─ pyproject.toml        ← pinned Agent Framework + A365 SDK deps
│  ├─ Dockerfile            ← python:3.11-slim + uv
│  ├─ a365.config.json      ← aiTeammate=true; CLI reads this
│  ├─ a365.generated.config.json  ← written by `a365 setup all` (gitignored, has secret)
│  ├─ ToolingManifest.json  ← written by `a365 develop add-mcp-servers`
│  └─ .env / .env.example   ← config (gitignored)
├─ frontend/
│  ├─ teams/                ← Teams app package (manifest.json + icons — CLI-owned)
│  └─ playground/           ← AgentsPlayground config for local agentic-auth testing
└─ deploy/
   ├─ deploy-containerapp.ps1  ← provision ACR + Container Apps, build & deploy
   ├─ set-endpoint.ps1         ← register the messaging endpoint with the blueprint
   ├─ set-appsettings.ps1      ← push .env → Container App (secrets as secrets)
   └─ generate-icons.ps1       ← placeholder Teams icons
```

---

## Prerequisites

| Tool | Why |
|---|---|
| **Python 3.11+** and **uv** | Build / run the agent |
| **Docker** *(optional)* | Local image build (`az acr build` builds in the cloud, no local daemon needed) |
| **Azure CLI** (`az`) + a subscription with **Contributor** | Deploy to Container Apps |
| **Agent 365 CLI** (`a365`) | Register, publish, manage the agent — `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli` |
| **Entra roles** | *Agent ID Developer* (blueprint) + an admin (*Application/Global Admin*) for consent, MCP permissions, and instance approval |
| Azure OpenAI resource | The LLM (a `gpt-4.1` deployment) |

---

## Phase A — build & run locally

```powershell
cd backend
copy .env.example .env      # then fill AZURE_OPENAI_ENDPOINT + DEPLOYMENT
uv sync
python -c "import host_agent_server, agent; print('imports OK')"

# Run the host
python start_with_generic_host.py
# → "Agent server listening on http://0.0.0.0:3978 (/api/messages, /api/health)"
```

Health check and Playground (in another terminal):

```powershell
curl http://localhost:3978/api/health          # {"status":"healthy",...}
agentsplayground                                # point it at http://localhost:3978/api/messages
```

For local runs set `ENABLE_A365_OBSERVABILITY_EXPORTER=false` (spans print to the console instead
of shipping to A365) and `USE_AGENTIC_AUTH=false` (use a `BEARER_TOKEN` from `a365 develop get-token`
for WorkIQ, or skip tools).

---

## Phase B — onboard, deploy, publish, go live

All `a365`/`az` commands run from **`backend/`**. Browser + admin steps are called out.

### 1. Register the blueprint (creates the AI Teammate identity)

```powershell
cd backend
az login --allow-no-subscriptions
a365 setup all --agent-name a365-full-demo --aiteammate --dry-run   # preview
a365 setup all --agent-name a365-full-demo --aiteammate --m365      # apply
```

This writes `a365.generated.config.json` (Blueprint id, client secret, tenant). Copy those into
`.env` (`CONNECTIONS__SERVICE_CONNECTION__SETTINGS__*`, `agent365Observability__agentId/__tenantId`,
`AGENT365_BLUEPRINT_ID`). If you're **not** a Global Admin, the CLI prints a PowerShell consent
script for an admin to run.

### 2. Add WorkIQ tools

```powershell
a365 develop list-available                    # find the exact server names
a365 develop add-mcp-servers mcp_MailTools mcp_TeamsTools mcp_SharePointTools mcp_OneDriveTools
a365 develop list-configured                   # confirm — writes ToolingManifest.json
```

If the blueprint already existed, a Global Admin runs `a365 setup permissions mcp` from `backend/`.

### 3. Deploy the container to Azure Container Apps

```powershell
cd ..
./deploy/deploy-containerapp.ps1 -ResourceGroup rg-a365-full -Location eastus `
    -AcrName a365fullacr -AppName a365-full-demo
# → prints  https://<fqdn>/api/messages
```

The script builds the image in ACR (`az acr build` — no local Docker needed), creates the Container
Apps environment + app (external HTTPS ingress on 3978, system-assigned identity, scale-to-zero),
and pushes `.env` (secrets as Container Apps secrets). Set `AGENT_HOSTNAME` to `<fqdn>` and re-run
`./deploy/set-appsettings.ps1` if you update `.env`.

> **Azure OpenAI auth in the container:** leave `AZURE_OPENAI_API_KEY` set, **or** grant the
> Container App's managed identity the *Cognitive Services OpenAI User* role and leave the key empty.

### 4. Register the endpoint + publish

```powershell
cd backend
../deploy/set-endpoint.ps1 -Endpoint https://<fqdn>/api/messages   # a365 setup blueprint --update-endpoint … --m365
a365 publish                                                       # → manifest.zip
```

### 5. Upload, configure, request an instance (browser + admin)

1. **Upload** `manifest.zip` at **M365 Admin Center → Agents → Upload custom agent**
   (`https://admin.cloud.microsoft/#/agents/all`). Org-wide install needs a Teams Administrator.
   *Sideload for just you:* Teams → Apps → Manage your apps → Upload a custom app.
2. **Verify** in Teams Developer Portal —
   `https://dev.teams.microsoft.com/tools/agent-blueprint/<blueprintId>/configuration`:
   Agent Type = **API Based**, Notification URL = your `/api/messages` (step 4 already set it via `--m365`).
3. **Request an instance:** Teams → Apps → your agent → **Request Instance**. A tenant admin approves
   at `https://admin.cloud.microsoft/#/agents/all/requested`, then assigns the agent user a license
   (E5 / Teams / Copilot). Propagation to Teams search takes minutes–hours.

### 6. Distribute across the org

Once instances are approved, a Teams Administrator can install/pin the app org-wide; it's discoverable
in **Teams → Apps** and in **Microsoft Copilot**.

---

## Verify it end-to-end

- **Cloud running:** `az containerapp show -g rg-a365-full -n a365-full-demo --query properties.runningStatus` → `Running`;
  `curl https://<fqdn>/api/messages` ≠ 404; `az containerapp logs show -g rg-a365-full -n a365-full-demo --follow`.
- **Teams:** chat the agent → replies in seconds with a typing indicator; *"Send an email to me@… saying hi"* actually sends.
- **Observability:** M365 Admin Center → Agents → `a365-full-demo` → **Activity** shows sessions, triggers,
  and tool calls (indexing lag 15–90 min; the exporter's HTTP-200 log lines are the immediate signal).
  Defender → Advanced Hunting → `CloudAppEvents` filtered by AgentId.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| No response in Teams | Dev Portal Notification URL must equal `messagingEndpoint` and Agent Type = API Based. Re-run `set-endpoint.ps1` if the FQDN changed. |
| `Request Instance` disabled | Microsoft Agent 365 **Frontier** not enabled for the tenant — admin must enable it. |
| Tool calls fail (403) | Global Admin runs `a365 setup permissions mcp` from `backend/`; confirm MCP servers under the agent's **Permissions** in the admin center. |
| Prod agent ignores tools / no OBO | `PYTHON_ENVIRONMENT` must be `Production` in Container Apps (else the WorkIQ SDK runs in dev mode). |
| No spans in admin center | `ENABLE_A365_OBSERVABILITY_EXPORTER=true` in the Container App; the per-turn token exchange needs the agentic handler configured. |
| `az acr build` fails | Ensure `az login` is current and the ACR name is globally unique. |

---

## How auth works (one paragraph)

This agent is an **AI Teammate**, so it authenticates as its **own Agentic User** (`agentic-user`).
Each turn, the host hands the agent an `Authorization` object; the agent calls `exchange_token(...)`
to mint per-audience tokens — for WorkIQ MCP servers (the SDK does this inside
`add_tool_servers_to_agent`) and for the Observability API (cached for the OTel exporter). Outbound
Teams replies are signed with the Blueprint's service-connection credentials
(`CONNECTIONS__SERVICE_CONNECTION__SETTINGS__*`), resolved by `MsalConnectionManager.from_environment()`.
No user tokens are used — the agent acts as itself.
