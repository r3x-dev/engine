RAILS_BIN := "bundle exec rails"

setup:
  git config --local core.hooksPath .githooks

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test
