---
title: Encapsulate Collections Behind Domain Methods
tags: data, encapsulate, collection, immutability
---

## Encapsulate Collections Behind Domain Methods

Treat collection encapsulation as an API change when callers currently mutate the exposed Array. Require that migration to be in scope and update its callers. A frozen shallow copy protects only collection membership; its item objects remain shared and mutable. Specify whether item mutation and duplicate-merging are also part of the accepted contract.

**Before (exposed collection allows uncontrolled mutation):**

```ruby
class ShoppingCart
  attr_accessor :items

  def initialize
    @items = []
  end

  def total
    items.sum { |item| item.price * item.quantity }
  end
end

cart = ShoppingCart.new
cart.items << CartItem.new(sku: "SHOE-42", price: 89.99, quantity: 1)
cart.items << CartItem.new(sku: "SHOE-42", price: 89.99, quantity: 1) # duplicate — no guard
cart.items.clear # caller can silently empty the cart
```

**Alternative (frozen collection with domain methods enforcing rules):**

```ruby
class ShoppingCart
  def initialize
    @items = []
  end

  def items
    @items.dup.freeze # external callers get a frozen snapshot
  end

  def add_item(item)
    existing = @items.find { |i| i.sku == item.sku }
    if existing
      existing.increment_quantity(item.quantity)
    else
      @items << item
    end
    self
  end

  def remove_item(sku)
    @items.reject! { |item| item.sku == sku }
    self
  end

  def total
    @items.sum { |item| item.price * item.quantity }
  end
end

cart = ShoppingCart.new
cart.add_item(CartItem.new(sku: "SHOE-42", price: 89.99, quantity: 1))
cart.add_item(CartItem.new(sku: "SHOE-42", price: 89.99, quantity: 1)) # merges quantity
cart.items << CartItem.new(sku: "HAT-01", price: 24.99, quantity: 1) # raises FrozenError
```
