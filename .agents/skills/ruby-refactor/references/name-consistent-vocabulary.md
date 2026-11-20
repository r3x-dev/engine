---
title: Use One Word per Concept Across Codebase
tags: name, vocabulary, consistency, convention
---

## Use One Word per Concept Across Codebase

When different parts of a codebase use `fetch`, `get`, `retrieve`, and `load` for the same conceptual operation, developers waste time wondering whether the synonyms imply different behavior. Pick one word per concept and enforce it everywhere. Consistency lets developers predict method names without searching.

Distinguish local names from database columns, serialized keys, and public
methods. Rename external fields only within an approved schema/API migration;
otherwise improve local names while preserving those boundaries. Update callers
and keep comments that explain constraints or reasons the code cannot express.

**Before (synonyms for the same operation across services):**

```ruby
class UserService
  def fetch_user(id)
    User.find(id)
  end
end

class OrderService
  def get_order(id)  # get vs fetch — different word, same concept
    Order.find(id)
  end
end

class PaymentService
  def retrieve_payment(id)  # retrieve vs fetch — yet another synonym
    Payment.find(id)
  end
end

class InvoiceService
  def load_invoice(id)  # load vs fetch — readers wonder if this is lazy-loading
    Invoice.find(id)
  end
end

# Same problem with class-level naming
class UserController; end
class OrderManager; end      # manager vs controller
class PaymentHandler; end    # handler vs controller
class InvoiceProcessor; end  # processor vs controller
```

**Alternative (one word per concept, applied consistently):**

```ruby
class UserService
  def fetch_user(id)
    User.find(id)
  end
end

class OrderService
  def fetch_order(id)  # same verb for same concept
    Order.find(id)
  end
end

class PaymentService
  def fetch_payment(id)
    Payment.find(id)
  end
end

class InvoiceService
  def fetch_invoice(id)
    Invoice.find(id)
  end
end

# Consistent class-level naming — one suffix per role
class UserController; end
class OrderController; end
class PaymentController; end
class InvoiceController; end
```
