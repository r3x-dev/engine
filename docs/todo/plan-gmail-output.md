# Plan: Gmail Output

## Overview

R3x output for sending emails via Gmail API with test mode for safe development.
Follows the `R3x::Outputs::Discord` pattern.

## Files

1. `Gemfile` — add `mail` gem (if not present)
2. `app/lib/r3x/outputs/gmail.rb` — output implementation
3. `lib/r3x/workflow/context.rb` — add to ClientProxy

---

## 1. Gemfile

Check if `mail` gem is present, if not add:

```ruby
gem "mail"  # For RFC 2822 email building
```

---

## 2. `app/lib/r3x/outputs/gmail.rb`

### Class: `R3x::Outputs::Gmail`

```ruby
module R3x
  module Outputs
    class Gmail
      include R3x::Concerns::Logger

      def initialize(credentials:, mode: nil)
        @credentials = credentials
        @mode = mode || ENV.fetch("R3X_GMAIL_MODE", "test")
      end

      def deliver(to:, subject:, body:)
        case mode
        when "real"
          deliver_real(to: to, subject: subject, body: body)
        when "test"
          deliver_test(to: to, subject: subject, body: body)
        else
          raise ArgumentError, "Unsupported Gmail mode: #{mode}. Supported: real, test"
        end
      end

      private

      attr_reader :credentials, :mode

      def deliver_real(to:, subject:, body:)
        service = Google::Apis::GmailV1::GmailService.new
        service.authorization = R3x::Client::GoogleAuth.from_json(
          credentials,
          scope: Google::Apis::GmailV1::AUTH_GMAIL_SEND
        )

        mail = Mail.new do
          to      to
          subject subject
          body    body
        end

        message = Google::Apis::GmailV1::Message.new(
          raw: Base64.urlsafe_encode64(mail.to_s)
        )

        result = service.send_user_message("me", message)
        {"mode" => "real", "message_id" => result.id}
      end

      def deliver_test(to:, subject:, body:)
        logger.info("Gmail [TEST] to=#{to} subject=#{subject}\n#{body}")
        {"mode" => "test"}
      end
    end
  end
end
```

### Public API

| Method | Returns | Description |
|--------|---------|-------------|
| `deliver(to:, subject:, body:)` | `Hash` | Send email (real mode) or log (test mode) |

### Mode behavior

| Mode | Env var value | Behavior |
|------|--------------|----------|
| `test` | default | Log to Rails logger, no API call |
| `real` | `"real"` | Send via Gmail API |

### Error handling

- `Google::Apis::ClientError` (400) — invalid recipient
- `Google::Apis::ClientError` (403) — quota exceeded or permission denied
- `Signet::AuthorizationError` — refresh token expired

---

## 3. ClientProxy addition

File: `lib/r3x/workflow/context.rb`

Add inside `ClientProxy` class:

```ruby
def gmail(credentials_env:, mode: nil)
  credentials = fetch_google_credentials(credentials_env)
  R3x::Outputs::Gmail.new(credentials: credentials, mode: mode)
end
```

The `fetch_google_credentials` private method is shared with `google_sheets` (see plan-google-sheets-client.md).

---

## Env var

```bash
R3X_GMAIL_MODE=test  # or "real" for production
```

Can also be overridden per-call:
```ruby
ctx.client.gmail(credentials_env: "...", mode: "real").deliver(...)
```

---

## Usage in workflow

```ruby
ctx.client.gmail(
  credentials_env: "GOOGLE_CREDENTIALS_MYAPP"
).deliver(
  to: "recipient@example.com",
  subject: "Weekly pulse",
  body: formatted_content
)

# Test mode returns:
# {"mode" => "test"}

# Real mode returns:
# {"mode" => "real", "message_id" => "18a3f..."}
```

---

## Comparison with Discord Output

| Aspect | `Outputs::Discord` | `Outputs::Gmail` |
|--------|-------------------|------------------|
| Mode env var | `R3X_DISCORD_MODE` | `R3X_GMAIL_MODE` |
| Test output | Logs to Rails logger | Logs to Rails logger |
| Auth | Webhook URL | OAuth2 credentials |
| Content | Plain text | RFC 2822 email |
| Method | `deliver(content:)` | `deliver(to:, subject:, body:)` |

---

## Gmail API limits

- Personal account: ~100 emails/day
- Google Workspace: ~1500 emails/day
- OAuth app must be in "Testing" or "Published" status

---

## Dependencies

```ruby
gem "google-apis-gmail_v1"  # Already in Gemfile
gem "mail"                  # Check/add for email building
gem "googleauth"            # Already in Gemfile
```

---

## Related files

- `app/lib/r3x/client/google_auth.rb` — shared OAuth2 module (plan: plan-google-oauth2.md)
- `app/lib/r3x/outputs/discord.rb` — similar output pattern
- `lib/r3x/workflow/context.rb` — ClientProxy integration
- `docs/todo/plan-google-oauth2.md` — OAuth2 setup
- `docs/todo/plan-google-sheets-client.md` — Sheets client
