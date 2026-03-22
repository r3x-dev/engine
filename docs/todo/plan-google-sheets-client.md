# Plan: Google Sheets Client

## Overview

R3x client for reading Google Sheets data, supporting per-project credentials via Vault.

## Files

1. `Gemfile` — add `google-apis-sheets_v4`
2. `app/lib/r3x/client/google_sheets.rb` — client implementation
3. `lib/r3x/workflow/context.rb` — add to ClientProxy

---

## 1. Gemfile

Add after existing Google gems (line ~28):

```ruby
gem "google-apis-sheets_v4"
```

---

## 2. `app/lib/r3x/client/google_sheets.rb`

### Class: `R3x::Client::GoogleSheets`

```ruby
module R3x
  module Client
    class GoogleSheets
      def initialize(spreadsheet_id:, credentials:)
          @spreadsheet_id = spreadsheet_id
          @credentials = credentials
          @service = build_service
        end

        def read_rows(range:)
          response = service.get_spreadsheet_values(spreadsheet_id, range)
          rows = response.values || []
          return [] if rows.empty?

          headers = rows.first
          rows.drop(1).map { |row| headers.zip(row).to_h }
        end

        private

        attr_reader :spreadsheet_id, :credentials, :service

        def build_service
          service = Google::Apis::SheetsV4::SheetsService.new
          service.authorization = R3x::Client::GoogleAuth.from_json(
            credentials,
            scope: Google::Apis::SheetsV4::AUTH_SPREADSHEETS_READONLY
          )
          service
        end
      end
    end
  end
end
```

### Public API

| Method | Returns | Description |
|--------|---------|-------------|
| `read_rows(range:)` | `Array<Hash>` | First row = headers, rest = data |

### Behavior

- First row of range = column headers (used as hash keys)
- Remaining rows = data mapped to hashes
- Empty cells = `""` (not nil)
- Empty sheet = `[]`
- Range format: `"SheetName"` or `"SheetName!A1:D100"`

### Error handling

- `Google::Apis::ClientError` (403) — sheet not shared with OAuth account
- `Google::Apis::ClientError` (404) — spreadsheet or sheet not found
- `Signet::AuthorizationError` — refresh token expired

---

## 3. ClientProxy addition

File: `lib/r3x/workflow/context.rb`

Add inside `ClientProxy` class, after `llm` method:

```ruby
def google_sheets(spreadsheet_id:, credentials_env:)
  R3x::Client::GoogleSheets.new(
    spreadsheet_id: spreadsheet_id,
    credentials: MultiJson.load(R3x::Env.secure_fetch(credentials_env, prefix: "GOOGLE_CREDENTIALS_"))
  )
end
```



---

## Usage in workflow

```ruby
ctx.client.google_sheets(
  spreadsheet_id: "13T1oLQXmhbBYMe0shLs-5aJJsW5Esgx9xaNjSMclubU",
  credentials_env: "GOOGLE_CREDENTIALS_MYAPP"
).read_rows(range: "ThisWeekApproved")

# Returns:
# [
#   {"name" => "Concert", "start_date" => "15/1/2026", "location" => "Beach", ...},
#   {"name" => "Festival", "start_date" => "17/1/2026", "location" => "Town", ...}
# ]
```

---

## Sharing requirement

The Google Sheet must be shared with the OAuth account's email address.
If not shared, API returns 403 `insufficientPermissions`.

---

## Dependencies

```ruby
gem "google-apis-sheets_v4"  # NEW — add to Gemfile
gem "googleauth"             # Already present
gem "multi_json"             # Already present
```

---

## Related files

- `app/lib/r3x/client/google_auth.rb` — shared OAuth2 module (plan: plan-google-oauth2.md)
- `lib/r3x/workflow/context.rb` — ClientProxy integration
- `docs/todo/plan-google-oauth2.md` — OAuth2 setup
- `docs/todo/plan-gmail-output.md` — Gmail output
