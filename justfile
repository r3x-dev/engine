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

# Use Docker's own context filtering so `!` rules are evaluated correctly.
show_dockerignore:
	#!/bin/sh
	set -eu
	LC_ALL=C
	export LC_ALL

	test_dir="$(mktemp -d)"
	trap 'rm -rf "$test_dir"' 0 1 2 3 15
	mkdir -p "$test_dir/context"

	docker build --file - --progress=quiet --output "type=local,dest=$test_dir/context" . >/dev/null <<-'EOF'
	# syntax=docker/dockerfile:1
	#check=skip=CopyIgnoredFile
	FROM scratch
	COPY . /context
	EOF

	find "$test_dir/context/context" \( -type f -o -type l \) -print |
		sed "s#^$test_dir/context/context/##" |
		sort > "$test_dir/included"

	cat "$test_dir/included"
	printf '\n%s\n' '---'
	printf 'Total files:\t%s\n' "$(wc -l < "$test_dir/included" | awk '{print $1}')"
	printf 'Total size:\t%s\n' "$(du -sh "$test_dir/context/context" | awk '{print $1}')"
