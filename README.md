# infra

Azure infrastructure for [mastrocola.dev](https://github.com/mastrocola-dev), managed with Terraform.

## Structure

```
bootstrap/     Terraform state backend, identities, cost guardrails — applied manually
foundation/    Core platform resources — applied via CI
```

The split follows the privilege boundary, not just the chicken-and-egg problem:

- `bootstrap` is applied once, locally, by a human Owner (`az login`). It creates the state backend — which cannot provision itself — and everything requiring elevated rights: resource groups, RBAC assignments, subscription budget. Its own state is intentionally local.
- `foundation` is applied by CI. The CI identity holds Contributor on `rg-portfolio-dev` only, so this layer references resource groups as data sources and never attempts subscription-level changes.

## Pipeline

[`infra.yml`](.github/workflows/infra.yml) runs on changes to `foundation/**`:

| Trigger | Behavior |
|---|---|
| Pull request to `main` | `fmt` check, `validate`, `plan` |
| Push to `main` | plan + `apply` |
| Manual dispatch | plan, with optional apply (`apply: true`) |

A single concurrency group serializes runs, preventing state lock contention.

## Authentication

The pipeline authenticates to Azure via OIDC federation — no stored credentials. The Entra application trusts GitHub's immutable subject format (`repo:owner@id/repo@id:...`), with one federated credential for `main` and one for pull requests. Storage access uses Entra ID tokens exclusively (`storage_use_azuread`); shared account keys are disabled everywhere.

Required repository configuration:

| Type | Name | Purpose |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Entra application (client) ID |
| Secret | `AZURE_TENANT_ID` | Entra tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Target subscription |
| Variable | `TFSTATE_RESOURCE_GROUP` | State backend resource group |
| Variable | `TFSTATE_STORAGE_ACCOUNT` | State backend storage account |

## Bootstrap (manual, one-time)

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in values
terraform init
terraform apply
```

Outputs from this apply feed the `TFSTATE_*` repository variables above. Backend configuration for `foundation` comes from the `foundation_backend_config` output (local runs) or `-backend-config` flags (CI) — environment-specific values never enter version control.

Resources that predated this code (`rg-portfolio-dev`, the CI Contributor assignment) were adopted into state via `import` at the first apply; the one-shot import blocks were removed once consumed.

## Conventions

- No comments in code — rationale lives in this README, mechanics in the resource names
- `.terraform.lock.hcl` is committed in every root module — CI and local runs use identical provider versions
- Terraform `1.9.8`, pinned in the workflow
- Resource names retain the original `portfolio` prefix — renaming forces destroy/recreate; accepted as debt until a new environment supersedes them. Tags carry the current `mastrocola-dev` identity
- Architecture rationale lives in [docs](https://github.com/mastrocola-dev/docs); this README covers operation only