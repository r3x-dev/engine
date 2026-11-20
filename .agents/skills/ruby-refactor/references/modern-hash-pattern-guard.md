---
title: Use Pattern Matching with Guard Clauses
tags: modern, pattern-matching, guard, case-in
---

## Use Pattern Matching with Guard Clauses

Use guards on Ruby 3.0+ to retain the original numeric comparisons and fallbacks. Assume an ordinary symbol-keyed response Hash. Preserve missing bodies, empty/error payloads, and the unexpected-status branch; do not tighten items to an Array or statuses to integers as an incidental refactor.

**Before (nested if/case for status and body handling):**

```ruby
class HttpResponseHandler
  def process(response)
    if response[:status]
      status = response[:status]
      body = response[:body]
      if status >= 200 && status < 300
        if body && body[:items] && body[:items].size > 0  # structure check tangled with status logic
          { result: :success, items: body[:items] }
        else
          { result: :empty }
        end
      elsif status >= 400 && status < 500
        if body && body[:error]
          { result: :client_error, message: body[:error][:message] }
        else
          { result: :client_error, message: "unknown client error" }
        end
      elsif status >= 500
        { result: :server_error, retry: true }
      else
        { result: :unexpected, status: status }
      end
    else
      { result: :invalid_response }
    end
  end
end
```

**Alternative (pattern matching with guard clauses):**

```ruby
class HttpResponseHandler
  def process(response)
    case response
    in { status: } if status && status >= 200 && status < 300
      body = response[:body]
      items = body && body[:items]
      if items && items.size > 0
        { result: :success, items: items }
      else
        { result: :empty }
      end
    in { status: } if status && status >= 400 && status < 500
      body = response[:body]
      if body && body[:error]
        { result: :client_error, message: body[:error][:message] }
      else
        { result: :client_error, message: "unknown client error" }
      end
    in { status: } if status && status >= 500
      { result: :server_error, retry: true }
    in { status: } if status
      { result: :unexpected, status: status }
    else
      { result: :invalid_response }
    end
  end
end
```
