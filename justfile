RAILS_BIN := "bundle exec rails"

setup:
  bundle config set --local path "$PWD/.bundle"
  git config --local core.hooksPath .githooks
  bin/setup --skip-server

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

test-postgres:
  #!/usr/bin/env bash
  set -euo pipefail
  port="${R3X_TEST_POSTGRES_PORT:-55432}"
  trap 'docker compose -f compose.test.yml down --volumes --remove-orphans' EXIT
  docker compose -f compose.test.yml up -d --wait
  R3X_TEST_DATABASE_URL="postgresql://r3x:r3x@127.0.0.1:${port}/r3x_test" {{RAILS_BIN}} db:test:prepare test

vault_check:
  R3X_SKIP_VAULT_ENV_LOAD=true {{RAILS_BIN}} runner 'puts MultiJSON.generate(R3x::Client::HashiCorpVault.diagnose, pretty: true)'

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore
