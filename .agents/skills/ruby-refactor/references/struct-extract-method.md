---
title: Extract Long Methods into Focused Units
tags: struct, extract-method, sandi-metz, readability
---

## Extract Long Methods into Focused Units

Extract a cohesive operation when a name makes its responsibility clearer. Preserve validation order, calculation, external effects, and return value. Do not enforce an arbitrary method line count or extract one-use wrappers without a clarity benefit. The keyword-value omission syntax below requires Ruby 3.1+.

**Before (monolithic method with multiple responsibilities):**

```ruby
class OrderProcessor
  def process(order)
    # Validation, calculation, and payment all tangled together
    raise ArgumentError, "Order must have items" if order.items.empty?
    raise ArgumentError, "Customer email required" if order.customer.email.nil?

    subtotal = order.items.sum { |item| item.price * item.quantity }
    discount = 0
    if order.customer.loyalty_years > 5
      discount = subtotal * 0.15
    elsif order.customer.loyalty_years > 2
      discount = subtotal * 0.10
    end
    subtotal_after_discount = subtotal - discount

    tax = subtotal_after_discount * 0.08
    shipping = subtotal_after_discount > 100 ? 0 : 12.99
    total = subtotal_after_discount + tax + shipping

    payment_result = order.payment_method.charge(total)
    raise PaymentError, "Charge failed: #{payment_result.error}" unless payment_result.success?

    order.update!(
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      shipping: shipping,
      total: total,
      status: :completed,
      completed_at: Time.current
    )
  end
end
```

**Alternative (extract named responsibilities):**

```ruby
class OrderProcessor
  def process(order)
    validate(order)
    subtotal = calculate_subtotal(order)
    discount = apply_discount(order.customer, subtotal)
    tax, shipping, total = calculate_total(subtotal - discount)
    charge_payment(order.payment_method, total)
    finalize(order, subtotal:, discount:, tax:, shipping:, total:)
  end

  private

  def validate(order)
    raise ArgumentError, "Order must have items" if order.items.empty?
    raise ArgumentError, "Customer email required" if order.customer.email.nil?
  end

  def calculate_subtotal(order)
    order.items.sum { |item| item.price * item.quantity }
  end

  def apply_discount(customer, subtotal)
    return subtotal * 0.15 if customer.loyalty_years > 5
    return subtotal * 0.10 if customer.loyalty_years > 2

    0
  end

  def calculate_total(subtotal_after_discount)
    tax = subtotal_after_discount * 0.08
    shipping = subtotal_after_discount > 100 ? 0 : 12.99
    [tax, shipping, subtotal_after_discount + tax + shipping]
  end

  def charge_payment(payment_method, total)
    payment_result = payment_method.charge(total)
    raise PaymentError, "Charge failed: #{payment_result.error}" unless payment_result.success?
  end

  def finalize(order, subtotal:, discount:, tax:, shipping:, total:)
    order.update!(subtotal:, discount:, tax:, shipping:, total:, status: :completed, completed_at: Time.current)
  end
end
```

Choose extraction boundaries from behavior and state ownership, not a line-count quota.
