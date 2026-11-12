# State and delivery

Read before introducing resumptions, deduplication, reservations or delivery changes.
Sources: [Base](../../../../lib/r3x/workflow/base.rb),
[DurableSet](../../../../lib/r3x/workflow/durable_set.rb),
[Delivery](../../../../app/lib/r3x/client/delivery.rb),
[worked example](../../../../docs/workflows/example_multi_step_digest.md).

## Stable input across resumptions

A resumed job runs `run` again and skips completed steps. Continuable saves step
names and cursors; it does not automatically persist arbitrary instance variables,
locals or block results. Code outside completed steps runs again.

Save the original membership, order and content required by the logical run before
applying a saved cursor. Refetching `[a, b, c]` as `[c, b, a]` and reusing index 1
can lose `c` and process `a` twice. Item IDs alone do not preserve membership; IDs
also need versioned content if the original text must remain stable.

- For a small bounded JSON-compatible snapshot, explicitly serialize/deserialize job
  attributes and call `super` in both methods. Serialization must not fetch data:
  initial enqueue serializes too. Preserve an empty saved list as empty.
- Use an immutable run/batch record and an ID for large input, durable results or
  stronger recovery. Do not serialize clients, credentials or downloaded image bodies.
- Persist required intermediate results and accepted classification/delivery intent.
  Reclassification on resume must not turn unfinished delivery into a completed skip.
- Store the next index with `step.set!(index + 1)` or `step.advance!(from: index)`;
  `advance!(from: index + 1)` skips an item.
- Bound snapshot size and resumptions. A per-page API limit does not bound all pages;
  never silently drop data to fit a job snapshot.

TTL caching and cross-run markers do not preserve a run's input. Save the snapshot
independently of cache expiry, time-bucket changes, eviction and `--skip-cache`.

Job attributes become persisted when Active Job serializes a continuation/retry.
Assignment or a checkpoint is not a synchronous durable write. A kill before
serialization can lose the execution's progress, and a kill between provider
acceptance and saving progress can repeat delivery. Never promise exactly-once
delivery from steps or cache markers.

When changing state/cursor meaning, inspect old queued payloads. Finish them on
their original code or reconcile/cancel/restart with explicit operator approval.
Reject a resumed payload missing required input rather than silently refetching it.

Before review, manually simulate JSON serialize/deserialize with external requests
blocked: change source membership/order, evict cache, and change model classification.
Verify remaining original input, content and accepted intent are used. Include
empty input, affected old payloads and snapshot limits. In-process restore does not
prove durable queue persistence or hard-kill recovery.

## Completion markers and processing reservations

Write completion only after all required work succeeds or a legitimate final skip
is accepted. Use stable item-derived keys, such as an external ID or URL digest.
Adding completion before a download, classification or send can suppress retries.

Keep temporary reservations separate from completion. A busy item remains unfinished
and must retry later; an early return must not complete it. Recheck completion after
acquiring a reservation. Acquire delivery reservations after preparation/classification
so those failures do not block behind their own reservation.

`ctx.durable_set(name, ttl:)` is workflow/set-scoped cache-backed best-effort dedup,
not permanent history or hard uniqueness. Choose TTLs for actual timeouts/retries and
keep them within the cache store's maximum age. Its `add?` supports a best-effort
reservation but has no owner token or compare-and-delete. Let reservations expire;
a cleanup delete can remove a newer owner's reservation. Eviction, concurrent
acquisition and work outliving TTL can allow overlap.

If exclusivity or nonduplicated upstream calls are required, use provider idempotency
or durable owner-checked database state. Preserve valid old completion history when
correcting marker semantics; reconcile abandoned entries separately.

## Pipelines with multiple deliveries

Decide which destinations are required and which are optional. Save prepared input,
final subject/text/HTML and accepted delivery intent. Required delivery and source
acknowledgment belong in separate isolated steps so acknowledgment failure does not
resend completed content.

Check each required client's actual delivery result before marking completion or
acknowledging the source. A skipped write or completed dry-run step is not delivery.
Do not make required confirmation depend on an optional backup.

Gmail and Discord return `R3x::Client::Delivery`: check `delivered?` and handle
`dry_run?` explicitly; reject unexpected results. `message` retains the provider
response and is nil for dry run. A nonblank message ID is required for reported
delivery; Discord requests confirmation with `wait=true`. Provider acceptance
does not prove recipient delivery or reading. Save a JSON-compatible delivery flag
when needed rather than serializing the result object.

Use client-owned transient errors for bounded queue retries, such as Gmail's
`R3x::Client::Google::Gmail::TransientError`; do not add explicit retries for
authentication/configuration errors. Do not refer to lazy SDK error constants in
workflow declarations. Before adding or changing a resumable step with side effects
or adding retry behavior, read [caching and retries](caching-and-retries.md) for
the automatic Continuable resume boundary.

Before repeating an external write, establish provider idempotency or an explicit
response contract proving no required write happened, or reconcile the unknown
outcome. The exception is when the user explicitly accepts duplicate risk for that
operation; follow [caching and retries](caching-and-retries.md#short-request-retries-versus-queued-recovery)
for that decision. A later run can also repeat unfinished work; queue retries alone
do not close that boundary.

After required work succeeds, optional copies can share a final phase with source
acknowledgment. Bound each optional call with a short total timeout. Catch/log
ordinary errors only around that optional boundary without hiding required failures.
Avoid separate optional retry/marker machinery without a product requirement.

For Feedway, check the [client](../../../../app/lib/r3x/client/feedway.rb) for its
publish contract. Optional `feed:` selects a slug; omitting it leaves an unassigned
entry visible in the aggregate feed, not a named default. Optional `data_json:`
adds native JSON alongside HTML. These capabilities do not select required destinations.

Manually verify required delivery failure, acknowledgment retry and optional-backup
failure. The first retries only safely transient failures within its budget; the
second does not resend completed content; the third does not fail the run. Inspect
old attempted jobs before upgrading: manual queue retry can retain original arguments
and reset execution counters. Neither an empty continuation nor `executions == 0`
proves that nothing was delivered.
