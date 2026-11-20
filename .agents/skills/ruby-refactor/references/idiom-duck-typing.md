---
title: Use respond_to? Over is_a? for Type Checking
tags: idiom, duck-typing, respond-to, polymorphism
---

## Use respond_to? Over is_a? for Type Checking

Use an explicit behavior protocol when multiple real implementations need it. Treat broadening accepted types as an API decision, not an equivalent replacement for is_a?. Remember that is_a? already accepts subclasses. Preserve branch priority and conversion errors; a respond_to? check alone does not prove protocol semantics.

**Before (type checking couples to class hierarchy):**

```ruby
class NotificationDispatcher
  def dispatch(destination, message)
    if destination.is_a?(String)  # Accept String and its subclasses under the original API.
      send_to_email(destination, message)
    elsif destination.is_a?(Array)
      destination.each { |dest| dispatch(dest, message) }
    elsif destination.is_a?(User)  # Accept User subclasses; unrelated adapters need an explicit protocol.
      send_to_user(destination, message)
    else
      raise ArgumentError, "unsupported destination type: #{destination.class}"
    end
  end
end
```

**Alternative (check behavior, not ancestry):**

```ruby
class NotificationDispatcher
  def dispatch(destination, message)
    if destination.respond_to?(:to_str)  # any string-like object works
      send_to_email(destination.to_str, message)
    elsif destination.respond_to?(:each)  # any enumerable works
      destination.each { |dest| dispatch(dest, message) }
    elsif destination.respond_to?(:email)  # any object with an email works
      send_to_user(destination, message)
    else
      raise ArgumentError, "destination must respond to :to_str, :each, or :email"
    end
  end
end
```
