RAILS_BIN := "bundle exec rails"

setup:
  git config --local core.hooksPath .githooks
  bin/setup --skip-server
  bundle config set --local path "$PWD/.bundle"

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore
