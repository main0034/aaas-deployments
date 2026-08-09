# Runbook — create a deployment

Produces one PR against `aaas-deployments`. Assumes the app repo already exists.

## 1. Gather what you cannot infer

Required, never guessed:

- **owner** — a person's name or handle
- **costCenter** — for the POC, `poc` is acceptable if the requester confirms it

Useful for sizing, ask in plain language:

- What is this for, and roughly how many people will use it?
- Does it need to respond instantly, or is a few seconds' delay on the first request after an idle period acceptable?

That second question is the whole `min_replicas` decision. Do not ask it in those words.

## 2. Read the contract

```bash
cat schemas/app-stack.schema.json
```

Also read `modules/app-stack/README.md` in the modules repo if you have it locally. The schema is authoritative — where they disagree, follow the schema and report the discrepancy.

Never write a key that is not in the schema. `additionalProperties` is `false`, so CI will reject it, but you should not get that far.

## 3. Choose the infrastructure shape

| Situation | cpu / memory | min_replicas | postgres_sku |
|---|---|---|---|
| Demo, internal tool, low traffic | `0.25` / `0.5Gi` | `0` | `B_Standard_B1ms` |
| Small API people rely on during the day | `0.5` / `1Gi` | `1` | `B_Standard_B2s` |

Anything heavier than the second row is outside the POC. Say so rather than picking the largest allowed value.

`memory` must be exactly `cpu × 2` in Gi. Both the schema and the module enforce this; getting it wrong is the most common mistake.

## 4. Scaffold the directory

```bash
git checkout -b deploy/<name>
mkdir -p deployments/dev/<name>
cp deployments/dev/demo/main.tf deployments/dev/demo/variables.tf deployments/dev/<name>/
```

Then write `backend.hcl`:

```hcl
key = "dev/<name>.tfstate"
```

And `terraform.tfvars.json`. `container_image` is `ghcr.io/main0034/<app-repo>:bootstrap` for a first deployment — CI replaces it with a real SHA after the first image build.

`name` must equal the directory name, and `environment` must equal the parent directory name. CI checks both.

## 5. Validate — before pushing, every time

```bash
python3 scripts/validate_deployment.py deployments/dev/<name>
```

Fix the tfvars until this passes. Do not edit the schema.

## 6. Open the PR

```bash
git add deployments/dev/<name>
git commit -m "feat(<name>): add dev deployment"
git push -u origin deploy/<name>
gh pr create --title "feat(<name>): add dev deployment" --body "..."
```

The PR body should say, in language a non-technical person can follow:

- what application this is and what it does
- roughly what it will cost per month (`B_Standard_B1ms` + a scale-to-zero container app is on the order of £15–25/month; say "roughly £20/month" and note it is an estimate)
- what you assumed, and what you asked about
- that the first apply takes 10–15 minutes, most of it waiting for the database

Then stop. Report the PR URL. **Do not merge.**

## 7. If the plan fails

Read the plan comment on the PR. The likely causes, in order:

1. `memory` is not exactly `cpu × 2`
2. A name collides with an existing global Azure resource name
3. The module ref in `main.tf` points at a tag that does not exist

Fix and push to the same branch. After two failed attempts, stop and explain.
