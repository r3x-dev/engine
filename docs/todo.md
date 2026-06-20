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

Several clients built `HTTPX.with(...)` timeout options by hand even when the
provider did not need custom timeout policy.

**Done:** speculative timeout overrides were removed from thin clients that can
use HTTPX defaults. `R3x::Client::Http` now keeps its own option builder private
and only applies options when callers request custom SSL or timeout behavior.
Client-specific headers stay near the request code.

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

**Done:** Regex-heavy error details now live in `R3x::Dashboard::ErrorDetails`.
Dashboard helpers delegate to it and keep only view formatting concerns such as
truncation.

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

### [ ] F. Decide whether the pre-commit hook should keep running full CI

**File:** `.githooks/pre-commit`

The hook currently runs `bin/ci`, which includes setup, RuboCop, dprint,
`bin/lint-r3x`, bundler-audit, Brakeman, and the full Rails test suite. This
makes every commit green but slows down local commit shaping.

**Suggested fix:**

- Keep as-is if green commits matter more than fast local history editing.
- Otherwise move full `bin/ci` to pre-push or CI, and keep pre-commit focused on
  formatting plus cheap lint checks.

---

## Notes

- Prefer direct fixes over new cops or enforcement machinery unless the same
  drift repeats.
- Keep behavior changes and mechanical/style cleanup in separate commits.
- Before closing any item, run focused tests first, then `bin/ci`.
