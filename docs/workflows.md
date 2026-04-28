# Workflow Writing Notes

These notes apply to workflow code in general.

`bin/workflow` boots Rails through the internal `workflow_cli` runtime profile.
That profile is headless: it skips the dashboard/Mission Control web stack,
web-only gems, and app route registration, and it keeps
`ActionController::Base.include_all_helpers = false` so framework eager-load
does not scan app helpers. Unlike the slimmer `jobs` profile used by
`bin/jobs-worker` and `bin/jobs-scheduler`, `workflow_cli` still leaves
`lib/r3x/workflow/cli.rb` available for the Thor wrapper.

## Workflows Are Jobs

- Workflows inherit from `R3x::Workflow::Base` and implement `#run`.
- `R3x::Workflow::Base` is an `ApplicationJob` and includes `ActiveJob::Continuable`.
- The current execution context is available as `ctx` on the workflow instance during `perform`, so
  helper methods can use it without threading it through every call.
- Use `step` around boundaries that should be resumable, such as external API calls, slow network
  work, or other distinct phases.
- Keep steps small and meaningful. A step should mark a real unit of progress, not just wrap every
  line.

## Step Semantics

- `step` is a resumable boundary, not a value-return helper.
- Do not assign the result of a `step` block to a variable and assume it is the block result.
- Put data-fetching logic in a normal helper, then use `step` around the resumable work that consumes
  that data.
- If you see `true.select` or `nil.select` in a workflow crash, check whether a `step` block was used
  as if it returned the fetched value.

  ```ruby
  # Good
  raw_events = fetch_from_apify

  step :process_events do |step|
    process_events(Array.wrap(raw_events), step)
  end

  # Bad
  raw_events = step :fetch_events do
    fetch_from_apify
  end
  ```

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
- `ctx.durable_set(name = :default, ttl: 90.days)`
  - Returns a workflow-scoped durable set backed by `Rails.cache`.
  - Good for remembering which items were already processed, sent, uploaded, or otherwise handled
    across workflow runs.
  - Members are scoped by workflow key and set name, so different workflows and different sets do
    not collide.
  - When the app uses `:solid_cache_store`, custom `ttl:` values must not exceed
    `config/cache.yml` `store_options.max_age`.
  - Use `include?`, `add`, and `delete` on the returned set.
- Prefer this for best-effort dedup across runs; prefer a real table only when you need permanent
  history or hard uniqueness guarantees.

## Inline Parsing

- For small extraction chains, prefer `presence` and chained fallbacks over repeated `blank?`
  branches.
- Keep simple parsing close to the data source unless the logic is genuinely reusable.
- Good:

  ```ruby
  body = normalize_text(node.at_xpath("./description")&.inner_html).presence ||
    normalize_text(node.at_xpath("./encoded")&.inner_html).presence ||
    normalize_text(node.at_xpath("./title")&.text)
  ```

- Bad:

  ```ruby
  body = normalize_text(node.at_xpath("./description")&.inner_html)
  body = normalize_text(node.at_xpath("./encoded")&.inner_html) if body.blank?
  body = normalize_text(node.at_xpath("./title")&.text) if body.blank?
  ```

## Fail Fast

- Prefer letting workflows fail loudly.
- Avoid broad `rescue` blocks that hide the original problem.
- Only rescue when translating a known boundary error into a clearer domain failure or cleanup.

## Debugging And Caching

- Prefer `with_cache` only around clearly expensive or noisy calls, not around the whole workflow.
- Prefer `ctx.durable_set` for cross-run item dedup, not `with_cache`.
- The normal workflow is:
  - add `with_cache` around the slowest boundary while iterating
  - use `bin/workflow run --skip-cache <path>` when you want a fresh uncached run
  - leave the helper in place if it remains useful for future debugging
- For durable dedup, use a stable member key from the item itself, such as a URL digest or external
  post ID, and add it only after the relevant side effect succeeds.
- If a cached block becomes confusing or hides too much behavior, remove it instead of stacking more
  flags or conditions around it.
- When a workflow suddenly sees a boolean or `nil` where an array should be, inspect the nearest
  `step` boundary first before blaming the external API.

## Schedule Timezones

- `trigger :schedule` accepts an optional `timezone:`.
- Timezones may be IANA names like `Europe/Paris` or Rails names like `Pacific Time (US & Canada)`.
- Rails-style names are normalized to canonical TZInfo names before scheduling.
- If `timezone:` is omitted, `R3X_TIMEZONE` is used when present.
- If the cron string already embeds a timezone, that embedded timezone wins over `R3X_TIMEZONE`.
- Use one of these styles, not both:

  ```ruby
  trigger :schedule, cron: "every day at 9am Europe/Paris"
  ```

  ```ruby
  trigger :schedule, cron: "every day at 9am", timezone: "Europe/Paris"
  ```

- If both `timezone:` and the cron string specify timezones, configuration fails fast.

## Logging

- Prefer `logger.debug { ... }` for debug logs so the message is lazy evaluated.
- Use block form when the log string is expensive to build or includes interpolated values.
- For `info`, `warn`, and `error`, use eager string logging when the message should always be
  emitted.
- Workflow execution already carries tagged context such as `r3x.run_active_job_id` and `r3x.trigger_key`
  for indexed log correlation in the dashboard. Orchestration jobs also tag lines with `r3x.workflow_key`
  where that broader workflow-level context is useful. Prefer logging through the existing Rails logger so
  those tags stay attached to emitted lines.
- App logs are always emitted as structured JSON with explicit `level`, `message`, and `tags`.
- Dashboard run logs read the explicit `level` from structured log payloads. They do not infer levels
  from free-form message text.

### Pretty-Printing Hashes And Structures

- When logging hashes or structured data, avoid manually interpolating individual fields.
- `amazing_print` is preloaded globally — you can call `.ai(...)` on any object without adding
  `require "amazing_print"` yourself.
- Use `.ai(plain: true)` so keys are aligned and output is readable, without ANSI colour codes
  that clutter log files.

  ```ruby
  # Good
  logger.info("Camera check result:\n#{result.ai(plain: true)}")

  # Bad
  logger.info("Checked camera #{url}, result: #{result["status"]}, description: #{result["description"]}")
  ```

- If the structure is large, consider logging it on `debug` instead of `info`.

## LLM Output

- When a workflow expects structured LLM output, prefer `RubyLLM` schema support.
- Use a schema when you want JSON-like data back instead of parsing free-form text by hand.
- Keep the schema close to the prompt so the expected shape is obvious.
- Define new workflow schemas with `R3x::Workflow::LlmSchema.define`.
- This is the current convention because it keeps `ruby_llm-schema` off the boot path for workflows that do not use structured LLM output.
- Older direct inheritance from `RubyLLM::Schema` still works, but treat it as legacy in new code.
- For nested JSON, define the shape with `array` and `object` blocks inside the helper block,
  then pass that schema to `message(...)`.
- Read the parsed structured result from `response.content`; avoid manual JSON parsing when the
  schema already captures the shape.

  ```ruby
  WeeklyDigestSchema = R3x::Workflow::LlmSchema.define do
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
- Prefer `Retryable.retryable(...)` over manual `begin/rescue/retry` loops in workflow code.
- Use it for HTTP requests, API calls, file downloads, or any operation where transient failures
  are expected and safe to retry.
- Basic usage:

  ```ruby
  Retryable.retryable(tries: 3, on: [HTTPX::TimeoutError, HTTPX::ConnectionError]) do
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
  Retryable.retryable(tries: 4, on: HTTPX::HTTPError) do |retries, exception|
    logger.debug { "Attempt #{retries} failed: #{exception}" } if retries > 0
    http.get("/endpoint")
  end
  ```

- For logging retries, use `log_method`:

  ```ruby
  log_method = lambda do |retries, exception|
    logger.debug { "[Attempt ##{retries}] Retrying: #{exception.class} - #{exception.message}" }
  end

  Retryable.retryable(tries: 3, on: HTTPX::TimeoutError, log_method: log_method) do
    http.get("/endpoint")
  end
  ```

- Avoid retrying operations that are not idempotent or that cause external side effects (e.g.
  sending emails, creating records) unless the remote API guarantees idempotency.
- Full documentation: https://github.com/nfedyashev/retryable

## LLM Retry

`ruby_llm` has built-in automatic retry through its Faraday middleware. Defaults are applied
per `RubyLLM::Context` inside `R3x::Client::Llm`, so every workflow run gets an isolated copy.
Processes that never call `ctx.client.llm` do not load the gem at all.

The retry defaults are set in `app/lib/r3x/client/llm.rb` inside the `RubyLLM.context` block.
Only `retry_interval` has a project-level override (the gem default is `0.1`); everything else uses the gem defaults.

This means the first retry waits 60 seconds, the second waits 120 seconds, then it gives up.
The gem automatically retries on transient provider errors:

- `RubyLLM::RateLimitError` (HTTP 429)
- `RubyLLM::ServerError` (HTTP 500)
- `RubyLLM::ServiceUnavailableError` (HTTP 502-504)
- `RubyLLM::OverloadedError` (HTTP 529)
- Network timeouts and connection failures

### Per-workflow override

If a particular workflow needs different retry behavior, pass overrides directly to
`ctx.client.llm(...)`:

```ruby
response = ctx.client.llm(
  api_key_env: "GEMINI_API_KEY_MICHAL",
  max_retries: 5,
  retry_interval: 30.0
).message(
  model: "gemini-3-flash-preview",
  prompt: prompt
)
```

Any option passed this way overrides the default for that single `R3x::Client::Llm`
instance. The rest of the call stays the same -- the retry is handled transparently by
`ruby_llm`.

## Return Value

- Do not design `#run` to return a special metadata hash, status object, or summary structure.
- If the last expression happens to return a value (for example an array from `filter_map` or the result of a helper), that is acceptable, but do not write `run` specifically to produce a return value unless the user explicitly asks for one.
- Workflows are side-effect driven: their purpose is to fetch data, transform it, and deliver it. Prefer logging and monitoring over return-value contracts.
- If a caller needs to observe what a workflow did, inspect the durable set, the logs, or the downstream system (Discord, email, API) rather than relying on a return value from `run`.
