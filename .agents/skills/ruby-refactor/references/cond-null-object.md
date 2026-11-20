---
title: Replace nil Checks with Null Object
tags: cond, null-object, nil, duck-typing
---

## Replace nil Checks with Null Object

Use a Null Object only when absence has a defined domain default and several callers need the same protocol. Keep a simple nil guard when it is clearer. Assume `subscription` returns a subscription object or nil; do not overwrite the model association or make absent subscriptions truthy throughout the application.

**Before (nil guards scattered across call sites):**

```ruby
class AccountDashboard
  def display_plan(user)
    if user.subscription
      plan_name = user.subscription.plan
    else
      plan_name = "Free"
    end

    if user.subscription&.premium?
      show_premium_badge(user)
    end

    remaining = if user.subscription
      user.subscription.days_remaining  # every call site repeats the nil guard
    else
      0
    end

    render_dashboard(plan_name: plan_name, days_remaining: remaining)
  end
end
```

**Alternative (Null Object with matching interface):**

```ruby
class NullSubscription
  def plan
    "Free"
  end

  def premium?
    false
  end

  def days_remaining
    0
  end

  def active?
    false
  end
end

class AccountDashboard
  def display_plan(user)
    subscription = user.subscription || NullSubscription.new
    plan_name = subscription.plan
    show_premium_badge(user) if subscription.premium?
    remaining = subscription.days_remaining

    render_dashboard(plan_name: plan_name, days_remaining: remaining)
  end
end
```

**See also:** [`pattern-null-object-protocol`](pattern-null-object-protocol.md) for implementing the full protocol with multiple methods.
