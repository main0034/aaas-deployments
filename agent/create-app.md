# Runbook — write the application

Produces one PR against an application repository. Assumes the repository
already exists.

**Not yet exercised by a real run.** Written alongside the harness so the pair
is reviewable together; the first run to use it is Phase 4c, and anything here
that turns out to be wrong should be corrected from that run rather than
defended.

**Not yet runnable either.** The harness image has no .NET SDK and its command
policy allows only `git`, `gh`, `jq` and the schema validator, so every
`dotnet` command below would be refused. Adding both is the first step of
Phase 4c. Until then this runbook describes the target, not something the
agent can do.

## 0. What has already been done for you

The application repository is created before you start, and not by you. Creating
it requires three things a scoped token cannot do:

- creating the repo from the `aaas-app-template` template
- installing the `aaas-bot` GitHub App on it
- setting `AAAS_APP_ID` and `AAAS_APP_PRIVATE_KEY` as repository secrets

Without all three, `release.yml` fails about forty seconds into the first merge
with a stack trace from inside a third-party action that names neither the
repository nor the mistake. That failure mode is `FINDINGS.md` #3, and the fix
is not to give you the permissions — it is that provisioning belongs to a
verified setup step, which is exactly the surface a real product would have to
automate.

So: if the repository does not exist, or `.aaas/deployment` is missing, **stop
and say so**. Do not create it.

## 1. Read the conventions first

```bash
cat AGENT.md
```

`AGENT.md` is the contract, not a style guide. Two rules in it will cost you a
deployment if you ignore them:

- **`GET /health` must return 200 without touching the database.** The
  container's liveness probe hits it. If health depends on Postgres, a database
  problem presents as a failed deployment and a rolled-back revision, and you
  will debug the wrong layer for a long time. Database checks go on `/ready`.
- **There is no database password.** The container's managed identity fetches a
  short-lived token at connect time; `src/App/Data/Database.cs` already does this. Do not
  introduce a connection string, a Key Vault secret, or a Container App secret. It
  fails at Terraform plan time, not at runtime, and the error will not mention
  the application at all.

A third rule is new with the .NET template and is where data gets lost if it is
ignored:

- **The schema changes only through EF Core migrations**, generated with
  `dotnet ef migrations add` and never edited once merged. The platform applies
  them in an init container before each new version starts. See section 3.

Never edit the files `AGENT.md` lists as off-limits: `Dockerfile`,
`.github/workflows/`, `scripts/check-migrations.sh`, `Directory.Build.props`,
`global.json`, `.editorconfig`, `.aaas/deployment`, `AGENT.md`. If one of them
genuinely needs to change, say so and stop.

## 2. Understand the request before writing code

Ask about anything that changes the data model, because a schema is expensive to
change later and the requester will not think to volunteer it:

- What are the things being tracked, and what does each one need to record?
- Who needs to see what — is everything visible to everyone?
- What happens to old records: kept forever, or archived?

Ask in plain language. Do not ask about frameworks, table design, or hosting.

## 3. Write it

```bash
git checkout -b feat/<short-description>
```

Follow the structure in `AGENT.md`. Beyond a handful of routes, move them into
`src/App/Endpoints/` rather than growing `Program.cs`. Replace the template's
`items` resource with what was asked for rather than building beside it.

**Schema changes go through migrations, never ad-hoc DDL.** The data model will
change repeatedly and the requester's data has to survive it:

```bash
dotnet restore && dotnet tool restore
# change the entity classes and AppDbContext, then:
dotnet ef migrations add <PascalCaseDescription> --project src/App
```

Read the generated `Up()` before going further - it is what will run against
live data. Three rules, all enforced by CI:

- every model change has a migration
- a migration that is already on `master` is never edited, renamed or deleted
- migrations only add: no dropping or renaming a table or column. Rollback
  redeploys the previous image against the current schema, so the previous
  code must still work. New columns are nullable or have a default

If the request genuinely needs something removed or renamed, **stop and say
so**. That is a two-release change and a human decides when the second half
happens.

Pin every dependency. Versions live only in `Directory.Packages.props`; after
adding a package, run `dotnet restore` and commit the updated
`packages.lock.json` files, or CI's locked restore fails.

## 4. Prove it before anyone looks at it

```bash
dotnet format
dotnet build -c Release
dotnet test -c Release --no-build
dotnet ef migrations has-pending-model-changes --project src/App --no-build --configuration Release
```

All must pass, with zero warnings - warnings are errors. (`dotnet ef` spells the
configuration `--configuration`; its `-c` means `--context`.) CI runs the same
commands, then checks the migration history, builds the image, smoke-tests
`/health` with no database, and applies your migrations twice to a real Postgres
before exercising the app against it. A failure here is a failure there.

Every new route gets a test, and tests must pass with **no database available**.
If a test needs Postgres, the design is probably wrong — the logic under test
should be separable from the connection.

**Do not open a PR with failing tests.** The evidence that generated code is
correct is that the tests pass; a PR without that evidence is asking a human to
do the part you were supposed to do.

## 5. Open the PR

```bash
git add -A
git commit -m "feat: <what this adds>"
git push -u origin feat/<short-description>
gh pr create --title "feat: <what this adds>" --body-file /tmp/pr-body.md
```

Write the body for the person who asked, not for a reviewer of code:

- what the application now does, in their words
- what you assumed, and what you had to ask about
- anything you deliberately left out, and why
- that merging it builds the image and opens a second PR that does the actual
  deploying

Then stop. Report the PR URL. **Do not merge.**

## 6. If CI fails

Read the actual failure in the Actions log — not the summary line.

Most likely, in order:

1. `format` — run `dotnet format` and commit the result
2. `build` — a compiler warning; warnings are errors
3. A test that assumed a database
4. `model has a migration` — the model changed without `dotnet ef migrations add`
5. `migrations are immutable and expand-only` — you edited a merged migration or
   dropped/renamed something. Do not work around this; see section 3
6. `Migrations apply to a real Postgres` — the migration's SQL is wrong. The log
   line starting `[migrate] FAILED:` names the cause
7. The container smoke test: the app did not answer `/health` within 30 seconds,
   which almost always means something at startup needs the database

Fix the cause and push to the same branch. Two rounds is reasonable. After that,
stop and explain what you tried and why you think it did not work — a clear
description of a blocker is worth more than a third guess.

## 7. What happens after merge

Merging to `master` builds an image tagged with the commit SHA, pushes it to
GHCR, and opens a PR against `aaas-deployments` bumping `container_image`. That
second PR is what deploys: the new revision's `migrate` init container applies
your migrations, and the app starts only if they succeed.

You do nothing to trigger it, and you must never edit the deployments repo by
hand to work around it. If the image bump does not appear, the problem is
`release.yml` or the App credentials — say so; do not route around it.
