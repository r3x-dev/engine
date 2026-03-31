# Instructions

This Rails app uses a small set of preferred libraries for common integration work. Follow these defaults for new code and agent-authored changes unless an existing subsystem already requires a different interface.

## Project Overview

- `r3x` is a Rails API app that acts as a Ruby-native workflow executor and automation engine.
- The high-level split is: framework/runtime code lives in the app and `lib/r3x/`, while user-defined workflows live under `workflows/`.
- Workflows are file-based, Git-friendly, and loaded into a database-backed runtime that uses Active Job + Solid Queue for execution and recurring scheduling.
- Workflow classes are enqueued directly as Active Job classes so workflow code can use `ActiveJob::Continuable` and `step` on the real workflow job instance.
- `Solid Queue` is the active job backend for app/runtime execution. Treat queueing semantics as database-backed, not Redis-backed.
- In the current app configuration, `Solid Queue` is not wired through `config.solid_queue.connects_to`, so queue records use the same Active Record database connection as the app in the environments configured here. That means queue inserts can participate in the same database transaction as app writes.
- If `Solid Queue` is ever moved to a separate database, or replaced with a non-database backend, revisit any code that relies on transactional integrity between app writes and job enqueueing. In that setup, `enqueue_after_transaction_commit` and related tests become important again.
- The default local UI surface is Mission Control Jobs mounted at `/jobs`; the root route redirects there.

## Codebase Map

- `lib/r3x/`: core framework code for the workflow DSL, trigger types, workflow loading, registry, execution context, recurring-task config, and shared DSL helpers.
- `lib/r3x/workflow/executor.rb`: shared workflow execution helper that resolves the trigger and builds `Workflow::Context` for a loaded workflow class.
- `lib/r3x/dsl/`: shared DSL infrastructure, especially validation concerns and configuration errors used by workflow-declared objects.
- `lib/r3x/trigger_manager.rb` + `lib/r3x/trigger_manager/`: trigger infrastructure — `R3x::TriggerManager::Collection` (manages workflow triggers as a hash keyed by `unique_key`) and `R3x::TriggerManager::Execution` (wraps a trigger for runtime use).
- `app/lib/r3x/`: runtime support code such as client wrappers and shared concerns.
- `app/lib/r3x/client/google/credentials.rb`: shared Google credentials loader used by Gmail and Google Sheets integrations.
- `app/lib/r3x/client/google/gmail.rb`: Gmail API client used by workflows via `ctx.client.gmail(...)`.
- `R3x::Client::Google` is a project namespace; when referencing the third-party Google gem namespace, use `::Google` to avoid constant collisions.
- `app/jobs/r3x/`: job entrypoints, especially `R3x::RunWorkflowJob`, which resolves a workflow key and dispatches to the workflow job class, and `R3x::ChangeDetectionJob`, which evaluates change-detecting triggers before enqueueing workflow runs.
- `app/models/r3x/`: runtime support models such as `R3x::TriggerState` for per-trigger change-detection state.
- `workflows/`: user workflow packs. These are not the framework itself; they are loaded by the framework.
- `config/initializers/r3x_workflow_loader.rb`: boot-time workflow loading hook.
- `test/fixtures/workflows/`: fixture workflows for framework tests. Prefer these over hardcoding real workflows in tests.

## Runtime Flow

- Workflows subclass `R3x::Workflow::Base`, declare triggers via the DSL, and implement `#run`.
- `R3x::Workflow::Base` is also an `ApplicationJob`; its `#perform` delegates trigger/context setup to `R3x::Workflow::Executor`, stores the context on the job, and then calls `#run` on the current job instance.
- Workflow-declared DSL objects must validate themselves before being registered; invalid DSL configuration should raise `R3x::ConfigurationError` with collected validation errors.
- `R3x::Workflow::PackLoader` discovers workflow entrypoints named `workflow.rb` from directories listed in `R3X_WORKFLOW_PATHS`, loads them, and registers their classes in `R3x::Workflow::Registry`.
- `R3x::RecurringTasksConfig` turns schedulable workflow triggers into Solid Queue dynamic recurring tasks via `SolidQueue::RecurringTask`. All triggers have a `unique_key` (based on type + options hash) used for identification and duplicate detection. `schedule_all!` persists dynamic tasks and sweeps stale ones.
- Change-detecting triggers are file-defined trigger objects that provide `cron`, `unique_key`, and `detect_changes(workflow_key:, state:)`. Their durable runtime state lives in `R3x::TriggerState`.
- `R3x::ChangeDetectionJob` loads the trigger, fetches/updates `R3x::TriggerState`, and only enqueues the workflow job class itself when the trigger reports a change.
- Because the app currently uses `Solid Queue` as a database-backed backend on the same Active Record database connection, code may intentionally rely on a database transaction covering both `TriggerState` updates and `perform_later`. Do not assume those guarantees survive a future backend or database split.
- `R3x::RunWorkflowJob` fetches the workflow from the registry and calls `workflow_class.perform_now(trigger_key, trigger_payload: ...)` for compatibility with callers that still dispatch by workflow key.
- Known limitation: because queued workflow runs persist the concrete workflow class name, renaming or removing a workflow class across deploys can strand older queued runs with job deserialization failures. This is currently an accepted tradeoff for preserving `ActiveJob::Continuable` on the workflow job itself.
- Trigger discovery is filesystem-backed through `lib/r3x/triggers/*.rb`, so trigger file names, constants, and supported types must stay aligned.

## Working with Workflows

If you're changing workflows or workflow framework code, read
`docs/workflows.md` first. It collects the current guidance on steps,
debugging, logging, LLM output, dry run behavior, and error handling.

Use `bin/workflow` to interact with workflows from the command line. It loads all workflow packs via `PackLoader.load!` and queries `Registry`.

### Output safety

- New workflow code that can cause external side effects (email, API writes, webhooks, state changes outside R3x) should default to `dry_run: true` or equivalent safe mode.
- Only switch to real delivery with an explicit opt-in in the workflow or script, e.g. `dry_run: false`.
- If a client can be destructive or noisy, prefer a boolean `dry_run` flag over an implicit ENV-based mode switch.
- When a client is used from app/runtime code, resolve the default through `R3x::Policy.dry_run_for(:key, dry_run)`: development and test should be dry-run by default, production should default to real delivery unless the caller explicitly opts into `dry_run: true`.
- `R3x::Policy` may also honor per-feature overrides like `R3X_GMAIL_DRY_RUN` and a global `R3X_DRY_RUN` if we need to widen or narrow the policy later.
- For integration credentials, prefer passing `*_env` references like `credentials_env:` or `api_key_env:` instead of raw secrets or parsed credential hashes. Resolve the secret lazily inside the client/output so dry-run paths can avoid loading credentials when they do not need them.
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
| `bin/workflow run -d <path>` | Dry run — show what would be executed without running. |

**Global options:** `-h, --help` — print usage.

The CLI handles workflow resolution internally: it checks if the argument looks like a file path (contains `/` or ends with `workflow.rb`), loads from file if so, otherwise fetches from the registry via `workflow_key`. The resolved workflow class is then executed with `perform_now`.

**Note:** `bin/workflow run` always requires a file path. Use `bin/workflow list` and `bin/workflow info` to discover workflows loaded from `R3X_WORKFLOW_PATHS`.

### Operational note

- When refactoring workflow class names, remember that already queued scheduled or change-detected runs may still point at the old concrete class name.
- If a workflow class is renamed or removed, consider cleaning up pending jobs and recurring tasks created under the old class, or accept that older queued runs may fail deserialization.

## Maintenance Warning

- Keep this file synchronized with the real codebase. If you change workflow loading, trigger discovery, scheduling flow, top-level directory structure, namespaces, or the framework/user-workflow boundary, update the relevant `AGENTS.md` sections in the same change.
- In particular, update examples and notes here when changing files such as `lib/r3x/workflow.rb`, `lib/r3x/workflow/pack_loader.rb`, `lib/r3x/workflow/registry.rb`, `lib/r3x/recurring_tasks_config.rb`, `lib/r3x/triggers.rb`, `app/jobs/r3x/run_workflow_job.rb`, `bin/workflow`, or `config/initializers/r3x_workflow_loader.rb`.
- Also update this file when changing the shared DSL validation contract in files such as `lib/r3x/dsl/validatable.rb`, `lib/r3x/configuration_error.rb`, or the base classes for workflow-declared objects.
- Also update this file when changing Active Job backend semantics, `Solid Queue` database wiring, or any logic that depends on enqueueing being inside the same database transaction as app writes.
- When adding a new subsystem or moving code between `lib/r3x/`, `app/lib/r3x/`, `app/jobs/r3x/`, or `workflows/`, refresh the project overview and codebase map so future agents can still orient themselves quickly.

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
- **Good**: `Class.new(R3x::Workflow::Base) { def self.name; "Test"; end }`
- **Bad**: Testing `MyUserWorkflow` workflow directly in framework tests

### TDD Pattern

- When fixing a bug, write a failing test first that reproduces the issue, then fix the code.
- **Flow**: Write test → verify it fails → fix code → verify test passes.
- This ensures the bug is actually fixed and prevents regressions.

## Logging

- Use Rails tagged logging with `self.class.name` for per-class log prefixes.
- **Good**: `logger.tagged(self.class.name) { logger.info("message") }`
- **Bad**: `logger.info("[Hardcoded::Class::Name] message")` or manual string interpolation
- Reasoning: Using `self.class.name` keeps log tags synchronized with actual class names automatically, supports nested tagging, and works consistently with Rails log formatting.
- Use `R3x::Concerns::Logger` - provides both instance and class method `logger` tagged with class name. `Rails.logger` is already `TaggedLogging` so just call `.tagged(name)` directly.
- For class methods: `extend R3x::Concerns::Logger` then call `logger.info(...)`
- For instance methods: `include R3x::Concerns::Logger` then call `logger.info(...)`
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

- When reading required environment variables, use `R3x::Env.fetch("KEY")` which rejects both missing and blank values.
- **Good**: `R3x::Env.fetch("VAULT_ADDR")`
- **Bad**: `ENV["VAULT_ADDR"].presence || raise(ArgumentError, "Missing VAULT_ADDR")` — use the helper instead of inline pattern
- **Bad**: `ENV["VAULT_ADDR"] || raise(ArgumentError, "Missing VAULT_ADDR")` — allows empty strings to pass through
- The helper lives in `lib/r3x/env.rb`. In Rails/Dotenv, misconfigured `.env` files often yield empty strings (e.g., `VAULT_ADDR=`), which are truthy but invalid. Failing fast with a clear error prevents confusing downstream failures.

## Object Design

- Prefer capability-based APIs over branching on symbolic types when behavior can be expressed through an object interface.
- **Good**: `triggers.select(&:cron_schedulable?)`
- **Bad**: `triggers.select { |t| t.type == :schedule }`
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
