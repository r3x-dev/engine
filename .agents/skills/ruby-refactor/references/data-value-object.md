---
title: Replace Primitive Obsession with Value Objects
tags: data, value-object, primitive-obsession, domain
---

## Replace Primitive Obsession with Value Objects

Extract a value object when repeated validation belongs to an actual domain concept. Preserve normalization and persisted values; do not lowercase an email or change which value is sent to the mailer as an incidental refactor. Treat this regex as the example application contract, not complete email-address validation.

**Before (raw string with validation scattered across call sites):**

```ruby
class UserRegistration
  def register(email, name)
    # Validation duplicated wherever email is used
    raise ArgumentError, "invalid email" unless email.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)

    user = User.create!(email: email, name: name)
    Mailer.send_welcome(user.email)
    Analytics.track_signup(email.split("@").last) # domain extraction repeated elsewhere
    user
  end
end

class PasswordReset
  def request_reset(email)
    raise ArgumentError, "invalid email" unless email.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)

    token = SecureRandom.hex(20)
    ResetToken.create!(email: email, token: token)
    Mailer.send_reset(email)
  end
end
```

**Alternative (value object centralizes validation and behavior):**

```ruby
class EmailAddress
  PATTERN = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i

  attr_reader :address

  def initialize(address)
    raise ArgumentError, "invalid email" unless address.match?(PATTERN)

    @address = address.dup.freeze  # Preserve case and do not freeze the caller's string.
    freeze
  end

  # Domain behavior lives with the data that owns it
  def domain = address.split("@").last
  def to_s = address
  def ==(other) = other.is_a?(self.class) && address == other.address
  alias_method :eql?, :==
  def hash = address.hash
end

class UserRegistration
  def register(email, name)
    email = EmailAddress.new(email)

    user = User.create!(email: email.to_s, name: name)
    Mailer.send_welcome(user.email)  # Preserve the persisted value used by the original.
    Analytics.track_signup(email.domain)
    user
  end
end

class PasswordReset
  def request_reset(email)
    email = EmailAddress.new(email) # validates once — no duplication

    token = SecureRandom.hex(20)
    ResetToken.create!(email: email.to_s, token: token)
    Mailer.send_reset(email.to_s)
  end
end
```
