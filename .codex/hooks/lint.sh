#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Resolve paths on the host: linked worktrees can reference Git metadata outside
# the checkout mounted in the development container.
ruby_paths=('*.rb' '*.rake' '*.ru' '*.gemspec' Gemfile Rakefile 'bin/*')

lint_changed_ruby() {
  {
    git diff --name-only --diff-filter=ACMRT -z HEAD -- "${ruby_paths[@]}" &&
      git ls-files --others --exclude-standard -z -- "${ruby_paths[@]}"
  } | xargs -0 -r ./dockerized.sh bin/rubocop --force-exclusion --only-recognized-file-types --format simple --no-color --
}

if ! output=$(lint_changed_ruby 2>&1); then
  printf 'RuboCop check failed:\n%s\n' "$output" >&2
  exit 2
fi
