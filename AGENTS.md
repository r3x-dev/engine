# Instructions

This Rails app uses a small set of preferred libraries for common integration work. Follow these defaults for new code and agent-authored changes unless an existing subsystem already requires a different interface.

## JSON

- Prefer `MultiJson` for JSON parsing and serialization work.
- Reasoning: it gives the app one consistent JSON abstraction instead of scattering direct `JSON` stdlib usage across the codebase, which makes adapter swaps and shared conventions easier later.

## HTTP

- Prefer `Faraday` for outbound HTTP and API integrations.
- Reasoning: it is already a direct project dependency and gives us a standard place for middleware, retries, authentication, adapters, and test stubbing instead of ad hoc HTTP clients.
- **JSON handling**: When making HTTP requests that send/receive JSON, use Faraday's built-in `:json` middleware (available via `faraday` gem 2.0+) instead of manually serializing with `MultiJson`. Configure the connection with `f.request :json` and `f.response :json` - this automatically sets the Content-Type header and handles request/response body serialization.
  - **Bad**: `request.body = MultiJson.dump({"key" => "value"})`
  - **Good**: `connection.post(url, { key: "value" })` with `f.request :json` middleware

## Naming Conventions

- When a class is namespaced within a descriptive module (e.g., `R3x::Outputs`, `R3x::Triggers`), do not repeat the module name in the class name.
- **Good**: `R3x::Outputs::Discord`, `R3x::Triggers::Schedule`, `R3x::Services::HttpClient`
- **Bad**: `R3x::Outputs::DiscordOutput`, `R3x::Triggers::ScheduleTrigger`
- Exception: When the class name would be ambiguous without the qualifier (e.g., `HttpClient` clearly describes an HTTP client, but `Discord` in the `Services` module might need to be `DiscordWebhookClient` to distinguish from `Discord` in `Outputs`).

### Zeitwerk & File Structure

- Adhere strictly to Zeitwerk's path-to-constant mapping: file names must match their defined constant exactly (snake_case to CamelCase).
- **Files**: `lib/r3x/services/http_client.rb` must define `R3x::Services::HttpClient`.
- **Directories**: Directories represent namespaces. If a file is in `app/models/r3x/`, it must be wrapped in `module R3x`.
- **Acronyms**: Use standard inflection (e.g., `rss.rb` → `Rss`, `api_client.rb` → `ApiClient`) unless a custom inflection is explicitly defined in `config/initializers/inflections.rb`.
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
- **Good**: `Class.new(R3x::Workflow) { def self.name; "Test"; end }`
- **Bad**: Testing `MyUserWorkflow` workflow directly in framework tests

## Logging

- Use Rails tagged logging with `self.class.name` for per-class log prefixes.
- **Good**: `logger.tagged(self.class.name) { logger.info("message") }`
- **Bad**: `logger.info("[Hardcoded::Class::Name] message")` or manual string interpolation
- Reasoning: Using `self.class.name` keeps log tags synchronized with actual class names automatically, supports nested tagging, and works consistently with Rails log formatting.

## Validators

- Place shared validation logic in `lib/r3x/validators/`.
- **Good**: `R3x::Validators::Cron`, `R3x::Validators::Url`
- **Bad**: `R3x::Triggers::CronValidator`, `R3x::Services::UrlChecker`
- Reasoning: Validators are reusable across triggers, services, and other components. Keep them in a dedicated namespace.
- Pattern: Each validator should expose a `validate!(value, field_name: "field")` class method that raises `ArgumentError` on invalid input.

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
