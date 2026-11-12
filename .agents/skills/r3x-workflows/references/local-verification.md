# Local verification

Read before local execution or validating a pack. Sources:
[CLI](../../../../lib/r3x/workflow/cli.rb), [Policy](../../../../lib/r3x/policy.rb),
[environment](../../../../docs/environment.md),
[Vault setup](../../../../docs/deployment.md#vault-secrets),
[test image](../../../../Dockerfile).

## Select execution and dry-run policy first

`bin/workflow` boots Rails headlessly and runs in-process. Discovery uses the
catalog path; execution takes an entrypoint path:

```sh
export R3X_WORKFLOW_PATHS="$PWD/workflows"
bin/workflow list
bin/workflow info example_digest
bin/workflow run --dry-run workflows/example_digest/workflow.rb
```

Use a real catalog path and pack name; the example is fictional. The CLI uses the
Active Job callback and exception-handler lifecycle, including `retry_on` and
Continuable's recovery after progress. Retries and continuations of the running
instance are serialized/restored in-process, with their requested waits and limits.
`--skip-wait` fast-forwards those local waits; it is not evidence of real queue
timing. Local execution has no durable queue persistence or Solid Queue concurrency
controls. Separate explicit `perform_later` calls still use the configured backend,
including calls on the same workflow class.

New side effects should default dry. Resolve client/helper defaults through
`R3x::Policy.dry_run_for(:key, dry_run)`. Development/test defaults are dry;
per-feature configuration can permit real writes when global dry run is not enabled.

`--dry-run` and `R3X_DRY_RUN=true` establish global dry run across resumptions.
Neither per-feature env nor per-call `dry_run: false` overrides it. Reads, paid
generation and clients without dry-run support retain their behavior. Check each
affected boundary before running; do not assume a dry run is free or offline.

`--no-dry-run` / `R3X_DRY_RUN=false` allow a real-write default; feature-specific
policies still apply. CLI flags override global env for that run. CLI messages show
configuration/exceptions, not the integrations actually called or proof of delivery.

For intentionally fresh reads, combine `--dry-run --skip-cache`. Cache bypass can
repeat paid/model calls. Do not run real delivery merely to validate documentation
or prove rollout readiness.

## Credentials and Vault

Local Vault can hydrate the same env credential contract as production.
Use configured token or Kubernetes auth appropriate to the environment; do not copy
secret values into source, artifacts or logs. Follow the canonical setup links
above rather than maintaining another env inventory here.

Vault parity prevents config drift; it does not protect delivery. Keep local
execution dry unless real effects are explicitly authorized. `just vault_check`
checks connectivity and visible key names without printing values.

## Manual verification and requested acceptance suites

Follow the root AGENTS.md validation policy. Do not add tests under a user catalog
unless explicitly requested. Normal pack checks use controlled manual execution;
a complex resumable change also needs the blocked-network restore scenarios in
[state and delivery](state-and-delivery.md). Framework tests use generic fixtures,
not classes from a user's mounted catalog.

For an explicitly requested pack-owned Minitest suite, the engine publishes
`ghcr.io/r3x-dev/engine:test`. The `test` channel follows the default branch;
`test-<full-commit-SHA>` pins an engine revision. Production excludes test dependencies.

From the catalog root:

```sh
docker run --rm --network none \
  --mount "type=bind,source=$PWD,target=/workflows,readonly" \
  ghcr.io/r3x-dev/engine:test /workflows/example_digest/test/publication_test.rb
```

The example test path is fictional. The image runs `bundle exec ruby` in `/rails`
with headless test configuration and Vault skipped. It does not prepare a database
or load engine fixtures; the suite owns setup and blocks/stubs external calls.
The mount is read-only, and image-owned code/gems are root-owned; only log, storage
and tmp under `/rails` are writable by UID 1000. A local equivalent is
`docker build --target test --tag r3x-test:local .`.

Dockerfile, CI and `.ruby-version` own build/cache stages, publishing and base-image
updates. Inspect those files when changing image behavior rather than copying their
implementation into workflow instructions.

## Logging and evidence

Use the existing Rails logger/concern so run/job/workflow/trigger tags survive.
Use lazy `logger.debug { ... }`; use strings for info/warn/error. For structured
objects, globally loaded amazing_print supports `value.ai(plain: true)` without
another require. Keep large output at debug and exclude secrets.

`R3X_LOG_FORMAT=json` supplies explicit level/message/tags for dashboard logs;
plain is the default. Do not infer levels from free-form text or claim log
correlation from a local render alone.

Report what was actually verified: local blocked-network checks, CI, mounted
revision/deployment, live model/source requests and real delivery are separate
claims. If a required check is unavailable, name the limitation instead of
treating missing evidence as success.
