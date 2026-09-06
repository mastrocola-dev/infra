# infra

Azure infrastructure for [mastrocola.dev](https://github.com/mastrocola-dev), managed with Terraform.

## Structure

```
bootstrap/     Terraform state backend, identities, cost guardrails — applied manually
foundation/    Core platform resources — applied via CI
site/          Public site hosting and DNS — applied via CI
```

The split follows the privilege boundary, not just the chicken-and-egg problem:

- `bootstrap` is applied once, locally, by a human Owner (`az login`). It creates the state backend — which cannot provision itself — and everything requiring elevated rights: resource groups, RBAC assignments, subscription budget. Its own state is intentionally local.
- `foundation` is applied by CI. The CI identity holds Contributor on `rg-portfolio-dev` only, so this layer references resource groups as data sources and never attempts subscription-level changes.
- `site` is applied by CI under the same identity. It declares the Static Web App serving [mastrocola.dev](https://mastrocola.dev) and the Cloudflare DNS records pointing at it (see [ADR-002](https://github.com/mastrocola-dev/docs/blob/main/adr/002-public-site-hosting.md)). Site content lives in the [www](https://github.com/mastrocola-dev/www) repository and is deployed by its own pipeline.

## Pipelines

One workflow per root module, same shape, separate state keys and concurrency groups:

| Workflow | Watches | State key |
|---|---|---|
| [`infra.yml`](.github/workflows/infra.yml) | `foundation/**` | `foundation.tfstate` |
| [`site.yml`](.github/workflows/site.yml) | `site/**` | `site.tfstate` |

| Trigger | Behavior |
|---|---|
| Pull request to `main` | `fmt` check, `validate`, `plan` |
| Push to `main` | plan + `apply` |
| Manual dispatch | plan, with optional apply (`apply: true`) |

## Authentication

The pipelines authenticate to Azure via OIDC federation — no stored credentials. The Entra application trusts GitHub's immutable subject format (`repo:owner@id/repo@id:...`), with one federated credential for `main` and one for pull requests. Storage access uses Entra ID tokens exclusively (`storage_use_azuread`); shared account keys are disabled everywhere.

The `site` module additionally authenticates to Cloudflare with an API token scoped to DNS edit on the `mastrocola.dev` zone only — an accepted static secret (ADR-002).

Required repository configuration:

| Type | Name | Purpose |
|---|---|---|
| Secret | `AZURE_CLIENT_ID` | Entra application (client) ID |
| Secret | `AZURE_TENANT_ID` | Entra tenant ID |
| Secret | `AZURE_SUBSCRIPTION_ID` | Target subscription |
| Secret | `CLOUDFLARE_API_TOKEN` | DNS edit on the site zone (site module only) |
| Variable | `TFSTATE_RESOURCE_GROUP` | State backend resource group |
| Variable | `TFSTATE_STORAGE_ACCOUNT` | State backend storage account |
| Variable | `CLOUDFLARE_ZONE_ID` | Zone holding the site records |

## Site specifics
 
- Static Web Apps is not available in `brazilsouth`; the resource lives in `eastus2`. This is metadata placement only — content is served from the global edge.
- Cloudflare records for the site are DNS-only (proxy off): Static Web Apps brings its own edge, and proxying interferes with domain validation.
- The apex validates by TXT token (one-shot, removed after validation); the www subdomain validates by CNAME delegation, which requires the record to exist first — hence the explicit `depends_on`. Patterns and failure modes: [static-web-apps runbook](https://github.com/mastrocola-dev/docs/blob/main/runbooks/static-web-apps.md).
- `repository_url`/`repository_branch` on the app and `validation_type` on the www domain are excluded from reconciliation: the first pair is written by the `www` content pipeline on every deploy, the last is not returned by the Azure API and would force replacement of imported domains.
- The CI identity holds a custom subscription-scope role (`Web Async Operation Reader`, defined in bootstrap) because Static Web Apps mutations report async status at subscription scope, outside the resource-group Contributor boundary.
- The deployment token consumed by the `www` pipeline is retrieved with `az staticwebapp secrets list --name stapp-portfolio-www` and stored as a secret in that repository. It can only publish static content.

## Bootstrap (manual, applied by a human Owner)
 
```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars   # fill in values
terraform init \
  -backend-config="resource_group_name=<state rg>" \
  -backend-config="storage_account_name=<state account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=bootstrap.tfstate" \
  -backend-config="use_azuread_auth=true"
terraform plan   # read it — bootstrap has no CI gate
terraform apply
```
 
Bootstrap state lives in the same remote backend as everything else (`bootstrap.tfstate`). Its first apply ever ran with local state — the backend cannot provision itself — and was migrated once the backend existed; local state stops being a necessity after day zero, and an unversioned file on a workstation is a liability (lesson learned when a repo migration lost it).
 
The privilege boundary is unchanged by where state lives: bootstrap is applied exclusively by a human Owner via `az login`, never by CI. Authentication to the state blob uses the operator's Entra identity.
 
Outputs from this module feed the `TFSTATE_*` repository variables above. Resources that predated this code were adopted into state via one-shot `import` blocks, removed once consumed.
 
Because bootstrap sits outside CI, nothing validates it on push — run `terraform fmt -recursive` and `terraform validate` locally before committing, and read plans with extra care.

## Conventions

- No comments in code — rationale lives in this README, mechanics in the resource names
- `.terraform.lock.hcl` is committed in every root module — CI and local runs use identical provider versions
- Terraform `1.9.8`, pinned in the workflow
- `outputs.tf` is a separate file in every root module
- Resource names retain the original `portfolio` prefix — renaming forces destroy/recreate; accepted as debt until a new environment supersedes them. Tags carry the current `mastrocola-dev` identity
- Architecture rationale lives in [docs](https://github.com/mastrocola-dev/docs); this README covers operation only
