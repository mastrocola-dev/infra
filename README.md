# infra

Azure infrastructure for [mastrocola.dev](https://github.com/mastrocola-dev), managed with Terraform.

## Structure

```
bootstrap/     State backend, identities, Key Vault, role assignments, cost guardrails — applied manually
foundation/    Core platform resources — applied via CI
site/          Public site hosting and DNS — applied via CI
agent/         Agent runtime: function apps, queues, storage, telemetry — applied via CI
```

The split follows the privilege boundary, not just the chicken-and-egg problem:

- `bootstrap` is applied once, locally, by a human Owner (`az login`). It creates the state backend — which cannot provision itself — and everything requiring elevated rights: resource groups, identities, Key Vault, every role assignment, subscription budget. It has no apply pipeline.
- `foundation` is applied by CI. The CI identity holds Contributor on `rg-portfolio-dev` only, so this layer references resource groups as data sources and never attempts subscription-level changes.
- `agent` is applied by CI under the same identity. It declares the runtime of [ADR-007](https://github.com/mastrocola-dev/docs/blob/main/adr/007-agent-runtime.md); see [Agent specifics](#agent-specifics).
- `site` is applied by CI under the same identity. It declares the Static Web App serving [mastrocola.dev](https://mastrocola.dev) and the Cloudflare DNS records pointing at it (see [ADR-002](https://github.com/mastrocola-dev/docs/blob/main/adr/002-public-site-hosting.md)). Site content lives in the [www](https://github.com/mastrocola-dev/www) repository and is deployed by its own pipeline.

## Pipelines

One workflow per root module, same shape, separate state keys and concurrency groups:

| Workflow | Watches | State key |
|---|---|---|
| [`infra.yml`](.github/workflows/infra.yml) | `foundation/**` | `foundation.tfstate` |
| [`site.yml`](.github/workflows/site.yml) | `site/**` | `site.tfstate` |
| [`agent.yml`](.github/workflows/agent.yml) | `agent/**` | `agent.tfstate` |

[`secret-expiry.yml`](.github/workflows/secret-expiry.yml) runs weekly and on demand: it reads secret metadata (never values) and fails when any secret has no expiry or expires within 30 days — the failure notification is the rotation reminder. GitHub disables scheduled workflows after 60 days without repository activity and emails a warning first; re-enable it from the Actions tab.

[`terraform-check.yml`](.github/workflows/terraform-check.yml) runs `fmt -check` from the root and `validate` in every root module — `bootstrap` included — on any `.tf` change. It needs no state and no credentials (`init -backend=false`, `contents: read`), so it is the only gate that covers `bootstrap`.

| Trigger | Behavior |
|---|---|
| Pull request to `main` | `terraform-check`, `plan` |
| Push to `main` | plan + `apply` |
| Manual dispatch | plan, with optional apply (`apply: true`) |

## Authentication

The pipelines authenticate to Azure via OIDC federation as their repository's own managed identity — see [Identities and secrets](#identities-and-secrets). Storage access uses Entra ID tokens exclusively (`storage_use_azuread`); shared account keys are disabled everywhere.

The `site` module additionally authenticates to Cloudflare with an API token scoped to DNS edit on the `mastrocola.dev` zone only. The pipeline reads it from Key Vault at run time; GitHub stores no secrets.

Required repository configuration:

| Type | Name | Purpose |
|---|---|---|
| Variable | `AZURE_CLIENT_ID` | Client ID of `id-infra` (bootstrap output `ci_client_ids`) |
| Variable | `AZURE_TENANT_ID` | Entra tenant ID |
| Variable | `AZURE_SUBSCRIPTION_ID` | Target subscription |
| Variable | `KEY_VAULT_NAME` | Vault holding `cloudflare-api-token` |
| Variable | `TFSTATE_RESOURCE_GROUP` | State backend resource group |
| Variable | `TFSTATE_STORAGE_ACCOUNT` | State backend storage account |
| Variable | `CLOUDFLARE_ZONE_ID` | Zone holding the site records |
| Variable | `MCP_DOCS_CLIENT_ID` | App registration that names the `mcp-docs` token audience (bootstrap output) |

## Site specifics
 
- Static Web Apps is not available in `brazilsouth`; the resource lives in `eastus2`. This is metadata placement only — content is served from the global edge.
- Cloudflare records for the site are DNS-only (proxy off): Static Web Apps brings its own edge, and proxying interferes with domain validation.
- The apex validates by TXT token (one-shot, removed after validation); the www subdomain validates by CNAME delegation, which requires the record to exist first — hence the explicit `depends_on`. Patterns and failure modes: [static-web-apps runbook](https://github.com/mastrocola-dev/docs/blob/main/runbooks/static-web-apps.md).
- `repository_url`/`repository_branch` on the app and `validation_type` on the www domain are excluded from reconciliation: the first pair is written by the `www` content pipeline on every deploy, the last is not returned by the Azure API and would force replacement of imported domains.
- The CI identity holds a custom subscription-scope role (`Web Async Operation Reader`, defined in bootstrap) because Static Web Apps mutations report async status at subscription scope, outside the resource-group Contributor boundary.
- The `www` pipeline fetches the deployment token at deploy time (`az staticwebapp secrets list`) as `id-www`; no copy is stored. Resetting it (`az staticwebapp secrets reset-api-key`) needs no change anywhere else.

## Agent specifics

- Three function apps on Flex Consumption (`api`, `worker`, `mcp-docs`), Node 24, 512 MB, at most two instances each: the ceiling on cost and on concurrent runs. A Flex Consumption plan hosts a single app, hence one plan per app.
- One storage account per app. The Functions host needs account-wide blob access, so a shared account would let each app read the others' code packages and host keys. Shared keys are disabled; host and deployment storage authenticate as the app's identity (`AzureWebJobsStorage__*` settings and `storage_authentication_type`).
- Each app runs as its user-assigned identity from bootstrap, read here as a data source. No app has a system-assigned identity and no setting holds a credential: `worker` reads the Anthropic key from Key Vault at run time, from the address in `ANTHROPIC_API_KEY_URI`.
- Service Bus Basic with SAS authentication disabled. `jobs` dead-letters after two deliveries and drops messages older than ten minutes — a question nobody is waiting for is not worth answering. `events` keeps the default delivery count and one hour, so cost reports survive a short outage of `api`.
- `mcp-docs` requires an Entra token (built-in authentication, no client secret): audience is its app registration, and the only accepted caller is the `worker` identity. It has no IP restriction because `worker` calls it from addresses that are not fixed.
- App names carry a random suffix, so `worker` is given the `mcp-docs` address by construction (`func-mcp-docs-<suffix>.azurewebsites.net`) rather than by reference, which would be a cycle inside one resource.
- One Application Insights component over a Log Analytics workspace capped at 1 GB a day.
- The data-plane roles of the three identities (queues, storage) are assigned by bootstrap, which reads this module's outputs to build their scopes. On a new environment the apps exist but cannot start until that second bootstrap apply.

## Identities and secrets

Every pipeline authenticates as its repository's own user-assigned managed identity, federated with GitHub's immutable subject format (`repo:owner@id/repo@id:...`) ([ADR-006](https://github.com/mastrocola-dev/docs/blob/main/adr/006-identity-and-secrets.md)). Identities, federated credentials, the Key Vault and every role assignment live in bootstrap, inside `rg-identity` — a resource group the CI identity has no role on. Contributor over an identity could federate it to any subject; Contributor over the vault could change its permission model.

| Identity | Federated subjects | Grants |
|---|---|---|
| `id-infra` | `main`, `pull_request` | Contributor on `rg-portfolio-dev`, state blob, `Web Async Operation Reader`, `cloudflare-api-token`, vault metadata, `Managed Identity Operator` on each runtime identity |
| `id-www` | `main`, `pull_request` | `Static Web App Secrets Reader` (custom: list deployment tokens) on `rg-portfolio-dev` |
| `id-docs` | `main`, `pull_request` | `anthropic-api-key-ci`; deploys `mcp-docs` (`Website Contributor` on that app, `Reader` on its plan) |
| `id-service-agent` | `main` | deploys `worker` (`Website Contributor` on that app, `Reader` on its plan) |

The agent runtime ([ADR-007](https://github.com/mastrocola-dev/docs/blob/main/adr/007-agent-runtime.md)) adds one identity per function app. They are not federated: the platform attaches them to the apps. `id-infra` holds `Managed Identity Operator` on each one, which lets the `agent` module read and attach it but not federate it or change its grants. Whoever controls that pipeline can therefore act as a runtime identity by attaching it to a resource of its own — the price of letting CI deploy the apps.

| Identity | Attached to | Grants |
|---|---|---|
| `id-run-api` | `api` function app | `turnstile-secret-key`; blob owner and table contributor on its storage account; send on `jobs`, receive on `events` |
| `id-run-worker` | `worker` function app | `anthropic-api-key-runtime`; blob owner on its storage account; receive on `jobs`, send on `events` |
| `id-run-mcp-docs` | `mcp-docs` function app | blob owner on its storage account |

Their grants on queues and storage are scoped to resources the `agent` module creates. Bootstrap reads that module's outputs from its state (`terraform_remote_state`, same backend) and builds each scope from them, so the names never appear here and a recreated module is followed by a bootstrap apply, not an edit. The order on a new environment is therefore bootstrap, `agent`, bootstrap again. Granting at resource-group scope instead would let the worker send and receive on every queue.

Deploy rights are per app, never on the resource group. `Website Contributor` is the smallest built-in role that can publish code; it can also change the app's settings, which adds nothing to what a deployer already has, since deployed code runs as the app's identity. `Reader` on the plan only spares the Azure CLI a minute of retries. `mcp-docs` is deployed from `docs`, whose content it serves, so the `mcp-docs` repository has no identity at all.

`mcp-docs` is also represented by an Entra app registration with no credentials (`azuread` provider). It only names the audience of the token `worker` presents; the application ID URI is `api://<client id>`. The operator needs permission to register applications in the tenant.

Secrets are declared with a write-only placeholder (`value_wo`, never stored in state) so each role can be scoped to a single secret. Real values are written out of band, always with an expiry:

```bash
read -rs VALUE && az keyvault secret set --vault-name kv-mastrocola-dev --name <secret> --value "$VALUE" \
  --expires "$(date -u -d '+180 days' +%Y-%m-%dT%H:%M:%SZ)" --query attributes.expires -o tsv
```

The Cloudflare origin certificate of `api.mastrocola.dev` follows the same idea. Bootstrap declares `origin-api` as a self-signed certificate generated inside the vault, only so that a role can be scoped to it; the real certificate is imported over it out of band and its private key never reaches Terraform (`certificate_policy` is excluded from reconciliation, since the import rewrites it). The App Service resource provider holds `Key Vault Certificate User` on that certificate and on the secret that backs it, nothing else in the vault. The operator holds `Key Vault Certificates Officer` to run the import.

`expiration_date` and `tags` are excluded from reconciliation: rotation writes the first, and `az keyvault secret set` adds a `file-encoding` tag on every write. The operator holds `Key Vault Secrets Officer` on the vault; a 90-second `time_sleep` lets that assignment propagate before the placeholders are written. Azure rejects concurrent federated credential writes on one identity (409 Conflict); when adding several at once, apply with `-parallelism=1`.

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
 
Requires Terraform `>= 1.11` (write-only arguments). Outputs feed the `TFSTATE_*`, `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `KEY_VAULT_NAME`, `MCP_DOCS_AUDIENCE` and `MCP_DOCS_CLIENT_ID` repository variables. Resources that predated this code were adopted into state via one-shot `import` blocks, removed once consumed.
 
Bootstrap is validated by `terraform-check` but never planned or applied by CI — read its plans with extra care.

## Conventions

- No comments in code — rationale lives in this README, mechanics in the resource names
- `.terraform.lock.hcl` is committed in every root module — CI and local runs use identical provider versions
- Terraform `1.16.4`, pinned in every workflow
- `outputs.tf` is a separate file in every root module
- Resource names retain the original `portfolio` prefix — renaming forces destroy/recreate; accepted as debt until a new environment supersedes them. Tags carry the current `mastrocola-dev` identity
- Architecture rationale lives in [docs](https://github.com/mastrocola-dev/docs); this README covers operation only
