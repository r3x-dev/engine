---
title: Flatten Deep Nesting with Early Extraction
tags: struct, nesting, complexity, extract-method
---

## Flatten Deep Nesting with Early Extraction

Flatten nesting without changing the failure contract. Keep the original error hashes and their precedence; replacing them with exceptions is a separate API change. Extract only the cohesive payment operation after all guards succeed.

**Before (4+ levels of nesting in payment processing):**

```ruby
class PaymentProcessor
  def process(payment)
    if payment.amount > 0
      if payment.currency_supported?
        account = Account.find_by(id: payment.account_id)
        if account
          if account.active?
            if account.balance >= payment.amount
              if !payment.flagged_for_review?
                transaction = account.debit(payment.amount)
                receipt = Receipt.create!(transaction: transaction, payment: payment)
                NotificationService.send_confirmation(account.owner, receipt)
                { success: true, receipt_id: receipt.id }
              else
                { success: false, error: "Payment flagged for manual review" }
              end
            else
              { success: false, error: "Insufficient balance" }
            end
          else
            { success: false, error: "Account is suspended" }
          end
        else
          { success: false, error: "Account not found" }
        end
      else
        { success: false, error: "Currency not supported" }
      end
    else
      { success: false, error: "Amount must be positive" }
    end
  end
end
```

**Alternative (flat methods with early returns):**

```ruby
class PaymentProcessor
  def process(payment)
    return { success: false, error: "Amount must be positive" } unless payment.amount > 0
    return { success: false, error: "Currency not supported" } unless payment.currency_supported?
    account = Account.find_by(id: payment.account_id)
    return { success: false, error: "Account not found" } unless account
    return { success: false, error: "Account is suspended" } unless account.active?
    return { success: false, error: "Insufficient balance" } unless account.balance >= payment.amount
    return { success: false, error: "Payment flagged for manual review" } if payment.flagged_for_review?

    execute_payment(account, payment)
  end

  private

  def execute_payment(account, payment)
    transaction = account.debit(payment.amount)
    receipt = Receipt.create!(transaction: transaction, payment: payment)
    NotificationService.send_confirmation(account.owner, receipt)
    { success: true, receipt_id: receipt.id }
  end
end
```

Reference: [Replace Nested Conditional with Guard Clauses](https://refactoring.com/catalog/replaceNestedConditionalWithGuardClauses.html)
