---
title: Use case/in for Structural Pattern Matching
tags: modern, pattern-matching, case-in, ruby3
---

## Use case/in for Structural Pattern Matching

Match structure without silently replacing truthiness checks with key-presence checks. Require ordinary symbol-keyed Hashes for populated data/user/error objects in this example, with nil/false for absent objects. On Ruby 3.0+, preserve fallback messages and treat any truthy verified value as true, as the original does.

**Before (chained nil guards for nested hash access):**

```ruby
class ApiResponseParser
  def extract_user_email(response)
    if response[:data] && response[:data][:user] && response[:data][:user][:email]
      email = response[:data][:user][:email]  # 3 redundant traversals of the same path
      if response[:data][:user][:verified]
        { email: email, verified: true }
      else
        { email: email, verified: false }
      end
    elsif response[:error]
      { error: response[:error][:message] || "unknown error" }
    else
      { error: "malformed response" }
    end
  end
end
```

**Alternative (pattern matching with destructuring):**

```ruby
class ApiResponseParser
  def extract_user_email(response)
    case response
    in { data: { user: { email: } => user } } if email
      { email: email, verified: !!user[:verified] }
    in { error: error } if error
      { error: error[:message] || "unknown error" }
    else
      { error: "malformed response" }
    end
  end
end
```

**See also:** [`cond-pattern-matching`](cond-pattern-matching.md) for replacing nested hash access conditionals.
