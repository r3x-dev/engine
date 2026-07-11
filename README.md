# r3x

Ruby-native workflow engine for people who want automations to live as plain code. 🚀

`r3x` lets you write workflow packs as ordinary Ruby files, run them locally, schedule them with
Solid Queue, inspect them in a small dashboard, and keep the whole automation system versioned in
Git.

It is a good fit when you want:

- 🧩 file-based workflows instead of click-built automations
- 🐙 Git-friendly review, history, and rollback
- 🧠 LLM, Gmail, Google Sheets, Discord, HTTP, OCR, and other integration clients from Ruby
- 🔁 resumable `ActiveJob::Continuable` steps for long-running work
- 🧱 database-backed runtime state through Rails, Active Record, Solid Queue, and Solid Cache
- 🤖 agent-friendly docs so Codex-style agents can help write and maintain workflows

## Project Principles

`r3x` sits near tools like n8n, Huginn, and Argo Workflows, but takes a deliberately Ruby/Rails,
code-first route.

- 🧑‍💻 **Code-first, not UI-trapped** - workflow behavior lives in Ruby files that can be reviewed,
  tested, refactored, and replayed locally.
- 🏠 **Local-first feedback loop** - run workflows with `bin/workflow`, use `--dry-run` for safe
  delivery checks, and add Minitest coverage beside the workflow pack.
- 🌿 **Git from day one** - workflow packs are just files and directories, so changes get normal
  branches, pull requests, diffs, history, and rollback.
- 🤖 **Agent-first maintenance** - `AGENTS.md` and `docs/workflows.md` give coding agents the same
  project rules humans use, which makes generated workflows easier to review and keep consistent.
- 🚂 **Rails-native runtime** - Active Job, Solid Queue, Active Record, Rails cache, Minitest, and a
  small server-rendered dashboard do the heavy lifting instead of a separate orchestration stack.
- 🪶 **Small, repeatable pieces** - workflow packs stay easy to copy, test, disable, schedule, and
  operate without building a large framework around each automation.
- 📈 **Scale when needed** - run everything together for small deployments, or split web, worker,
  and scheduler processes when queues or scheduling need separate resources.
- 🔐 **Production-like local secrets** - optional Vault bootstrap lets local runs hydrate the same
  secret names and values used by production, while dry-run keeps side effects controlled.

## What It Is

`r3x` is a Rails API app that acts as a workflow executor and automation runtime.

Framework code lives in the app and `lib/r3x/`. Your automations live under `workflows/` as
workflow packs. Each pack is just a directory with a `workflow.rb` entrypoint, so you can clone this
project, point `R3X_WORKFLOW_PATHS` at your workflow catalog, and build your own automations in Ruby.

Workflows subclass `R3x::Workflow::Base`, declare triggers, and implement `#run`:

```ruby
module Workflows
  class DailyDigest < R3x::Workflow::Base
    trigger :schedule, cron: "0 8 * * *", timezone: "Europe/Lisbon"

    def run
      rows = ctx.client.google_sheets(
        spreadsheet_id: "spreadsheet-id",
        project: "EXAMPLE_PROJECT"
      ).read_rows(range: "Approved!A:Z")

      step :deliver do
        ctx.client.discord(webhook_url_env: "DISCORD_WEBHOOK_URL_EXAMPLE")
          .deliver(content: "Found #{rows.size} rows")
      end
    end
  end
end
```

For a fuller example with `step`, `with_cache`, `ctx.durable_set`, structured LLM output, and
multiple clients, read
[docs/workflows/example_multi_step_digest.md](docs/workflows/example_multi_step_digest.md). ✨

## Quick Start

```bash
git clone <your-r3x-repo-url>
cd r3x
mise install
just setup
bin/rails server
```

Open http://localhost:3000/ for the workflow dashboard.

The default development server loads `workflows/` and runs Solid Queue. For a production split
deployment, use `bin/web` for the workflow-agnostic web process and run `bin/jobs-worker` plus
`bin/jobs-scheduler` with `R3X_WORKFLOW_PATHS` in separate processes.

Useful local commands:

```bash
export R3X_WORKFLOW_PATHS="$PWD/workflows"
bin/workflow list
bin/workflow info <workflow_key>
bin/workflow run workflows/<workflow_name>/workflow.rb
bin/workflow run --dry-run workflows/<workflow_name>/workflow.rb
bin/workflow run --skip-cache workflows/<workflow_name>/workflow.rb
```

For an included workflow in this checkout:

```bash
bin/workflow info porto_santo_news
bin/workflow run --dry-run workflows/porto_santo_news/workflow.rb
```

`bin/workflow run --dry-run` enables the global dry-run policy for side-effecting clients. In
`development` and `test`, `bin/workflow run` defaults to dry-run, so side-effecting clients skip real
delivery unless you opt out with `--no-dry-run` or `R3X_DRY_RUN=false`. Use `--skip-cache` when you
want a fresh local run without changing workflow code.

## Build Your Workflow Catalog

A workflow catalog can be as small as one directory:

```text
workflows/
  daily_digest/
    workflow.rb
  invoices/
    workflow.rb
  monitoring/
    workflow.rb
```

The loader discovers `workflow.rb` files from directories listed in `R3X_WORKFLOW_PATHS`.

For local development, point it at this repo's `workflows/` directory:

```bash
export R3X_WORKFLOW_PATHS="$PWD/workflows"
```

You can also keep workflow packs in a separate private repo and point `R3X_WORKFLOW_PATHS` there.
That makes it easy to use `r3x` as the engine while keeping your own automation catalog separate.

Recommended workflow loop:

1. Create `workflows/<name>/workflow.rb`.
2. Read [docs/workflows.md](docs/workflows.md) for the workflow writing rules.
3. Run it locally with `bin/workflow run --dry-run workflows/<name>/workflow.rb`.
4. Add a pack-local test under `workflows/<name>/test/` when the behavior matters.
5. Schedule it with `trigger :schedule` or run it manually from the dashboard.

## Agent-Friendly By Design

This repo includes [AGENTS.md](AGENTS.md), which is the project contract for coding agents.

Agents use it to understand:

- where framework code ends and user workflow packs begin
- how workflows are loaded, scheduled, and run
- which clients and libraries to prefer for integrations
- how to write safe dry-run behavior for outputs
- how `ActiveJob::Continuable`, `step`, `with_cache`, and durable sets should be used

The workflow-specific knowledge lives in [docs/workflows.md](docs/workflows.md), and `AGENTS.md`
points agents there before they edit workflow code. In practice, that means you can ask an agent to
create or modify a workflow and it has a shared source of truth instead of guessing the local style.

## Dashboard

The default web surface is server-rendered and intentionally small:

- `/` shows the workflow overview and recent runtime state
- `/workflows` shows workflow health reconstructed from persisted queue data
- `/workflow-runs` shows recent runs inside the Solid Queue retention window
- `/ops/jobs` opens Mission Control Jobs for queue inspection and operational actions

If `R3X_LOGS_PROVIDER=victorialogs` and `R3X_VICTORIA_LOGS_URL` are configured, run pages can show
indexed logs correlated by Active Job IDs. Set `R3X_LOG_FORMAT=json` when you want structured logs
for the dashboard log view.

## Integrations

Workflow code uses `ctx.client.*` helpers for integration boundaries. Existing clients include:

- HTTP downloads and uploads
- Gmail delivery
- Google Sheets reads
- Google Translate
- Discord webhooks
- Apify actor runs
- OCR
- LLM messages, classifiers, and image analysis
- Prometheus queries
- VictoriaLogs dashboard reads
- Healthchecks.io pings

New integration code should usually live under `app/lib/r3x/client/`, lazy-load heavy gems, expose a
small workflow-facing API, and keep real side effects behind explicit dry-run-aware boundaries.

## Runtime Model

Workflows are real Active Job classes. That is the key design choice.

- workflow classes inherit from `R3x::Workflow::Base`
- `R3x::Workflow::Base` is an `ApplicationJob`
- workflow jobs can use `ActiveJob::Continuable` and `step`
- Solid Queue is the Active Job backend
- workflow runtime state is database-backed
- recurring triggers are persisted as Solid Queue recurring tasks

In the current app configuration, Solid Queue and Solid Cache use the primary Active Record
connection in development and production. That means queue inserts can participate in the same
database transaction as app writes. If Solid Queue or Solid Cache is moved to a separate database,
revisit any code that relies on that transactional behavior.

## Secrets

Secrets are environment-only in this repo.

- Do not use Rails encrypted credentials or `RAILS_MASTER_KEY`.
- Provide `SECRET_KEY_BASE` in production.
- Pass integration secrets by environment variable references such as `api_key_env:` or `project:`.
- For Google OAuth setup, see [docs/google_oauth.md](docs/google_oauth.md).
- Optional Vault bootstrap is documented in
  [docs/deployment.md#vault-secrets](docs/deployment.md#vault-secrets).

## Deployment

For production, prefer split processes:

- web process: dashboard and HTTP surface
- worker process: `bin/jobs-worker`
- scheduler process: `bin/jobs-scheduler`

The generic `bin/jobs` entrypoint keeps the default Solid Queue behavior. The split worker and
scheduler commands set the internal `jobs` runtime profile before boot, trimming web-only load from
headless job pods while keeping the operator-facing commands stable.

Read [docs/deployment.md](docs/deployment.md) for Kubernetes process layouts, Vault configuration,
database env vars, and shutdown behavior.

## Development

After cloning, run:

```bash
just setup
```

That installs dependencies, prepares the database, configures pre-commit hooks, and writes a local
absolute Bundler path for the checkout. Keep that Bundler setting local to each clone so Ruby LSP and
the app resolve the same bundle cleanly.

Run tests with:

```bash
bin/rails test
```

SQLite is the default test adapter. To run the same suite against an ephemeral local PostgreSQL container:

```bash
just test-postgres
```

Run the project lint/reference checks with:

```bash
mise exec -- bin/lint-r3x
```

This repo uses `.githooks/`; the pre-commit hook runs `bin/ci`, including the `AGENTS.md` reference
checks.

## Documentation

- [docs/workflows.md](docs/workflows.md) - workflow writing guide
- [docs/workflows/example_multi_step_digest.md](docs/workflows/example_multi_step_digest.md) - full example workflow
- [docs/google_oauth.md](docs/google_oauth.md) - Google OAuth setup
- [docs/deployment.md](docs/deployment.md) - deployment and operations
- [AGENTS.md](AGENTS.md) - instructions used by coding agents
