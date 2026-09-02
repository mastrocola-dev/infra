# Cloud Foundation — Azure + Terraform + GitHub Actions

Infrastructure-as-code foundation for my personal engineering portfolio, designed the way I would bootstrap a real company: identity first, least privilege everywhere, no long-lived credentials, and cost guardrails from day one.

Everything here runs on an Azure free-tier-friendly footprint, but every decision was made as if this subscription would one day host production fintech workloads — because it might.

## Architecture at a glance

```
GitHub Actions ──OIDC (no secrets)──> Microsoft Entra ID ──RBAC──> Azure
     │                                                              │
     │  terraform plan/apply                                        │
     └───────────> azurerm backend <── rg-tfstate (state, versioned)
                        │
                        └────────────> rg-portfolio-dev (workloads)
```

| Layer | Directory | Applied by | State |
|---|---|---|---|
| Bootstrap | `infra/bootstrap` | Human Owner, locally, once | Local |
| Foundation | `infra/foundation` | CI (GitHub Actions) | Remote (Azure Blob) |

## Key design decisions

### 1. Identity before infrastructure

The subscription was set up with a deliberate separation of identities:

- **Working identity** (`marcio@…`) — a native Entra ID user on a verified custom domain, holding Global Administrator + subscription Owner, protected by MFA. Used for all day-to-day administration.
- **Break-glass account** — the original account that created the tenant (an external Microsoft account). Demoted from daily use, credentials stored offline, kept because it retains billing ownership and an authentication path independent of the custom domain — exactly what you want when DNS is on fire.
- **CI identity** (`github-actions-portfolio`) — an app registration with **zero standing credentials**. No client secrets exist anywhere in this project.

Tenant-level *elevated access* ("User Access Administrator" at root scope) was explicitly revoked after initial setup to minimize blast radius.

### 2. Passwordless CI/CD with OIDC — and the immutable-subject lesson

GitHub Actions authenticates to Azure through workload identity federation: the runner presents a short-lived token issued by GitHub, and Entra ID validates it against a trust relationship. Nothing to store, rotate, or leak.

One battle scar worth documenting: **GitHub changed its default OIDC subject format for repositories created after July 15, 2026**. New repos emit immutable subjects that embed owner and repository IDs (`repo:owner@123/repo@456:ref:…`) instead of the historical name-based format. The Azure portal's guided "GitHub Actions" federated-credential scenario still generates the name-based subject, so the trust never matches and every login fails with `AADSTS700213`.

The fix: create the federated credential with the **Other issuer** scenario and the exact immutable subject from the token. The security rationale is sound — name-based subjects are vulnerable to *subject recycling*, where an abandoned org/repo name is re-registered by someone else who can then mint matching tokens against your cloud trust.

### 3. Least privilege, enforced by architecture

The CI identity holds exactly two permissions:

- `Contributor` on `rg-portfolio-dev` — it can deploy workloads there and nowhere else.
- `Storage Blob Data Contributor` on the state storage account — data plane only.

This is why the code is split in two layers. The **bootstrap** layer (resource groups, state backend, budgets, role assignments) requires Owner rights and is applied by a human, once. The **foundation** layer runs in CI and *cannot* escalate: it consumes resource groups as data sources and only manages resources inside them. The permission boundary is structural, not a convention.

### 4. Hardened state backend

Terraform state is the most sensitive artifact in any IaC setup. The backend storage account is configured with:

- **Shared access keys disabled** — all access (human and CI) goes through Entra ID with RBAC, `use_azuread_auth = true` in the backend config.
- **Blob versioning + 14-day soft delete** — point-in-time recovery from a corrupted or mistakenly overwritten state.
- **No public access, TLS 1.2 minimum.**

### 5. Cost guardrails as code

A subscription-level monthly budget with alerts at 50/80/100% actual spend plus a forecasted-overrun alert is part of the bootstrap layer. Workload resources default to the cheapest sensible SKUs (LRS, Cool tier). The bill is an architectural constraint, not an afterthought.

## Repository layout

```
.
├── .github/workflows/terraform.yml   # CI: init → fmt → validate → plan → apply
├── infra/
│   ├── bootstrap/                    # human-applied: state backend, budget, RBAC
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── foundation/                   # CI-applied: workloads in rg-portfolio-dev
│       ├── providers.tf              # partial azurerm backend
│       └── main.tf
└── .gitignore
```

## Getting started

Prerequisites: Terraform ≥ 1.9, Azure CLI, an Azure subscription, and the one-time manual identity setup (verified custom domain, admin user, app registration with an OIDC federated credential — see design decisions above for why the CI identity is not self-provisioned: the identity that runs Terraform cannot create itself).

### Bootstrap (once, locally)

```bash
az login   # as the human Owner identity

cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in your values
terraform init

# Adopt the pre-existing Contributor role assignment created via portal:
ASSIGNMENT_ID=$(az role assignment list \
  --resource-group rg-portfolio-dev \
  --query "[?roleDefinitionName=='Contributor' && principalType=='ServicePrincipal'].id | [0]" -o tsv)
terraform import azurerm_role_assignment.ci_workload_contributor "$ASSIGNMENT_ID"

terraform apply
```

The apply also executes an `import` block that adopts the manually created `rg-portfolio-dev`, bringing the full foundation under code management. Note the `foundation_backend_config` output — you'll need the storage account name next.

### Wire up CI

In the GitHub repository, create:

- **Secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- **Variables**: `TFSTATE_RESOURCE_GROUP` (`rg-tfstate`), `TFSTATE_STORAGE_ACCOUNT` (from the bootstrap output)

Push to `main` (or trigger the workflow manually) and the foundation layer plans and applies with zero stored credentials.

### Local foundation runs (optional)

```bash
cd infra/foundation
terraform init -backend-config=backend.hcl   # paste the bootstrap output into backend.hcl
terraform plan
```

## Roadmap

- **PR-based plans** — add a second federated credential for the `pull_request` OIDC subject so plans can run on pull requests before merge.
- **Environments** — promote the layout to `dev`/`prd` with separate state keys and GitHub environment protection rules.
- **First workloads** — an event-driven data pipeline (Airflow + messaging) and a parametrizable BPMN decision engine, drawing on my background in fintech backends and data engineering.

---

*Built by [Marcio Mastrocola Alcantara](https://www.linkedin.com/in/marciomastrocola) — Software Architect & Tech Lead. This repository doubles as documentation of how I approach greenfield cloud foundations.*
