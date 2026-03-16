# r3x

Ruby-native workflow executor and automation engine. File-based workflow definitions with database runtime state. Built for local-first execution, self-hosting, and Git-native version control.

Rails API backend with SQLite, Active Record, and Active Job. Supports staged DAG execution, pack-based extensibility, and multiple executor backends.

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

Then open http://localhost:3000/ to view the Mission Control Jobs dashboard.

## Test

```bash
bin/rails test
```
