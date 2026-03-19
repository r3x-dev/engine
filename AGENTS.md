# Instructions

This Rails app uses a small set of preferred libraries for common integration work. Follow these defaults for new code and agent-authored changes unless an existing subsystem already requires a different interface.

## Project Overview

- `r3x` is a Rails API app that acts as a Ruby-native workflow executor and automation engine.
- The high-level split is: framework/runtime code lives in the app and `lib/r3x/`, while user-defined workflows live under `workflows/`.
- Workflows are file-based, Git-friendly, and loaded into a database-backed runtime that uses Active Job + Solid Queue for execution and recurring scheduling.
- The default local UI surface is Mission Control Jobs mounted at `/jobs`; the root route redirects there.

## Codebase Map

- `lib/r3x/`: core framework code for the workflow DSL, trigger types, workflow loading, registry, execution context, recurring-task config, and shared DSL helpers.
- `lib/r3x/dsl/`: shared DSL infrastructure, especially validation concerns and configuration errors used by workflow-declared objects.
- `lib/r3x/trigger_collection.rb`: internal collection class that manages workflow triggers as a hash keyed by `unique_key`.
- `app/lib/r3x/`: runtime support code such as outputs, client wrappers, and shared concerns.
- `app/jobs/r3x/`: job entrypoints, especially `R3x::RunWorkflowJob`, which resolves and executes workflows, and `R3x::ChangeDetectionJob`, which evaluates change-detecting triggers before enqueueing workflow runs.
- `app/models/r3x/`: runtime support models such as `R3x::TriggerState` for per-trigger change-detection state.
- `workflows/`: user workflow packs. These are not the framework itself; they are loaded by the framework.
- `config/initializers/r3x_workflow_loader.rb`: boot-time workflow loading hook.
- `test/fixtures/workflows/`: fixture workflows for framework tests. Prefer these over hardcoding real workflows in tests.

## Runtime Flow

- Workflows subclass `R3x::Workflow`, declare triggers via the DSL, and implement `#run(ctx)`.
- Workflow-declared DSL objects must validate themselves before being registered; invalid DSL configuration should raise `R3x::ConfigurationError` with collected validation errors.
- `R3x::WorkflowPackLoader` discovers `workflow.rb` entrypoints from directories listed in `R3X_WORKFLOW_PATHS`, loads them, and registers their classes in `R3x::WorkflowRegistry`.
- `R3x::RecurringTasksConfig` turns schedulable workflow triggers into Solid Queue recurring-task definitions. All triggers have a `unique_key` (based on type + options hash) used for identification and duplicate detection.
- Change-detecting triggers are file-defined trigger objects that provide `cron`, `unique_key`, and `detect_changes(workflow_key:, state:)`. Their durable runtime state lives in `R3x::TriggerState`.
- `R3x::ChangeDetectionJob` loads the trigger, fetches/updates `R3x::TriggerState`, and only enqueues `R3x::RunWorkflowJob` when the trigger reports a change.
- `R3x::RunWorkflowJob` fetches the workflow from the registry, resolves the trigger by `trigger_key`, builds a `WorkflowContext`, and calls `workflow_class.new.run(ctx)`.
- Trigger discovery is filesystem-backed through `lib/r3x/triggers/*.rb`, so trigger file names, constants, and supported types must stay aligned.

## Maintenance Warning

- Keep this file synchronized with the real codebase. If you change workflow loading, trigger discovery, scheduling flow, top-level directory structure, namespaces, or the framework/user-workflow boundary, update the relevant `AGENTS.md` sections in the same change.
- In particular, update examples and notes here when changing files such as `lib/r3x/workflow.rb`, `lib/r3x/workflow_pack_loader.rb`, `lib/r3x/workflow_registry.rb`, `lib/r3x/recurring_tasks_config.rb`, `lib/r3x/triggers.rb`, `app/jobs/r3x/run_workflow_job.rb`, or `config/initializers/r3x_workflow_loader.rb`.
- Also update this file when changing the shared DSL validation contract in files such as `lib/r3x/dsl/validatable.rb`, `lib/r3x/configuration_error.rb`, or the base classes for workflow-declared objects.
- When adding a new subsystem or moving code between `lib/r3x/`, `app/lib/r3x/`, `app/jobs/r3x/`, or `workflows/`, refresh the project overview and codebase map so future agents can still orient themselves quickly.

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

- When a class is namespaced within a descriptive module (e.g., `R3x::Outputs`, `R3x::Triggers`), do not repeat the module name in the class name.
- **Good**: `R3x::Outputs::Discord`, `R3x::Triggers::Schedule`, `R3x::Client::Http`
- **Bad**: `R3x::Outputs::DiscordOutput`, `R3x::Triggers::ScheduleTrigger`
- Exception: When the class name would be ambiguous without the qualifier (e.g., `Http` clearly describes an HTTP client, but `DiscordWebhook` in the `Client` module might be needed to distinguish from `Discord` in `Outputs`).

### Zeitwerk & File Structure

- Adhere strictly to Zeitwerk's path-to-constant mapping: file names must match their defined constant exactly (snake_case to CamelCase).
- **Files**: `app/lib/r3x/client/http.rb` must define `R3x::Client::Http`.
- **Directories**: Directories represent namespaces. If a file is in `app/models/r3x/`, it must be wrapped in `module R3x`.
- **Acronyms**: Use standard inflection (e.g., `rss.rb` → `Rss`, `api_client.rb` → `ApiClient`) unless a custom inflection is explicitly defined in `config/initializers/inflections.rb`.
- **Validation**: Always ensure the filename and the class/module name are perfectly aligned to avoid `NameError` during autoloading.

### Autoloading

- Everything autoloaded by Rails (paths configured in `autoload_paths`, `autoload_lib`, etc.) is handled by Zeitwerk. You should never need to use `require` or `require_relative` for files within autoloaded paths.
- **Bad**: `require_relative "../validators/cron"` at the top of a file in `lib/r3x/triggers/`
- **Good**: Just reference `R3x::Validators::CronValidator` directly - Zeitwerk will find and load it automatically.
- The only exception is requiring external gems that don't auto-require their components.
- **Debugging**: If you get a `NameError` when referencing a class that should exist, it's likely a Zeitwerk autoloading issue (wrong file name, wrong constant name, or missing namespace). Check that file names match constants exactly (snake_case ↔ CamelCase).

## Testing

- When writing tests for workflow DSL or infrastructure, use generic workflow names (e.g., `TestWorkflow`, `MyTestWorkflow`), not real workflow names from `workflows/` folder.
- Real workflows in `workflows/` are "user workflows" and should not be hardcoded in tests for the core framework.
- Use anonymous classes or fixture workflows in `test/fixtures/workflows/` for testing framework behavior.
- **Good**: `Class.new(R3x::Workflow) { def self.name; "Test"; end }`
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

## Validators

- Place shared validation logic in `lib/r3x/validators/`.
- **Good**: `R3x::Validators::Cron`, `R3x::Validators::Url`
- **Bad**: `R3x::Triggers::Cron`, `R3x::Services::UrlChecker`
- Reasoning: Validators are reusable across triggers, services, and other components. Keep them in a dedicated namespace.
- Validators used with `validates_with` should inherit from `ActiveModel::Validator` and implement `validate(record)`.
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

- When reading required environment variables, use `.presence || raise` to reject both missing and blank values.
- **Good**: `ENV["VAULT_ADDR"].presence || raise(ArgumentError, "Missing VAULT_ADDR")`
- **Bad**: `ENV["VAULT_ADDR"] || raise(ArgumentError, "Missing VAULT_ADDR")` — allows empty strings to pass through
- Reasoning: In Rails/Dotenv, misconfigured `.env` files often yield empty strings (e.g., `VAULT_ADDR=`), which are truthy but invalid. Failing fast with a clear error prevents confusing downstream failures.

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

## Scope

- Apply these as defaults for new work.
- Do not rewrite existing code only to satisfy these preferences unless the task explicitly calls for that refactor.
