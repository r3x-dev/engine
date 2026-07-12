# Instructions

This is a Rails API app for the `r3x` Ruby-native workflow engine. Keep changes small, boring, and easy to maintain. Prefer the simplest DHH/Sandi-friendly production code first; tests and tooling should validate that design, not force extra production seams.

## Agent Workflow

- Do not commit, push, open PRs, or merge unless the user explicitly asks.
- Before finishing implementation work, run `bin/ci` and fix failures unless the user accepts a known failure.
- The pre-commit hook intentionally runs the full local `bin/ci` suite while it remains reasonably fast. Keep failures close to the change, use the same acceptance gate before a commit exists, and avoid making remote CI the first feedback loop. Do not narrow this hook to targeted lint or tests without an explicit project decision; revisit only when its runtime materially disrupts normal commits. This follows the local-CI reasoning in [DHH's write-up](https://world.hey.com/dhh/we-re-moving-continuous-integration-back-to-developer-machines-3ac6c611).
- Use `git --no-pager` for agent-read Git output such as diff, show, log, and status details.
- Keep this file and `docs/todo.md` synchronized when code changes alter architecture, workflow loading, trigger discovery, scheduling, validation contracts, env behavior, HTTP policy, or repo layout.

## Project Shape

- Framework/runtime code lives in the app and `lib/r3x/`; user workflow packs live under `workflows/`.
- Workflows subclass `R3x::Workflow::Base`, declare triggers through the DSL, and implement `#run`.
- Workflow classes are real `ApplicationJob`s so workflow code can use `ActiveJob::Continuable` and `step` on the actual job instance.
- Solid Queue is the Active Job backend. App, queue, and cache tables currently share the primary Active Record connection in development and production; queue inserts can participate in app transactions. Revisit transactional assumptions if Solid Queue/Cache moves to another DB or backend.
- Production DB config is env-driven: prefer `R3X_DATABASE_URL`, fall back to `R3X_DATABASE_PATH`.
- Secrets are ENV-only. Do not rely on Rails encrypted credentials or `RAILS_MASTER_KEY`; provide `SECRET_KEY_BASE` and integration secrets through env/Vault.
- Vault env bootstrap supports `R3X_VAULT_TOKEN` or Kubernetes auth via `R3X_VAULT_AUTH_METHOD=kubernetes` and `R3X_VAULT_KUBERNETES_ROLE`. Invalid configured Vault auth should fail fast at boot.

## Runtime Profiles

- `bin/jobs-worker` and `bin/jobs-scheduler` set `R3X_RUNTIME_PROFILE=jobs`; this headless profile skips routes/web gems/helpers and ignores `lib/r3x/workflow/cli.rb`.
- `bin/workflow` sets `R3X_RUNTIME_PROFILE=workflow_cli`; it is headless but keeps `lib/r3x/workflow/cli.rb`.
- `bin/web` is the explicit web-only entrypoint. It disables Solid Queue in Puma and does not load workflow packs.
- These profiles are command-owned internals, not deployment knobs.
- Prefer separate web, worker, and scheduler processes in production. Plain `bin/rails server` defaults to the combined process, which loads workflow packs and owns Solid Queue scheduling. Use `bin/web` for an explicit web-only process; do not run a separate jobs scheduler with the combined process.

## Dashboard

- The default local UI is the server-rendered dashboard at `/`; Mission Control Jobs remains at `/ops/jobs`.
- Dashboard pages are DB-first and reconstructed from persisted Solid Queue recurring-task/job rows. Workflows with no persisted runtime artifacts are invisible by design.
- Dashboard queue boundaries are `Dashboard::Run`, `Dashboard::RecurringTask`, and `Dashboard::DirectWorkflowEnqueuer`.
- Web-only pods do not load workflow packs. `POST /workflows/:workflow_key/runs` may enqueue through `Dashboard::DirectWorkflowEnqueuer` without constantizing workflow classes.
- Logs are optional and read-only. `R3X_LOGS_PROVIDER=victorialogs` reads `R3X_VICTORIA_LOGS_URL`; missing config or query failures must not break main pages.
- Dashboard authentication is deployment-owned. Keep the web surface private or behind an authentication proxy; do not add an application user/auth system unless that product boundary changes explicitly.
- `R3X_LOG_FORMAT=json` emits structured logs with explicit levels for dashboard log views; `plain` is standard Rails text. Unsupported values raise on boot. Do not infer levels from message regexes.

## Code Map

- `lib/r3x/`: workflow DSL, triggers, loading/registry, execution context, recurring tasks, validators, gem loading.
- `app/lib/r3x/client/`: integration clients used by workflows and runtime.
- `app/lib/r3x/dashboard/`: dashboard query/composition objects and log provider code.
- `app/models/dashboard/`: dashboard-facing models over Solid Queue metadata.
- `app/controllers/r3x/`, `app/views/r3x/dashboard/`, `app/views/layouts/r3x/dashboard.html.erb`: dashboard and HTML surfaces in the API app.
- `app/jobs/r3x/`, `app/models/r3x/`: runtime support jobs/models.
- `workflows/`: user workflow packs. Do not write tests for workflows under this folder.
- `test/fixtures/workflows/`: fixture workflows for framework tests.
- Third-party Google constants must be referenced as `::Google`; `R3x::Client::Google` is a project namespace.

## Workflow Runtime

- Workflow packs are loaded explicitly by process entrypoints, not globally during Rails boot.
- `R3x::Workflow::PackLoader` discovers `workflow.rb` files from `R3X_WORKFLOW_PATHS`, skips top-of-file `# r3x:disable ...`, and registers classes in `R3x::Workflow::Registry`.
- `PackLoader.load!(rebuild_registry: true)` rebuilds registry state but still uses Ruby `require`; it is not same-process source reload.
- Catalog-dependent entrypoints (`bin/jobs*`, `bin/workflow`, and default or combined Puma) require `R3X_WORKFLOW_PATHS` to resolve to existing directories with at least one `workflow.rb`; fail before scheduling so a broken or empty mount cannot sweep persisted tasks. An explicit web-only process has no catalog dependency.
- `R3x::RecurringTasksConfig.schedule_all!` persists schedulable triggers as Solid Queue dynamic recurring tasks and sweeps stale ones. Trigger file names, constants, and supported types must stay aligned with `lib/r3x/triggers/*.rb`.
- Already queued jobs persist concrete workflow class names. Renaming/removing a workflow can strand old queued jobs; clean up pending jobs/tasks or accept deserialization failures.
- Workflow code can use `ctx.durable_set(name = :default, ttl: 90.days)` for best-effort dedup. Keep `ttl:` at or below `config/cache.yml` `store_options.max_age` when using `:solid_cache_store`.

## Workflow Work

- If changing workflows or workflow framework code, read `docs/workflows.md` first.
- Use `bin/workflow list` and `bin/workflow info <key>` to inspect registered workflows.
- `bin/workflow run <path>` always requires a path to `workflow.rb`; use `-d` for dry run and `--skip-cache` to bypass `with_cache`.
- New code with external side effects should default to `dry_run: true` or equivalent safe mode. Real delivery must be explicit, e.g. `dry_run: false`.
- App/runtime clients should resolve dry-run defaults through `R3x::Policy.dry_run_for(:key, dry_run)`: development/test default dry, production default real unless explicitly dry.
- Scratchpad scripts also default to dry run unless the user explicitly asks for real delivery.

## Integrations

- Put third-party API logic in a dedicated client under `app/lib/r3x/client/<provider>/...`; keep outputs thin.
- Prefer env-name references such as `api_key_env:` or `project:` over raw secrets or parsed credential hashes. Resolve secrets lazily so dry-run paths avoid credential loading.
- Lazy-load optional/heavy gems at the smallest practical boundary with `R3x::GemLoader.require(...)`; mark the gem `require: false` in `Gemfile`.
- Prefer `R3x::Workflow::LlmSchema.define` for workflow-defined structured LLM output so workflows without schemas do not load the schema gem.

## HTTP & JSON

- Prefer `httpx` for outbound HTTP in `R3x::Client` code. Do not add direct Faraday usage; existing Faraday is transitive.
- For small integration clients, build the `httpx` client inside the class. Do not inject raw HTTP connections unless the production design needs that abstraction.
- Do not use `HTTPX.with({})`; call `HTTPX.get/post/...` directly when there are no shared options.
- For repeated workflow HTTP calls in one controlled scope, use `ctx.client.persistent_http(...) { |http| ... }`; keep persistence opt-in for measured hot paths.
- Use `json:` for JSON request bodies and `response.json` for JSON responses. Prefer `MultiJSON` elsewhere.
- Call `.raise_for_status` when a client should fail fast on transport 4xx/5xx. Do not hand-roll ordinary 2xx checks in thin clients.
- Manual provider-level error translation is fine after successful transport status, e.g. a `200` response with an error field.

## Database & SQL

- Raw SQL must support both SQLite and PostgreSQL unless explicitly adapter-branched.
- Do not write DB-specific SQL strings directly without an adapter branch and a clear unsupported-adapter error.
- Prefer DB-side filtering, deduplication, ranking, aggregation, and `UNION` over loading many rows and shaping them in Ruby.
- Tests use SQLite by default. Set `R3X_TEST_DATABASE_URL` to exercise PostgreSQL; `just test-postgres` provides the local acceptance path, and CI runs both adapters.

## Env

- Required env: `R3x::Env.fetch!("KEY")`. Optional env: `R3x::Env.fetch("KEY")`.
- Do not use direct `ENV[...]` patterns that let blank strings through.
- Keep `docs/environment.md` synchronized when adding, renaming, or removing env vars.
- Clients with env-name overrides should expose provider-level defaults and validate variants with underscore-suffixed prefixes, e.g. `R3x::Env.secure_fetch(api_key_env, prefix: "#{DEFAULT_API_KEY_ENV}_")`.

## Naming, Zeitwerk, Autoloading

- Do not repeat namespace names in class names: `R3x::Client::Http`, not `R3x::Client::HttpClient`.
- Follow Zeitwerk path-to-constant mapping exactly. Files, directories, namespaces, and acronyms must align.
- Do not `require` or `require_relative` files from Rails autoload paths. Just reference the constant. Require only external gems/components that do not auto-require.
- One class per file. Extract nested classes to files under the parent namespace.

## Object Design

- Prefer capability-based APIs over branching on symbolic types when behavior can live on the object.
- Framework code should avoid hardcoding concrete subtypes. Prefer polymorphism, explicit capability predicates, and object-owned methods.
- Name methods around behavior, not subtype names, unless exact subtype identity is the real contract.
- Use instance variables only for state needed across methods or object lifetime. Use locals or small helpers for one-method derived values.
- When multiple classes share a capability, extract a small concern with explicit predicates/required methods.
- Keep production APIs small. Do not add methods, wrappers, adapters, keyword seams, or dependency injection just because they may help a test.

## Testing

- Framework tests for workflow DSL/runtime must use generic workflow names or fixtures from `test/fixtures/workflows/`; do not hardcode real `workflows/` classes.
- Do NOT write tests for user workflow packs under `workflows/` unless explicitly required. For now, test workflows manually after writing them.
- Bug fixes should follow red/green: write a failing regression test, verify it fails, fix, verify it passes.
- Use Minitest, fixtures, semantic assertions, and the repo's RuboCop/Minitest conventions.
- Prefer `assert_predicate`, `assert_empty`, `assert_includes`, `assert_nil`, etc. over generic boolean/equality assertions.
- Keep `assert_raises` blocks around only the exact expression expected to raise.

### Stubbing and Mocking

- Use Mocha for method-level stubbing. It auto-cleans stubs and avoids manual restore boilerplate.
- `require "mocha/minitest"` must come after `require "rails/test_help"` in `test_helper.rb`.
- Prefer `stubs`; use `expects` only when the call itself is the side effect being verified.
- Do not change production APIs just to make tests easier. Test at the nearest owned boundary with Mocha, WebMock, fixtures, or plain Ruby fakes.
- `R3x/NoManualMethodPatchingInTests` forbids global method patching in tests: no constant-level `define_singleton_method`, `singleton_class.define_method`, `alias_method`, `remove_method`, or restore-by-hand patterns. Use Mocha for class/global stubs and plain fake classes/objects for stateful collaborators.
- Do not stub what you do not own via Mocha. Use WebMock for HTTP; keep Active Record queries and Solid Queue state real when practical.
- Complex stateful fakes should be plain Ruby objects/classes, not chains of Mocha expectations.
- If removing the real implementation under a stub would not break the test, the stub covers too much.

## Logging

- Use `R3x::Concerns::Logger` for class/instance logging and class-name tags. Do not hardcode class names in log strings.
- Preserve workflow/job correlation tags: `r3x.run_active_job_id`, and where useful `r3x.workflow_key` / `r3x.trigger_key`. Update dashboard log queries/docs if renaming them.
- Use block form for debug logs: `logger.debug { "..." }`.
- Use string form for info/warn/error logs: `logger.info "..."`.

## Validators

- Put shared validation logic in `lib/r3x/validators/`.
- Validators used with `validates_with` inherit from `ActiveModel::Validator` and implement `validate(record)`; they may expose `validate!` for direct use.
- Workflow DSL objects must go through the shared DSL validation layer and raise `R3x::ConfigurationError` with collected validation errors.
- Capability concerns should include their validations so individual triggers do not repeat them.

## Control Flow

- `case` dispatch on config/env/modes must list supported values or raise in `else`.
- Fail fast for unknown env prefixes, provider names, modes, trigger types, and other closed sets.

## CLI Scripts

- Use Thor for all `bin/` CLIs; do not use raw OptionParser.
- Each command is a method with `desc` and `option`.
- Set `def self.exit_on_failure? = true` and a `namespace`.
- Avoid Thor reserved method names (`run`, `invoke`, `shell`, `options`, `behavior`, `root`, `action`, `create_file`, `inside`, `run_ruby_script`). Use `map "run" => :execute` if the command must be named `run`.
- Thor `-h/--help` does not work on subcommands with required options; use `bin/tool help <command>`.

## Ruby & Rails Style

- Prefer the smallest Ruby/Rails primitive that expresses the real contract: `Hash`, `Mutex`, constants, `Data.define`, Rails helpers, models, scopes, and concerns before new abstractions/gems.
- Avoid over-engineering for hypothetical future requirements. Each class/method should have one clear reason to change.
- Keep registries idempotent and process-wide caches keyed by the real domain key. Protect concurrent writes with `Mutex`; freeze cached values when callers should not mutate them.
- Do not use `Thread.current`, `thread_mattr`, or `Current` for shared configuration, provider registries, or process caches. Use them only for intentional thread/request scope.
- Avoid `cattr_accessor`/`mattr_accessor` for mutable global state unless Rails-owned configuration behavior is specifically desired.
- For immutable value objects, prefer class-form `Data.define` and put constants inside the class body.
- For singleton-method namespace modules, use `extend self` only when the module is not meant to be included.
- Prefer expressive stdlib methods (`values_at`, `slice`, `filter_map`, `each_with_object`, `sum`, `tally`) over verbose manual loops when they make intent clearer.
- For conditional hash keys, build a base hash, assign optional keys, and return it. Avoid `Hash#tap`/`merge` for simple conditional key assignment.
- Method chaining is fine when it makes data flow clearer; introduce locals when the intermediate value is reused or has important meaning.
- Prefer one-line `tap { it... }` for a single obvious post-construction tweak on the returned object. Use a named block parameter or multiline block when the object role is not obvious, there is more than one mutation, or the block contains branching/side effects that deserve a name.
- Do not remove existing code comments without explicit user approval.

## Ruby Version Updates

- `.ruby-version` is the source of truth. `Gemfile` reads it; `mise` follows it; CI should let `ruby/setup-ruby` auto-detect it.
- Keep `Dockerfile ARG RUBY_VERSION` aligned with `.ruby-version`; GitHub Actions reads `.ruby-version` for Docker builds.
- When bumping Ruby: update `.ruby-version`, update Docker ARGs/scripts that hardcode Ruby, run `bundle update --ruby`, update `Gemfile.lock` through Bundler only, and rebuild Docker `production` and `ci` targets.

## Scope

- Apply these defaults to new work and touched code.
- Do not rewrite existing code only to satisfy preferences unless the task calls for that refactor.
- Future ideas and design debt live in `docs/todo.md`; when picking up an item, update its status there.
