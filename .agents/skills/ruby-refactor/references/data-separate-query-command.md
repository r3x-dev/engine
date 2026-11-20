---
title: Separate Query Methods from Command Methods
tags: data, cqrs, query, command, side-effects
---

## Separate Query Methods from Command Methods

Add a side-effect-free query when callers need to inspect state without invoking a command. Keep useful command return values: a withdrawal returning its new balance is not inherently wrong. Preserve the existing withdraw API and do not infer that a query remains fresh or can be cached while state changes.

**Before (query and command tangled in one method):**

```ruby
class Account
  attr_reader :balance, :transactions

  def initialize(balance:)
    @balance = balance
    @transactions = []
  end

  def withdraw(amount)
    # Preserve the command's documented remaining-balance result.
    raise InsufficientFundsError, "balance too low" if amount > @balance

    @balance -= amount
    @transactions << { type: :withdrawal, amount: amount, at: Time.current }
    @balance
  end
end

account = Account.new(balance: 500.00)
remaining = account.withdraw(100.00) # Perform withdrawal and use its result.
```

**Alternative (query returns data, command mutates state):**

```ruby
class Account
  attr_reader :balance, :transactions

  def initialize(balance:)
    @balance = balance
    @transactions = []
  end

  # Query — read the current state; do not assume the answer remains fresh.
  def sufficient_funds?(amount)
    amount <= @balance
  end

  # Command — mutate state and preserve the documented balance result.
  def withdraw(amount)
    raise InsufficientFundsError, "balance too low" unless sufficient_funds?(amount)

    @balance -= amount
    @transactions << { type: :withdrawal, amount: amount, at: Time.current }
    @balance
  end
end

account = Account.new(balance: 500.00)
if account.sufficient_funds?(100.00)  # query — no side effects
  account.withdraw(100.00)            # command — explicit mutation
end
```

Keep validation inside the command. A prior sufficient_funds? check is not a
lock or a transaction; it cannot prevent concurrent withdrawals by itself.
