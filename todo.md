# TODO / future improvements

This file collects improvement proposals and future ideas for the project.
Items are ordered by expected impact (Pareto: biggest payoff for smallest effort first).

## Legend

- `[ ]` — not started
- `[~]` — in progress
- `[x]` — done

---

## Phase 1 — safety and AGENTS.md compliance

### [ ] A. `R3x::Policy` — development should default to dry-run

**File:** `lib/r3x/policy.rb:22`

Current code:

```ruby
def default_dry_run_for(key = nil)
  # ...
  Rails.env.test?
end
```

`AGENTS.md` says: *“development and test should be dry-run by default, production should default to real delivery”*.

In `development` every external client (Gmail, Discord, HTTP, Apify, OCR, …) currently performs **real** requests unless the user explicitly sets `R3X_*_DRY_RUN=true`. This is a real risk of sending real emails or writing real data during local iteration.

**Suggested fix:** change to `Rails.env.test? || Rails.env.development?` and add a regression test.

**Test to update:** `test/lib/r3x/policy_test.rb`

---

### [ ] B. `R3x::Env.load_from_vault` should fail-fast on bad Vault config

**File:** `lib/r3x/env.rb:81-86`

Current code:

```ruby
rescue ArgumentError, RuntimeError
  raise
rescue => e
  logger.warn("Vault error: #{e.message}")
  {}
end
```

`AGENTS.md` says: *“If `R3X_VAULT_SECRETS_PATH` is set and `R3X_VAULT_ADDR` is also set, invalid or incomplete Vault auth configuration should fail fast during boot rather than silently skipping secrets.”*

Network/auth/timeout errors are currently swallowed and the app boots without secrets, only failing later in client calls.

**Suggested fix:** remove the broad `rescue => e`; let errors propagate. Only skip Vault when `R3X_VAULT_ADDR` is absent.

---

### [x] C. `Dashboard::Run.observed_triggers` dead placeholder

**Files:** `app/models/dashboard/run.rb:35`, `app/lib/r3x/dashboard/workflow/catalog.rb:5,89-139`

The `observed_triggers` scope always returned `where(class_name: [])`, making the `recent_trigger_observed_jobs` path in `Catalog` dead code. This was leftover from the removed change-detecting trigger runtime (#73).

**Done:** removed the scope, `TRIGGER_OBSERVATION_JOB_LIMIT`, `recent_trigger_observed_jobs`, `workflow_key_from_trigger`, and simplified `observed_class_names_to_keys`.

**Verification:** `bin/rails test` (502 runs, 0 failures) and `bin/lint-r3x` (81 passed).

---

## Phase 2 — configuration and client consistency

### [ ] D. Replace direct `ENV` reads with `R3x::Env`

**Files:**

- `config/runtime_profile.rb:11`
- `config/puma.rb:28,31,34,40,44`
- `config/environments/production.rb:5,47,92`
- `config/initializers/r3x_vault_env.rb:4`
- `lib/r3x/log.rb:28`
- `lib/r3x/workflow/entrypoint.rb:17,22`
- `lib/r3x/workflow/pack_loader.rb:51`

Many places read `ENV` directly instead of the project’s own helper. This allows empty strings from `.env` files to pass as valid values and skips fail-fast boolean parsing.

**Suggested fix:** migrate to `R3x::Env.fetch` / `fetch!` / `fetch_boolean` / `present?`. Pay special attention to `config/puma.rb:31`, which uses `ActiveModel::Type::Boolean.new.cast` and silently accepts typos.

---

### [ ] E. Large classes with too many responsibilities

**Files:**

- `app/models/dashboard/run.rb` (254 lines) — argument parsing, Solid Queue statuses, enqueueing, normalization, querying.
- `app/lib/r3x/dashboard/workflow/summaries.rb` (274 lines) — summary building, Ruby sorting, health logic.
- `app/helpers/r3x/dashboard/application_helper.rb` (378 lines) — view helpers plus manual error parsing with regexes.

This violates SRP and makes every Solid Queue / error-format / UI change touch the same files.

**Suggested fix:**

- Extract `Dashboard::Run::ArgumentsNormalizer` and `Dashboard::Run::StatusResolver`.
- Extract error parsing logic to `Dashboard::ErrorParser`.
- Simplify or move sorting in `Summaries` closer to SQL.

---

### [ ] F. Coupling `lib/r3x/workflow/` to Solid Queue internals

**File:** `lib/r3x/workflow/execution.rb:25`

```ruby
@recurring_task = SolidQueue::RecurringTask.find_by(key: @workflow_key)
```

`AGENTS.md` points to `app/models/dashboard/` as the boundary over `solid_queue_*`. Framework code in `lib/r3x/workflow/` should not query Solid Queue internal tables directly.

**Suggested fix:** introduce a small adapter/repository, e.g. `Dashboard::RecurringTask.find_by_workflow_key(...)`, or pass `previous_run_at` from a higher layer.

---

### [ ] G. Duplicate HTTP setup and inconsistent dry-run logging

**Files:**

- `app/lib/r3x/client/miniflux.rb:61`
- `app/lib/r3x/client/ocr.rb:42`
- `app/lib/r3x/client/apify.rb:44`
- `app/lib/r3x/client/healthchecks_io.rb:94`
- `app/lib/r3x/client/markdownify.rb:99`
- `app/lib/r3x/client/victoria_logs.rb:9`

Each client builds `HTTPX.with(...)` by hand. There is no shared timeout/SSL/options builder.

Also, dry-run logging uses hard-coded tags:

```ruby
logger.info "[DRY-RUN]: content: #{content}"
```

`AGENTS.md` prefers `R3x::Concerns::Logger` with `self.class.name`.

**Suggested fix:** introduce `R3x::Client::HttpBuilder` (or extend `R3x::Client::Http`) and a shared dry-run logging mixin.

---

## Phase 3 — architecture and tests

### [ ] H. Refactor tests to use Mocha and add missing coverage

**Files:**

- `test/lib/r3x/client/google/gmail_test.rb:8-46` — manual `define_singleton_method` / `alias_method`.
- `test/lib/r3x/dashboard/run_test.rb:166-182` — manual `alias_method` on `SolidQueue::Job.singleton_class`.
- `test/lib/r3x/client/llm_test.rb:42-105` — `expects` on internal `RubyLLM` objects (fragile, “stubbing what you don't own”).
- `test/lib/r3x/policy_test.rb` — missing a `development` dry-run test.

`AGENTS.md` strongly recommends Mocha and warns against manual monkey-patching and stubbing third-party internals.

**Suggested fix:** rewrite to Mocha `stubs`/`expects`, add the missing `development` policy test, and wrap RubyLLM behind a narrow client boundary so tests can stub our own API instead of the gem.

---

### [ ] I. `R3x::TriggerManager::Execution` uses `method_missing` for type predicates

**File:** `lib/r3x/trigger_manager/execution.rb:16-26`

Metaprogramming makes static analysis hard and can answer `true` to any `foo?` question.

**Suggested fix:** replace with explicit predicates (`schedule?`, `manual?`) or a capability-based API.

---

### [ ] J. `R3x::Workflow::CacheKey` relies on `RubyVM::InstructionSequence`

**File:** `lib/r3x/workflow/cache_key.rb:28`

```ruby
RubyVM::InstructionSequence.of(block).to_a.dig(4, :code_location)
```

This is brittle against interpreter changes and hard to understand.

**Suggested fix:** use an explicit, stable cache key source (e.g. caller location + workflow key + explicit discriminator) instead of bytecode introspection.

---

## Phase 4 — long-term / optional

### [ ] K. RBS signatures are stale for new clients

**Files:** `sig/r3x/client/*.rbs`

Many newer clients (`discord`, `google/gmail`, `google/translate`, `google_sheets`, `apify`, `ocr`, `healthchecks_io`, `prometheus`, `markdownify`, `llm/classifier`, `llm/provider_configuration`, …) lack signatures.

`AGENTS.md` says to update `sig/` when changing client methods.

**Suggested fix:** add minimal RBS signatures for the workflow-facing client methods.

---

### [ ] L. Pre-commit hook runs the full CI suite

**File:** `.githooks/pre-commit`

The hook runs `bin/ci`, which includes `bin/lint-r3x`, RuboCop, dprint, typecheck, bundler-audit, brakeman, and the full test suite. This can be slow for every commit.

**Suggested fix:** consider a lighter pre-commit (format + lint references) and run the full suite on push / in CI.

---

## Notes

- This backlog is intentionally read-only design-debt tracking. Pick items in order; do not try to fix everything at once.
- When an item changes code covered by `AGENTS.md`, update `AGENTS.md` in the same PR.
- When an item changes `R3x::Workflow::Context`, `R3x::Workflow::Context::Client`, or `R3x::Client::Http`, update matching `sig/` files.
