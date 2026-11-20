---
title: Enforce Law of Demeter with Delegation
tags: couple, law-of-demeter, delegate, forwardable
---

## Enforce Law of Demeter with Delegation

Expose a stable domain operation when repeated callers depend on an internal object graph. Do not enforce a dot-count rule or add delegates without a concrete caller need. Preserve the full path: city and postal_code belong to customer.address, not automatically to customer. Use Rails delegate only in a project that loads it.

**Before (chained calls couple caller to 3 levels of structure):**

```ruby
class OrderMailer
  def send_confirmation(order)
    # Each dot is a dependency — 3 objects must stay stable
    city = order.customer.address.city
    email = order.customer.email
    postal_code = order.customer.address.postal_code

    deliver(
      to: email,
      subject: "Order confirmed",
      body: "Shipping to #{city}, #{postal_code}"
    )
  end
end
```

**Alternative (delegate through the immediate collaborator):**

```ruby
class Customer
  delegate :city, :postal_code, to: :address
end

class Order
  # Expose only what callers need — internal structure stays private
  delegate :email, to: :customer
  delegate :city, :postal_code, to: :customer, prefix: true
end

class OrderMailer
  def send_confirmation(order)
    city = order.customer_city
    email = order.email
    postal_code = order.customer_postal_code

    deliver(
      to: email,
      subject: "Order confirmed",
      body: "Shipping to #{city}, #{postal_code}"
    )
  end
end
```

**Alternative (stdlib Forwardable for non-Rails projects):**

```ruby
require "forwardable"

class Customer
  extend Forwardable
  def_delegators :address, :city, :postal_code
end
```
