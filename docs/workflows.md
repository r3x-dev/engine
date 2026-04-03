# Workflow Writing Notes

These notes apply to workflow code in general.

## Workflows Are Jobs

- Workflows inherit from `R3x::Workflow::Base` and implement `#run`.
- `R3x::Workflow::Base` is an `ApplicationJob` and includes `ActiveJob::Continuable`.
- The current execution context is available as `ctx` on the workflow instance during `perform`, so
  helper methods can use it without threading it through every call.
- Use `step` around boundaries that should be resumable, such as external API calls, slow network
  work, or other distinct phases.
- Keep steps small and meaningful. A step should mark a real unit of progress, not just wrap every
  line.

## Available Helpers

- `ctx`
  - The current workflow execution context.
  - Available during `perform` / `run`.
  - Use it to access clients and runtime data without passing context through every helper method.
- `step`
  - Marks a resumable boundary using `ActiveJob::Continuable`.
  - Use it around slow or externally dependent phases that should resume cleanly after interruption
    or retry.
- `with_cache`
  - Wraps an expensive block in `Rails.cache` so repeated local runs can reuse the same result.
  - Good for slow, noisy, or hard-to-reproduce API calls while iterating on a workflow.
  - `bin/workflow run --skip-cache <path>` bypasses all `with_cache` blocks for that run without
    editing the workflow.
  - `R3X_SKIP_CACHE=true` does the same override at the env level.
  - In production, `with_cache` still raises by default unless `R3X_SKIP_CACHE=true` is set.
  - Use `with_cache(force: true)` when you need to refresh a stale cached value.

## Fail Fast

- Prefer letting workflows fail loudly.
- Avoid broad `rescue` blocks that hide the original problem.
- Only rescue when translating a known boundary error into a clearer domain failure or cleanup.

## Debugging And Caching

- Prefer `with_cache` only around clearly expensive or noisy calls, not around the whole workflow.
- The normal workflow is:
  - add `with_cache` around the slowest boundary while iterating
  - use `bin/workflow run --skip-cache <path>` when you want a fresh uncached run
  - leave the helper in place if it remains useful for future debugging
- If a cached block becomes confusing or hides too much behavior, remove it instead of stacking more
  flags or conditions around it.

## Logging

- Prefer `logger.debug { ... }` for debug logs so the message is lazy evaluated.
- Use block form when the log string is expensive to build or includes interpolated values.
- For `info`, `warn`, and `error`, use eager string logging when the message should always be
  emitted.

## LLM Output

- When a workflow expects structured LLM output, prefer `RubyLLM` schema support.
- Use a schema when you want JSON-like data back instead of parsing free-form text by hand.
- Keep the schema close to the prompt so the expected shape is obvious.
- For nested JSON, define the shape with `array` and `object` blocks on a `RubyLLM::Schema` class,
  then pass that schema to `message(...)`.
- Read the parsed structured result from `response.content`; avoid manual JSON parsing when the
  schema already captures the shape.

  ```ruby
  class WeeklyDigestSchema < RubyLLM::Schema
    array :EN do
      object :entry do
        string :name
        string :location
        string :date_time
      end
    end

    array :PT do
      object :entry do
        string :name
        string :location
        string :date_time
      end
    end
  end
  ```

## Dry Run

- Side-effecting workflow helpers should support `dry_run` when it makes sense.
- Resolve defaults with `R3x::Policy.dry_run_for(:key, dry_run)`.
- Not every client supports dry run.
- If a client does not support it, say so clearly in the workflow or helper instead of assuming it
  will no-op.

## Retry Fragile Operations

- Network calls and other flaky external interactions should be wrapped with the `retryable` gem
  (already in the Gemfile).
- Use it for HTTP requests, API calls, file downloads, or any operation where transient failures
  are expected and safe to retry.
- Basic usage:

  ```ruby
  Retryable.retryable(tries: 3, on: [Faraday::TimeoutError, Faraday::ConnectionFailed]) do
    connection.get("/api/data").body
  end
  ```

- Common options:
  - `tries` — total attempts (default 2). Set to `3` for two retries.
  - `on` — exception class or array of classes to catch (default `StandardError`).
  - `sleep` — seconds between retries (default 1). Use `0` to skip pauses, or a lambda
    for exponential backoff: `lambda { |n| 4**n }`.
  - `matching` — retry based on exception message: `matching: /timeout/i`.
  - `not` — exceptions that should never be retried, takes precedence over `on`.

- Block receives two optional arguments: retry count so far and the last exception:

  ```ruby
  Retryable.retryable(tries: 4, on: Faraday::ServerError) do |retries, exception|
    logger.debug { "Attempt #{retries} failed: #{exception}" } if retries > 0
    http.get("/endpoint")
  end
  ```

- For logging retries, use `log_method`:

  ```ruby
  log_method = lambda do |retries, exception|
    logger.debug { "[Attempt ##{retries}] Retrying: #{exception.class} - #{exception.message}" }
  end

  Retryable.retryable(tries: 3, on: Faraday::TimeoutError, log_method: log_method) do
    http.get("/endpoint")
  end
  ```

- Avoid retrying operations that are not idempotent or that cause external side effects (e.g.
  sending emails, creating records) unless the remote API guarantees idempotency.
- Full documentation: https://github.com/nfedyashev/retryable
