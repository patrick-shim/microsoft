# Agent 365 — local demo: an AI agent that chats, uses Microsoft 365 tools, and is observable

This folder is a small, self-contained demo of a **Microsoft Agent 365** agent running on
your own machine. In one terminal you chat with an AI agent that can:

1. **Answer questions** using an Azure OpenAI model (GPT-4.1).
2. **Act on your Microsoft 365 mailbox** — read/search/draft email — through "WorkIQ" tools.
3. **Report everything it does** to Agent 365 as **observability** activities you can see in
   the Microsoft admin center and Microsoft Defender.

It deliberately runs **without** Microsoft Teams or the Agents Playground, so the whole
thing is one Python script you can demo live.

> **New to Microsoft / Agent 365?** Start with **[§1 Concepts](#1-concepts-a-5-minute-primer)** —
> it explains every term used below (Entra, tenant, Blueprint, MCP, observability, …).
>
> **Two samples in this repo** — see the [root README](../README.md) for how they compare. When you're
> ready for a *real* agent that runs inside Microsoft Teams and Copilot (deployed to Azure), graduate
> to [`../a365-agent-full`](../a365-agent-full/README.md).
>
> **Configuration:** copy the fully-annotated [`.env.example`](.env.example) to `.env` and fill it in
> (every variable is commented with where it comes from and what reads it).

---

## Table of contents

1. [Concepts — a 5-minute primer](#1-concepts-a-5-minute-primer)
2. [What the demo does & how it works](#2-what-the-demo-does--how-it-works)
3. [Prerequisites](#3-prerequisites)
4. [Onboard the agent with the `a365` CLI](#4-onboard-the-agent-with-the-a365-cli)
5. [Configuration — the `.env` file](#5-configuration--the-env-file)
6. [Run the demo](#6-run-the-demo)
7. [How the code is structured](#7-how-the-code-is-structured)
8. [SDKs and packages used](#8-sdks-and-packages-used)
9. [See the activities in Agent 365](#9-see-the-activities-in-agent-365)
10. [Troubleshooting & notes](#10-troubleshooting--notes)

---

## 1. Concepts — a 5-minute primer

If you've never touched Microsoft's cloud, here are the only terms you need. Skim it once
and the rest of this README will make sense.

| Term | Plain-English meaning |
|---|---|
| **Microsoft Entra ID** | Microsoft's identity system (formerly "Azure AD"). It stores users, apps, and their permissions. Every login and API call is authorized here. |
| **Tenant** | One organization's private slice of Microsoft's cloud. It has an ID (a GUID) and a domain (e.g. `contoso.onmicrosoft.com`). Everything in this demo lives in **one tenant**. |
| **App registration / Service principal** | How a *program* (not a person) gets an identity in Entra so it can sign in and call APIs. The app registration is the definition; the service principal is its instance in your tenant. |
| **Microsoft Agent 365 (A365)** | Microsoft's platform for building and governing AI **agents** inside Microsoft 365. Agents get their own identity, scoped permissions, tools, and observability. |
| **Blueprint** | The agent's **app registration in Entra** — its identity template plus a client secret and the permissions it may use. Created for you by the `a365` CLI. |
| **Agent identity ("Entra agent ID" / agentic app id)** | A GUID that uniquely identifies *this agent*. Everything the agent does is attributed to this id. |
| **Azure OpenAI** | Microsoft's hosted version of OpenAI models (GPT-4.1 here), reachable at an HTTPS endpoint in your tenant. |
| **MCP (Model Context Protocol)** | An open standard for giving an LLM **tools** it can call. A "tool" is just a function the model can invoke (e.g. "search my mail"). |
| **WorkIQ tools** | Microsoft's ready-made MCP tool servers that expose Microsoft 365 data — Mail, Calendar, Teams, SharePoint, etc. This demo uses the **Mail** server. |
| **OpenTelemetry (OTel)** | The industry-standard way to record what software does as **spans** (timed, structured events). "Observability" = collecting and viewing those spans. |
| **A365 observability** | Agent 365's backend that receives the agent's spans, so admins can see every message, LLM call, and tool use in the admin center and in Microsoft Defender. |
| **Bearer token** | A short-lived signed credential (a JWT string) that proves "I'm allowed to call this API." Tokens expire (often ~1 hour) and must be refreshed. |
| **Client credentials / FMI chain** | Ways an app proves its identity to Entra to get a token. This demo uses a 3-step "FMI" (Federated Managed Identity) chain so the Blueprint can obtain a token **as the agent identity** for the observability API. |

---

## 2. What the demo does & how it works

You type a message. Under the hood, each turn does four things:

```
        You type: "How many unread emails do I have?"
                          │
                          ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  agent.py                                                     │
   │                                                              │
   │  1. Mint an observability token (FMI 3-hop chain) ──────────►│  Microsoft Entra ID
   │       so the agent is allowed to report telemetry            │  (login.microsoftonline.com)
   │                                                              │
   │  2. Open a baggage scope tagging spans with the agent id     │
   │                                                              │
   │  3. agent.run(message) ──────────────────────────────────────►  Azure OpenAI (GPT-4.1)
   │       the model decides to call a Mail tool ─────────────────►  WorkIQ Mail MCP server
   │       gets the answer, writes a reply                        │  (agent365.svc.cloud.microsoft)
   │                                                              │
   │  4. Export the spans (InvokeAgent + Chat) ──────────────────►│  Agent 365 observability
   │       "📡 activity exported to A365"                         │  (agent365.svc.cloud.microsoft)
   └──────────────────────────────────────────────────────────────┘
                          │
                          ▼
        Agent: "You have 123 unread emails. The latest is …"
```

- **The agent** = an Azure OpenAI model wrapped by the Microsoft **Agent Framework**, given
  the Mail tools. When you ask about email, the model *chooses* to call a Mail tool, reads
  the result, and answers in natural language.
- **Observability** = the Agent Framework automatically produces OpenTelemetry spans for the
  turn (an `InvokeAgent` span and a `Chat` span). We authenticate and ship those spans to the
  Agent 365 backend, where they show up as **activities**.

> **Why is this a standalone script and not a hosted service?** The "proper" way to run an
> A365 agent is a web service that Teams calls. In this SDK build that hosting layer silently
> drops locally-sent messages, so this demo talks to the model directly — same agent, same
> tools, same observability, just no web server in the middle.

---

## 3. Prerequisites

You need four things. Install what's missing, then verify with the "check" command.

### 3.1 Python 3.11+ and the virtual environment

The demo is Python. A **virtual environment** (`.venv`) is an isolated set of packages so this
project's dependencies don't collide with anything else on your machine.

```powershell
python --version                 # check: 3.11 or higher

# create the venv and install this project's dependencies (defined in pyproject.toml)
pip install uv                   # 'uv' is a fast Python package installer
uv venv                          # creates .venv\
uv pip install -e . --python .venv\Scripts\python.exe
```

> Everything below runs Python as `.venv\Scripts\python.exe` so it uses that isolated
> environment. (Or activate it once with `.venv\Scripts\Activate.ps1` and just type `python`.)

### 3.2 Azure CLI (`az`) — for signing in

`az` is Microsoft's command-line tool for Azure/Entra. The agent uses **your** signed-in
identity to call Azure OpenAI (this tenant disallows API keys), so you must be logged in.

```powershell
az version                                       # check it's installed
az login --allow-no-subscriptions                # sign in to your tenant
az account show --query "{user:user.name, tenantId:tenantId}" -o json   # confirm
```

### 3.3 Agent 365 CLI (`a365`) — for onboarding & the Mail token

`a365` is Microsoft's tool for registering agents with Agent 365. You use it **once** to
onboard the agent (§4), and again whenever you need to refresh the Mail token (§6).

```powershell
dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli   # install (needs .NET 8+)
a365 --version                                                    # check: e.g. 1.1.214
```

> **`az` vs `a365`** — two different tools. `az` signs you into the tenant; `a365` registers
> and manages the agent. The demo itself (`agent.py`) calls **neither** at runtime.

### 3.4 Entra roles (permissions on your account)

To onboard an agent, your signed-in account needs:

- **Agent ID Developer** — to create the Blueprint and its permissions.
- **Global Administrator** (or Application/Cloud Application Administrator) — to grant
  tenant-wide consent for the agent's permissions. If you're *not* an admin, `a365 setup all`
  still runs and prints a script for an admin to finish the consent step.

---

## 4. Onboard the agent with the `a365` CLI

"Onboarding" = registering the agent with Agent 365. This is a **one-time** step that creates
the agent's identity and permissions in Entra and writes the resulting IDs into your `.env`
so the demo can use them. (This folder's agent, `agent-obs-demo`, is already onboarded — the
steps below show how it was done and how to do a fresh one.)

### 4.1 Preview first (a dry run — nothing is created)

```powershell
a365 setup all --agent-name agent-obs-demo --authmode obo --dry-run
```
```
The following steps would be performed.
  1. Prerequisites                validate (Azure CLI, PowerShell modules)
  2. Blueprint                    create (multi-tenant): agent-obs-demo Blueprint
                                  + service principal + client secret + FIC + managed identity
  3. Inheritable Permissions      Microsoft Graph, Agent 365 Tools, Observability API, Power Platform API
  4. Blueprint Permission Grants  delegated grants for the signed-in principal
  5. Agent identity               create: agent-obs-demo Identity
  6. Agent Registration           register: agent-obs-demo Agent
  7. Messaging endpoint           skipped (non-M365 agent)
  8. Project settings             write to .env
```

- **`--agent-name`** is your choice: 3–20 chars, starts with a letter. It becomes
  `"<name> Blueprint"` and `"<name> Identity"`.
- **`--authmode obo`** = *on-behalf-of* (the agent acts using delegated user permissions).
  Use `--authmode s2s` for an unattended service-principal-only agent.

### 4.2 Apply — create the Blueprint, identity, and permissions

```powershell
a365 setup all --agent-name agent-obs-demo --authmode obo
```

While it runs:
- A **Windows sign-in dialog** may pop up — complete it.
- It asks `Assign this application permission now? [y/N]` for
  **`Agent365.Observability.OtelWrite`** — press **`y`**. *(This is the permission that lets
  the agent send telemetry to Agent 365 — the whole point of the demo.)*
- A **browser opens for admin consent** — sign in and click **Accept**.

Success ends with a summary:
```
Setup Summary
  2. Blueprint                    created  'agent-obs-demo Blueprint' (ID: d06067f7-…)
  5. Agent identity               created  'agent-obs-demo Identity'  (ID: d435d1c6-…)
  6. Agent Registration           registered 'agent-obs-demo Agent'   (ID: T_668bb499-…)
  8. Project settings             written
Setup completed successfully
```
The command is **idempotent** — safe to re-run; it reuses the same Blueprint.

### 4.3 What you just created, and where the IDs live

`a365 setup all` writes two files:

**`a365.generated.config.json`** — the registration record:

```powershell
Get-Content a365.generated.config.json | ConvertFrom-Json |
  Select-Object agentBlueprintId, agenticAppId, agentRegistrationId
```

| Field | What it is | Example |
|---|---|---|
| `agentBlueprintId` | The **Blueprint** (app/client) id | `d06067f7-…` |
| `agenticAppId` | The **agent identity** ("Entra agent ID") — what activity is attributed to | `d435d1c6-…` |
| `agentRegistrationId` | The agent registration id | `T_668bb499-…` |

**`.env`** — stamped with the values the demo reads (Blueprint client id/secret, tenant id,
agent id). See §5.

> **One manual touch-up:** after onboarding, make sure `.env` has
> `AGENT365_ACTIVITY_AGENT_ID=<agenticAppId>` — the demo attributes activities to the
> **agent identity**, not the Blueprint id.

### 4.4 Useful follow-up commands

```powershell
a365 query-entra --help                                        # inspect scopes/permissions/consent
a365 setup blueprint --agent-name agent-obs-demo --show-secret # reprint the client secret
a365 develop list-available                                    # list WorkIQ tool servers you can add
a365 cleanup --agent-name agent-obs-demo                       # tear everything down
```

---

## 5. Configuration — the `.env` file

`.env` is a plain text file of `KEY=value` lines that the demo loads at startup. It is **not**
committed to git (it holds secrets). Most values are written by `a365 setup all`; a few you set
yourself. Here's every key the demo reads:

| Key | What it is | Set by |
|---|---|---|
| `AZURE_OPENAI_ENDPOINT` | Your Azure OpenAI HTTPS endpoint | you |
| `AZURE_OPENAI_DEPLOYMENT` | The model deployment name (e.g. `gpt-4.1`) | you |
| `AZURE_OPENAI_API_VERSION` | API version — use `preview` for the `/openai/v1` endpoint | you |
| `AGENT365OBSERVABILITY__TENANTID` | Your tenant id | `a365 setup all` |
| `AGENT365OBSERVABILITY__CLIENTID` | Blueprint (client) id — used to mint the observability token | `a365 setup all` |
| `AGENT365OBSERVABILITY__CLIENTSECRET` | Blueprint client secret | `a365 setup all` |
| `AGENT365OBSERVABILITY__AGENTBLUEPRINTID` | Blueprint id (span metadata) | `a365 setup all` |
| `AGENT365_ACTIVITY_AGENT_ID` | **Agent identity** id — activities are attributed to this | you (from `agenticAppId`) |
| `BEARER_TOKEN` | Short-lived WorkIQ Mail token — enables the Mail tools | `refresh-mail-token.ps1` |

If a `CONNECTIONS__SERVICE_CONNECTION__SETTINGS__*` variant exists (also stamped by the CLI),
the demo falls back to it for tenant/client id/secret — so either naming works.

---

## 6. Run the demo

### 6.1 (Optional) enable the Mail tools

The Mail tools need a **bearer token** scoped to your mailbox. It lasts ~1 hour. This script
fetches one (via `a365 develop get-token`) and writes it into `.env` as `BEARER_TOKEN`:

```powershell
.\refresh-mail-token.ps1
```
Skip this and the agent still chats — it just can't touch your mail.

### 6.2 Chat

```powershell
# interactive — type messages; each turn prints "📡 activity exported to A365"
.venv\Scripts\python.exe agent.py

# one-shot (non-interactive)
.venv\Scripts\python.exe agent.py -m "How many unread emails do I have?"

# chat only, skip the A365 export
.venv\Scripts\python.exe agent.py --no-export
```

On start you'll see:
```
🔭 Observability ON — activities export to A365 as agent d435d1c6-…
🔧 Mail tools enabled (WorkIQ mcp_MailTools).
🤖 agent-obs-demo Identity ready (Azure OpenAI: gpt-4.1).
```

Good things to ask:
- *"How many unread emails do I have, and summarize the latest one."*
- *"Draft a reply to my most recent email saying I'll follow up tomorrow."*
- *"What can you help me with?"* (plain chat — no tools)

---

## 7. How the code is structured

Everything lives in one file, **`agent.py`**, read top-to-bottom. Its sections:

| Section | What it does |
|---|---|
| **Imports** | Grouped: standard library · third-party (`httpx`, `msal`, `azure-identity`, `dotenv`) · Agent Framework · Agent 365 observability · OpenTelemetry. |
| **Constants** | The Mail server URL, the default agent id, the OAuth scopes, and the agent's system prompt. |
| **Configuration** | A `Config` dataclass + `load_config()` — reads `.env` into a typed object. |
| **Observability** | `_mint_observability_token()` runs the **FMI 3-hop chain** to get a token allowed to write telemetry; `enable_observability()` wires the OpenTelemetry exporter to use it. |
| **Agent construction** | `_connect_mail_tool()` connects the Mail MCP server (auth on the http client so the *connect handshake* is authenticated); `build_agent()` creates the Azure OpenAI agent and stamps it with the agent id so its spans attribute correctly. |
| **Chat turn** | `run_turn()` runs one message inside a *baggage scope* (which tags every span with the tenant + agent id), then flushes so the activity ships immediately. |
| **Session** | `_chat()` ties it together: validate config → turn on observability → build the agent → run one message or an interactive loop. |
| **Entry point** | `main()` parses `-m` / `--no-export` and starts the async loop. |

Two implementation details worth knowing (both commented in the code):

- **MCP auth goes on the HTTP client, not per-call.** The Mail server rejects the initial
  *connect* handshake if it's unauthenticated, so the bearer token is set as a default header on
  an `httpx.AsyncClient` that the tool uses for every request.
- **The agent id is stamped onto the agent** (`as_agent(id=…)`). Otherwise the framework
  invents a random id per turn and the observability backend can't group/authenticate the spans.

---

## 8. SDKs and packages used

| Package | Role in the demo |
|---|---|
| **`agent-framework`** (Microsoft Agent Framework: `-core`, `-openai`) | Builds the agent. `OpenAIChatClient` talks to Azure OpenAI; `.as_agent()` turns it into a runnable agent; `MCPStreamableHTTPTool` connects the Mail tools. |
| **`microsoft-opentelemetry`** (Microsoft's OpenTelemetry distro) | Sets up telemetry and the **Agent 365 exporter** (`use_microsoft_opentelemetry`), plus `BaggageBuilder` to tag spans with the tenant/agent identity. |
| **`azure-identity`** | `AzureCliCredential` — lets the agent authenticate to Azure OpenAI using your `az login` session (no API key). |
| **`msal`** (Microsoft Authentication Library) | `ConfidentialClientApplication` — the final hop of the observability-token chain. |
| **`httpx`** | HTTP client — used for the token-endpoint calls and as the authenticated transport for the Mail MCP tool. |
| **`python-dotenv`** | Loads `.env`. |
| **`opentelemetry`** | The underlying OTel API (`trace`) — used to flush spans after each turn. |
| **`a365` CLI** (`Microsoft.Agents.A365.DevTools.Cli`) | Command-line tool — onboards the agent (§4) and fetches the Mail token (§6). Not called by the Python code. |
| **Azure CLI (`az`)** | Command-line sign-in — provides the identity `azure-identity` uses. |

---

## 9. See the activities in Agent 365

Each turn that prints `📡 activity exported to A365` sends spans to the Agent 365 backend.
View them:

- **Microsoft 365 admin center** → **Agents → All agents → `agent-obs-demo` → Activity**.
- **Microsoft Defender / Purview** → **Advanced Hunting → `CloudAppEvents`**, filter
  `AgentId == "<AGENT365_ACTIVITY_AGENT_ID from .env>"`.

> **Indexing takes 15–90 minutes.** If you query right after a turn you'll see nothing — that's
> normal, not a failure. The terminal's `📡 exported` line is your immediate confirmation.

---

## 10. Troubleshooting & notes

- **Mail calls suddenly fail** → the bearer token expired (~1 hour). Re-run
  `.\refresh-mail-token.ps1` and restart `agent.py`.
- **`Could not enable observability` / token errors** → check `.env` has the Blueprint
  `CLIENTID` / `CLIENTSECRET` / `TENANTID` and that `AGENT365_ACTIVITY_AGENT_ID` is the
  **agentic app id** (not the Blueprint id).
- **`Missing AZURE_OPENAI config`** → fill `AZURE_OPENAI_ENDPOINT` / `_DEPLOYMENT` /
  `_API_VERSION` in `.env`, and make sure you've run `az login`.
- **A tool returns "Response size exceeds maximum"** → the mailbox is large and the model
  picked a greedy Mail query. Ask a narrower question; the agent handles it gracefully.
- **This is a demo, not a deployable service.** The original hosted A365 agent (aiohttp server,
  `AgentInterface`, etc.) was removed to keep the folder clean — recover it from git history
  (`git log`) if you need it.
