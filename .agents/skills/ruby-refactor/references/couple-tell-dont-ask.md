---
title: "Tell Objects What to Do, Don't Query Their State"
tags: couple, tell-dont-ask, encapsulation, command
---

## Tell Objects What to Do, Don't Query Their State

Move a state transition to its owner when that makes the domain contract clearer. Preserve guards, mutation order, and return values. In this example, a negative pending total must remain unchanged; neither charging it nor marking it paid preserves the original behavior. Assume stable ordinary readers during one call.

**Before (caller queries state then acts on behalf of the object):**

```ruby
class PaymentProcessor
  def process(order)
    # Caller interrogates order internals — rules duplicated everywhere this pattern appears
    if order.status == :pending && order.total > 0
      order.payment_method.charge(order.total)
      order.status = :paid
      order.paid_at = Time.current
    elsif order.status == :pending && order.total.zero?
      order.status = :paid
      order.paid_at = Time.current
    end
  end
end
```

**Alternative (tell the object to handle its own transition):**

```ruby
class Order
  def process_payment
    return unless status == :pending

    if total > 0
      payment_method.charge(total)
    elsif !total.zero?
      return
    end
    self.status = :paid
    self.paid_at = Time.current
  end
end

class PaymentProcessor
  def process(order)
    order.process_payment
  end
end
```
