# Plan: Google OAuth2 Helper

## Overview

Interactive CLI helper for obtaining Google refresh tokens and shared OAuth2 credential module
for per-project Google API credentials stored in Vault.

## Files

1. `app/lib/r3x/client/google_auth.rb` — shared credential builder
2. `bin/google-oauth` — interactive CLI helper

---

## 1. `app/lib/r3x/client/google_auth.rb`

Shared module for building OAuth2 credentials from JSON.

```ruby
module R3x::Client::GoogleAuth
  SCOPE_ALIASES = {
    sheets: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY,
    gmail:  Google::Apis::GmailV1::AUTH_GMAIL_SEND
  }.freeze

  def self.from_json(parsed_json, scope:)
    Signet::OAuth2::Client.new(
      client_id:     parsed_json.fetch("client_id"),
      client_secret: parsed_json.fetch("client_secret"),
      refresh_token: parsed_json.fetch("refresh_token"),
      token_credential_uri: "https://oauth2.googleapis.com/token",
      scope: Array(scope)
    ).tap(&:fetch_access_token!)
  end
end
```

**Error handling:**
- `KeyError` if required fields missing from JSON
- Propagate `Signet::AuthorizationError` on invalid refresh token

---

## 2. `bin/google-oauth`

```bash
#!/usr/bin/env ruby
require_relative "../config/environment"
require "optparse"
```

### Commands

| Command | Description |
|---------|-------------|
| `authorize --project PROJECT --scopes sheets,gmail` | Start OAuth2 flow |
| `status --project PROJECT` | Check credential status |

### Pre-setup (manual)

1. Google Cloud Console → create project
2. Enable APIs: Sheets API + Gmail API
3. OAuth consent screen → External → Add test users
4. Credentials → Create OAuth client ID → Desktop app
5. Extract `client_id` and `client_secret`
6. Store in Vault: `GOOGLE_CLIENT_ID_<PROJECT>`, `GOOGLE_CLIENT_SECRET_<PROJECT>`

### `authorize` flow

1. Read `GOOGLE_CLIENT_ID_<PROJECT>` and `GOOGLE_CLIENT_SECRET_<PROJECT>` from ENV
2. Map scope aliases to Google OAuth scopes
3. Build auth URL with `Signet::OAuth2::Client` (redirect_uri: `urn:ietf:wg:oauth:2.0:oob`)
4. Print URL to console
5. Prompt user to paste authorization code
6. Exchange code for tokens
7. Output JSON to console:
   ```json
   {"client_id":"...","client_secret":"...","refresh_token":"..."}
   ```
8. Instruct user to store in Vault as `GOOGLE_CREDENTIALS_<PROJECT>`

### `status` flow

1. Check if `GOOGLE_CREDENTIALS_<PROJECT>` exists in ENV
2. Try to fetch access token (validates refresh token)
3. Report: credentials present, token valid/invalid

### Scope aliases

| Alias | Google scope |
|-------|-------------|
| `sheets` | `https://www.googleapis.com/auth/spreadsheets.readonly` |
| `gmail` | `https://www.googleapis.com/auth/gmail.send` |

---

## Env Vars

**Pre-OAuth (temporary, from Google Cloud Console):**
- `GOOGLE_CLIENT_ID_PXOPULSE`
- `GOOGLE_CLIENT_SECRET_PXOPULSE`

**Post-OAuth (permanent, from `bin/google-oauth authorize`):**
- `GOOGLE_CREDENTIALS_PXOPULSE` — JSON with client_id, client_secret, refresh_token

All loaded from Vault via `R3x::Env.load_from_vault` at boot.

---

## Vault structure

```
secret/data/env/r3x
  ├── GOOGLE_CLIENT_ID_PXOPULSE
  ├── GOOGLE_CLIENT_SECRET_PXOPULSE
  ├── GOOGLE_CREDENTIALS_PXOPULSE
  └── GOOGLE_CREDENTIALS_OTHERPROJECT
```

---

## Per-project pattern

Follows same naming as LLM API keys (`GEMINI_API_KEY_MICHAL`).

Workflow specifies which credentials to use:
```ruby
ctx.client.google_sheets(
  spreadsheet_id: "...",
  credentials_env: "GOOGLE_CREDENTIALS_PXOPULSE"
)
```

Validation via `secure_fetch`:
```ruby
R3x::Env.secure_fetch(credentials_env, prefix: "GOOGLE_CREDENTIALS_")
```

---

## Dependencies

- `googleauth` gem (already in Gemfile)
- `signet` (comes with googleauth)
- `multi_json` (already in Gemfile)

---

## Related files

- `lib/r3x/env.rb` — `secure_fetch`, `load_from_vault`
- `config/initializers/r3x_vault_env.rb` — boot-time Vault loading
- `docs/todo/plan-google-sheets-client.md`
- `docs/todo/plan-gmail-output.md`
