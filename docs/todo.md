# TODO / future improvements

This file collects improvement proposals and future ideas for the project.
Items are ordered by expected impact (Pareto: biggest payoff for smallest effort first).

## Legend

- `[ ]` — not started
- `[~]` — in progress
- `[x]` — done

---

## Phase 1 — safety and AGENTS.md compliance

### [x] A. `R3x::Policy` — development should default to dry-run

**File:** `lib/r3x/policy.rb:22`

**Done:** changed default to `Rails.env.test? || Rails.env.development?`, added a regression test, and updated CLI to support `--no-dry-run` so real delivery is an explicit opt-out in development. Updated `README.md`, `docs/workflows.md`, and `docs/environment.md`.

---

### [x] B. `R3x::Env.load_from_vault` should fail-fast on bad Vault config

**File:** `lib/r3x/env.rb:81-86`

**Done:** removed the broad `rescue => e` block in `load_from_vault` so all Vault configuration and request errors propagate and fail fast. Added test verification in `test/lib/r3x/env/vault_test.rb`.

**Verification:** `bin/rails test` (504 runs, 0 failures).

---

### [x] C. `Dashboard::Run.observed_triggers` dead placeholder

**Files:** `app/models/dashboard/run.rb:35`, `app/lib/r3x/dashboard/workflow/catalog.rb:5,89-139`

The `observed_triggers` scope always returned `where(class_name: [])`, making the `recent_trigger_observed_jobs` path in `Catalog` dead code. This was leftover from the removed change-detecting trigger runtime (#73).

**Done:** removed the scope, `TRIGGER_OBSERVATION_JOB_LIMIT`, `recent_trigger_observed_jobs`, `workflow_key_from_trigger`, and simplified `observed_class_names_to_keys`.

**Verification:** `bin/rails test` (502 runs, 0 failures) and `bin/lint-r3x` (81 passed).

---

## Phase 2 — configuration and client consistency

### [x] D. Replace direct `R3X_*` ENV reads with `R3x::Env`

**Files:**

- `config/runtime_profile.rb:11`
- `config/initializers/r3x_vault_env.rb:4`
- `lib/r3x/log.rb:28`
- `lib/r3x/workflow/pack_loader.rb:51`

**Done:** migrated `R3X_*` variable reads to `R3x::Env.fetch` / `present?`. Added custom RuboCop cop `R3x/PreferR3xEnv` to enforce this in `app/` and `lib/`. Left standard Rails / Puma / Solid Queue variables (`RAILS_MAX_THREADS`, `PORT`, `RAILS_ENV`, `SOLID_QUEUE_IN_PUMA`, etc.) using direct `ENV` reads, since they follow external conventions.

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

### [x] H. Refactor tests to use Mocha and add missing coverage

**Files:**

- `test/lib/r3x/client/google/gmail_test.rb:8-46` — manual `define_singleton_method` / `alias_method`.
- `test/lib/r3x/dashboard/run_test.rb:166-182` — manual `alias_method` on `SolidQueue::Job.singleton_class`.
- `test/lib/r3x/client/llm_test.rb:42-105` — `expects` on internal `RubyLLM` objects (fragile, “stubbing what you don't own”).
- `test/lib/r3x/policy_test.rb` — missing a `development` dry-run test.

`AGENTS.md` strongly recommends Mocha and warns against manual monkey-patching and stubbing third-party internals.

**Suggested fix:** rewrite to Mocha `stubs`/`expects`, add the missing `development` policy test, and keep RubyLLM tests at the closest external boundary instead of stubbing inner chat/model-registry objects.

**Done:** `gmail_test` and `run_test` no longer monkey-patch global methods; `llm_test` stubs only the `RubyLLM.context` boundary and uses plain fake context/chat objects; policy development dry-run coverage is present.

---

### [x] I. `R3x::TriggerManager::Execution` uses `method_missing` for type predicates

**File:** `lib/r3x/trigger_manager/execution.rb:16-26`

Metaprogramming makes static analysis hard and can answer `true` to any `foo?` question.

**Suggested fix:** replace with explicit predicates (`schedule?`, `manual?`) or a capability-based API.

**Done:** `Execution` now exposes explicit `manual?` and `schedule?` predicates and no longer synthesizes arbitrary `foo?` methods.

---

### [x] J. `R3x::Workflow::CacheKey` relies on `RubyVM::InstructionSequence`

**File:** `lib/r3x/workflow/cache_key.rb:28`

```ruby
RubyVM::InstructionSequence.of(block).to_a.dig(4, :code_location)
```

This is brittle against interpreter changes and hard to understand.

**Suggested fix:** use an explicit, stable cache key source (e.g. caller location + workflow key + explicit discriminator) instead of bytecode introspection.

**Done:** removed `RubyVM::InstructionSequence` from cache-key generation. `with_cache` remains keyless by default, derives the generated cache key from workflow key, source file path, source line, and file digest, and raises with a clear message if multiple cache calls share one source line without explicit `key:`.

---

## Phase 4 — long-term / optional

### [x] K. Remove RBS + Steep static type checks

**Files:** `sig/`, `Steepfile`, `bin/typecheck`, `Gemfile`, `config/ci.rb`

**Done:**

- Removed the `sig/` directory, `Steepfile`, and `bin/typecheck` script.
- Removed `rbs` and `steep` gems from `Gemfile` and regenerated `Gemfile.lock`.
- Removed the "Types: Static Types" step from `config/ci.rb`.
- Removed the Static Typing section from `AGENTS.md` and updated references in `docs/todo.md`.

**Reason:** Steep does not yet support Ruby 3.4's `it` block parameter (see https://github.com/soutaro/steep/pull/2238). Keeping RBS signatures in sync was also adding friction without enough payoff at the current project size. Static typing can be reintroduced once the upstream blocker is resolved.

---

### [ ] L. Pre-commit hook runs the full CI suite

**File:** `.githooks/pre-commit`

The hook runs `bin/ci`, which includes `bin/lint-r3x`, RuboCop, dprint, bundler-audit, brakeman, and the full test suite. This can be slow for every commit.

**Suggested fix:** consider a lighter pre-commit (format + lint references) and run the full suite on push / in CI.

---

## Architectural notes — what would DHH and Sandi Metz say?

These are not actionable todos yet; they are framing notes for larger refactor discussions.

### DHH / 37signals perspective

- **Less layering, more Rails.** Much of `app/lib/r3x/dashboard/workflow/` (`Catalog`, `Summaries`, `Runs`) is logic that belongs in models under `app/models/dashboard/`, not in parallel service/query layers. `Dashboard::Run` is the model — let it own its queries and summaries.
- **Pre-commit running full CI is expensive.** Running `bin/ci` (RuboCop, dprint, bundler-audit, brakeman, full test suite) on every commit slows the local loop. A lighter pre-commit with full CI on push is more Rails-like.
- **Keep boot-time failures loud.** `R3x::Env.load_from_vault` now propagates Vault configuration and request errors; preserve that fail-fast behavior when changing secret bootstrapping.
- **Use your own conventions everywhere.** Direct `ENV.fetch` calls in `config/puma.rb` and `production.rb` undermine the `R3x::Env` helper and create inconsistent semantics.

### Sandi Metz perspective

- **Classes are too large.** `Dashboard::Run` (254 lines), `Summaries` (274 lines), and `ApplicationHelper` (378 lines) violate SRP. Extract `StatusResolver`, `ArgumentsNormalizer`, and `ErrorParser`.
- **Don't use bytecode introspection.** `R3x::Workflow::CacheKey` no longer relies on `RubyVM::InstructionSequence.of(block)`. Preserve the simpler file/line/digest default and use explicit `with_cache(key: ...)` for rare same-line disambiguation.
- **Duplicate HTTP setup signals a missing object.** Every client builds `HTTPX.with(...)` by hand. A shared `R3x::Client::HttpBuilder` (or extension of `R3x::Client::Http`) would remove copy-paste and make SSL/timeout policy consistent.

### Top 3 rewrites worth considering

1. **Split `Dashboard::Run` and `Summaries` into smaller, single-responsibility classes.** This is the highest-impact structural improvement.
2. **Introduce a shared HTTP builder and unify dry-run logging across clients.** Removes duplication and makes new integrations cheaper.
3. **Keep cache boundaries simple.** The bytecode-based cache key is gone; keyless `with_cache` remains the common path, with explicit `key:` only for rare ambiguous lines.

---

## Notes

- This backlog is intentionally read-only design-debt tracking. Pick items in order; do not try to fix everything at once.
- When an item changes code covered by `AGENTS.md`, update `AGENTS.md` in the same PR.
