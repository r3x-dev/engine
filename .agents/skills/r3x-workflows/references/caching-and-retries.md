# Caching and retries

Read before wrapping an expensive boundary or changing retries.
Sources: [Base#with_cache](../../../../lib/r3x/workflow/base.rb),
[CacheKey](../../../../lib/r3x/workflow/cache_key.rb),
[DurableSet](../../../../lib/r3x/workflow/durable_set.rb),
[cache limits](../../../../config/cache.yml),
[Policy](../../../../lib/r3x/policy.rb).

## Choose one tool for each responsibility

| Need | Tool |
| --- | --- |
| Freeze an expensive/noisy call during local iteration only | Plain `with_cache` |
| Reuse a paid, rate-limited or expensive result in production | `with_cache(key:, ttl:)` |
| Remember completed items across runs, best-effort | `ctx.durable_set(name, ttl:)` |
| Preserve input/results for unfinished resumable work | Saved job attributes or an immutable run record |

Keep caching around a clear expensive boundary, not the whole workflow. Do not
nest plain and TTL cache modes around the same call. Use stable item identities
for completion markers and add them only after the required side effect succeeds.

Plain `with_cache` is development iteration support, available outside production
and raising in production. Its key includes workflow, source location and file digest;
source edits rotate it. Its lifetime is `Base::CACHE_TTL`. Calls sharing one source
line need distinct lines or explicit `key:` values; collisions raise.
An explicit key without `ttl:` is still plain mode.

TTL mode requires a nonblank explicit key and works in every environment. Its key
adds TTL and an epoch-aligned time bucket; source edits do not invalidate it.
`ttl:` replaces the plain-mode lifetime. Writes use `expires_in: ttl`; runs on
opposite sides of a bucket boundary can both recompute. `force: true` refreshes
an entry intentionally.

TTL must not exceed Solid Cache's store-wide `max_age`. Manual clearing, size
pressure and concurrent misses can still recompute; cache fetches do not serialize
upstream work. Use provider idempotency or durable claims if duplicate paid/API
calls are unacceptable. Never use caching as evidence that a run's input is stable.

`bin/workflow run --skip-cache <path>` bypasses all workflow cache modes.
The `R3X_SKIP_CACHE` environment switch is rejected at production boot; the CLI
option remains an explicit one-run operator override in production. Bypassing cache
may repeat paid calls and source reads; it is not a side-effect protection.

## Short request retries versus queued recovery

Use short request retries only for transient, safely repeatable boundaries. Prefer
existing client retry behavior; when a workflow needs its own short synchronous
retry, use the installed `retryable` gem instead of a manual rescue/retry loop.
Keep attempts and total waits bounded. Check its installed API rather than copying
a long option/default inventory into the pack.

Use workflow-level Active Job `retry_on` for multi-minute outages so Solid Queue
schedules recovery without sleeping in a worker. Use client-owned exception classes
and save content/intent before retry. Do not add explicit retries for authorization
or configuration failures. Do not add blanket retries for writes with unknown outcomes; see
[state and delivery](state-and-delivery.md).

`ActiveJob::Continuable` can also resume a job without `retry_on`: by default,
after a step completes or a cursor advances in the current execution, an ordinary
error can cause a new execution with the progress serialized. This includes
authorization and configuration errors, and can occur before `retry_on` handles
the error. Such a resume uses `resume_options` and `max_resumptions`, not that
`retry_on` handler's wait or attempts. Do not assume an error is immediately
fatal or an unfinished side effect will not run again. A checkpoint is not an
exactly-once guarantee. Check the installed Rails behavior and the workflow's
continuation settings when designing recovery.

For an external write with an unknown outcome, establish whether the user has
explicitly accepted duplicate risk for that specific operation. If the decision is
unclear and affects the solution, ask the user, explaining the possible duplicate
and the alternative of stopping for reconciliation. If duplicates are unacceptable,
use provider idempotency or a durable attempt guard recorded before the write that
stops repetition until the outcome is reconciled; if neither is available, report
the blocker. If duplicates are accepted, document the decision and its scope in the
owning workflow. Acceptance does not by itself authorize adding a new retry. Preserve
accepted intent across resumptions in either case.

## LLM retry

The [LLM client](../../../../app/lib/r3x/client/llm.rb) uses an isolated RubyLLM
context. Only `max_retries:` is exposed as a local retry override; omission/nil
inherits SDK behavior, zero disables SDK retries, and changes affect only that
client. Provider options can also be configured in its context block.

RubyLLM owns current retry defaults, intervals, backoff and provider error handling;
read installed SDK behavior if those values matter. Request retries occupy the
worker and are not a total request deadline. HTTP latency/timeouts and provider
retry headers add time.

For scheduled recovery, set `max_retries: 0` and use bounded `retry_on` for
`R3x::Client::Llm::TransientError`. The client translates transient rate-limit,
server/overload and network failures after SDK retries are exhausted. Authentication
and invalid-response failures propagate. Choose the queue budget in the owning
pack; slow generation alone does not justify resending an in-flight request.
