# a365-agent-full — a real Microsoft Agent 365 AI Teammate (Teams + Copilot)

This project is a **complete, production-shaped AI agent** that lives inside Microsoft 365. You
chat with it in **Microsoft Teams** (and it shows up in **Microsoft Copilot**), it can **read and
send your email, read Teams messages, and open SharePoint/OneDrive files** on your behalf, and
every action it takes is **recorded** so admins can audit it.

It is the grown-up sibling of [`../a365-agent-slim`](../a365-agent-slim). The slim demo runs one
Python script on your laptop and never touches Teams. This one runs as a **container in Azure**,
speaks the real Teams protocol, and is onboarded to Microsoft 365 like any first-class app.

> **Never heard of any of this?** Jump to [§1 Concepts in plain English](#1-concepts-in-plain-english).
> Just want to stand it up? Jump to [§7 Re-provision from scratch](#7-re-provision-from-scratch-copypaste).

---

## Table of contents

1. [Concepts in plain English](#1-concepts-in-plain-english)
2. [The big picture (architecture)](#2-the-big-picture-architecture)
3. [What "backend" and "frontend" mean here](#3-what-backend-and-frontend-mean-here)
4. [How one message flows — and how tokens are minted](#4-how-one-message-flows--and-how-tokens-are-minted)
5. [The code, file by file](#5-the-code-file-by-file)
6. [Configuration reference (`.env`)](#6-configuration-reference-env)
7. [Re-provision from scratch (copy-paste)](#7-re-provision-from-scratch-copypaste)
8. [Run & test locally](#8-run--test-locally)
9. [Troubleshooting (every wall we hit)](#9-troubleshooting-every-wall-we-hit)
10. [Repository layout](#10-repository-layout)

---

## 1. Concepts in plain English

| Term | What it actually means |
|---|---|
| **Microsoft Entra ID** | Microsoft's identity system (old name: "Azure AD"). Every user, app, and agent has an identity here, and every login/API call is checked against it. |
| **Tenant** | One organization's private slice of Microsoft's cloud. Identified by a GUID (e.g. `ff8b1e46-…`) and a domain (e.g. `contoso.onmicrosoft.com`). |
| **Subscription** | The Azure billing container where you create resources (the container, registry, etc.). A tenant can have several. |
| **Microsoft Agent 365 (A365)** | Microsoft's platform for building and governing AI **agents** inside Microsoft 365. Agents get their own identity, permissions, tools, and audit trail. |
| **Blueprint** | The agent's **app registration in Entra** — its identity template, a client secret, and the list of permissions it may use. Created by the `a365` CLI. Think "the agent's passport office." |
| **Agentic User** | The agent's **own user account** in Microsoft 365 (its own mailbox, its own UPN like `agent@contoso.onmicrosoft.com`). Created when you provision an **instance** of the blueprint. This is *who the agent is* when it acts. |
| **AI Teammate** | An agent that behaves like a colleague: it has its Agentic User identity and works inside Teams/Copilot. (As opposed to a background "system agent.") |
| **WorkIQ tools** | Microsoft's ready-made **MCP tool servers** that expose M365 data — Mail, Teams, SharePoint, OneDrive, Calendar, etc. The agent calls them to actually *do* things. |
| **MCP (Model Context Protocol)** | An open standard for giving an LLM callable **tools**. A "tool" is just a function the model can invoke ("search my mail"). |
| **Observability** | Every message, model call, and tool use is emitted as an **OpenTelemetry span** and shipped to A365, so admins see the agent's activity in the admin center and Microsoft Defender. |
| **Container / Azure Container Apps** | The agent runs as a Docker **container**. **Azure Container Apps** is the managed service that runs it and gives it a public HTTPS address Teams can reach. |
| **Foundry (Azure OpenAI)** | Microsoft's hosted OpenAI models (this project uses **gpt-5**), reached at an HTTPS endpoint. This is the agent's "brain." |
| **Token** | A short-lived signed string that proves "I'm allowed to call this API." The whole security model is about minting the *right* token for the *right* API as the *right* identity. See [§4](#4-how-one-message-flows--and-how-tokens-are-minted). |
| **Frontier** | The Agent 365 preview program. A tenant must be enrolled before it can create agent instances. |

---

## 2. The big picture (architecture)

```
                              ┌──────────────────────────────────────────┐
   YOU (in Microsoft Teams    │            MICROSOFT 365 CLOUD           │
   or Microsoft Copilot)      │                                          │
        │                     │   Teams / Copilot  ──►  Bot Framework    │
        │  "Summarize my      │        service            (routing)      │
        │   unread email"     │                              │           │
        ▼                     └──────────────────────────────┼───────────┘
   ┌─────────┐                                                │ HTTPS POST
   │  Teams  │                                                │ /api/messages
   └─────────┘                                                ▼
                              ┌──────────────────────────────────────────┐
                              │      AZURE CONTAINER APPS (your code)     │
                              │      "the backend" — one container        │
                              │                                          │
                              │   host_agent_server.py  (aiohttp)        │
                              │     ├─ /api/health   (liveness)          │
                              │     └─ /api/messages (validates Teams,   │
                              │            runs the agent, replies)      │
                              │                  │                       │
                              │                  ▼                       │
                              │   agent.py  (MyAgent)                    │
                              │     ├─ Azure OpenAI (Agent Framework) ───┼──►  Foundry (gpt-5)
                              │     └─ WorkIQ MCP tools ─────────────────┼──►  Mail / Teams /
                              │                                          │     SharePoint / OneDrive
                              │   token exchange + OTel spans ───────────┼──►  A365 Observability
                              └──────────────────────────────────────────┘
                                       ▲                    ▲
                                       │ identity/secret    │ blueprint + permissions
                              ┌────────┴────────┐  ┌─────────┴──────────┐
                              │   Entra ID       │  │  a365 CLI (setup)  │
                              │  (Blueprint +    │  │  creates blueprint,│
                              │   Agentic User)  │  │  grants consents   │
                              └──────────────────┘  └────────────────────┘
```

Three worlds cooperate:

1. **Microsoft 365** — where the user chats (Teams/Copilot) and where the agent's data lives (mail, files).
2. **Your backend** — the container that receives messages, thinks (LLM), acts (tools), and replies.
3. **Entra ID + the `a365` CLI** — the identity/permission plumbing that lets the backend prove *who it is* and *what it's allowed to do*.

---

## 3. What "backend" and "frontend" mean here

An AI Teammate is a **chat agent**, not a website — so "frontend" does **not** mean a web UI.

- **`backend/`** — the real program: the Python container that hosts the agent (HTTP server + LLM +
  tools + telemetry). This is 95% of the code and the only thing that "runs."
- **`frontend/`** — the **surfaces users reach the agent through**, and the packaging that puts it there:
  - **`frontend/teams/`** — the **Teams app package**: a `manifest.json` (name, icons, bot id, the
    `/api/messages` URL) plus two PNG icons, zipped into `manifest.zip`. Uploading that zip is what
    makes the agent *appear* in Teams and Copilot. The `a365` CLI generates it — you don't hand-write it.
  - **`frontend/playground/`** — a config file for **AgentsPlayground**, a local chat window you use
    to test the backend on your laptop before deploying.
  - **Microsoft Copilot** — no extra code: once the agent is published + instanced, it's discoverable
    in Copilot automatically because it's a registered M365 agent.

So: **backend = the agent. frontend = how people find and talk to it.**

---

## 4. How one message flows — and how tokens are minted

This is the heart of the system. Follow one message: *"Summarize my unread email."*

```
 (1) INBOUND — Teams proves itself
     Teams ──HTTPS POST /api/messages──►  container
     Header: Authorization: Bearer <JWT signed by Bot Framework, audience = our CLIENT_ID>
     → jwt_authorization_middleware VALIDATES it using CLIENT_ID + TENANT_ID.
       (We don't mint anything here — we CHECK that Teams is really calling us.)

 (2) OBSERVABILITY TOKEN — agent acts as itself, to report telemetry
     host_agent_server._setup_observability_token():
        token = agent_app.auth.exchange_token(
                    context,                                   # the live turn = the agent's identity
                    scopes = Observability API (OtelWrite),
                    auth_handler_id = "AGENTIC")               # "mint AS the Agentic User"
        token_cache.cache_agentic_token(tenant, agent_id, token)
     → later, the OpenTelemetry exporter reads this token to ship spans to A365.

 (3) TOOL TOKENS — agent acts as itself, to touch mailbox
     agent.setup_mcp_servers() → SDK's add_tool_servers_to_agent():
        internally calls exchange_token(scope = Tools.ListInvoke.All, handler = "AGENTIC")
        → gets a token that says "I am the Agentic User" → WorkIQ Mail server trusts it
        → the agent can read the user-scoped mailbox AS the agent's own identity.

 (4) LLM CALL — agent thinks
     agent.run("Summarize my unread email")  →  Foundry (gpt-5)
        auth = AZURE_OPENAI_API_KEY  (or managed identity if the key is blank)
        the model decides to call the Mail tool, reads results, writes a summary.

 (5) OUTBOUND — agent replies, and must prove itself to Teams
     context.send_activity(<summary>)  →  Bot Framework service
        MsalConnectionManager mints an app-only token from the BLUEPRINT credentials
        (CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID / CLIENTSECRET / TENANTID)
        → Teams accepts the reply and shows it to you.
```

### The four kinds of tokens (why there are so many)

| # | Direction | Who it proves you are | Where the credential comes from | Used for |
|---|---|---|---|---|
| **1. Inbound JWT** | Teams → agent | *validates* Teams | `CLIENT_ID` + `TENANT_ID` (we verify, not mint) | Trusting the incoming request |
| **2. Agentic token** | agent → A365/WorkIQ | the **Agentic User** (the agent itself) | `exchange_token(..., "AGENTIC")` using the live turn | Observability + WorkIQ tools |
| **3. Blueprint (S2S) token** | agent → Teams | the **app** (blueprint) | `CONNECTIONS__…__CLIENTSECRET` (client credentials) | Sending replies back to Teams |
| **4. LLM token/key** | agent → Foundry | the app / managed identity | `AZURE_OPENAI_API_KEY` or `DefaultAzureCredential` | Calling gpt-5 |

**Key idea — "acting as itself":** an AI Teammate does *not* borrow the user's token. When it reads
your mail, it uses **its own** Agentic User identity (token #2). That's why the admin grants the
blueprint specific permissions (Mail.ReadWrite, etc.) — the agent is a real actor with its own rights.

> **How the slim demo differs:** the slim agent has no hosting layer and no live turn context, so it
> can't call `exchange_token`. Instead it mints the observability token the manual way — the **FMI
> 3-hop chain**: blueprint client-credentials + `fmi_path=<agent id>` → a token *as the agent* → a
> token for the Observability API. The full agent's `exchange_token` does the equivalent, driven by
> the incoming Teams activity. See [`../a365-agent-slim/README.md`](../a365-agent-slim/README.md).

---

## 5. The code, file by file

Everything runs from **`backend/`**. Read them in this order:

| File | In one sentence |
|---|---|
| **`start_with_generic_host.py`** | The entry point — imports `MyAgent` and calls `create_and_run_host(MyAgent)`. This is what the container runs. |
| **`host_agent_server.py`** | The **hosting layer**. Builds the aiohttp web server, the Bot Framework adapter, the auth handlers, and the message/notification routing. **Owns observability**: initializes OpenTelemetry, exchanges the per-turn telemetry token, and wraps each turn in a "baggage" scope so spans are attributed to the agent. Exposes `/api/messages` (guarded by JWT) and `/api/health` (open). Binds `0.0.0.0` so the container's ingress can reach it. |
| **`agent.py`** (`MyAgent`) | The **agent itself**. Creates the Azure OpenAI client (Agent Framework), attaches WorkIQ MCP tools, and answers each message. `process_user_message()` is the one turn. Also handles email notifications. The LLM logic lives here; the host never touches the model. |
| **`agent_interface.py`** | The tiny **contract** between host and agent (`initialize`, `process_user_message`, `cleanup`). The host talks to the agent only through this, so you could swap the LLM framework without touching the host. |
| **`token_cache.py`** | A dictionary that stores the per-turn **observability token** so the telemetry exporter can read it back (`cache_agentic_token` / `get_cached_agentic_token`). |
| **`pyproject.toml`** | The Python dependencies, pinned to a working set (Agent Framework 1.11 + A365 SDK 1.0 + the OpenTelemetry distro). Note `httpx>=0.28.1` is required. |
| **`Dockerfile`** | Builds the container image: `python:3.11-slim` + `uv sync` + run `start_with_generic_host.py`. |
| **`a365.config.json`** | Tells the `a365` CLI who the agent is (tenant, client-app id, display names, `aiTeammate: true`). |
| **`ToolingManifest.json`** | The list of WorkIQ MCP servers the agent uses. **Written by `a365 develop add-mcp-servers`** — don't hand-edit. |
| **`.env`** | All runtime configuration and secrets (gitignored). See [§6](#6-configuration-reference-env). |

### The one thing that surprises everyone

The host flips into **anonymous mode** (no Teams auth) unless the **top-level** `CLIENT_ID`,
`TENANT_ID`, and `CLIENT_SECRET` env vars are set — these are *separate* from the
`CONNECTIONS__SERVICE_CONNECTION__SETTINGS__*` values (even though they hold the same blueprint
id/secret/tenant). If your container logs say `Auth: Anonymous`, that's why. Set all three.

---

## 6. Configuration reference (`.env`)

Copy `backend/.env.sample` → `backend/.env` and fill it. Values marked *(from setup)* come from
`a365.generated.config.json` after `a365 setup all`; get the secret with
`a365 setup blueprint --show-secret`.

| Key | What it is |
|---|---|
| `AZURE_OPENAI_ENDPOINT` / `_DEPLOYMENT` / `_API_VERSION` | The Foundry endpoint, model deployment (**gpt-5**), and API version. |
| `AZURE_OPENAI_API_KEY` | Foundry key. Leave **blank** to use the container's managed identity instead (needs the *Cognitive Services OpenAI User* role). |
| `PORT` (3978) · `PYTHON_ENVIRONMENT` (Production) | Server port; **must be `Production` in the cloud** or the WorkIQ SDK runs in dev mode and skips token exchange. |
| `AUTH_HANDLER_NAME=AGENTIC` · `USE_AGENTIC_AUTH=true` | Turns on the "act as the Agentic User" path (token #2/#3). |
| `AGENTAPPLICATION__USERAUTHORIZATION__HANDLERS__AGENTIC__SETTINGS__TYPE/SCOPES` | Registers the agentic auth handler. |
| `CONNECTIONS__SERVICE_CONNECTION__SETTINGS__CLIENTID / CLIENTSECRET / TENANTID` *(from setup)* | Blueprint credentials the host uses to **reply to Teams**. |
| `CONNECTIONSMAP__0__SERVICEURL=*` / `__CONNECTION=SERVICE_CONNECTION` | Routes all outbound calls through that connection. **Double underscores.** |
| `CLIENT_ID` / `TENANT_ID` / `CLIENT_SECRET` *(from setup)* | Top-level copies used to **validate inbound Teams JWTs**. Without them the host is anonymous (see above). |
| `ENABLE_A365_OBSERVABILITY_EXPORTER` | `true` in the cloud (ship spans to A365); `false` locally (console only). |
| `agent365Observability__agentId` / `__tenantId` *(from setup)* | Stamp spans with the agent + tenant. |
| `BEARER_TOKEN` | Local-only WorkIQ token from `a365 develop get-token`. Empty in the cloud. |

---

## 7. Re-provision from scratch (copy-paste)

This is the exact end-to-end sequence to stand the agent up in a **fresh tenant/subscription**,
straight from a clone of this repo. It bakes in every issue we actually hit.

### 0. Prerequisites (install once)

```powershell
winget install Microsoft.AzureCLI Microsoft.PowerShell Python.Python.3.11 Docker.DockerDesktop
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli   # the a365 CLI (needs .NET 8+)
python -m pip install uv                                          # or: irm https://astral.sh/uv/install.ps1 | iex
```

You also need, in the target tenant: **Global Administrator** (for consents), **Frontier enrolled**,
an **Azure subscription** (Contributor), and an **Azure OpenAI / Foundry** resource with a model
deployment.

### 1. Sign in to the tenant

```powershell
az login --tenant <TENANT_ID> --use-device-code    # device code avoids "hidden dialog" problems
```

> **Do the next steps that need a browser in your OWN terminal**, not an embedded/agent terminal.
> The `a365` CLI's admin step uses a browser sign-in with a **120-second** device-code window that
> embedded terminals routinely miss. Your own terminal gets a normal popup.

### 2. Register the blueprint (creates the agent's identity)

From **the repo root of this project** (`a365-agent-full/`):

```powershell
a365 setup all --agent-name a365-full-demo --tenant-id <TENANT_ID> --aiteammate --m365 `
    --messaging-endpoint https://placeholder.azurecontainerapps.io/api/messages
```

- When it asks **"Enter a client app ID, or [C] to create one"** → type **`C`** (first run in a new tenant).
- Answer **`y`** to admin-consent and any service-principal prompts.
- ⚠️ **Then set `clientAppId`**: the CLI creates the "Agent 365 CLI" app but does **not** write its id
  back, so the endpoint step fails with *"clientAppId is required."* Copy the printed app id into
  **`a365.config.json`** (`"clientAppId": "<that id>"`, both the root and `backend/` copies).
- Save the **Blueprint client secret** it prints (or fetch later: `a365 setup blueprint --show-secret`).

### 3. Grant the tool + bot permissions (own terminal, admin)

```powershell
a365 setup permissions mcp    # browser consent + answer y to provision the 4 tool service principals
a365 setup permissions bot    # Messaging Bot API + Observability
```

### 4. Add the WorkIQ tools

```powershell
a365 develop list-available                                   # see the catalog
a365 develop add-mcp-servers mcp_MailTools mcp_TeamsServer mcp_SharePointRemoteServer mcp_OneDriveRemoteServer
Copy-Item ToolingManifest.json backend\ToolingManifest.json   # the container image needs it
```

### 5. Fill `backend/.env`

Copy `backend/.env.sample` → `backend/.env`, then set the Foundry values (endpoint, `gpt-5`,
api-version, key) and the blueprint values from `a365.generated.config.json` +
`a365 setup blueprint --show-secret` (see [§6](#6-configuration-reference-env)). Set **both** the
`CONNECTIONS__…` *and* the top-level `CLIENT_ID/TENANT_ID/CLIENT_SECRET`.

### 6. Deploy the container

```powershell
./deploy/deploy-containerapp.ps1 -ResourceGroup rg-a365-full -Location eastus2 `
    -AcrName a365fullacr<unique> -AppName a365-full-demo
# → prints the FQDN, e.g. https://a365-full-demo.<hash>.eastus2.azurecontainerapps.io/api/messages
```

The script registers the needed Azure resource providers (**incl. `Microsoft.Network`**), builds the
image in ACR (no local Docker needed), and creates the Container Apps environment + app.

> **If the environment fails with `AKSCapacityHeavyUsage`**, that region is full — re-run with a
> different `-Location` (e.g. `eastus2`, `westus3`).

### 7. Point the blueprint at the real endpoint, then publish

```powershell
cd backend
../deploy/set-endpoint.ps1 -Endpoint https://<fqdn>/api/messages   # registers it (with --m365)
a365 publish                                                       # → manifest/manifest.zip
```

### 8. Upload + create the instance (browser/admin)

1. Upload `manifest/manifest.zip` at **[admin.cloud.microsoft → Agents → Upload custom agent](https://admin.cloud.microsoft/#/agents/all)**; activate for users.
2. **Create an instance** (give it an alias) and **assign it a license** (Microsoft 365 Copilot / the
   Agent 365 seat). The blueprint page's **"View associated licenses"** tells you exactly which SKU.
3. Wait a few minutes for the Agentic User to appear, then **chat it in Teams**.

You're live. ✅

---

## 8. Run & test locally

```powershell
cd backend
copy .env.sample .env      # set AZURE_OPENAI_* and ENABLE_A365_OBSERVABILITY_EXPORTER=false
uv sync
uv run python start_with_generic_host.py
# → "Listening on http://0.0.0.0:3978/api/messages  (health: /api/health)"
```

In another terminal:

```powershell
curl http://localhost:3978/api/health     # {"status":"ok","agent_type":"MyAgent",...}
agentsplayground                          # point it at http://localhost:3978/api/messages
```

Locally the host runs **anonymous** (no Teams JWT) — that's fine for AgentsPlayground. For WorkIQ
tools locally, put a token from `a365 develop get-token` into `BEARER_TOKEN` and set
`USE_AGENTIC_AUTH=false`.

---

## 9. Troubleshooting (every wall we hit)

| Symptom | Cause & fix |
|---|---|
| Container logs say **`Auth: Anonymous`** | Top-level `CLIENT_ID`/`TENANT_ID`/`CLIENT_SECRET` not set. Set all three + restart. |
| `a365 setup all` fails **"clientAppId is required"** | The CLI created the app but didn't write it back. Put the printed app id into `a365.config.json`, then re-run `a365 setup blueprint --endpoint-only`. |
| `a365` browser sign-in **times out (120s)** | You're in an embedded terminal. Run `a365 setup …` in your own terminal (real popup). After one success the token cache is warm. |
| Container Apps env fails **`MissingSubscriptionRegistration`** | Fresh subscription. `deploy-containerapp.ps1` now registers `Microsoft.App/ContainerRegistry/OperationalInsights/Network/ContainerInstance` — re-run it. |
| Container Apps env **`ManagedEnvironmentNotProvisioned` / Failed** | Usually `Microsoft.Network` unregistered **or** `AKSCapacityHeavyUsage` in that region. Register the provider / pick another region. |
| **"You have run out of licenses"** on Add instance | The agent instance needs a specific license SKU. Assign an available Copilot / Agent 365 seat (blueprint → *View associated licenses*). |
| **Add instance** disabled or 500 | Tenant not enrolled in **Frontier**, or license/backend not ready. Enroll Frontier; retry. |
| No response in Teams | Dev Portal Notification URL must equal the blueprint `messagingEndpoint` and Agent Type = **API Based**. Re-run `set-endpoint.ps1` if the FQDN changed. |
| Tool calls fail (403) | Run `a365 setup permissions mcp` (admin); confirm the servers under the agent's **Permissions**. |
| Prod agent ignores tools | `PYTHON_ENVIRONMENT` must be `Production` in the Container App. |
| No spans in the admin center | `ENABLE_A365_OBSERVABILITY_EXPORTER=true` in the cloud; indexing lags 15–90 min. |
| Rotate a leaked secret | `az ad app credential reset --id <blueprintId> --query password -o tsv`, update `.env` + the Container App secrets, restart the revision. |

---

## 10. Repository layout

```
a365-agent-full/
├─ backend/                       ← the agent (runs in the container); also the a365 project dir
│  ├─ start_with_generic_host.py  ← entry point
│  ├─ host_agent_server.py        ← aiohttp host + auth + routing + observability
│  ├─ agent.py                    ← MyAgent: Agent Framework (gpt-5) + WorkIQ tools
│  ├─ agent_interface.py          ← host⇄agent contract
│  ├─ token_cache.py              ← per-turn observability token cache
│  ├─ pyproject.toml · uv.lock    ← pinned dependencies
│  ├─ Dockerfile · .dockerignore  ← container build
│  ├─ a365.config.json            ← agent identity for the a365 CLI
│  ├─ ToolingManifest.json        ← WorkIQ servers (CLI-written)
│  └─ .env(.example)              ← config + secrets (.env gitignored)
├─ frontend/
│  ├─ teams/                      ← Teams app package: manifest.json + icons (CLI-owned)
│  └─ playground/                 ← AgentsPlayground config for local testing
├─ deploy/
│  ├─ deploy-containerapp.ps1     ← register providers, build image, create Container App
│  ├─ set-endpoint.ps1            ← register the messaging endpoint on the blueprint
│  ├─ set-appsettings.ps1         ← push .env → Container App (secrets as secrets)
│  └─ generate-icons.ps1          ← placeholder Teams icons
├─ manifest/                      ← output of `a365 publish` (manifest.json + manifest.zip)
└─ README.md                      ← you are here
```

Secrets (`.env`, `a365.generated.config.json`, `*.local.json`) are gitignored and never committed.
See the [root README](../README.md) for how the slim and full demos relate.
