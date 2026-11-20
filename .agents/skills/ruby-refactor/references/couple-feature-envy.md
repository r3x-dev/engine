---
title: Move Method to Resolve Feature Envy
tags: couple, feature-envy, move-method, cohesion
---

## Move Method to Resolve Feature Envy

Move cohesive domain calculation only when it belongs with the data owner. Preserve one snapshot of the inputs; do not turn a single subtotal calculation into several scans through mutually calling accessors. Keep formatting in the printer and preserve the existing output.

**Before (OrderPrinter reaches into Order for every value):**

```ruby
class OrderPrinter
  def format_total(order)
    # Every line pulls data from order — this method envies Order
    subtotal = order.items.sum { |item| item.price * item.quantity }
    discount = subtotal * order.discount_rate
    tax = (subtotal - discount) * order.tax_rate
    total = subtotal - discount + tax

    "Subtotal: #{subtotal}, Discount: #{discount}, Tax: #{tax}, Total: #{total}"
  end
end
```

**Alternative (calculation moves to Order, printer only formats):**

```ruby
class Order
  def pricing_summary
    subtotal = items.sum { |item| item.price * item.quantity }
    discount = subtotal * discount_rate
    tax = (subtotal - discount) * tax_rate
    { subtotal: subtotal, discount: discount, tax: tax,
      total: subtotal - discount + tax }
  end
end

class OrderPrinter
  def format_total(order)
    values = order.pricing_summary
    "Subtotal: #{values[:subtotal]}, Discount: #{values[:discount]}, " \
      "Tax: #{values[:tax]}, Total: #{values[:total]}"
  end
end
```
