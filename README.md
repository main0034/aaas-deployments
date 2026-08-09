# aaas-deployments

The state of the world. One directory per deployed application.

Everything here is **data**, not code. The only file that varies between deployments is `terraform.tfvars.json`; `main.tf`, `variables.tf` and `backend.hcl` are boilerplate generated once and rarely touched.

## Layout

```
deployments/<env>/<name>/
  terraform.tfvars.json   # the only file the agent writes
  backend.hcl             # state key, must be "<env>/<name>.tfstate"
  main.tf                 # module block, pinned to a module tag
  variables.tf            # pass-through declarations
schemas/app-stack.schema.json
scripts/validate_deployment.py
agent/                    # prompts and runbooks
```

## Flow

```
PR touching deployments/**
  → validate (JSON Schema, identity checks)   ← fails in seconds, precise message
  → terraform plan (read-only identity)
  → plan posted as a PR comment
  → human merges
  → terraform apply (write identity, 'dev' environment gate)
  → app URL posted back on the PR
```

Image bumps arrive here automatically as PRs from the app repos, opened by CI after a successful image build.

## Validating locally

```bash
pip install jsonschema
python3 scripts/validate_deployment.py deployments/dev/demo
python3 scripts/validate_deployment.py --all
```

The agent runs exactly this command. Keeping one script means the local check and the CI gate cannot drift apart.

## Required repository configuration

**Variables** (identifiers, not credentials — set by `bootstrap.sh`):
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_CLIENT_ID_PLAN`, `AZURE_CLIENT_ID_APPLY`, `TFSTATE_RG`, `TFSTATE_SA`, `TFSTATE_CONTAINER`

**Secrets:**
`AAAS_APP_ID`, `AAAS_APP_PRIVATE_KEY` (GitHub App, used to fetch the private modules repo), `GHCR_READ_TOKEN` (registry pull credential)

There is no Azure credential stored anywhere. That is the point of OIDC.

## Two identities, on purpose

`plan` runs against unreviewed PR content and uses a **Reader** service principal. `apply` runs only on `main` and uses a **Contributor** one. Retrofitting this split later is awkward, so it exists from the first commit.

## Adding a deployment by hand

Copy `deployments/dev/demo/`, change the name in `terraform.tfvars.json` and the key in `backend.hcl`, validate, open a PR. This is worth doing at least once before involving the agent — if the pipeline is unproven, every agent failure is ambiguous.
