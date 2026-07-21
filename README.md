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

## References & further reading

Everything you need to build, deploy, and govern these agents. Verified links to the official
Microsoft Learn docs, source, and packages.

### Microsoft Agent 365 (the platform)
- [Agent 365 documentation](https://learn.microsoft.com/microsoft-agent-365/) · [Overview](https://learn.microsoft.com/microsoft-agent-365/overview)
- [Agent 365 SDK & CLI (developer hub)](https://learn.microsoft.com/microsoft-agent-365/developer/) · [SDK overview](https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-sdk)
- [Quickstart: a Python Agent Framework agent on Agent 365](https://learn.microsoft.com/microsoft-agent-365/developer/quickstart-python-agent-framework) — closest official walkthrough to these samples
- [Manage agents in the Microsoft 365 admin center](https://learn.microsoft.com/microsoft-365/admin/manage/agent-365-overview) — where observability activities appear
- [Product page](https://www.microsoft.com/microsoft-agent-365)
- `a365` CLI: install with `dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli` (needs .NET 8+)

### Microsoft Agent Framework (the agent runtime — all three samples)
- [Agent Framework documentation](https://learn.microsoft.com/agent-framework/)
- [GitHub: microsoft/agent-framework](https://github.com/microsoft/agent-framework) · [Python source & samples](https://github.com/microsoft/agent-framework/tree/main/python)
- [Sample gallery](https://github.com/microsoft/Agent-Framework-Samples) · [PyPI: `agent-framework`](https://pypi.org/project/agent-framework/)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io) — the standard behind the WorkIQ tools

### Azure OpenAI / Foundry (the model — `gpt-5`)
- [Azure AI Foundry documentation](https://learn.microsoft.com/azure/ai-foundry/) · [Azure OpenAI in Foundry Models](https://learn.microsoft.com/azure/ai-services/openai/)
- [Create a resource & deploy a model](https://learn.microsoft.com/azure/ai-services/openai/how-to/create-resource) · [Manage quota / TPM](https://learn.microsoft.com/azure/ai-services/openai/how-to/quota)

### Microsoft Entra & auth (identity + tokens — all three samples)
- [Register an application](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app) · [Permissions & consent](https://learn.microsoft.com/entra/identity-platform/permissions-consent-overview)
- [`azure-identity` for Python](https://learn.microsoft.com/python/api/overview/azure/identity-readme) · [MSAL for Python](https://learn.microsoft.com/entra/msal/python/)
- [`uv` (Python package manager)](https://docs.astral.sh/uv/)

### Azure Container Apps (hosting — the **full** sample)
- [Azure Container Apps documentation](https://learn.microsoft.com/azure/container-apps/) · [Deploy your first container app](https://learn.microsoft.com/azure/container-apps/get-started) · [Managed identity](https://learn.microsoft.com/azure/container-apps/managed-identity)
- [Teams app manifest schema](https://learn.microsoft.com/microsoftteams/platform/resources/schema/manifest-schema) — the package the `a365` CLI generates

### Microsoft Purview (data security — the **purview** sample)
- [Use the Microsoft Purview SDK with Agent Framework](https://learn.microsoft.com/agent-framework/integrations/purview) · [PyPI: `agent-framework-purview`](https://pypi.org/project/agent-framework-purview/)
- [Secure & compliant Foundry / custom AI apps with the Purview SDK](https://learn.microsoft.com/purview/developer/secure-ai-with-purview) · [`purview_agent` end-to-end sample](https://github.com/microsoft/agent-framework/tree/main/python/samples/05-end-to-end/purview_agent)
- [DSPM for AI — deployment considerations](https://learn.microsoft.com/purview/dspm-for-ai-considerations) · [Data Loss Prevention](https://learn.microsoft.com/purview/dlp-learn-about-dlp) · [Sensitive information types](https://learn.microsoft.com/purview/sensitive-information-type-learn-about) · [Insider Risk Management](https://learn.microsoft.com/purview/insider-risk-management)
- [`New-DlpCompliancePolicy` (Security & Compliance PowerShell)](https://learn.microsoft.com/powershell/module/exchange/new-dlpcompliancepolicy)
- Blog: [Building Secure, Enterprise-Ready AI Agents with the Purview SDK + Agent Framework](https://techcommunity.microsoft.com/blog/microsoft-security-blog/building-secure-enterprise-ready-ai-agents-with-purview-sdk-and-agent-framework/4492356)

---

## A note on secrets

None of the samples commit secrets. `.env`, `a365.generated.config.json`, and `*.local.json` are
gitignored at both the repo root and per-project. Client secrets live only in your local `.env` and
(for the full sample) in Azure Container Apps secrets. If a secret is ever printed or shared, rotate
it — the full sample's [troubleshooting section](a365-agent-full/README.md#9-troubleshooting-every-wall-we-hit)
shows how.

---

*Maintainer: Patrick Shim — patrick.shim@live.co.kr*
