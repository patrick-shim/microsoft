# Microsoft Agent 365 — sample agents

This repository contains **three working samples** that show how to build an AI agent on
**Microsoft Agent 365 (A365)** — Microsoft's platform for AI agents that live inside Microsoft 365
with their own identity, permissions, tools, and audit trail.

The samples are the same core idea at increasing levels of ambition, so you can start small and grow:

| | [`a365-agent-slim/`](a365-agent-slim/) | [`a365-agent-purview/`](a365-agent-purview/) | [`a365-agent-full/`](a365-agent-full/) |
|---|---|---|---|
| **What it is** | A single Python script on your laptop | The slim demo **+ Purview DLP** | A container deployed to Azure, used in Teams |
| **Talks to** | Your terminal (a REPL) | Your terminal (a REPL) | **Microsoft Teams** and **Microsoft Copilot** |
| **LLM** | Azure OpenAI gpt-5 (Agent Framework) | Azure OpenAI gpt-5 (Agent Framework) | Azure OpenAI **gpt-5** (Agent Framework) |
| **M365 tools** | WorkIQ **Mail** | WorkIQ **Mail** | WorkIQ **Mail, Teams, SharePoint, OneDrive** |
| **Observability** | ✅ exports to A365 | ✅ exports to A365 | ✅ exports to A365 |
| **Extra** | — | **Microsoft Purview DLP** blocks sensitive prompts inline | Real aiohttp host on **Azure Container Apps** |
| **Good for** | Understanding A365 fast | Showing **data-security / DLP** on an AI agent | A real, demoable Teams AI Teammate |
| **Setup effort** | Minutes | Minutes + a Purview app & DLP policy | End-to-end onboarding (blueprint, deploy, publish, license) |

---

## What is an AI agent on Agent 365? (30-second version)

- Microsoft gives your agent its **own identity** in Entra ID (a "Blueprint", and once instanced, an
  "Agentic User" with its own mailbox and UPN).
- The agent **thinks** with an Azure OpenAI model and **acts** on Microsoft 365 through ready-made
  **WorkIQ tools** (Mail, Teams, SharePoint, …) — using *its own* identity, not yours.
- Everything it does is emitted as **observability** and visible to admins in the Microsoft admin
  center and Microsoft Defender.
- Users reach it in **Microsoft Teams** and **Microsoft Copilot** (the full sample), or you drive it
  from a terminal (the slim sample).

New to all the vocabulary (tenant, Entra, blueprint, MCP, agentic user)? The
[full sample's §1](a365-agent-full/README.md#1-concepts-in-plain-english) explains every term in plain
English, and its [§4](a365-agent-full/README.md#4-how-one-message-flows--and-how-tokens-are-minted)
diagrams exactly how the agent proves who it is (token minting).

---

## Which one should I start with?

- **Just want to see it work and understand A365?** → [`a365-agent-slim/`](a365-agent-slim/README.md).
  You'll be chatting with an observable agent in a few minutes.
- **Want to see data-security / DLP govern an AI agent?** → [`a365-agent-purview/`](a365-agent-purview/README.md).
  The slim demo plus a Microsoft Purview policy that blocks sensitive prompts inline.
- **Want a real agent in Teams/Copilot, deployed to Azure?** → [`a365-agent-full/`](a365-agent-full/README.md).
  It has a complete, copy-paste [re-provision-from-scratch guide](a365-agent-full/README.md#7-re-provision-from-scratch-copypaste).

---

## Shared prerequisites

All three samples need:

- **Python 3.11+** and **[uv](https://docs.astral.sh/uv/)** (`python -m pip install uv`)
- **Azure CLI** (`az`) — `winget install Microsoft.AzureCLI`
- **Agent 365 CLI** (`a365`) — `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli` (needs .NET 8+)
- An **Azure OpenAI / Foundry** resource with a model deployment
- A tenant where you have **Global Administrator** (to grant the agent's permissions)

The **purview** sample additionally needs **Microsoft 365 E5** + Purview **pay-as-you-go billing** and a
DLP policy on the Application enforcement plane (see its README). The **full** sample additionally needs
an **Azure subscription** (to run the container) and, to go live in Teams, a tenant enrolled in
**Frontier** with an available **agent license**.

Each sample ships a fully-commented **`.env.sample`** — copy it to `.env` and fill it in. Every
variable is annotated with where it comes from (you / the `a365` CLI / Azure OpenAI) and what reads it.

---

## Repository layout

```
microsoft/
├─ README.md                ← you are here (overview of all three samples)
├─ a365-agent-slim/         ← the local demo (one script)
│  ├─ agent.py              ← chat + observability
│  ├─ refresh-mail-token.ps1← fetch a WorkIQ Mail token into .env
│  ├─ .env.sample          ← annotated config template
│  └─ README.md
├─ a365-agent-purview/      ← the slim demo + Microsoft Purview DLP
│  ├─ agent.py              ← chat + observability + Purview policy middleware
│  ├─ refresh-mail-token.ps1
│  ├─ .env.sample          ← annotated config template (+ PURVIEW_* keys)
│  └─ README.md
└─ a365-agent-full/         ← the real Teams AI Teammate
   ├─ backend/              ← the agent (runs in a container)
   ├─ frontend/             ← Teams app package + AgentsPlayground config
   ├─ deploy/               ← Azure Container Apps deploy scripts
   └─ README.md
```

---

## A note on secrets

Neither sample commits secrets. `.env`, `a365.generated.config.json`, and `*.local.json` are
gitignored at both the repo root and per-project. Client secrets live only in your local `.env` and
(for the full sample) in Azure Container Apps secrets. If a secret is ever printed or shared, rotate
it — the full sample's [troubleshooting section](a365-agent-full/README.md#9-troubleshooting-every-wall-we-hit)
shows how.
