# infra

Azure infrastructure for [mastrocola.dev](https://github.com/mastrocola-dev), managed with Terraform.

## Structure

```
bootstrap/     Terraform state backend (resource group, storage account) — applied manually
foundation/    Core platform resources — applied via CI
```

`bootstrap` is intentionally outside CI: it creates the storage account that holds all Terraform state, so it cannot depend on that state existing. It runs manually, once, and rarely changes.

## Pipeline

[`infra.yml`](.github/workflows/infra.yml) runs on changes to `foundation/**`:

| Trigger | Behavior |
|---|---|
| Pull request to `main` | `fmt` check, `validate`, `plan` |
| Push to `main` | plan + `apply` |
| Manual dispatch | plan, with optional apply (`apply: true`) |

A single concurrency group serializes runs, preventing state lock contention.

## Authentication

The pipeline authenticates to Azure via OIDC federation — no stored credentials. The Entra application trusts GitHub's immutable subject format (`repo:owner@id/repo@id:...`), with one federated credential for `main` and one for pull requests.

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

Outputs from this apply feed the `TFSTATE_*` repository variables above.

## Conventions

- `.terraform.lock.hcl` is committed in every root module — CI and local runs use identical provider versions
- Terraform `1.9.8`, pinned in the workflow
- Architecture rationale lives in [docs](https://github.com/mastrocola-dev/docs); this README covers operation only