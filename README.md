# r3x

Ruby-native workflow executor and automation engine. File-based workflow definitions with database runtime state. Built for local-first execution, self-hosting, and Git-native version control.

Rails API backend with SQLite, Active Record, and Active Job. Supports staged DAG execution, pack-based extensibility, and multiple executor backends.
Also includes a small server-rendered workflow dashboard at `/` and Mission Control Jobs at `/ops/jobs`.

## Development Setup

After cloning the repository, enable the pre-commit hooks:

```bash
git config --local core.hooksPath .githooks
```

This ensures that `bin/ci` runs automatically before each commit to catch issues early.

## Quick Start

```bash
mise install
bundle install
bin/rails db:setup
bin/rails server
```

Then open http://localhost:3000/ to view the workflow dashboard.

- `/` shows registered workflows, trigger state, and recent visible runs.
- `/workflow-runs` shows recent runs from the current `Solid Queue` retention window.
- `/ops/jobs` opens Mission Control Jobs for queue inspection and operational actions.

## Test

```bash
bin/rails test
```

## Operational Notes

- Workflow classes are enqueued directly as Active Job classes so workflows can use `ActiveJob::Continuable` and `step` on the real workflow job instance.
- Tradeoff: queued workflow runs persist the concrete workflow class name in Solid Queue.
- If a workflow class is renamed or removed before an older queued run executes, that older run may fail deserialization.
- After workflow class renames/removals, clean up pending jobs or recurring tasks that still reference the old class if you need a clean queue.
- The dashboard's recent run view is read-only and derived from current `solid_queue_jobs` state.
- Finished runs are only visible as long as `config.solid_queue.clear_finished_jobs_after` keeps them in the database. In this repo, development, test, and production are currently configured for `2.weeks`.
