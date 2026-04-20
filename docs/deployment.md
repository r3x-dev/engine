# Deployment

This app is designed to run from environment variables only. Do not use Rails
encrypted credentials in production deployments.

## Required Runtime Environment

- `SECRET_KEY_BASE`: required for production runtime processes. Generate with
  `bin/rails secret`.
- `R3X_DATABASE_URL`: preferred production database URL. `R3X_DATABASE_PATH`
  remains available for SQLite-style file paths.
- `R3X_WORKFLOW_PATHS`: one or more workflow pack directories for jobs processes.
- `R3X_SOLID_QUEUE_SHUTDOWN_TIMEOUT_SECONDS`: optional graceful shutdown timeout
  for Solid Queue. Defaults to `900` seconds in production.
- `R3X_LOGS_PROVIDER=victorialogs` and `R3X_VICTORIA_LOGS_URL`: optional
  dashboard run-log integration.

## Kubernetes Process Layouts

### Preferred Split Deployment

Run separate controllers or Deployments for the web process, workers, and
scheduler:

- Web: `./bin/rails server`
- Worker: `./bin/jobs-worker`
- Scheduler: `./bin/jobs-scheduler`

This is the preferred Kubernetes layout because web scaling, queue execution,
and recurring scheduling have separate lifecycle and resource needs. The worker
entrypoint loads workflow classes but skips recurring task ownership. The
scheduler entrypoint loads workflows and schedules recurring tasks.

### Single-Process Puma Deployment

For small or single-server deployments, set:

```sh
SOLID_QUEUE_IN_PUMA=true
```

Puma will run the Solid Queue supervisor in-process. Do not also run a separate
jobs scheduler that owns recurring scheduling in this mode.

### Generic Jobs Entrypoint

`bin/jobs` keeps the default Solid Queue CLI behavior. In split Kubernetes
deployments prefer `bin/jobs-worker` and `bin/jobs-scheduler` so the role is
encoded in the command and the matching queue config is selected by default.

## Vault Secrets

The built-in Vault loader is optional. When enabled, configure:

```sh
R3X_VAULT_ADDR=http://vault.kube-system:8200
R3X_VAULT_TOKEN=<renewable-token>
R3X_VAULT_SECRETS_PATH=secret/data/env/r3x
```

At boot, the app reads the configured KV v2 path and loads returned keys into
`ENV`. Keys starting with `R3X_` are rejected so app-internal configuration does
not come from the secret payload.

Use `R3X_SKIP_VAULT_ENV_LOAD=true` only for diagnostics or token renewal tasks
that must boot Rails even when the Vault token is broken.

## Vault Token Renewal

If `R3X_VAULT_TOKEN` is a static Vault token, issue it as a renewable periodic
token. For the current Kubernetes deployment, the token period is `72h`, so renew
it every `24h`.

Renewal extends the token lease in Vault. It does not rotate the token string,
so the Kubernetes Secret value does not need to change after a successful renew.
If the token fully expires or is revoked, renewal cannot recover it; issue a new
token and update the backing secret.

The recommended Kubernetes pattern is a dedicated CronJob outside Solid Queue:

- Schedule: once daily, for example `17 3 * * *`
- Command:
  ```sh
  ./bin/rails runner 'puts MultiJson.dump(R3x::Client::HashiCorpVault.renew_self, pretty: true)'
  ```
- Environment:
  ```sh
  R3X_SKIP_VAULT_ENV_LOAD=true
  R3X_VAULT_ADDR=http://vault.kube-system:8200
  R3X_VAULT_TOKEN=<from Kubernetes Secret>
  ```

Keep renewal outside the web and Solid Queue worker lifecycle so an expired
application token does not depend on normal workflow execution to repair itself.

## Operations

Local checks from this repo:

```sh
just vault_check
just vault_renew
```

Kubernetes checks:

```sh
kubectl -n default get cronjob | grep r3x
kubectl -n default create job --from=cronjob/<r3x-vault-renew-name> r3x-vault-renew-manual
kubectl -n default logs job/r3x-vault-renew-manual
```

`just vault_check` prints sanitized token metadata, capabilities, renewal
summary, and configured secret key names. It does not print the token or secret
values.
