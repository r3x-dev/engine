RAILS_BIN := "bundle exec rails"

setup:
  git config --local core.hooksPath .githooks

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

workflows-run:
  {{RAILS_BIN}} r3x:workflows:run

workflows-list:
  {{RAILS_BIN}} r3x:workflows:list

bundler-audit-update:
  bundle exec bundler-audit update
