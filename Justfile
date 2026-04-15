RAILS_BIN := "bundle exec rails"

setup:
  bundle config set --local path "$PWD/.bundle"
  git config --local core.hooksPath .githooks
  bin/setup --skip-server

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore
