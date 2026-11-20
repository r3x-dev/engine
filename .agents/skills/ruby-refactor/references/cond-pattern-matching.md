---
title: Use Pattern Matching for Structural Conditions
tags: cond, pattern-matching, ruby3, destructuring
---

## Use Pattern Matching for Structural Conditions

Use pattern matching on Ruby 3.0+ only if it clarifies the schema. In this example, require ordinary symbol-keyed Hashes for each populated nested object; allow nil/false to represent missing data. Preserve the original distinctions between empty, missing, incomplete, and malformed responses, including falsey values. Keep guard clauses instead if they are simpler.

**Before (nested hash checks with manual nil guards):**

```ruby
class PaymentResponseParser
  def extract_transaction(response)
    if response[:data]
      if response[:data][:transaction]
        txn = response[:data][:transaction]
        if txn[:id] && txn[:status] == "completed" && txn[:amount]
          if txn[:amount][:value] && txn[:amount][:currency]  # 4 levels deep, easy to miss a nil check
            build_record(
              id: txn[:id],
              value: txn[:amount][:value],
              currency: txn[:amount][:currency]
            )
          else
            handle_malformed_response(response)
          end
        else
          handle_incomplete_transaction(response)
        end
      else
        handle_missing_transaction(response)
      end
    else
      handle_empty_response(response)
    end
  end
end
```

**Alternative (pattern matching with destructuring):**

```ruby
class PaymentResponseParser
  def extract_transaction(response)
    case response
    in { data: { transaction: { id:, status: "completed",
          amount: { value:, currency: } } } } if id && value && currency
      build_record(id: id, value: value, currency: currency)
    else
      data = response[:data]
      return handle_empty_response(response) unless data
      txn = data[:transaction]
      return handle_missing_transaction(response) unless txn
      unless txn[:id] && txn[:status] == "completed" && txn[:amount]
        return handle_incomplete_transaction(response)
      end
      handle_malformed_response(response)
    end
  end
end
```

**See also:** [`modern-pattern-matching`](modern-pattern-matching.md) for additional pattern matching syntax and features.
