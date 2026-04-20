RAILS_BIN := "bundle exec rails"

setup:
  bundle config set --local path "$PWD/.bundle"
  git config --local core.hooksPath .githooks
  bin/setup --skip-server

up:
  {{RAILS_BIN}} s

tests:
  {{RAILS_BIN}} test

vault_check:
  R3X_SKIP_VAULT_ENV_LOAD=true {{RAILS_BIN}} runner 'puts MultiJson.dump(R3x::Client::HashiCorpVault.diagnose, pretty: true)'

vault_renew:
  R3X_SKIP_VAULT_ENV_LOAD=true {{RAILS_BIN}} runner 'puts MultiJson.dump(R3x::Client::HashiCorpVault.renew_self, pretty: true)'

test_dockerignore:
  rsync -avn . /dev/shm --exclude-from .dockerignore
