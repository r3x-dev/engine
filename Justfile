RAILS_BIN := "bundle exec rails"

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

workflows-run:
  {{RAILS_BIN}} r3x:workflows:run

workflows-list:
  {{RAILS_BIN}} r3x:workflows:list
