# Workflow Writing Notes

These notes apply to workflow code in general.

## Workflows Are Jobs

- Workflows inherit from `R3x::Workflow::Base` and implement `#run`.
- `R3x::Workflow::Base` is an `ApplicationJob` and includes
  `ActiveJob::Continuable`.
- The current execution context is available as `ctx` on the workflow
  instance during `perform`, so helper methods can use it without
  threading it through every call.
- Use `step` around boundaries that should be resumable, such as
  external API calls, slow network work, or other distinct phases.
- Keep steps small and meaningful. A step should mark a real unit of
  progress, not just wrap every line.

## Fail Fast

- Prefer letting workflows fail loudly.
- Avoid broad `rescue` blocks that hide the original problem.
- Only rescue when translating a known boundary error into a clearer
  domain failure or cleanup.

## Debugging And Caching

- Use `with_cache` for expensive, repeatable blocks while debugging or
  iterating.
- Good fits are calls that are slow, noisy, or hard to reproduce.
- When you're repeatedly running the same workflow during debugging,
  wrap the slowest API calls in `with_cache` temporarily so you can
  iterate faster.
- `with_cache` is for development and test; it raises in production so
  cached debug paths do not leak into live runs.
- Use `with_cache(force: true)` when you need to bypass a stale value.

## Logging

- Prefer `logger.debug { ... }` for debug logs so the message is lazy
  evaluated.
- Use block form when the log string is expensive to build or includes
  interpolated values.
- For `info`, `warn`, and `error`, use eager string logging when the
  message should always be emitted.

## LLM Output

- When a workflow expects structured LLM output, prefer `RubyLLM`
  schema support.
- Use a schema when you want JSON-like data back instead of parsing
  free-form text by hand.
- Keep the schema close to the prompt so the expected shape is obvious.

## Dry Run

- Side-effecting workflow helpers should support `dry_run` when it makes
  sense.
- Resolve defaults with `R3x::Policy.dry_run_for(:key, dry_run)`.
- Not every client supports dry run.
- If a client does not support it, say so clearly in the workflow or
  helper instead of assuming it will no-op.
