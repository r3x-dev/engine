# r3x

Ruby-native workflow executor and automation engine. File-based workflow definitions with database runtime state. Built for local-first execution, self-hosting, and Git-native version control.

Rails API backend with SQLite, Active Record, and Active Job. Supports staged DAG execution, pack-based extensibility, and multiple executor backends.

## Quick Start

```bash
mise install
bundle install
bin/rails db:setup
bin/rails server
```

## Test

```bash
bin/rails test
```
