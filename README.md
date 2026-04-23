# r3x

Ruby-native workflow executor and automation engine. File-based workflow definitions with database runtime state. Built for local-first execution, self-hosting, and Git-native version control.

Rails API backend with SQLite, Active Record, and Active Job. Supports staged DAG execution, pack-based extensibility, and multiple executor backends.
Also includes a small server-rendered workflow dashboard at `/` and Mission Control Jobs at `/ops/jobs`.

## Development Setup

After cloning the repository, run:

```bash
just setup
```

This installs dependencies, prepares the database, configures the pre-commit hooks, and writes a local absolute Bundler path for the checkout (`$PWD/.bundle`). Keep that setting per-clone and local; do not use a shared relative `BUNDLE_PATH`, because Ruby LSP boots through its own `.ruby-lsp/Gemfile` and needs to resolve the same bundle as the app.

This ensures that `bin/ci` runs automatically before each commit to catch issues early.

## Quick Start

```bash
mise install
just setup
bin/rails server
```

Then open http://localhost:3000/ to view the workflow dashboard.

## Secrets

- This repo is `ENV`-only for secrets and runtime configuration.
- Do not use Rails encrypted credentials for app secrets in this project.
- In production, provide `SECRET_KEY_BASE` explicitly in the environment. Generate one with `bin/rails secret`.
- Integration secrets should also be provided via environment variables such as `GOOGLE_CLIENT_ID_*`, `GOOGLE_CLIENT_SECRET_*`, `GOOGLE_REFRESH_TOKEN_*`, `DISCORD_WEBHOOK_URL_*`, and similar `*_env` references used by the app.
- See [docs/google_oauth.md](docs/google_oauth.md) for how to obtain and refresh Google OAuth2 tokens used by Gmail, Sheets, Calendar, and Translate integrations.

- `/` shows registered workflows, trigger state, and recent visible runs.
- `/workflow-runs` shows recent runs from the current `Solid Queue` retention window.
- `/ops/jobs` opens Mission Control Jobs for queue inspection and operational actions.
- If `R3X_LOGS_PROVIDER=victorialogs` and `R3X_VICTORIA_LOGS_URL` are configured, run detail pages can show indexed logs correlated by Active Job identifiers.

## Test

```bash
bin/rails test
```

## Operational Notes

- See [Deployment](docs/deployment.md) for Kubernetes process layouts, Vault
  setup and Kubernetes auth guidance.
- If `R3X_VAULT_SECRETS_PATH` is set, Vault bootstrap is treated as intentional:
  missing `R3X_VAULT_ADDR` skips Vault, but invalid or incomplete Vault auth
  configuration fails fast during boot.
- Workflow classes are enqueued directly as Active Job classes so workflows can use `ActiveJob::Continuable` and `step` on the real workflow job instance.
- `bin/jobs` remains the generic Solid Queue entrypoint for the default `config/queue.yml` behavior. For split-process deployments, use `bin/jobs-worker` and `bin/jobs-scheduler`; they encode the role in the command, default the matching queue config, and keep worker-only recurring suppression out of the generic path.
- Production `Solid Queue` shutdown is intentionally longer-lived and can be tuned with `R3X_SOLID_QUEUE_SHUTDOWN_TIMEOUT_SECONDS` so Kubernetes rollouts can wait for long workflow runs to finish gracefully.
- Tradeoff: queued workflow runs persist the concrete workflow class name in Solid Queue.
- If a workflow class is renamed or removed before an older queued run executes, that older run may fail deserialization.
- After workflow class renames/removals, clean up pending jobs or recurring tasks that still reference the old class if you need a clean queue.
- The dashboard's recent run view is read-only and derived from current `solid_queue_jobs` state.
- Finished runs are only visible as long as `config.solid_queue.clear_finished_jobs_after` keeps them in the database. In this repo, development, test, and production are currently configured for `2.weeks`.
