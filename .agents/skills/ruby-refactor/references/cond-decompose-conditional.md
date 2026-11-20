---
title: Extract Complex Booleans into Named Predicates
tags: cond, decompose, predicate, readability
---

## Extract Complex Booleans into Named Predicates

Extract a repeated condition under one domain name when that name adds meaning. Preserve operand order and short-circuit behavior. Do not split a short condition into several one-use helper methods merely to satisfy a pattern.

**Before (inline compound boolean):**

```ruby
class PurchaseService
  def attempt_purchase(user, item)
    if user.age >= 18 && user.verified? && !user.suspended? && user.subscription.active?  # what business rule is this?
      charge_user(user, item)
    else
      deny_purchase(user, item)
    end
  end

  def show_premium_catalog(user)
    if user.age >= 18 && user.verified? && !user.suspended? && user.subscription.active?  # duplicated, will diverge
      render_catalog(user)
    end
  end
end
```

**Alternative (named predicate methods):**

```ruby
class PurchaseService
  def attempt_purchase(user, item)
    if eligible_for_purchase?(user)  # reads as a business rule
      charge_user(user, item)
    else
      deny_purchase(user, item)
    end
  end

  def show_premium_catalog(user)
    render_catalog(user) if eligible_for_purchase?(user)
  end

  private

  def eligible_for_purchase?(user)
    user.age >= 18 && user.verified? && !user.suspended? && user.subscription.active?
  end
end
```
