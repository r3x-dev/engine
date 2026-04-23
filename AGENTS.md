# Instructions

This Rails app uses a small set of preferred libraries for common integration work. Follow these defaults for new code and agent-authored changes unless an existing subsystem already requires a different interface.

## Project Overview

- `r3x` is a Rails API app that acts as a Ruby-native workflow executor and automation engine.
- The high-level split is: framework/runtime code lives in the app and `lib/r3x/`, while user-defined workflows live under `workflows/`.
- Workflows are file-based, Git-friendly, and loaded into a database-backed runtime that uses Active Job + Solid Queue for execution and recurring scheduling.
- Workflow classes are enqueued directly as Active Job classes so workflow code can use `ActiveJob::Continuable` and `step` on the real workflow job instance.
- `Solid Queue` is the active job backend for app/runtime execution. Treat queueing semantics as database-backed, not Redis-backed.
- In the current app configuration, `Solid Queue` is not wired through `config.solid_queue.connects_to`, and `Solid Cache` is not pointed at a separate cache database. In development and production, app tables, queue tables, and cache tables all use the primary Active Record database connection.
- Because queue records use the same Active Record database connection as the app in the configured environments here, queue inserts can participate in the same database transaction as app writes.
- If `Solid Queue` or `Solid Cache` is ever moved to a separate database, or replaced with a non-database backend/store, revisit any code that relies on transactional integrity between app writes and job enqueueing. In that setup, `enqueue_after_transaction_commit` and related tests become important again.
- Production database configuration is environment-driven: prefer `R3X_DATABASE_URL`, and fall back to `R3X_DATABASE_PATH` for SQLite-style file paths.
- Secrets are ENV-only in this repo. Do not rely on Rails encrypted credentials or `RAILS_MASTER_KEY`; provide `SECRET_KEY_BASE` and integration secrets through environment variables.
- The optional Vault env bootstrap supports either a direct `R3X_VAULT_TOKEN` or in-cluster `auth/kubernetes` login via `R3X_VAULT_AUTH_METHOD=kubernetes` plus `R3X_VAULT_KUBERNETES_ROLE`. The Vault client code is split between the main client, `HashiCorpVault::Config`, and `HashiCorpVault::Auth::*` helpers so auth-specific env parsing and Kubernetes login logic stay out of the endpoint methods. If `R3X_VAULT_SECRETS_PATH` is set and `R3X_VAULT_ADDR` is also set, invalid or incomplete Vault auth configuration should fail fast during boot rather than silently skipping secrets.
- The default local UI surface is the server-rendered workflow dashboard mounted at `/`, with a debug-first overview hub at the root path and deeper drill-down pages for workflows and runs.
- Mission Control Jobs remains available at `/ops/jobs` for queue inspection and operational actions.
- `bin/jobs-worker` and `bin/jobs-scheduler` set `R3X_RUNTIME_PROFILE=jobs` before boot. That internal profile keeps production eager load enabled for jobs pods, but trims boot to the Active Model / Active Job / Active Record runtime, excludes the dashboard web stack and web-only gems, removes the app `config/routes.rb` / `config/routes/**/*` files from Rails path registration, keeps `ActionController::Base.include_all_helpers = false` for headless boot, ignores `lib/r3x/workflow/cli.rb` so worker/scheduler processes do not eager-load the Thor wrapper, and leaves the operator-facing commands unchanged.
- `bin/workflow` sets `R3X_RUNTIME_PROFILE=workflow_cli` before boot. `workflow_cli` is also headless and skips the web stack, but unlike `jobs` it keeps `lib/r3x/workflow/cli.rb` available so the command can load `R3x::Workflow::Cli`. This profile is command-owned and is not a deployment env knob.
- The dashboard is DB-first: workflow pages and recent runs are derived from current `Solid Queue` tables plus `trigger_states`, so they only show workflows and runs that have persisted runtime artifacts.
- The dashboard can optionally query indexed application logs when `R3X_LOGS_PROVIDER` is configured. The current supported provider is `victorialogs`, which reads from `R3X_VICTORIA_LOGS_URL` via VictoriaLogs native query API.

## Codebase Map

- `lib/r3x/`: core framework code for the workflow DSL, trigger types, workflow loading, registry, execution context, recurring-task config, and shared DSL helpers.
- `app/controllers/r3x/`: web controllers used to support HTML surfaces in the `api_only` app, including the shared `R3x::WebController` base for the dashboard and Mission Control.
- `app/controllers/r3x/dashboard/`: server-rendered dashboard controllers for workflows and recent runs.
- `app/controllers/r3x/dashboard/overview_controller.rb`: root overview screen that surfaces attention items, recent runs, and workflow shortcuts from persisted runtime data.
- `app/views/r3x/dashboard/` + `app/views/layouts/r3x/dashboard.html.erb`: dashboard UI templates and layout.
- `app/lib/r3x/dashboard/`: read-only query objects that build workflow summaries, recent runs, and optional indexed log views from `Solid Queue`, `TriggerState`, and configured log providers, plus the dashboard-side enqueuer used for `Run now`.
- `app/lib/r3x/dashboard/overview.rb`: assembles the root dashboard overview cards and sections from workflow summaries and persisted runs.
- `app/lib/r3x/client/hashi_corp_vault/`: Vault client helpers for config parsing and auth mode implementations (`Config`, `Auth::Token`, `Auth::Kubernetes`).
- `lib/r3x/workflow/executor.rb`: shared workflow execution helper that resolves the trigger and builds `Workflow::Context` for a loaded workflow class.
- `lib/r3x/workflow/cli.rb`: in-process implementation for `bin/workflow` commands so CLI behavior can be tested without shelling out.
- `lib/r3x/workflow/entrypoint.rb`: boot-policy layer used by `config/application.rb` and `bin/jobs*` to decide whether to only load workflows or also schedule recurring tasks.
- `config/runtime_profile.rb`: internal runtime-profile helper used during boot to distinguish the default web profile from the headless `jobs` and `workflow_cli` profiles set by `bin/jobs-worker`, `bin/jobs-scheduler`, and `bin/workflow`.
- `lib/r3x/dsl/`: shared DSL infrastructure, especially validation concerns and configuration errors used by workflow-declared objects.
- `lib/r3x/trigger_manager.rb` + `lib/r3x/trigger_manager/`: trigger infrastructure — `R3x::TriggerManager::Collection` (manages workflow triggers as a hash keyed by `unique_key`) and `R3x::TriggerManager::Execution` (wraps a trigger for runtime use).
- `app/lib/r3x/`: runtime support code such as client wrappers and shared concerns.
- `app/lib/r3x/client/victoria_logs.rb`: thin VictoriaLogs HTTP client used by the dashboard when log viewing is enabled.
- `app/lib/r3x/client/google_auth.rb`: resolves Google OAuth2 scope aliases and builds `Signet::OAuth2::Client` instances from per-project environment variables.
- `lib/r3x/gem_loader.rb`: tiny helper for one-time lazy `require` of heavy optional gems used by integrations and workflow helpers.
- `app/lib/r3x/client/google/gmail.rb`: Gmail API client used by workflows via `ctx.client.gmail(...)`.
- `app/lib/r3x/client/google/translate.rb`: Google Translate client used by workflows via `ctx.client.google_translate(...)`.
- `lib/r3x/workflow/llm_schema.rb`: lazy wrapper around `RubyLLM::Schema` for workflows that need structured LLM output.
- `R3x::Client::Google` is a project namespace; when referencing the third-party Google gem namespace, use `::Google` to avoid constant collisions.
- `app/jobs/r3x/`: job entrypoints, especially `R3x::RunWorkflowJob`, which resolves a workflow key and dispatches to the workflow job class, and `R3x::ChangeDetectionJob`, which evaluates change-detecting triggers before enqueueing workflow runs.
- `app/models/r3x/`: runtime support models such as `R3x::TriggerState` for per-trigger change-detection state.
- `workflows/`: user workflow packs. These are not the framework itself; they are loaded by the framework.
- `workflows/<pack>/test/`: self-contained tests for a specific workflow pack. Keep pack-local tests beside the workflow code, and use `test/fixtures/workflows/` for framework-level fixtures.
- `lib/r3x/workflow/boot.rb`: explicit workflow boot helper used by process entrypoints.
- `lib/r3x/workflow/durable_set.rb`: workflow-scoped durable set backed by `Rails.cache`, intended
  for remembering processed item keys across workflow runs.
- `test/fixtures/workflows/`: fixture workflows for framework tests. Prefer these over hardcoding real workflows in tests.

## Runtime Flow

- Workflows subclass `R3x::Workflow::Base`, declare triggers via the DSL, and implement `#run`.
- Workflow code can define structured LLM schemas via `R3x::Workflow::LlmSchema.define { ... }`, which lazy-loads `ruby_llm-schema` instead of requiring it for all processes at boot.
- `R3x::Workflow::Base` is also an `ApplicationJob`; its `#perform` delegates trigger/context setup to `R3x::Workflow::Executor`, stores the context on the job, and then calls `#run` on the current job instance.
- Workflow code can use `ctx.durable_set(name = :default, ttl: 90.days)` to get a durable,
  workflow-scoped set for best-effort cross-run dedup of processed items.
- When the app uses `:solid_cache_store`, keep `durable_set` `ttl:` at or below
  `config/cache.yml` `store_options.max_age` so cache retention does not silently shorten the
  dedup window.
- Workflow-declared DSL objects must validate themselves before being registered; invalid DSL configuration should raise `R3x::ConfigurationError` with collected validation errors.
- `R3x::Workflow::PackLoader` discovers workflow entrypoints named `workflow.rb` from directories listed in `R3X_WORKFLOW_PATHS`, loads them, and registers their classes in `R3x::Workflow::Registry`.
- `R3x::RecurringTasksConfig` turns schedulable workflow triggers into Solid Queue dynamic recurring tasks via `SolidQueue::RecurringTask`. All triggers have a `unique_key` (based on type + options hash) used for identification and duplicate detection. `schedule_all!` persists dynamic tasks and sweeps stale ones.
- Workflow packs are loaded explicitly by process entrypoints, not globally during Rails boot. `R3x::Workflow::Entrypoint` centralizes those boot decisions for the web server hook and `bin/jobs*`. In the current split-process setup, the generic `bin/jobs` entrypoint keeps the default Solid Queue behavior: it only loads workflow classes when `SOLID_QUEUE_IN_PUMA=true`, and otherwise it also schedules recurring tasks before starting the CLI. `bin/jobs-worker` only loads workflow classes, defaults `config/queue.worker.yml`, defaults `SOLID_QUEUE_SKIP_RECURRING=true`, and boots Rails under the internal `jobs` runtime profile. `bin/jobs-scheduler` defaults `config/queue.scheduler.yml`, schedules recurring tasks, and also boots under the `jobs` runtime profile. `bin/workflow` boots Rails under the internal `workflow_cli` runtime profile. Both `jobs` and `workflow_cli` are headless profiles selected by the command itself, not by deployment env: they remove the app route files from Rails path registration before initialization, keep `ActionController::Base.include_all_helpers = false` to avoid helper scans from framework eager-load, and deliberately exclude web-only gems. Only `jobs` also ignores `lib/r3x/workflow/cli.rb` to keep worker/scheduler boots slimmer. The web process also loads workflows on server boot so Mission Control Jobs can validate and enqueue workflow-backed recurring tasks; it only schedules recurring tasks when it is also hosting Solid Queue in-process, which currently means development or `SOLID_QUEUE_IN_PUMA=true`.
- Production deployments should prefer separate web and jobs controllers/processes over embedding Solid Queue into the Puma web process. Prefer separate worker and scheduler jobs controllers: worker pods can run `bin/jobs-worker`, while scheduler pods can run `bin/jobs-scheduler`. If `SOLID_QUEUE_IN_PUMA` is enabled, remember that the Puma plugin can fork an additional Solid Queue supervisor plus worker/dispatcher/scheduler processes inside the same pod, the web boot path will also load workflows and schedule recurring tasks, and separate jobs pods should not also try to own recurring scheduling in that mode.
- The dashboard does not require workflow packs to be loaded on the web pod. It reconstructs workflow pages from `solid_queue_recurring_tasks`, `solid_queue_jobs`, and `trigger_states`, and can enqueue `Run now` actions through `R3x::RunWorkflowJob` or `R3x::ChangeDetectionJob` without the original workflow class being present on the web pod.
- Change-detecting triggers are file-defined trigger objects that provide `cron`, `unique_key`, and `detect_changes(workflow_key:, state:)`. Their durable runtime state lives in `R3x::TriggerState`.
- `R3x::ChangeDetectionJob` loads the trigger, fetches/updates `R3x::TriggerState`, and only enqueues the workflow job class itself when the trigger reports a change.
- Because the app currently uses `Solid Queue` as a database-backed backend on the same Active Record database connection, code may intentionally rely on a database transaction covering both `TriggerState` updates and `perform_later`. Do not assume those guarantees survive a future backend or database split.
- `R3x::RunWorkflowJob` fetches the workflow from the registry and calls `workflow_class.perform_now(trigger_key, trigger_payload: ...)` for compatibility with callers that still dispatch by workflow key.
- `ApplicationJob`, `R3x::RunWorkflowJob`, `R3x::Workflow::Base`, and `R3x::ChangeDetectionJob` add stable tagged log context so indexed logs can be correlated back to run pages. The workflow job itself keeps the per-run tags minimal (`r3x.run_active_job_id` and `r3x.trigger_key`), while orchestration jobs still emit `r3x.workflow_key` for broader workflow-level correlation.
- App logs are always emitted as structured JSON with explicit `level`, `message`, and tag data so the dashboard can read real log levels directly.
- Known limitation: because queued workflow runs persist the concrete workflow class name, renaming or removing a workflow class across deploys can strand older queued runs with job deserialization failures. This is currently an accepted tradeoff for preserving `ActiveJob::Continuable` on the workflow job itself.
- The dashboard's run history is DB-first and parses `Solid Queue` / `Active Job` payloads directly. It still accepts the underlying tradeoff that finished runs are retention-bound and that workflows with no persisted runtime artifacts are invisible to the dashboard.
- The dashboard log view is also retention-bound, but by the configured log backend rather than `Solid Queue`; it is read-only and fail-soft, so missing log provider config or query failures should not break the main dashboard pages.
- Dashboard log rendering should consume explicit levels from structured log payloads. Do not reintroduce regex-based level inference from message text.
- Trigger discovery is filesystem-backed through `lib/r3x/triggers/*.rb`, so trigger file names, constants, and supported types must stay aligned.

## Working with Workflows

If you're changing workflows or workflow framework code, read
`docs/workflows.md` first. It collects the current guidance on steps,
debugging, logging, LLM output, dry run behavior, and error handling.

Use `bin/workflow` to interact with workflows from the command line. `list` and `info` load all workflow packs via `PackLoader.load!` and query `Registry`; `run` loads only the requested workflow file.

### Output safety

- New workflow code that can cause external side effects (email, API writes, webhooks, state changes outside R3x) should default to `dry_run: true` or equivalent safe mode.
- Only switch to real delivery with an explicit opt-in in the workflow or script, e.g. `dry_run: false`.
- If a client can be destructive or noisy, prefer a boolean `dry_run` flag over an implicit ENV-based mode switch.
- When a client is used from app/runtime code, resolve the default through `R3x::Policy.dry_run_for(:key, dry_run)`: development and test should be dry-run by default, production should default to real delivery unless the caller explicitly opts into `dry_run: true`.
- `R3x::Policy` may also honor per-feature overrides like `R3X_GMAIL_DRY_RUN` and a global `R3X_DRY_RUN` if we need to widen or narrow the policy later.
- For integration credentials, prefer passing `*_env` references like `api_key_env:` or `project:` instead of raw secrets or parsed credential hashes. Resolve the secret lazily inside the client/output so dry-run paths can avoid loading credentials when they do not need them.
- Prefer lazy-loading heavy third-party gems from the client or workflow helper that first needs them. Mark the gem `require: false` in `Gemfile`, then call `R3x::GemLoader.require("...")` at the boundary that actually uses it.
- Treat lazy-loading as a default design tool for optional workflow integrations and LLM helpers, especially in production boot paths.
- Reasoning: this app boots the workflow engine for web and jobs processes, but not every workflow uses every integration. Avoid making all processes pay the memory and boot-time cost of Gmail, Google Sheets, Google Calendar, Google Translate, RubyLLM, or similar stacks when only a subset of workflows needs them.
- When adding or reviewing integration code, actively consider whether the gem should stay eager-loaded or move behind `require: false` plus `R3x::GemLoader.require(...)`. Propose lazy-loading when the dependency is optional, heavy, or only used from specific workflows, CLI commands, or client methods.
- Prefer putting the lazy-load boundary at the smallest practical edge: the client method, workflow helper, or DSL helper that first needs the dependency. Avoid top-level constants or alias maps that force third-party namespaces to load during Rails eager load if the integration is not universally needed.
- For workflow-defined structured LLM output, prefer `R3x::Workflow::LlmSchema.define` so workflows that do not declare schemas do not pay to load the schema gem at boot.
- When integrating a third-party API, put the actual API logic in a dedicated client object under `app/lib/r3x/client/<provider>/...` and keep outputs as thin policy/delivery wrappers.
- When adding a new output/client with a real delivery path, include a dry-run path first and test that it does not call the external service.
- Scratchpad scripts should also default to dry-run unless the user explicitly asks for real delivery.

### `bin/workflow` — CLI entrypoint

```
bin/workflow [options] [command] [arguments]
```

| Command | Description |
|---------|-------------|
| `bin/workflow list` | List all registered workflows with their trigger types. |
| `bin/workflow info <key>` | Show class name and trigger details for a specific workflow. |
| `bin/workflow run <path>` | Execute a workflow from file path (always requires path to `workflow.rb`). |
| `bin/workflow run -d <path>` | Dry run — execute with global dry-run mode enabled for side-effecting clients. |
| `bin/workflow run --skip-cache <path>` | Execute while bypassing all `with_cache` blocks for that run. |

**Global options:** `-h, --help` — print usage.

`bin/workflow` delegates command behavior to `R3x::Workflow::Cli`, so fast tests can cover `run`, `list`, and `info` without spawning a new Ruby process. The command boots through the internal `workflow_cli` runtime profile rather than the default web profile. `workflow_cli` is headless like `jobs`: it skips the app route files before Rails registers them with the routes reloader, excludes web-only gems, and keeps `include_all_helpers` off for framework eager-load. Unlike `jobs`, it still leaves `lib/r3x/workflow/cli.rb` available for the Thor wrapper. The `run` command loads the requested workflow file directly and executes the workflow class it defines. Use `--skip-cache` when you want to ignore `with_cache` during local iteration without editing the workflow file. `list` and `info` load all workflow packs via `PackLoader.load!` and query `Registry`. In the current split-process setup, `bin/jobs` keeps the default Solid Queue boot behavior, while `bin/jobs-worker` and `bin/jobs-scheduler` provide the dedicated split-role entrypoints for worker-only and scheduler-only jobs pods and automatically switch Rails into the internal `jobs` boot profile. The web process also loads workflow packs on server boot so Mission Control Jobs can run recurring tasks manually, but it only schedules recurring tasks when it also runs Solid Queue in-process, which currently means development or `SOLID_QUEUE_IN_PUMA=true`.

**Note:** `bin/workflow run` always requires a file path. Use `bin/workflow list` and `bin/workflow info` to discover workflows loaded from `R3X_WORKFLOW_PATHS`.

### Operational note

- When refactoring workflow class names, remember that already queued scheduled or change-detected runs may still point at the old concrete class name.
- If a workflow class is renamed or removed, consider cleaning up pending jobs and recurring tasks created under the old class, or accept that older queued runs may fail deserialization.

## Maintenance Warning

- Keep this file synchronized with the real codebase. If you change workflow loading, trigger discovery, scheduling flow, top-level directory structure, namespaces, or the framework/user-workflow boundary, update the relevant `AGENTS.md` sections in the same change.
- In particular, update examples and notes here when changing files such as `lib/r3x/workflow.rb`, `lib/r3x/workflow/pack_loader.rb`, `lib/r3x/workflow/registry.rb`, `lib/r3x/workflow/boot.rb`, `lib/r3x/recurring_tasks_config.rb`, `lib/r3x/triggers.rb`, `app/jobs/r3x/run_workflow_job.rb`, `bin/workflow`, `bin/jobs`, or `config/application.rb`.
- Also update this file when changing the shared DSL validation contract in files such as `lib/r3x/dsl/validatable.rb`, `lib/r3x/configuration_error.rb`, or the base classes for workflow-declared objects.
- Also update this file when changing Active Job backend semantics, `Solid Queue` database wiring, or any logic that depends on enqueueing being inside the same database transaction as app writes.
- When adding a new subsystem or moving code between `lib/r3x/`, `app/lib/r3x/`, `app/jobs/r3x/`, or `workflows/`, refresh the project overview and codebase map so future agents can still orient themselves quickly.

## Ruby Version Updates

- `.ruby-version` is the primary source of truth for the Ruby version in this repo.
- `Gemfile` reads the version from `.ruby-version`.
- `mise` is configured to read idiomatic Ruby version files via `mise.toml`, so local tool selection follows `.ruby-version`.
- `ruby/setup-ruby` can auto-detect `.ruby-version` when `ruby-version:` is omitted, so keep CI on the convention unless the version file moves out of the repo root.
- `Dockerfile` must keep `ARG RUBY_VERSION` aligned with `.ruby-version`. The GitHub Actions workflow also reads `.ruby-version` and passes it to Docker build as `RUBY_VERSION`.
- When bumping Ruby, update these files together:
  - `.ruby-version`
  - `Dockerfile`
  - any workflow or script that hardcodes a Ruby version
  - `Gemfile.lock`, but only by running Bundler
- Preferred update flow:
  - change `.ruby-version`
  - verify `Gemfile` still reads from `.ruby-version`
  - update `Dockerfile ARG RUBY_VERSION`
  - run `bundle update --ruby` to refresh `Gemfile.lock`
  - rebuild both Docker targets: `production` and `ci`
- Do not hand-edit `Gemfile.lock` to add or change `RUBY VERSION`. If `Gemfile` and `Gemfile.lock` disagree, fix that by regenerating the lockfile through Bundler, not by manually patching the lockfile.

This repo uses `.githooks/` directory for git hooks. The pre-commit hook runs `bin/ci` which includes `bin/lint-r3x` to verify AGENTS.md references.

## JSON

- Prefer `MultiJson` for JSON parsing and serialization work.
- Reasoning: it gives the app one consistent JSON abstraction instead of scattering direct `JSON` stdlib usage across the codebase, which makes adapter swaps and shared conventions easier later.

## HTTP

- Prefer `Faraday` for outbound HTTP and API integrations.
- Reasoning: it is already a direct project dependency and gives us a standard place for middleware, retries, authentication, adapters, and test stubbing instead of ad hoc HTTP clients.
- For small integration clients under `R3x::Client`, build the Faraday client inside the class instead of injecting a `connection` dependency.
- Reasoning: these clients are thin integration boundaries, so passing a raw Faraday connection through the initializer adds indirection without improving the public interface we actually want to use.
- **JSON handling**: When making HTTP requests that send/receive JSON, use Faraday's built-in `:json` middleware (available via `faraday` gem 2.0+) instead of manually serializing with `MultiJson`. Configure the connection with `f.request :json` and `f.response :json` - this automatically sets the Content-Type header and handles request/response body serialization.
  - **Bad**: `request.body = MultiJson.dump({"key" => "value"})`
  - **Good**: `connection.post(url, { key: "value" })` with `f.request :json` middleware

## Naming Conventions

- When a class is namespaced within a descriptive module (e.g., `R3x::Client`, `R3x::Triggers`), do not repeat the module name in the class name.
- **Good**: `R3x::Client::Http`, `R3x::Triggers::Schedule`, `R3x::Client::Discord::Webhook`
- **Bad**: `R3x::Client::HttpClient`, `R3x::Triggers::ScheduleTrigger`

### Zeitwerk & File Structure

- Adhere strictly to Zeitwerk's path-to-constant mapping: file names must match their defined constant exactly (snake_case to CamelCase).
- **Files**: `app/lib/r3x/client/http.rb` must define `R3x::Client::Http`.
- **Directories**: Directories represent namespaces. If a file is in `app/models/r3x/`, it must be wrapped in `module R3x`.
- **Acronyms**: Use standard inflection (e.g., `lib/r3x/env.rb` → `R3x::Env`) unless a custom inflection is explicitly defined in `config/initializers/inflections.rb`.
- **Validation**: Always ensure the filename and the class/module name are perfectly aligned to avoid `NameError` during autoloading.

### Autoloading

- Everything autoloaded by Rails (paths configured in `autoload_paths`, `autoload_lib`, etc.) is handled by Zeitwerk. You should never need to use `require` or `require_relative` for files within autoloaded paths.
- **Bad**: `require_relative "../validators/cron"` at the top of a file in `lib/r3x/triggers/`
- **Good**: Just reference `R3x::Validators::Cron` directly - Zeitwerk will find and load it automatically.
- The only exception is requiring external gems that don't auto-require their components.
- **Debugging**: If you get a `NameError` when referencing a class that should exist, it's likely a Zeitwerk autoloading issue (wrong file name, wrong constant name, or missing namespace). Check that file names match constants exactly (snake_case ↔ CamelCase).

## Testing

- When writing tests for workflow DSL or infrastructure, use generic workflow names (e.g., `TestWorkflow`, `MyTestWorkflow`), not real workflow names from `workflows/` folder.
- Real workflows in `workflows/` are "user workflows" and should not be hardcoded in tests for the core framework.
- Use anonymous classes or fixture workflows in `test/fixtures/workflows/` for testing framework behavior.
- Pack-specific workflow tests should live under `workflows/<pack>/test/` next to the workflow pack itself.
- **Good**: `Class.new(R3x::Workflow::Base) { def self.name; "Test"; end }`
- **Bad**: Testing `MyUserWorkflow` workflow directly in framework tests

### TDD Pattern

- When fixing a bug, write a failing test first that reproduces the issue, then fix the code.
- **Flow**: Write test → verify it fails → fix code → verify test passes.
- This ensures the bug is actually fixed and prevents regressions.
- Apply this red/green flow broadly to bug fixes and behavioral regressions, not just parser or formatter changes. Keep a regression test that proves the user-visible or externally observable behavior that broke.

## Logging

- Use Rails tagged logging with `self.class.name` for per-class log prefixes.
- **Good**: `logger.tagged(self.class.name) { logger.info("message") }`
- **Bad**: `logger.info("[Hardcoded::Class::Name] message")` or manual string interpolation
- Reasoning: Using `self.class.name` keeps log tags synchronized with actual class names automatically, supports nested tagging, and works consistently with Rails log formatting.
- Use `R3x::Concerns::Logger` - provides both instance and class method `logger` tagged with class name. `Rails.logger` is already `TaggedLogging` so just call `.tagged(name)` directly.
- For class methods: `extend R3x::Concerns::Logger` then call `logger.info(...)`
- For instance methods: `include R3x::Concerns::Logger` then call `logger.info(...)`
- Preserve the shared workflow/job correlation tags emitted by `ApplicationJob` and workflow execution paths: `r3x.run_active_job_id` and, where useful for the emitting layer, `r3x.workflow_key` and `r3x.trigger_key`. Add nested tags when needed, but do not replace or rename these tags without updating the dashboard log queries and deployment env/docs in the same change.
- **Lazy logging for debug level**: Use block form `logger.debug { "..." }` — the block only executes if debug level is enabled, avoiding unnecessary string allocation.
- **Eager logging for info/warn/error**: Use string form `logger.info "..."` — these levels are always enabled, so block overhead is wasted.
- **Good**: `logger.debug { "Processing #{items.count} items" }` (block — skipped when debug off)
- **Good**: `logger.info "Workflow completed"` (string — always evaluated, no block overhead)
- **Bad**: `logger.debug "Processing #{items.count} items"` (string built even when debug off)
- **Bad**: `logger.info { "Workflow completed" }` (block overhead for always-enabled level)

## Validators

- Place shared validation logic in `lib/r3x/validators/`.
- **Good**: `R3x::Validators::Cron`, `R3x::Validators::Url`
- **Bad**: `R3x::Triggers::Cron`, `R3x::Services::UrlChecker`
- Reasoning: Validators are reusable across triggers, services, and other components. Keep them in a dedicated namespace.
- Validators used with `validates_with` should inherit from `ActiveModel::Validator` and implement `validate(record)`. They may also expose a `validate!` class method for direct use (e.g., `R3x::Validators::Url.validate!("https://example.com")`).
- Trigger concerns that provide capability predicates should also include the relevant validations. For example, `CronSchedulable` auto-includes `validates :cron, presence: true` and `validates_with Validators::Cron` — individual triggers should not repeat these.
- DSL objects should use `ActiveModel::Validations` via the shared DSL validation layer and call these validators from object-level validations for reusable value checks.
- Presence and object semantics belong to the DSL object itself; `R3x::Validators::*` should focus on validating the shape or format of a provided value.
- Every new workflow DSL object must go through the shared DSL validation layer. Do not add triggers, steps, outputs, or other workflow-declared objects that bypass validation or rely only on ad hoc `raise ArgumentError`.

## Control Flow

- `case` statements that dispatch on configuration values (e.g., ENV modes) must either exhaustively list all supported values or raise an exception in the `else` branch for unsupported values.
- **Good**:

  ```ruby
  case mode
  when "real" then # handle real
  when "test" then # handle test
  else
    raise ArgumentError, "Unsupported mode: #{mode}"
  end
  ```

- **Bad**:

  ```ruby
  case mode
  when "real" then # handle real
  else
    # silently assumes test mode, hides typos in configuration
  end
  ```

- Reasoning: Failing fast with a clear error prevents silent misconfiguration and makes debugging easier when an invalid mode is accidentally provided.

## Environment Variables

- When reading required environment variables, use `R3x::Env.fetch!("KEY")`; use `R3x::Env.fetch("KEY")` for optional values.
- **Good**: `R3x::Env.fetch!("VAULT_ADDR")`
- **Good**: `R3x::Env.fetch("R3X_TIMEZONE")`
- **Bad**: `ENV["VAULT_ADDR"].presence || raise(ArgumentError, "Missing VAULT_ADDR")` — use the helper instead of inline pattern
- **Bad**: `ENV["VAULT_ADDR"] || raise(ArgumentError, "Missing VAULT_ADDR")` — allows empty strings to pass through
- The helper lives in `lib/r3x/env.rb`. In Rails/Dotenv, misconfigured `.env` files often yield empty strings (e.g., `VAULT_ADDR=`), which are truthy but invalid. Failing fast with a clear error prevents confusing downstream failures.

## Object Design

- Prefer capability-based APIs over branching on symbolic types when behavior can be expressed through an object interface.
- **Good**: `triggers.select(&:cron_schedulable?)`
- **Bad**: `triggers.select { |t| t.type == :schedule }`
- Prefer instance variables only for state the object needs across method calls or as part of its long-lived identity.
- Do not use instance variables as local variables inside a single method. If a derived value is only needed within one method, use a local variable or extract a small helper. Instance variables are appropriate for memoization when a helper is called from multiple places and the result is stable for the lifetime of the object.
- When multiple classes share a capability, extract a small concern or module with an explicit predicate and required methods.
- **Good**: `include R3x::Triggers::Concerns::CronSchedulable`
- Framework code should avoid hardcoding knowledge of concrete subtypes. Prefer polymorphism, capability predicates, and object-owned methods like `to_h`.
- Name methods around behavior, not concrete subtype names, unless the code truly depends on that exact subtype.
- Prefer duck typing: focus on behavior rather than names. Ask what the object can do and which methods it responds to; prefer ability over identity.
- Reasoning: Duck typing is meritocratic. New classes can participate by exposing the right behavior without forcing central dispatch code to learn every subtype.

## Scratchpad

- `scratchpad/` is for quick test scripts, one-off experiments, and prototyping — anything outside the main implementation code and test suite.
- The directory is gitignored. Do not place production code there.
- Use it when you need to verify something quickly (e.g., hitting an API, testing a query) without writing a proper test.

## CLI Scripts

- Use [Thor](https://github.com/rails/thor) for all CLI scripts in `bin/`. Do not use raw OptionParser.
- Thor is a Rails dependency and auto-generates help from `desc`/`option` declarations — no manual `print_help` methods needed.
- Each command is a method with `desc` and `option`. Subcommands are separate methods on the same class.
- **Class setup:**
  ```ruby
  class MyCLI < Thor
    def self.exit_on_failure? = true
    namespace :"my-tool"
  end
  ```
- Known limitation: `-h`/`--help` does not work on subcommands that have `required: true` options. Thor validates required options before checking for help flags. Use `--help` without required options, or `bin/tool help <command>`. This is a Thor design limitation, not a bug in our scripts.
- Do not use Thor reserved words as method names: `run`, `invoke`, `shell`, `options`, `behavior`, `root`, `action`, `create_file`, `inside`, `run_ruby_script`. Use `map "run" => :execute` if the CLI command name must be `run`.

## Code Style

### Method Chaining

Prefer chaining methods across multiple lines over introducing single-use intermediate variables.

**Good:**
```ruby
@llm_context
  .chat(model: model, provider: :gemini)
  .ask(prompt, with: [io])
  .content
```

**Bad:**
```ruby
chat = @llm_context.chat(model: model, provider: :gemini)
response = chat.ask(prompt, with: [io])
response.content
```

**Rationale:**
- Each intermediate variable adds a name that must be understood and maintained
- Chaining makes the data flow obvious - input flows through transformations to output
- Fewer local variables reduce cognitive load and naming fatigue
- The pattern works well with Ruby's method chaining syntax and fluent interfaces

**Exceptions:**
- When intermediate results are used multiple times
- When the intermediate value has semantic meaning that aids comprehension
- When debugging requires inspecting intermediate state

### Module-Level Singleton API

When a module exists solely as a namespace for a group of related class-level (singleton) methods, use `extend self`. This avoids repeating `self.` on every method definition and signals that the module is intended to be called directly as `ModuleName.method`.

**Good:**
```ruby
module R3x::RuntimeProfile
  extend self

  def current
    # ...
  end
end
```

**Bad:**
```ruby
module R3x::RuntimeProfile
  def self.current
    # ...
  end
end
```

Do **not** use `extend self` in modules that are meant to be mixed in (`include`) or that contain both instance and class methods. Reserve it for pure singleton-method namespaces.

## Design Principles

### KISS (Keep It Simple, Stupid)

- Prefer simple solutions over clever ones.
- Avoid over-engineering for hypothetical future requirements.
- Each class/method should have one clear responsibility.
- Don't add methods that "might be useful someday" (like `save_to(path)` for in-memory file objects).
- When in doubt, choose the smaller API surface.

### SRP (Single Responsibility Principle)

- A class should have one reason to change.
- Data objects should store data; let calling code decide what to do with it.
- **Bad**: File wrapper with `save_to` method — mixes data storage with filesystem I/O.
- **Good**: File wrapper with `to_io` method — provides access to data, caller decides whether to save, upload, or process.
- Separate concerns: downloading ≠ processing ≠ persisting.

### One Class Per File

- Each class must be defined in its own file following Zeitwerk conventions.
- Nested classes should be extracted to separate files under the parent namespace.
- **Bad**: Defining `Http::DownloadedFile` inside `http.rb` alongside `Http` class.
- **Good**: `Http` in `app/lib/r3x/client/http.rb`, `Http::DownloadedFile` in `app/lib/r3x/client/http/downloaded_file.rb`.

## Scope

- Apply these as defaults for new work.
- Do not rewrite existing code only to satisfy these preferences unless the task explicitly calls for that refactor.
- **Do not remove existing comments from code without explicit user approval.** Comments in the codebase are intentional documentation — preserve them unless the user asks to remove or rewrite them.
