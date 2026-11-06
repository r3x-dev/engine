# Runtime and structure

Read before adding a pack or changing its loading, scheduling or lifecycle.
Sources: [Base](../../../../lib/r3x/workflow/base.rb),
[DSL](../../../../lib/r3x/workflow.rb),
[PackLoader](../../../../lib/r3x/workflow/pack_loader.rb),
[entrypoints](../../../../lib/r3x/workflow/entrypoint.rb),
[runtime profiles](../../../../config/runtime_profile.rb).

## Pack ownership and loading

- Put workflow entrypoints in a catalog's `<pack>/workflow.rb`, subclass
  `R3x::Workflow::Base`, declare triggers with the DSL and implement `run`.
  The engine owns reusable protocols/clients; packs own source-specific payloads.
- Catalog entrypoints load from `R3X_WORKFLOW_PATHS`. Use `bin/workflow list` /
  `info <key>` for discovery, not static job discovery. The CLI's `run` command
  requires a direct path to `workflow.rb`.
- Catalog-dependent processes require existing directories with at least one
  entrypoint. The registry is replaced only after all enabled entrypoints load;
  loading errors preserve the previous registry and stop schedule synchronization.
  `PackLoader.load!(rebuild_registry: true)` still uses Ruby `require`; it is not
  same-process source reload.
- To disable a pack, put `# r3x:disable Reason for disabling` near the top of its
  entrypoint. The loader skips its require, registration and scheduling.
- Worker/scheduler and workflow CLI profiles are headless. They skip routes, the
  web-only gem group and app helper scanning; the CLI profile retains its CLI class.
  Do not enable the web stack merely to use a helper in a workflow.
- Renaming/removing a class can strand queued jobs serialized with its old name.
  Inspect pending jobs and explicitly reconcile old work before rollout.

## Steps and lifecycle

Workflow instances are real `ApplicationJob`s with `ActiveJob::Continuable`.
Use `ctx` for execution data and client access; it is available during `perform`
and `run`, not as a boot-time configuration object. Do not override `perform`.

Use `step` for actual resumable work boundaries. Do not assign its return value:

```ruby
events = events_for_run
step :process_events do |step|
  process_events(events, step)
end
```

`events_for_run` and `process_events` are pack-owned methods, not engine APIs.
Before writing them, read [state and delivery](state-and-delivery.md): the original
input must survive resume even if an upstream source changes.

Use `isolated: true` when a step should run in a separate execution after previous
progress is serialized. Pair it with workflow-specific `resume_options` for queued
waits instead of sleeping inside a worker. Keep steps meaningful rather than
wrapping every line. If a workflow sees `true.select` or `nil.select`, inspect
whether it mistook a step result for source data.

`condition :eligible?, reason: "Not eligible"` uses an instance predicate and runs
only on initial execution. A false result skips the run and logs the reason;
conditions are not reevaluated on a continuation.

Use `on_complete` only for small final side effects, such as an authorized success
ping. Callbacks run in declaration order after `run` returns successfully. They
do not run when a condition skips, execution raises or Continuable interrupts.
A callback failure fails the workflow.

Do not design `run` around a special return/status hash unless explicitly asked.
Its incidental return value is allowed; observe completion through logs, saved
state and actual downstream results.

## Scheduling

Check the [schedule trigger](../../../../lib/r3x/triggers/schedule.rb) when changing
timezone handling. `timezone:` accepts IANA or Rails names and normalizes Rails
names. Choose either an explicit timezone argument or a timezone embedded in cron;
specifying both fails. Otherwise `R3X_TIMEZONE` supplies the default; a timezone
already embedded in cron takes precedence over that environment default.

Scheduling requires a prepared database. Keep preparation at the existing setup /
entrypoint boundary; do not hide missing queue tables or schedule-sync failures.
