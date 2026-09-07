# TODO / Future Improvements

This file tracks the current quality backlog for the app. Keep it short, concrete,
and ordered by payoff. Completed work belongs in Git history rather than this file.

There are no open app-quality items from the 2026-07-10 audit.

## Current review backlog (local only)

- Dashboard database errors and logical run selection: completed in `5823b08`.
- D2, implemented and awaiting review: count recent activity in SQL using the existing activity scopes
  and `Dashboard::Run.logical_count`, instead of loading every matching job into Ruby. Preserve
  the 24-hour window, deduplication across fragments, and exclusion of future scheduled jobs.
  No production slowdown has been measured; this is a small efficiency/simplification follow-up.
- Deferred by choice: LLM instrumentation and Flightdeck branding changes.

## Workflow backlog

- `madeira_weekly_news_digest`: persist the generated digest (e.g. via `with_cache(key:, ttl:)`) and
  move email/Feedway delivery into explicit steps so a failure after Gmail delivery does not resend
  the digest on retry. Consider migrating the hand-rolled `Rails.cache` `last_confirmed_at` state.
- `porto_santo_news`: claim items in `ctx.durable_set` before Discord delivery (delete on failure)
  to close the narrow double-post window between delivering and marking processed.
- `pxo_weekly`: disabled (`# r3x:disable`). When revived, review its plain `with_cache` usage — it
  is development-only; decide between removing it and switching to `with_cache(key:, ttl:)`.

When future work changes architecture, workflow loading, trigger discovery,
scheduling, validation contracts, env behavior, HTTP policy, or repo layout,
update `AGENTS.md` in the same change.

Container validation is defined by the pinned `droast` entry in
`mise.toml`, the matching `docker_validate` CI step, and `just show_dockerignore`.
Keep those files synchronized when changing Dockerfile or build-context policy.
