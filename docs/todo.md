# TODO / Future Improvements

This file tracks the current quality backlog for the app. Keep it short, concrete,
and ordered by payoff. When a task changes architecture, workflow loading, trigger
discovery, scheduling, validation contracts, env behavior, HTTP policy, or repo
layout, update `AGENTS.md` in the same change.

## Legend

- `[ ]` - not started
- `[~]` - in progress
- `[x]` - done

---

## Phase 1 - Correctness

### [x] A. Fix workflow `previous_run_at` lookup for namespaced recurring task keys

**Files:**

- `lib/r3x/workflow/execution.rb`
- `lib/r3x/workflow/context.rb`
- `lib/r3x/workflow/executor.rb`
- `test/lib/r3x/workflow/context_test.rb`

`R3x::Workflow::Execution#previous_run_at` used to look up a recurring task by
`key: workflow_key`, but schedulable workflow tasks are persisted as
`workflow:<workflow_key>:<trigger_key>` by `R3x::RecurringTasksConfig`.

The existing tests create synthetic Solid Queue task keys such as `test_fr`, so
they do not exercise the production key format. This can make
`ctx.execution.first_run?` report `true` even when a scheduled workflow has
already run.

**Done:** `Executor` passes the resolved trigger key and Active Job id through
`Context` into `Execution`, and `Execution#previous_run_at` delegates to
`Dashboard::RecurringTask` so the namespaced key format and current-run exclusion
live at the Solid Queue boundary.

---

## Phase 2 - Client Consistency

### [x] B. Consolidate repeated `HTTPX.with(...)` option setup

**Files:**

- `app/lib/r3x/client/http.rb`
- `app/lib/r3x/client/miniflux.rb`
- `app/lib/r3x/client/ocr.rb`
- `app/lib/r3x/client/apify.rb`
- `app/lib/r3x/client/healthchecks_io.rb`
- `app/lib/r3x/client/markdownify.rb`
- `app/lib/r3x/client/victoria_logs.rb`
- `lib/r3x/workflow/context/client.rb`

Several clients built `HTTPX.with(...)` timeout options by hand even when the
provider did not need custom timeout policy.

**Done:** speculative timeout overrides were removed from thin clients that can
use HTTPX defaults. `R3x::Client::Http` now keeps its own option builder private
and only applies options when callers request custom SSL or timeout behavior.
Client-specific headers stay near the request code.

Also resolved an issue where `Context::Client.llm` explicitly forwarded default keyword arguments (e.g. `max_retries: nil`), overriding the constructor-level defaults in `Llm.new` and disabling LLM retries. Refactored the method to use anonymous keyword arguments forwarding (`**`), ensuring default settings are correctly restored when not overridden by the workflow.

---

### [ ] C. Normalize dry-run logging in integration clients

**Files:**

- `app/lib/r3x/client/discord.rb`
- `app/lib/r3x/client/google/gmail.rb`
- `app/lib/r3x/client/markdownify.rb`
- workflow clients that add new dry-run paths

Dry-run logs currently use slightly different labels and payload shapes, and some
paths log full message bodies. This makes dashboard logs harder to scan and can
expose more content than needed.

**Suggested fix:**

- Standardize on one dry-run prefix, for example `[DRY-RUN]`.
- Log compact metadata by default: provider, action, destination, subject/title,
  URL, or content length.
- Avoid logging full email or Discord bodies unless a caller explicitly needs
  that detail for local debugging.
- Use the existing `R3x::Concerns::Logger` class tags; avoid a new mixin unless
  duplication becomes real after the first cleanup.

---

## Phase 3 - Dashboard Shape

### [x] D. Split dashboard error parsing out of `ApplicationHelper`

**Files:**

- `app/helpers/r3x/dashboard/application_helper.rb`
- `test/lib/r3x/dashboard/application_helper_test.rb`

`ApplicationHelper` still owns view helpers, timestamp formatting, icon helpers,
sort links, and manual error parsing. The highest-value extraction is the error
parsing code because it has regex-heavy behavior and should be testable without
view helper setup.

**Suggested fix:**

- Extract a small `R3x::Dashboard::ErrorDetails`.
- Keep helper methods focused on formatting parsed data for views.
- Move existing structured-error assertions to detail-level tests where possible.

**Done:** Regex-heavy error details now live in shared `R3x::ErrorDetails`.
Structured logging, dashboard log normalization, and dashboard helpers use it so
`error_class`, `message`, and `backtrace` stay aligned. `R3x::Dashboard::ErrorDetails`
remains a small dashboard-facing wrapper for display behavior.

---

### [x] E. Revisit dashboard run and summary responsibilities

**Files:**

- `app/models/dashboard/run.rb`
- `app/lib/r3x/dashboard/workflow/summaries.rb`
- `app/lib/r3x/dashboard/workflow/runs.rb`
- `app/lib/r3x/dashboard/workflow/run_counts.rb`

`Dashboard::Run` and dashboard workflow query objects still mix Solid Queue
state mapping, logical status resolution, summary shaping, and sorting. The code
works, but future Solid Queue or dashboard changes will continue touching the
same broad files.

**Suggested fix:**

- Extract only when making a related behavior change.
- Good first candidates are status resolution and Active Job argument
  normalization.
- Avoid moving code just to make files smaller; each extraction should remove a
  real reason for unrelated changes to collide.

**Done:** `R3x::Dashboard::Workflow::LogicalRun` now owns the shared logical run
hash construction used by run listings and workflow summaries. Solid Queue
scopes, status filtering, argument normalization, and count SQL remain on
`Dashboard::Run` where they belong.

---

## Phase 4 - Local Workflow

### [ ] I. Remove magic predicates in `TriggerManager::Execution`

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

### [x] K. RBS signatures are stale for new clients

**Files:** `sig/r3x/client/*.rbs`, `Steepfile`

**Done:**

- Added per-client RBS signatures under `sig/r3x/client/` for:
  - `apify`, `discord`, `google/gmail`, `google/translate`, `google_sheets`, `healthchecks_io`, `markdownify`, `ocr`, `prometheus`, `llm` (and nested `Classifier`, `ProviderConfiguration`, `ProviderRegistry`).
- Added signatures for client result/response objects: `Ocr::Result`, `HealthchecksIO::Response`, `Prometheus::Result`.
- Removed the stale `sig/r3x/workflow/base.rbs` (the class was not in `Steepfile` and the signature was incomplete).
- Removed the consolidated `sig/r3x/client/_stubs.rbs` in favor of explicit per-client signature files.
- Added the new clients to `Steepfile` so `bin/typecheck` covers them.
- Added missing dependency stubs to `sig/r3x/external_stubs.rbs` (`HTTPX.get/post/head`, `R3x::Env.fetch!`, `R3x::Client::GoogleAuth`, `Google::Apis::*`, `Mail::Part`, `RubyLLM`, `SecureRandom`, `Base64`, `String#blank?`).
- Made small code tweaks to keep type-checking clean:
  - `Ocr#build_params` now starts with an empty `Hash.new`.
  - `Llm` uses `Hash.new` for class-level caches and an explicit block param instead of `it`.
  - `Google::Translate#translate` validates the translations array explicitly.
  - `Google::Gmail#raw_message` uses an explicit `Mail::Part` block param.

**Verification:** `bin/typecheck` passes; `bin/rails test` passes; `bin/lint-r3x` passes.

---

### [ ] F. Decide whether the pre-commit hook should keep running full CI

**File:** `.githooks/pre-commit`

The hook currently runs `bin/ci`, which includes setup, RuboCop, dprint, `bin/lint-r3x`, typecheck, bundler-audit, Brakeman, and the full Rails test suite. This makes every commit green but slows down local commit shaping.

**Suggested fix:**
- Keep as-is if green commits matter more than fast local history editing.
- Otherwise move full `bin/ci` to pre-push or CI, and keep pre-commit focused on formatting plus cheap lint checks.

---

## Architectural notes — what would DHH and Sandi Metz say?

These are not actionable todos yet; they are framing notes for larger refactor discussions.

### DHH / 37signals perspective

- **Less layering, more Rails.** Much of `app/lib/r3x/dashboard/workflow/` (`Catalog`, `Summaries`, `Runs`) is logic that belongs in models under `app/models/dashboard/`, not in parallel service/query layers. `Dashboard::Run` is the model — let it own its queries and summaries.
- **Pre-commit running full CI is expensive.** Running `bin/ci` (RuboCop, dprint, typecheck, bundler-audit, brakeman, full test suite) on every commit slows the local loop. A lighter pre-commit with full CI on push is more Rails-like.
- **RBS/Steep may be overhead at this size.** Keeping signatures in sync is a tax. If the team is not actively relying on Steep, the narrow scope is good, but widening it would be a mistake.
- **Fail fast, don't swallow errors.** `R3x::Env.load_from_vault` catching `StandardError` violates the 37signals preference for loud failures over silent degradation.
- **Use your own conventions everywhere.** Direct `ENV.fetch` calls in `config/puma.rb` and `production.rb` undermine the `R3x::Env` helper and create inconsistent semantics.

### Sandi Metz perspective

- **Classes are too large.** `Dashboard::Run` (254 lines), `Summaries` (274 lines), and `ApplicationHelper` (378 lines) violate SRP. Extract `StatusResolver`, `ArgumentsNormalizer`, and `ErrorParser`.
- **Avoid magic predicates.** `R3x::TriggerManager::Execution` uses `method_missing` for trigger type predicates. Replace with explicit methods (`schedule?`, `manual?`) or a capability-based API.
- **Don't use bytecode introspection.** `R3x::Workflow::CacheKey` relies on `RubyVM::InstructionSequence.of(block)`. It will break on interpreter changes and is hard to reason about. Use an explicit, stable key.
- **Don't stub what you don't own.** `test/lib/r3x/client/llm_test.rb` stubs internal `RubyLLM` objects. Wrap LLM behind a narrow adapter and test your own boundary.
- **Duplicate HTTP setup signals a missing object.** Every client builds `HTTPX.with(...)` by hand. A shared `R3x::Client::HttpBuilder` (or extension of `R3x::Client::Http`) would remove copy-paste and make SSL/timeout policy consistent.

### Top 3 rewrites worth considering

1. **Split `Dashboard::Run` and `Summaries` into smaller, single-responsibility classes.** This is the highest-impact structural improvement.
2. **Introduce a shared HTTP builder and unify dry-run logging across clients.** Removes duplication and makes new integrations cheaper.
3. **Replace `method_missing` trigger predicates and bytecode-based cache keys with explicit implementations.** Eliminates two sources of fragility.

---

## Notes

- Prefer direct fixes over new cops or enforcement machinery unless the same drift repeats.
- Keep behavior changes and mechanical/style cleanup in separate commits.
- Before closing any item, run focused tests first, then `bin/ci`.
