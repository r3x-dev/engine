---
title: Extract Algorithm Variations into Strategy Objects
tags: pattern, strategy, open-closed, algorithm
---

## Extract Algorithm Variations into Strategy Objects

Use strategy objects only for existing variations whose independent behavior or reuse justifies the extra classes. Keep a short case when it is clearer. Preserve every tier and fallback, and use shared instances only for stateless strategies; freezing the registry does not freeze its values.

**Before (case/when coupling all pricing logic into one method):**

```ruby
class PricingCalculator
  def compute(order, tier)
    case tier
    when :standard
      subtotal = order.line_items.sum(&:price)
      subtotal *= 0.95 if order.line_items.size >= 10
      subtotal
    when :premium
      subtotal = order.line_items.sum(&:price) * 0.85
      subtotal -= 20.0 if order.recurring?
      subtotal
    when :enterprise
      # Every new tier forces a change here
      subtotal = order.line_items.sum(&:price) * 0.70
      subtotal -= 50.0 if order.annual_contract?
      [subtotal, order.negotiated_minimum].max
    else
      raise ArgumentError, "Unknown tier: #{tier}"
    end
  end
end
```

**Alternative (strategy objects with common `call` interface):**

```ruby
class StandardPricing
  def call(order)
    subtotal = order.line_items.sum(&:price)
    subtotal *= 0.95 if order.line_items.size >= 10
    subtotal
  end
end

class PremiumPricing
  def call(order)
    subtotal = order.line_items.sum(&:price) * 0.85
    subtotal -= 20.0 if order.recurring?
    subtotal
  end
end

class EnterprisePricing
  def call(order)
    subtotal = order.line_items.sum(&:price) * 0.70
    subtotal -= 50.0 if order.annual_contract?
    [subtotal, order.negotiated_minimum].max
  end
end

class PricingCalculator
  STRATEGIES = {
    standard:   StandardPricing.new,
    premium:    PremiumPricing.new,
    enterprise: EnterprisePricing.new
  }.freeze

  def compute(order, tier)
    strategy = STRATEGIES.fetch(tier) do
      raise ArgumentError, "Unknown tier: #{tier}"
    end
    strategy.call(order) # new tiers need only a new class and one hash entry
  end
end
```
