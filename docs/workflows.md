# Workflow Writing Notes

These notes apply to workflow code in general.

`bin/workflow` boots Rails through the internal `workflow_cli` runtime profile.
That profile is headless: it skips the dashboard/Flightdeck web stack,
web-only gems, and app route registration, and it keeps
`ActionController::Base.include_all_helpers = false` so framework eager-load
does not scan app helpers. Unlike the slimmer `jobs` profile used by
`bin/jobs-worker` and `bin/jobs-scheduler`, `workflow_cli` still leaves
`lib/r3x/workflow/cli.rb` available for the Thor wrapper.

## Temporarily Disabling A Workflow

- To disable a workflow without deleting it, add a top-of-file pragma near the start of
  `workflow.rb`:

  ```ruby
  # r3x:disable Reason for disabling
  ```

- `R3x::Workflow::PackLoader` scans the first lines of each entrypoint and skips files with this
  pragma, so the workflow file is not `require`d, not registered, and not scheduled.
- Keep the pragma near the top of the file (before constants/classes) so it is easy to spot during
  reviews and maintenance.

## Workflows Are Jobs

- Workflows inherit from `R3x::Workflow::Base` and implement `#run`.
- `R3x::Workflow::Base` is an `ApplicationJob` and includes `ActiveJob::Continuable`.
- The current execution context is available as `ctx` on the workflow instance during `perform`, so
  helper methods can use it without threading it through every call.
- Use `step` around boundaries that should be resumable, such as external API calls, slow network
  work, or other distinct phases.
- Keep steps small and meaningful. A step should mark a real unit of progress, not just wrap every
  line.
- Use `condition` for high-level guards that must be true before `run` starts.
  Conditions are evaluated only on the initial execution, not when `ActiveJob::Continuable`
  resumes an isolated or interrupted step.

## Step Semantics

- `step` is a resumable boundary, not a value-return helper.
- Use `isolated: true` for steps that should run in their own execution after prior progress is
  serialized. Pair it with workflow-specific `resume_options` when the next step should run after a
  deliberate delay instead of blocking a worker with `sleep`.
- Do not assign the result of a `step` block to a variable and assume it is the block result.
- Put data-fetching logic in a normal helper, then use `step` around the resumable work that consumes
  that data. The helper must restore the same run input on resume; see
  [Stable Input Across Resumptions](#stable-input-across-resumptions).
- If you see `true.select` or `nil.select` in a workflow crash, check whether a `step` block was used
  as if it returned the fetched value.

  ```ruby
  # Good
  raw_events = events_for_run

  step :process_events do |step|
    process_events(Array.wrap(raw_events), step)
  end

  # Bad
  raw_events = step :fetch_events do
    fetch_from_apify
  end
  ```

`events_for_run` above is a workflow-owned helper, not a framework API. It loads or restores saved
input as described below. The [worked example](workflows/example_multi_step_digest.md) implements
this pattern in its `candidates` helper.

## Stable Input Across Resumptions

A resumed job runs `run` again. Continuable restores completed step names and the current step's
cursor; it does not automatically save local variables, arbitrary instance variables, or step block
results. Code outside steps runs again, and completed steps are skipped.

For example, a run fetches `[a, b, c]` and completes `process_event_0` for `a`. Before it resumes,
the source changes to `[c, b, a]`. If the workflow fetches again, it skips index 0 (`c`) because
`process_event_0` is already complete. It eventually processes `[a, b, a]`: `c` is lost and `a` is
attempted twice. An offset cursor into a changing list has the same problem.

For each resumable workflow, decide what belongs to one logical run:

- Preserve the selected items, their order, and any content needed by later steps. A saved list of
  IDs is enough only when reading those IDs later gives the intended content, or a fixed version.
  Do not rebuild membership from a live query or a fresh API response on resume.
- For a small, bounded JSON-compatible input, store it on the job and explicitly include it in
  `serialize` / `deserialize`, calling `super` in both methods. Serialization must read the stored
  value without fetching data: initial enqueue also serializes the job. Restore an empty list as
  an empty list, not as a signal to fetch again.
- For large inputs, durable results, or stronger recovery requirements, use an immutable run/batch
  record and pass its ID. Do not put clients, credentials, or downloaded image bodies in job data.
- Cursor positions and index-based step names require that fixed list. Naming steps after item IDs
  alone does not preserve list membership or content. Define a cursor as the next item to process:
  `step.set!(index + 1)` or `step.advance!(from: index)`, never `advance!(from: index + 1)`.
- Persist intermediate results that later steps need using the same rule. A memoized instance
  variable or an accumulator reset at the top of `run` does not survive deserialization on its own.

TTL caching reduces upstream calls; it does not preserve a run's input. Expiry, bucket rollover,
eviction, manual clearing, or `--skip-cache` can change the response. Cache the initial fetch when
useful, then save the selected input independently. Cross-run dedup markers also do not reconstruct
missing input or results.

Explicit job attributes are persisted when Active Job serializes a retry or continuation. Merely
assigning an instance variable or reaching a checkpoint does not synchronously write it to the
database. A hard kill before serialization can lose that execution's input and progress. External
delivery and saving progress are also separate operations: a crash between them can repeat delivery.
Use provider idempotency or durable delivery state when that is unacceptable; never promise
exactly-once delivery from `step` or `ctx.durable_set` alone.

When adding saved input or changing step/cursor meaning, account for queued jobs from the previous
code. Finish them on that code or cancel and restart them with explicit operator approval. Reject a
resumed payload missing required input instead of silently fetching a replacement list.

Before review, manually simulate interruption and JSON serialization/deserialization with external
requests blocked. Change source order and membership, clear the cache, then verify the remaining
original items and content are used. Include empty input and any old payload format affected by the
change. Use fixture workflows for framework regression tests; keep user workflow packs under the
existing manual verification policy.

Rails references: [custom job serialization](https://api.rubyonrails.org/v8.1.3/classes/ActiveJob/Core.html)
and [Continuable steps and cursors](https://api.rubyonrails.org/v8.1.3/classes/ActiveJob/Continuation.html).

## Conditions

Use `condition` for workflow-level preconditions that must be true before any work starts:

```ruby
condition :nobody_home?, reason: "Somebody is home"
```

The predicate is an instance method, so it can use `ctx` and workflow helpers. If the predicate
returns false, the workflow returns `{ "status" => "skipped", "reason" => reason }` and logs the
skip instead of calling `run`. Conditions do not run during Continuable resumes, so they are safe to
combine with delayed or isolated steps.

## Completion Callbacks

Use `on_complete` for tiny side effects that should happen only after the whole workflow succeeds:

```ruby
on_complete { ctx.client.healthchecks_io(HEALTHCHECK_UUID).ping }
```

Completion callbacks run after `run` returns and before the workflow logs `Workflow run completed`.
Blocks execute on the workflow instance, so they can use `ctx`, constants, and private workflow
helpers. Multiple callbacks run in declaration order.

`on_complete` does not run when `condition` skips the workflow, when `run` raises, or when
`ActiveJob::Continuable` interrupts before the full workflow completes. If a completion callback
raises, the workflow fails instead of logging a false success.

## Available Helpers

- `ctx`
  - The current workflow execution context.
  - Available during `perform` / `run`.
  - Use it to access clients and runtime data without passing context through every helper method.
- `step`
  - Marks a resumable boundary using `ActiveJob::Continuable`.
  - Use it around slow or externally dependent phases that should resume cleanly after interruption
    or retry.
  - Use `isolated: true` plus `resume_options = { wait: ... }` when the next step should be queued
    for later instead of sleeping inside the current job.
- `condition`
  - Declares a workflow-level guard that must return true before `run` on the initial execution.
  - Requires a positive predicate method and a human-readable reason for skipped runs.
- `on_complete`
  - Runs a block after successful full workflow completion.
  - Keep it for small final side effects, such as success healthcheck pings.
  - A raised callback error fails the workflow.
- `with_cache`
  - Wraps an expensive block in `Rails.cache` so repeated local runs can reuse the same result.
  - Good for slow, noisy, or hard-to-reproduce API calls while iterating on a workflow.
  - `bin/workflow run --skip-cache <path>` bypasses all `with_cache` blocks for that run without
    editing the workflow.
  - `R3X_SKIP_CACHE=true` does the same override at the env level in development; production boot
    rejects this global environment switch. The explicit CLI option remains available in production.
- Plain `with_cache` is development-only and raises in production.
- A plain cached value is reused for at most one day (`R3x::Workflow::Base::CACHE_TTL`); any edit to
  the workflow file rotates the cache key, so the next run recomputes immediately.
- `with_cache(key:, ttl:)` provides best-effort reuse within each period and works in all
  environments; see "Caching Policy" below. Use it for paid, rate-limited, or expensive external
  fetches — retries and resumed executions then reuse the cached value instead of repeating the call.
  `key:` is required and remains stable across workflow edits and deployments. The `ttl:` you pass
  replaces the default one-day lifetime entirely; it is not combined with it.
  - Use `with_cache(force: true)` when you need to refresh a stale cached value.
  - Use `with_cache(key: "name")` when multiple cache blocks share the same source line or when a
    stable human-readable discriminator makes the cached boundary clearer.
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

## Reusing HTTP Clients

- `ctx.client.http` returns a new instance of the HTTP client (`R3x::Client::Http`) on every call.
- When making requests in a loop, instantiate the client once outside the loop so timeout and SSL
  configuration is built once and the workflow code stays clear.
- **Good:**

  ```ruby
  http = ctx.client.http
  urls.map do |url|
    response = http.get(url)
    # ...
  end
  ```

- **Bad:**

  ```ruby
  urls.map do |url|
    response = ctx.client.http.get(url)
    # ...
  end
  ```

- For ad hoc batch work that benefits from a persistent HTTPX session, use
  `ctx.client.persistent_http` so connection lifecycle is explicit:

  ```ruby
  ctx.client.persistent_http(timeout: 30) do |http|
    urls.each { |url| http.get(url) }
  end
  ```

- Do not add `persistent:` options to thin clients such as Discord, Google Translate, Prometheus,
  or VictoriaLogs unless there is a measured hot path that performs many requests in one controlled
  scope.

## Example Workflow

See [example_multi_step_digest.md](workflows/example_multi_step_digest.md) for a
full worked example that combines `step`, `with_cache`, `ctx.durable_set`, structured LLM output,
and multiple `ctx.client.*` integrations in one workflow.

## Running Workflows Locally

Use `bin/workflow` for local workflow development. It boots Rails through the `workflow_cli` runtime
profile, loads the requested workflow file, and runs the workflow in-process.

```bash
export R3X_WORKFLOW_PATHS="$PWD/workflows"
bin/workflow list
bin/workflow info <workflow_key>
bin/workflow run workflows/<workflow_name>/workflow.rb
bin/workflow run --dry-run workflows/<workflow_name>/workflow.rb
bin/workflow run --skip-cache workflows/<workflow_name>/workflow.rb
bin/workflow run --skip-wait workflows/<workflow_name>/workflow.rb
```

For an included workflow in this checkout:

```bash
bin/workflow info porto_santo_news
bin/workflow run --dry-run workflows/porto_santo_news/workflow.rb
```

- `list` and `info` load workflow packs from `R3X_WORKFLOW_PATHS`.
- `run` always takes a direct path to a `workflow.rb` file.
- In `development` and `test`, `bin/workflow run` defaults to dry-run, so dry-run-aware clients avoid
  real side effects.
- `run` resumes `ActiveJob::Continuable` interruptions in-process until the workflow completes.
  For `isolated: true` steps it waits according to the workflow's `resume_options[:wait]`, matching
  queued execution.
- `--dry-run` explicitly enables dry-run for that run (`R3X_DRY_RUN=true`).
- `--no-dry-run` explicitly disables dry-run for that run (`R3X_DRY_RUN=false`), even in
  `development`.
- `--skip-cache` sets `R3X_SKIP_CACHE=true` for that run and bypasses all `with_cache` caching,
  including `ttl:` mode. It is an explicit one-run operator override and works in production.
- `--skip-wait` fast-forwards through local Continuable waits when debugging isolated steps.
- Use `--dry-run --skip-cache` together when you want a fresh, low-risk local run:

  ```bash
  bin/workflow run --dry-run --skip-cache workflows/<workflow_name>/workflow.rb
  ```

- To run with real delivery in `development`, use `--no-dry-run` or set `R3X_DRY_RUN=false`:

  ```bash
  R3X_DRY_RUN=false bin/workflow run workflows/<workflow_name>/workflow.rb
  ```

## Testing Workflows

Do NOT write tests for workflows under `workflows/` unless explicitly required! Workflows should be simple scripts containing minimal logic, relying on standard framework helpers and dry-run policies. For now, test workflows manually after writing them (e.g. using `bin/workflow run`).


## Local Secret Parity With Vault

For workflows that depend on real integration credentials, Vault gives local development strong
dev/prod parity. When local env points at the same Vault address and secret path as production, the
app can boot, log in to Vault, and hydrate `ENV` with the same secret names used by production pods.

That means you can test a workflow locally against the same credential contract that production
uses:

```bash
export R3X_VAULT_ADDR=http://vault.example.internal:8200
export R3X_VAULT_SECRETS_PATH=secret/data/env/r3x
export R3X_VAULT_AUTH_METHOD=kubernetes
export R3X_VAULT_KUBERNETES_ROLE=r3x

bin/workflow run --dry-run workflows/<workflow_name>/workflow.rb
```

The exact auth mode depends on your environment. Token auth is also supported for local operator
work:

```bash
export R3X_VAULT_ADDR=http://vault.example.internal:8200
export R3X_VAULT_TOKEN=<token>
export R3X_VAULT_SECRETS_PATH=secret/data/env/r3x
```

Keep the distinction clear:

- Vault parity means the same secret names and values can be loaded locally and in production.
- `bin/workflow run --dry-run` should still be the default local command for workflows with side effects.
- Dry run protects delivery behavior; Vault parity protects configuration drift.
- Use `just vault_check` to verify Vault connectivity and visible secret keys without printing
  secret values.
- See [docs/deployment.md#vault-secrets](./deployment.md#vault-secrets) for the full Vault setup.

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
- A normal `with_cache` key is derived from the workflow key, source file, source line, and file
  digest. If multiple `with_cache` calls share one line, the workflow raises and asks for separate
  lines or explicit `key:` values instead of silently reusing the wrong cache entry.
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

## Caching Policy

Three tools with disjoint responsibilities:

| Tool | Purpose | Works in production |
| --- | --- | --- |
| `with_cache` | Development iteration sugar: freeze an expensive or noisy boundary while iterating. The cached value is reused for at most one day (`Base::CACHE_TTL`), and any edit to the workflow file rotates the key so the next run recomputes immediately. | No (raises) |
| `with_cache(key:, ttl:)` | Best-effort runtime reuse for a named boundary within each period. Use for paid, rate-limited, or expensive external fetches. | Yes |
| `ctx.durable_set(name, ttl:)` | Cross-run dedup markers ("already processed"), not value caching. | Yes |

Decision guide:

- Should production reuse this result within a period? Use `with_cache(key:, ttl:)` — development
  gets the same reuse for free.
- Must production always execute fresh, but you need stability while iterating locally? Use plain
  `with_cache`.
- Remembering processed items across runs? Use `ctx.durable_set`.
- Must resumptions use the same input or intermediate result? Save it with the run; see
  [Stable Input Across Resumptions](#stable-input-across-resumptions). None of these cache tools
  provides that contract.

Anti-patterns:

- Do not stack plain `with_cache` and `with_cache(key:, ttl:)` around the same boundary.
- Do not use plain `with_cache` for paid API quotas; code outside `step` re-executes on every retry
  and resume. Use `ttl:` mode to reduce repeated calls in production.

How `ttl:` mode works: `key:` names a stable workflow boundary, and the runtime cache key adds the
TTL plus a time bucket (`now / ttl`). Workflow source edits do not rotate that key. `Rails.cache.fetch`
reuses the value while that bucket is present. Concurrent misses are not serialized, so overlapping
workers may both execute the block. This is intentionally best-effort; use provider idempotency or a
durable database-backed claim when duplicate upstream calls are unacceptable.

The cache write uses `expires_in: ttl`, while the bucket determines freshness. When Solid Cache is
configured, `ttl:` must not exceed its store-wide `max_age` in `config/cache.yml`, so normal cleanup
cannot evict the current bucket before its advertised period ends. As with any cache, manual clearing
or size-pressure eviction can still force recomputation. Buckets align to epoch windows, so two runs
straddling a boundary can both recompute; this is expected.

`R3X_SKIP_CACHE` / `bin/workflow run --skip-cache` bypass all workflow caching, including `ttl:`
mode. The environment switch is development-only and production boot rejects it. The CLI option is
an explicit one-run operator override and remains available in production.

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
- App logs use `plain` format by default. Set `R3X_LOG_FORMAT=json` for structured `level`,
  `message`, and `tags` fields and dashboard log correlation.
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
- This is the current convention because it keeps `schematist` off the boot path for workflows that do not use structured LLM output.
- Keep provider-specific schema constants out of workflow packs; the helper owns the Schematist integration.
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

The retry defaults are set in `app/lib/r3x/client/llm.rb` inside the `RubyLLM.context` block. RubyLLM
waits inside the current request between attempts, so these retries keep the worker occupied. Keep
them for short request-level recovery only.

The gem retries transient provider errors:

- `RubyLLM::RateLimitError` (HTTP 429)
- `RubyLLM::ServerError` (HTTP 500)
- `RubyLLM::ServiceUnavailableError` (HTTP 502-504)
- `RubyLLM::OverloadedError` (HTTP 529)
- Network timeouts and connection failures

After request-level retries are exhausted, `R3x::Client::Llm` translates these failures to
`R3x::Client::Llm::TransientError`. A workflow that expects a multi-minute outage should disable
request-level retries with `max_retries: 0` and use bounded Active Job `retry_on` backoff. This
returns the work to Solid Queue as a scheduled job instead of sleeping in a worker.

### Per-workflow override

If a particular workflow needs different short request-level retry behavior, pass overrides
directly to `ctx.client.llm(...)`:

```ruby
response = ctx.client.llm(
  api_key_env: "GEMINI_API_KEY_MICHAL",
  max_retries: 0
).message(
  model: "gemini-3-flash-preview",
  prompt: prompt
)
```

Any option passed this way overrides the default for that single `R3x::Client::Llm`
instance. Keep any enabled request-level retries short. Use workflow-level `retry_on` for
longer backoff that should return work to Solid Queue.

OpenAI-compatible provider aliases can carry their own RubyLLM routing defaults and are automatically resolved based on the API key environment variable name:

```ruby
response = ctx.client.llm(
  api_key_env: "OPENCODE_GO_API_KEY"
).message(
  model: "deepseek-chat",
  prompt: prompt
)
```

The provider is dynamically inferred from the environment variable name prefix (e.g. `OPENCODE_GO` to `:opencode_go`), routing the request through the lazy registered custom provider adapter while allowing the workflow to choose the exact token env variant (such as `OPENCODE_GO_API_KEY`, `OPENCODE_GO_API_KEY_PROJECTA`, or `OPENCODE_GO_API_KEY_PROJECTB`). Dynamic providers use RubyLLM's provider-level model assumption hook, so workflows can pass provider-specific model IDs without maintaining a static model registry.

## Return Value

- Do not design `#run` to return a special metadata hash, status object, or summary structure.
- If the last expression happens to return a value (for example an array from `filter_map` or the result of a helper), that is acceptable, but do not write `run` specifically to produce a return value unless the user explicitly asks for one.
- Workflows are side-effect driven: their purpose is to fetch data, transform it, and deliver it. Prefer logging and monitoring over return-value contracts.
- If a caller needs to observe what a workflow did, inspect the durable set, the logs, or the downstream system (Discord, email, API) rather than relying on a return value from `run`.
