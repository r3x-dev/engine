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

Local commands use the explicit Docker runner after [development setup](#development).

## Project Principles

`r3x` sits near tools like n8n, Huginn, and Argo Workflows, but takes a deliberately Ruby/Rails,
code-first route.

- 🧑‍💻 **Code-first, not UI-trapped** - workflow behavior lives in Ruby files that can be reviewed,
  tested, refactored, and replayed locally.
- 🏠 **Local-first feedback loop** - run workflows with `bin/workflow` and use `--dry-run` for safe
  delivery checks before explicitly enabling real side effects.
- 🌿 **Git from day one** - workflow packs are just files and directories, so changes get normal
  branches, pull requests, diffs, history, and rollback.
- 🤖 **Agent-first maintenance** - `AGENTS.md` and the R3x workflow skill give coding agents the same
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
    trigger :schedule, key: :daily, cron: "0 8 * * *", timezone: "Europe/Lisbon"

    def run
      rows = ctx.client.google_sheets(
        spreadsheet_id: "spreadsheet-id",
        project: "EXAMPLE_PROJECT"
      ).read_rows(range: "Approved!A:Z", as_hashes: true)

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
just setup
just up
```

Local development requires Docker with Compose, Git, and `just`. Ruby and the local CI
toolchain run in the development image; host Ruby is optional.

Open http://localhost:3000/ for the workflow dashboard.

The default development server loads `workflows/` and runs Solid Queue. For a production split
deployment, use `bin/web` for the workflow-agnostic web process and run `bin/jobs-worker` plus
`bin/jobs-scheduler` with `R3X_WORKFLOW_PATHS` in separate processes.

Useful local commands:

```bash
./dockerized.sh bin/workflow list
./dockerized.sh bin/workflow info <workflow_key>
./dockerized.sh bin/workflow run workflows/<workflow_name>/workflow.rb
./dockerized.sh bin/workflow run --dry-run workflows/<workflow_name>/workflow.rb
./dockerized.sh bin/workflow run --skip-cache workflows/<workflow_name>/workflow.rb
```

`bin/workflow run --dry-run` and `R3X_DRY_RUN=true` enable the same global dry run: clients that
support it skip side effects, regardless of per-feature or per-call settings. CLI flags override
the global ENV value for that run. Without global dry run, per-feature settings remain selective;
`development` and `test` default to dry-run. The CLI reports the effective policy and configured
exceptions. Use `--skip-cache` for a fresh local run without changing workflow code.

Local execution uses the Active Job callback and retry lifecycle. Retries and continuations of
the running job stay in the CLI process; `--skip-wait` skips their delays. Solid Queue concurrency
controls and durable queue persistence apply only to queued execution.

## Build Your Workflow Catalog

Workflow catalogs are user-owned and independent of the engine. Keep concrete workflow behavior,
integration contracts, retry/recovery instructions, and backlog in each workflow's directory.
Engine documentation covers framework contracts and general principles; its examples use placeholders.

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
Enabled packs must resolve to distinct workflow classes across those directories. Conflicting
entrypoints fail before any pack is evaluated, so one catalog cannot silently overwrite another.

For local development, `.env` defaults `R3X_WORKFLOW_PATHS` to `workflows`. Keep a separate
private catalog checkout under that directory so the same project bind includes it. Catalogs
outside the checkout need an explicit additional bind at the same host path.

Recommended workflow loop:

1. Create `workflows/<name>/workflow.rb`.
2. Read the [R3x workflow skill](.agents/skills/r3x-workflows/SKILL.md) for the workflow writing rules.
3. Run it locally with `./dockerized.sh bin/workflow run --dry-run workflows/<name>/workflow.rb`.
4. Inspect the dry-run output and repeat with `--skip-cache` when you need fresh provider data.
5. Schedule it with `trigger :schedule` or run it manually from the dashboard.

## Agent-Friendly By Design

This repo includes [AGENTS.md](AGENTS.md), which is the project contract for coding agents.

Agents use it to understand:

- where framework code ends and user workflow packs begin
- how workflows are loaded, scheduled, and run
- which clients and libraries to prefer for integrations
- how to write safe dry-run behavior for outputs
- how `ActiveJob::Continuable`, `step`, `with_cache`, and durable sets should be used

Workflow authoring rules live in the [R3x workflow skill](.agents/skills/r3x-workflows/SKILL.md).
`AGENTS.md` directs agents there before they edit workflows; its task-specific references
cover state, delivery, caching, integrations and verification without loading the whole guide.

For structured Rails code inspection, the development bundle includes
[rails-ai-context CLI](https://github.com/crisnahine/rails-ai-context). No MCP server or
additional skill is needed:

```bash
./dockerized.sh bundle exec rails-ai-context tool schema --table solid_queue_jobs --no-boot
./dockerized.sh bundle exec rails-ai-context tool model_details --model Dashboard::Run --no-boot
./dockerized.sh bundle exec rails-ai-context tool search_code --pattern logical_key_sql --match-type trace --no-boot
```

`--no-boot` reads source without starting Rails. The tool's job catalog does not include workflow
packs, and its static route discovery can misread the headless profile's route reset; read
`config/routes.rb` directly when that happens. `.rails-ai-context.yml` disables context-file
generation, SQL queries, and log reads. Existing project instructions and validation remain authoritative.

## Dashboard

The default web surface is server-rendered and intentionally small:

- `/` shows the workflow overview and recent runtime state
- `/workflows` shows workflow health reconstructed from persisted queue data
- `/workflow-runs` shows recent runs inside the Solid Queue retention window
- `/ops/jobs` opens Flightdeck for queue inspection and operational actions

Dashboard Run now queues an admission request for a worker that has loaded the
workflow packs. The worker enqueues the real workflow through Active Job, so its
callbacks and Solid Queue concurrency policy also apply to dashboard runs.
Run now opens a waiting page and follows that request's workflow run automatically,
showing its status and optional live logs. Status updates do not depend on the log
provider. The workflow page keeps request history in technical details and surfaces
admission errors separately; an admitted request is not a successful workflow run.
Requests reserve their workflow's Active Job ID before admission so concurrent
starts, retries and continuations remain associated with the correct run.
Requests are not automatically retried.
Inspect Flightdeck before manually retrying a failed or interrupted request:
a worker crash after admission can leave an unfinished request even though its
workflow was queued, so retrying that request can enqueue another run.

Before deploying this request format, pause dashboard run submissions and finish
pending admission requests with the old workers. Do not mix old and new web/worker
versions during this switch. The new worker requires the reserved workflow job ID;
old pending requests are intentionally incompatible.
Existing workflow jobs and completed request history do not need conversion.

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
Reusable protocol clients such as `Http` and `Mcp` also live there. Provider clients compose them
with service configuration; workflow packs own source-specific tool choices and payload schemas.
`lib/r3x/` contains workflow engine machinery rather than an alternate home for integration helpers.

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

The host needs Bash 4+, `sha256sum`, `just`, and Docker with the Compose plugin. Use a local
Docker daemon that can bind-mount the checkout at its host path. App tools run in containers;
Ruby and Node.js are not required on the host.

After cloning, run:

```bash
just setup
```

Before `just up`, place a workflow catalog under `workflows/` (or configure another mounted path
in `.env`). The default server runs both web and jobs and requires at least one `workflow.rb`;
an empty or missing catalog fails visibly. See [workflow catalogs](#build-your-workflow-catalog)
for catalog ownership. Then run `just up` to start the app at `http://localhost:3000`.

Setup builds the development image, pulls the JavaScript, Dockerfile lint and PostgreSQL images,
installs the locked gems in `.bundle/gems`, prepares dprint plugins in `.dev/cache`, prepares SQLite,
and configures the pre-commit hook. These dependencies belong to this checkout. Re-run setup after
pulling dependency changes or deleting caches. Ordinary tasks never build or pull images, install
gems, or fall back to host tools. Bundler enforces the lockfile and reports missing or inconsistent
gems. dprint owns its plugin cache and may download a missing plugin during formatting or checking;
`./dockerized.sh bin/dprint install` prepares it separately when needed.
The development image, Gemfile and Gemfile.lock define the toolchain.

When editing Gemfile or deliberately updating gems, explicitly allow Bundler to change the lockfile:

```bash
./dockerized.sh env BUNDLE_VERSION=lockfile BUNDLE_FROZEN=false bundle install
./dockerized.sh env BUNDLE_VERSION=lockfile BUNDLE_FROZEN=false bundle update <gem>
```

Ordinary commands use the Bundler shipped in the image. Explicit dependency maintenance uses the
lockfile version, installing that Bundler if needed, so it does not incidentally downgrade the lockfile.
Review both Gemfile and Gemfile.lock before committing. `just setup` installs locked dependencies;
it does not resolve a changed Gemfile. Setup also runs `bin/setup`, which prepares the database and
clears development logs and temporary files.

Use `just up`, `just format`, `just tests [ARG...]`, and `just ci` from anywhere in the checkout;
recipes run at the project root. The runner is an explicit command, with no shell activation or
PATH changes:

```bash
./dockerized.sh bin/rails console
./dockerized.sh bundle exec ruby -e 'puts RUBY_VERSION'
cd app
../dockerized.sh ruby -e 'puts Dir.pwd'
```

Direct commands preserve their arguments and the caller's directory, including subdirectories.
Run Rails and workflow commands from the project root so `.env` and relative workflow paths resolve
consistently; use `just` recipes when working from a subdirectory. A runner invoked from outside its
own checkout refuses to run. Each worktree gets its own Compose project, gems, caches, SQLite, and
generated state. The absolute checkout path is the same inside
and outside the container. Shell exports are not automatically forwarded; use the project `.env`
or `./dockerized.sh env KEY=value COMMAND` for one-off tools. Rails loads `.env` after the container
entrypoint. For web/jobs variables needed before Rails boot, including `RAILS_ENV` and
`SECRET_KEY_BASE`, use `./dockerized.sh compose run --rm --no-deps --env KEY=value app bin/web`;
add `--service-ports` and `-b 0.0.0.0` for access from the host. This keeps the runtime command visible
to the entrypoint so database preparation and production startup checks run. Editor/LSP integration
is deferred.

The runner executes the Compose plugin registered by Docker directly, preserving signal delivery
and the command's exit status. Docker's parent CLI can cancel the plugin connection instead of
forwarding `SIGTERM`; see the [CLI signal handler](https://github.com/docker/cli/blob/v29.9.2/cmd/docker/docker.go#L329-L364)
and [Compose signal forwarding](https://github.com/docker/compose/blob/v5.7.1/pkg/compose/run.go#L46-L52).
A missing Compose plugin is an explicit prerequisite failure.

Rootless Docker maps the app container's root to the daemon user. Rootful Docker uses the host
UID/GID; rootful user namespace remapping is rejected because bind mount IDs differ.
Stop the checkout's containers with `./dockerized.sh compose down` before deleting it. Removing
the checkout frees its gems and caches; Docker images and build layers require separate cleanup.
Ordinary shutdown removes one-off containers; a killed Docker client or host crash can require
targeted cleanup. Production keeps its separate `/rails` image and entrypoints.

Run tests with:

```bash
just tests
just test-javascript
```

The development image includes standalone dprint. JavaScript tests run in a separate Node.js
distroless container, with a read-only checkout and networking disabled. For a single Ruby test, use
`just tests test/path/to_test.rb`; Rails selects the test environment.
Direct Ruby invocations retain the development environment unless explicitly overridden.

SQLite is the default test adapter. To run the same suite against an ephemeral local PostgreSQL container:

```bash
just test-postgres
```

The PostgreSQL test service uses temporary storage and publishes no host port.

Run the project lint/reference checks with:

```bash
./dockerized.sh bin/lint-r3x
just lint-docker
```

Run `just format` explicitly to correct Ruby with RuboCop and format YAML with dprint before staging.
It uses the same project rules and scope as CI and changes only working-tree files; it never stages them.
This repo uses `.githooks/`;
the pre-commit hook runs the full local
`just ci` suite: `bin/ci` runs the Ruby/tooling checks in the development container, followed by
`just test-javascript` in the Node.js container. This is intentional while the suite remains reasonably
fast: developers get the complete feedback loop before a commit exists, with GitHub Actions
providing an independent check.
The default `bin/bundler-audit` invocation refreshes the advisory database before scanning, so
local CI requires network access and fails if that refresh fails. Formatter and audit caches live
in `.dev/cache` for this checkout and are removed with it. The hook checks the working tree, not a
separately staged snapshot.
An explicit offline scan is
available as `./dockerized.sh bin/bundler-audit check --no-update`; it uses the cached database and can miss newer advisories.
See [DHH's local CI reasoning](https://world.hey.com/dhh/we-re-moving-continuous-integration-back-to-developer-machines-3ac6c611).

## Documentation

- [R3x workflow skill](.agents/skills/r3x-workflows/SKILL.md) - workflow authoring rules and task-specific references
- [docs/workflows.md](docs/workflows.md) - workflow overview
- [docs/workflows/example_multi_step_digest.md](docs/workflows/example_multi_step_digest.md) - full example workflow
- [docs/google_oauth.md](docs/google_oauth.md) - Google OAuth setup
- [docs/deployment.md](docs/deployment.md) - deployment and operations
- [AGENTS.md](AGENTS.md) - instructions used by coding agents
