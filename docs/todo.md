# TODO / Future Improvements

This file tracks the current quality backlog for the app. Keep it short, concrete,
and ordered by payoff. Completed work belongs in Git history rather than this file.

There are no open app-quality items from the 2026-07-10 audit.

## Current review backlog (local only)

- Implemented, awaiting review: engine lint guards for provider/dynamic ENV reads in clients,
  external Google constants, and literal requires of autoloaded files. Workflow linting remains
  a separate, deferred profile; keep autoload root configuration aligned with Rails.

- Dashboard database errors and logical run selection: completed in `5823b08`.
- D2, implemented and awaiting review: count recent activity in SQL using the existing activity scopes
  and `Dashboard::Run.logical_count`, instead of loading every matching job into Ruby. Preserve
  the 24-hour window, deduplication across fragments, and exclusion of future scheduled jobs.
  No production slowdown has been measured; this is a small efficiency/simplification follow-up.
- Deferred by choice: LLM instrumentation and Flightdeck branding changes.

## Documentation scope

Keep this backlog about the engine. Concrete workflow behavior, integration contracts,
retry/recovery instructions, verification evidence, and future work belong in each workflow's
directory. Engine docs and agent instructions use general principles and fictional examples,
so they remain valid for independently supplied catalogs.

When future work changes architecture, workflow loading, trigger discovery,
scheduling, validation contracts, env behavior, HTTP policy, or repo layout,
update `AGENTS.md` in the same change.

Container validation is defined by the pinned `droast` entry in
`mise.toml`, the matching `docker_validate` CI step, and `just show_dockerignore`.
Keep those files synchronized when changing Dockerfile or build-context policy.
