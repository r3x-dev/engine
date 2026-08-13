# TODO / Future Improvements

This file tracks the current quality backlog for the app. Keep it short, concrete,
and ordered by payoff. Completed work belongs in Git history rather than this file.

There are no open app-quality items from the 2026-07-10 audit.

When future work changes architecture, workflow loading, trigger discovery,
scheduling, validation contracts, env behavior, HTTP policy, or repo layout,
update `AGENTS.md` in the same change.

Container validation is defined by the pinned `droast` entry in
`mise.toml`, the matching `docker_validate` CI step, and `just show_dockerignore`.
Keep those files synchronized when changing Dockerfile or build-context policy.
