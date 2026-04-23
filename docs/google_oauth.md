# Google OAuth2 Setup

`bin/google-oauth` is a small CLI for obtaining and validating Google refresh tokens used by workflow integrations (Gmail, Google Sheets, Google Calendar, Google Translate).

## When do you need this?

Any time a workflow or client needs to act on behalf of a Google account via OAuth2. The app loads `client_id`, `client_secret`, and `refresh_token` from three separate environment variables scoped by project, and the individual clients use those credentials at runtime.

Typical situations:
- Setting up a new project/integration for the first time.
- Adding a new scope to an existing project (e.g., you started with Gmail and now need Sheets).
- A refresh token expired or was revoked and you need a new one.
- Verifying that stored credentials are still valid.

## Prerequisites

Before running `authorize`, make sure the following environment variables are set:

- `GOOGLE_CLIENT_ID_<PROJECT>` — OAuth2 client ID from Google Cloud Console.
- `GOOGLE_CLIENT_SECRET_<PROJECT>` — OAuth2 client secret from Google Cloud Console.

These represent the app registration itself and are shared across all scopes for a project.

## Credential storage convention

Each project uses three separate environment variables:

| Variable | Description |
|----------|-------------|
| `GOOGLE_CLIENT_ID_<PROJECT>` | OAuth2 client ID |
| `GOOGLE_CLIENT_SECRET_<PROJECT>` | OAuth2 client secret |
| `GOOGLE_REFRESH_TOKEN_<PROJECT>` | OAuth2 refresh token obtained via `bin/google-oauth authorize` |

Example for project `MYAPP`:

```bash
export GOOGLE_CLIENT_ID_MYAPP="..."
export GOOGLE_CLIENT_SECRET_MYAPP="..."
export GOOGLE_REFRESH_TOKEN_MYAPP="1//0dx..."
```

Workflows reference the project by name:

```ruby
ctx.client.gmail(project: "MYAPP")
ctx.client.google_sheets(spreadsheet_id: "...", project: "MYAPP")
ctx.client.google_translate(project: "MYAPP")
```

## Commands

### `bin/google-oauth authorize --project <PROJECT>`

Starts the interactive OAuth2 flow.

1. Verifies `GOOGLE_CLIENT_ID_<PROJECT>` and `GOOGLE_CLIENT_SECRET_<PROJECT>` are set (fails fast if missing).
2. Prompts for scope selection (or accepts `--scopes` directly).
3. Generates an authorization URL and prints it.
4. You open the URL in a browser, grant access, and copy the authorization `code` from the redirect URL.
5. The CLI exchanges the code for a `refresh_token`.
6. Prints the refresh token. Store it as `GOOGLE_REFRESH_TOKEN_<PROJECT>` in your secret backend (e.g., Vault).

**Scope selection**

If you do not pass `--scopes`, the CLI prompts you interactively. You can pick scopes one by one, or choose **`all`** to select every available scope at once.

```bash
bin/google-oauth authorize --project MYAPP
# Interactive menu: pick individual scopes or select 'all'
```

You can also pass scopes directly:

```bash
bin/google-oauth authorize --project MYAPP --scopes gmail.readonly,sheets.readonly
```

Available scope aliases can be listed with `bin/google-oauth scopes`.

### `bin/google-oauth status --project <PROJECT>`

Checks whether `GOOGLE_CLIENT_ID_<PROJECT>`, `GOOGLE_CLIENT_SECRET_<PROJECT>`, and `GOOGLE_REFRESH_TOKEN_<PROJECT>` are present, and attempts to fetch an access token from the refresh token. Use this to verify that stored credentials are still valid.

```bash
bin/google-oauth status --project MYAPP
```

### `bin/google-oauth scopes`

Lists all supported scope aliases and their full Google OAuth2 scope URLs.

```bash
bin/google-oauth scopes
```

## Security notes

- The authorization redirect is `http://localhost`. The browser will show a connection error after redirect — this is expected. Copy the `code` parameter from the URL.
- Keep `client_secret` and `refresh_token` in your secret backend (Vault, 1Password, etc.), never commit them to the repo.
- If a refresh token is revoked, simply re-run `authorize` for the same project to get a new one.
- Rotating `GOOGLE_CLIENT_SECRET_<PROJECT>` only requires updating one env var — the refresh token stays valid.
