set positional-arguments

setup:
  git config --local core.hooksPath .githooks
  ./dockerized.sh setup
  ./dockerized.sh bin/setup --skip-server

up:
  ./dockerized.sh up

tests *args:
  ./dockerized.sh bin/rails test "$@"

format:
  ./dockerized.sh bin/rubocop -a
  ./dockerized.sh bin/dprint fmt

lint-docker:
  ./dockerized.sh compose run --pull never --rm --no-deps -T dockerfile-lint

test-javascript:
  ./dockerized.sh compose run --pull never --rm --no-deps -T js-tests

ci:
  ./dockerized.sh bin/ci
  just test-javascript

test-postgres:
  #!/usr/bin/env bash
  set -euo pipefail
  trap './dockerized.sh compose --profile postgres rm --stop --force postgres' EXIT
  ./dockerized.sh compose --profile postgres up --no-build --pull never -d --wait postgres
  ./dockerized.sh env R3X_TEST_DATABASE_URL="postgresql://r3x:r3x@postgres:5432/r3x_test" bin/rails db:test:prepare test

vault_check:
  ./dockerized.sh env R3X_SKIP_VAULT_ENV_LOAD=true bin/rails runner 'puts MultiJSON.generate(R3x::Client::HashiCorpVault.diagnose, pretty: true)'

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
