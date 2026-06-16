# Environment

This app is configured through environment variables. Do not document real
secret values here, in workflow docs, or in examples. Use placeholder values
that show shape only.

## Runtime

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `SECRET_KEY_BASE` | Production | Rails | Rails secret key base for production boot. | `SECRET_KEY_BASE=<generated>` |
| `RAILS_ENV` | Optional | Rails, Puma | Rails environment. Defaults depend on the command. | `RAILS_ENV=production` |
| `RAILS_LOG_LEVEL` | Optional | Production config | Rails log level. Defaults to `info` in production. | `RAILS_LOG_LEVEL=debug` |
| `RAILS_MAX_THREADS` | Optional | Puma, database config | Web and database thread sizing. | `RAILS_MAX_THREADS=5` |
| `WEB_CONCURRENCY` | Optional | Puma | Puma worker count. | `WEB_CONCURRENCY=2` |
| `PORT` | Optional | Puma | HTTP port. Defaults to `3000`. | `PORT=3000` |
| `PIDFILE` | Optional | Puma | Puma pidfile path. | `PIDFILE=tmp/pids/server.pid` |
| `CI` | Optional | Test config | Enables eager loading in test. | `CI=true` |
| `BUNDLE_GEMFILE` | Optional | Bundler boot | Gemfile path. Defaults to this repo's `Gemfile`. | `BUNDLE_GEMFILE=/app/Gemfile` |

## Database And Queue

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `R3X_DATABASE_URL` | Production preferred | `config/database.yml` | Primary database URL. Preferred production setting. | `R3X_DATABASE_URL=postgres://<user>:<password>@db.example/r3x` |
| `R3X_DATABASE_PATH` | Optional | `config/database.yml` | SQLite-style production database path fallback. | `R3X_DATABASE_PATH=storage/production.sqlite3` |
| `JOB_THREADS` | Optional | Solid Queue config, database pool sizing | Worker thread count. Defaults to `3` in queue configs. | `JOB_THREADS=3` |
| `JOB_CONCURRENCY` | Optional | Solid Queue config | Worker process count. Defaults to `1`. | `JOB_CONCURRENCY=1` |
| `SOLID_QUEUE_SHUTDOWN_TIMEOUT_SECONDS` | Optional | Production config | Solid Queue graceful shutdown timeout. Defaults to `900`. | `SOLID_QUEUE_SHUTDOWN_TIMEOUT_SECONDS=900` |
| `SOLID_QUEUE_IN_PUMA` | Optional | Puma, workflow entrypoint | Runs Solid Queue inside Puma when true. Prefer split web, worker, and scheduler processes for production. | `SOLID_QUEUE_IN_PUMA=false` |

## Workflow Runtime

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `R3X_WORKFLOW_PATHS` | Required for workflow packs | Pack loader, `bin/workflow` | File path list of workflow pack directories. Uses the platform path separator. | `R3X_WORKFLOW_PATHS=/app/workflows` |
| `R3X_RUNTIME_PROFILE` | Command-owned | `config/runtime_profile.rb`, `bin/jobs-worker`, `bin/jobs-scheduler`, `bin/workflow` | Internal boot profile. Entrypoints set this themselves; deployment charts should not set it directly. | `R3X_RUNTIME_PROFILE=jobs` |
| `R3X_TIMEZONE` | Optional | Schedule triggers, dashboard helper | Default timezone for cron triggers and dashboard timestamp display when no trigger timezone is embedded. | `R3X_TIMEZONE=Atlantic/Madeira` |
| `R3X_SKIP_CACHE` | Optional | Workflow CLI, workflow cache policy | Boolean. Bypasses `with_cache`; also required for production use of `with_cache`. | `R3X_SKIP_CACHE=true` |
| `R3X_DRY_RUN` | Optional | `R3x::Policy` | Boolean global dry-run override. `true` forces dry-run; `false` disables it. In `development` and `test`, dry-run is the default, so set this to `false` for real delivery. | `R3X_DRY_RUN=false` |
| `R3X_<FEATURE>_DRY_RUN` | Optional | `R3x::Policy` | Boolean per-feature dry-run override, for keys such as `GMAIL`, `HTTP`, `DISCORD`, and `MARKDOWNIFY`. | `R3X_DISCORD_DRY_RUN=true` |

## Logging And Dashboard

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `R3X_LOG_FORMAT` | Optional | `R3x::Log` | `json` or `plain`. Structured JSON is required for dashboard log levels and run-log correlation. | `R3X_LOG_FORMAT=json` |
| `R3X_LOGS_PROVIDER` | Optional | Dashboard logs | Enables indexed run-log queries. Current supported value is `victorialogs`. | `R3X_LOGS_PROVIDER=victorialogs` |
| `R3X_VICTORIA_LOGS_URL` | Required when VictoriaLogs client/log provider is used | `R3x::Client::VictoriaLogs`, dashboard logs | VictoriaLogs base URL. Custom names may start with this prefix. | `R3X_VICTORIA_LOGS_URL=http://victoria-logs.example:9428` |
| `R3X_VICTORIA_LOGS_URL_*` | Optional variant | `R3x::Client::VictoriaLogs` | Alternate VictoriaLogs URL env names accepted by explicit `url_env:`. | `R3X_VICTORIA_LOGS_URL_STAGING=http://victoria-logs-staging.example:9428` |
| `MISSION_CONTROL_AUTH_ENABLED` | Optional | Production config | Boolean-ish Mission Control Jobs basic-auth toggle. Defaults to enabled in production. | `MISSION_CONTROL_AUTH_ENABLED=true` |

## Vault Bootstrap

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `R3X_VAULT_ADDR` | Required when Vault is active | Vault client and boot initializer | Vault base URL. | `R3X_VAULT_ADDR=http://vault.example:8200` |
| `R3X_VAULT_SECRETS_PATH` | Required to load env from Vault | Vault boot initializer, diagnose command | KV v2 path loaded into `ENV` at boot. Secret payload keys must not start with `R3X_`. | `R3X_VAULT_SECRETS_PATH=secret/data/env/r3x` |
| `R3X_VAULT_TOKEN` | Required for token auth | Vault client | Vault token for token auth. | `R3X_VAULT_TOKEN=<token>` |
| `R3X_VAULT_AUTH_METHOD` | Optional | Vault config | `token` or `kubernetes`. Blank defaults to token auth. | `R3X_VAULT_AUTH_METHOD=kubernetes` |
| `R3X_VAULT_KUBERNETES_ROLE` | Required for Kubernetes auth | Vault Kubernetes auth | Vault role used for Kubernetes login. | `R3X_VAULT_KUBERNETES_ROLE=r3x` |
| `R3X_VAULT_KUBERNETES_AUTH_PATH` | Optional | Vault Kubernetes auth | Vault Kubernetes auth mount. Defaults to `auth/kubernetes`. | `R3X_VAULT_KUBERNETES_AUTH_PATH=auth/kubernetes` |
| `R3X_VAULT_KUBERNETES_TOKEN_PATH` | Optional | Vault Kubernetes auth | Service account token file path. Defaults to Kubernetes' standard token path. | `R3X_VAULT_KUBERNETES_TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token` |
| `R3X_SKIP_VAULT_ENV_LOAD` | Optional | Vault boot initializer | Boolean diagnostic escape hatch that skips Vault env loading. | `R3X_SKIP_VAULT_ENV_LOAD=true` |

## Integration Clients

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `MINIFLUX_URL` | Required when Miniflux client is used | `R3x::Client::Miniflux`, `ctx.client.miniflux` | Miniflux base URL. Custom names may start with this prefix. | `MINIFLUX_URL=https://miniflux.example` |
| `MINIFLUX_URL_*` | Optional variant | Miniflux explicit `url_env:` | Alternate Miniflux URL env names. | `MINIFLUX_URL_PERSONAL=https://miniflux.example` |
| `MINIFLUX_API_KEY` | Required when Miniflux client is used | `R3x::Client::Miniflux`, `ctx.client.miniflux` | Miniflux API token. Custom names may start with this prefix. | `MINIFLUX_API_KEY=<token>` |
| `MINIFLUX_API_KEY_*` | Optional variant | Miniflux explicit `api_key_env:` | Alternate Miniflux token env names. | `MINIFLUX_API_KEY_PERSONAL=<token>` |
| `PROMETHEUS_URL` | Required when Prometheus client is used | `R3x::Client::Prometheus`, `ctx.client.prometheus` | Prometheus base URL. Custom names may start with this prefix. | `PROMETHEUS_URL=http://prometheus.example:9090` |
| `PROMETHEUS_URL_*` | Optional variant | Prometheus explicit `url_env:` | Alternate Prometheus URL env names. | `PROMETHEUS_URL_HOME=http://prometheus-home.example:9090` |
| `DISCORD_WEBHOOK_URL` | Required when Discord client uses default env | `R3x::Client::Discord`, `ctx.client.discord` | Discord webhook URL. Custom names may start with this prefix. | `DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...` |
| `DISCORD_WEBHOOK_URL_*` | Optional variant | Discord explicit `webhook_url_env:` | Alternate Discord webhook env names for workflow-specific destinations. | `DISCORD_WEBHOOK_URL_NEWS=https://discord.com/api/webhooks/...` |
| `OCRSPACE_API_KEY` | Required when OCR client is used | `R3x::Client::Ocr`, `ctx.client.ocr` | OCR.space API key. Custom names may start with this prefix. | `OCRSPACE_API_KEY=<token>` |
| `OCRSPACE_API_KEY_*` | Optional variant | OCR explicit `api_key_env:` | Alternate OCR.space key env names. | `OCRSPACE_API_KEY_WORKFLOW=<token>` |
| `APIFY_API_KEY` | Required when Apify context client uses default env | `ctx.client.apify` | Apify API token. Custom names may start with this prefix. | `APIFY_API_KEY=<token>` |
| `APIFY_API_KEY_*` | Optional variant | Apify explicit `api_key_env:` | Alternate Apify token env names. | `APIFY_API_KEY_SCRAPERS=<token>` |
| `OPENCODE_GO_API_KEY` | Required when selected as `api_key_env` for `ctx.client.llm` | `ctx.client.llm` | OpenCode Go token. Routed through RubyLLM's OpenAI-compatible adapter with the OpenCode endpoint. | `OPENCODE_GO_API_KEY=<token>` |
| `OPENCODE_GO_API_KEY_*` | Optional variant | `ctx.client.llm(api_key_env: ...)` | Alternate OpenCode Go token env names. | `OPENCODE_GO_API_KEY_PROJECTA=<token>` |
| `<PROVIDER>_API_KEY` / `<PROVIDER>_API_KEY_*` | Required when LLM client is used | `ctx.client.llm` | Dynamic LLM API key env names. Must match the uppercase provider/key pattern, such as Gemini. | `GEMINI_API_KEY=<token>` / `GEMINI_API_KEY_MAIN=<token>` |
| `GOOGLE_CLIENT_ID_*` | Required when Google OAuth clients are used | `R3x::Client::GoogleAuth` | OAuth client ID for the selected project suffix. | `GOOGLE_CLIENT_ID_MAIN=<client-id>` |
| `GOOGLE_CLIENT_SECRET_*` | Required when Google OAuth clients are used | `R3x::Client::GoogleAuth` | OAuth client secret for the selected project suffix. | `GOOGLE_CLIENT_SECRET_MAIN=<client-secret>` |
| `GOOGLE_REFRESH_TOKEN_*` | Required when Google OAuth clients are used | `R3x::Client::GoogleAuth`, `bin/google-oauth` | OAuth refresh token for the selected project suffix. | `GOOGLE_REFRESH_TOKEN_MAIN=<refresh-token>` |
| `HEALTHCHECKS_IO_URL` | Required when Healthchecks.io client uses env endpoint | `R3x::Client::HealthchecksIO`, `ctx.client.healthchecks_io` | Healthchecks ping endpoint base. Pass `ping_endpoint:` to avoid env lookup. | `HEALTHCHECKS_IO_URL=https://hc.example/ping/` |
| `FB_EVENTS_OCR_TOKEN_PXOPULSE` | Required by matching workflow | `workflows/camara_ps_events` | Workflow-specific token for OCR-backed Facebook events access. | `FB_EVENTS_OCR_TOKEN_PXOPULSE=<token>` |

## Scratchpad And Local Scripts

| Name | Required | Used by | Description | Example |
| --- | --- | --- | --- | --- |
| `MARKDOWNIFY_URL` | Optional | `scratchpad/markdownify_test.rb` | URL used by the scratchpad markdownify script. | `MARKDOWNIFY_URL=https://example.com/article` |
| `MARKDOWNIFY_METHOD` | Optional | `scratchpad/markdownify_test.rb` | Markdownify method for the scratchpad script. | `MARKDOWNIFY_METHOD=auto` |
| `MARKDOWNIFY_RETAIN_IMAGES` | Optional | `scratchpad/markdownify_test.rb` | String boolean for retaining images in scratchpad output. | `MARKDOWNIFY_RETAIN_IMAGES=false` |
