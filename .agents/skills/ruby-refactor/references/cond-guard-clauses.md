---
title: Replace Nested Conditionals with Guard Clauses
tags: cond, guard-clause, early-return, nesting
---

## Replace Nested Conditionals with Guard Clauses

Use guard clauses when they make the existing branch order easier to follow. Preserve short-circuit evaluation, error precedence, and the happy-path return value. Keep nesting when branches need a shared scope or when an early return would skip required cleanup. The example assumes Rails present? semantics.

**Before (deeply nested validation):**

```ruby
class PaymentAuthorizer
  def authorize(payment)
    if payment.amount > 0
      if payment.card.present?
        if payment.card.balance >= payment.amount
          if !payment.flagged_for_fraud?
            payment.charge!  # happy path buried under 4 levels of nesting
            { success: true, transaction_id: payment.transaction_id }
          else
            { success: false, error: "payment flagged for fraud review" }
          end
        else
          { success: false, error: "insufficient balance" }
        end
      else
        { success: false, error: "no card on file" }
      end
    else
      { success: false, error: "invalid payment amount" }
    end
  end
end
```

**Alternative (flat guard clauses with early returns):**

```ruby
class PaymentAuthorizer
  def authorize(payment)
    return { success: false, error: "invalid payment amount" } unless payment.amount > 0
    return { success: false, error: "no card on file" } unless payment.card.present?
    return { success: false, error: "insufficient balance" } unless payment.card.balance >= payment.amount
    return { success: false, error: "payment flagged for fraud review" } if payment.flagged_for_fraud?

    payment.charge!  # happy path at natural reading level
    { success: true, transaction_id: payment.transaction_id }
  end
end
```
