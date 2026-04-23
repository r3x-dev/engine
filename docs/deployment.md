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
  dashboard run-log integration backed by VictoriaLogs.
- Do not use `R3X_LOGS_PROVIDER=file_log` in production deployments. `file_log`
  is a local development convenience provider; production workflow/job logs
  should stay on `stdout`, and dashboard log panels should use an indexed
  provider such as VictoriaLogs.

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

The built-in Vault loader is optional. It supports two auth modes.

Default token auth:

```sh
R3X_VAULT_ADDR=http://vault.kube-system:8200
R3X_VAULT_TOKEN=<renewable-token>
R3X_VAULT_SECRETS_PATH=secret/data/env/r3x
```

Recommended Kubernetes auth for in-cluster workloads:

```sh
R3X_VAULT_ADDR=http://vault.kube-system:8200
R3X_VAULT_SECRETS_PATH=secret/data/env/r3x
R3X_VAULT_AUTH_METHOD=kubernetes
R3X_VAULT_KUBERNETES_ROLE=r3x
R3X_VAULT_KUBERNETES_AUTH_PATH=auth/kubernetes
R3X_VAULT_KUBERNETES_TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
```

At boot, if `R3X_VAULT_SECRETS_PATH` is set, the app treats Vault bootstrap as
intentional and reads that KV v2 path into `ENV`. Keys starting with `R3X_` are
rejected so app-internal configuration does not come from the secret payload.

If `R3X_VAULT_SECRETS_PATH` is set and `R3X_VAULT_ADDR` is missing, Vault is
skipped. If `R3X_VAULT_ADDR` is set but the selected auth mode is invalid or
incomplete, boot fails fast with an error instead of silently continuing without
secrets.

With Kubernetes auth, the app does not get a Vault token from Kubernetes. It
gets a Kubernetes service account JWT from the pod filesystem, by default from
`/var/run/secrets/kubernetes.io/serviceaccount/token`, or from
`R3X_VAULT_KUBERNETES_TOKEN_PATH` when overridden. The app sends that JWT and
`R3X_VAULT_KUBERNETES_ROLE` to Vault at
`v1/<R3X_VAULT_KUBERNETES_AUTH_PATH>/login`.

Vault validates the JWT against its configured Kubernetes auth backend and, if
the role bindings match, returns a Vault client token in the response `auth`
payload. The app caches that Vault token only in-process and uses it for the
subsequent Vault API calls in that process. A pod restart naturally performs a
fresh Kubernetes login.

Use `R3X_SKIP_VAULT_ENV_LOAD=true` only for diagnostics or other operator tasks
that must boot Rails even when the Vault token is broken.

### Kubernetes Auth Notes

- Keep `automountServiceAccountToken: true` on pods that must bootstrap secrets
  from Vault through Kubernetes auth.
- Bind the Vault Kubernetes role to the dedicated service account used by the
  workload.
- Scope the Vault policy to the exact paths the app needs, for example
  `secret/data/env/r3x`.
- `just vault_check` works with both auth modes and is read-only.

## Operations

Local checks from this repo:

```sh
just vault_check
```

`just vault_check` prints sanitized token metadata, capabilities, and
configured secret key names. It does not renew the token and it does not print
the token or secret values.
