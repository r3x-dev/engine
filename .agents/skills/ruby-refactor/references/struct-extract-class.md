---
title: Extract Class for Single Responsibility
tags: struct, extract-class, srp, sandi-metz
---

## Extract Class for Single Responsibility

Extract a class only when a cohesive responsibility has a useful independent owner. Preserve the existing User accessors and methods in this example: email remains the original String or nil, and validation does not trim or coerce it. Do not enforce a class-size quota or introduce a value-object API migration unintentionally.

**Before (User class absorbing email logic):**

```ruby
class User
  attr_accessor :name, :email, :role

  def validate_email
    return false if email.nil? || email.strip.empty?

    email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
  end

  def email_domain
    email.split("@").last.downcase
  end

  def send_welcome_email
    return unless validate_email

    Mailer.deliver(
      to: email,
      subject: "Welcome, #{name}!",
      body: "Your account on #{email_domain} is ready."
    )
  end

  def corporate_email?
    !%w[gmail.com yahoo.com hotmail.com].include?(email_domain)
  end
end
```

**Alternative (extracted EmailAddress value object):**

```ruby
class User
  attr_accessor :name, :email, :role

  def validate_email
    EmailAddress.new(email).valid?
  end

  def email_domain
    EmailAddress.new(email).domain
  end

  def corporate_email?
    EmailAddress.new(email).corporate?
  end

  def send_welcome_email
    return unless validate_email
    Mailer.deliver(
      to: email,
      subject: "Welcome, #{name}!",
      body: "Your account on #{email_domain} is ready."
    )
  end
end

class EmailAddress
  CORPORATE_FREEMAIL = %w[gmail.com yahoo.com hotmail.com].freeze
  FORMAT = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

  def initialize(address)
    @address = address
  end

  def valid?
    return false if @address.nil? || @address.strip.empty?
    @address.match?(FORMAT)
  end

  def domain
    @address.split("@").last.downcase
  end

  def corporate?
    !CORPORATE_FREEMAIL.include?(domain)
  end
end
```

Keep these small delegating methods only when the extraction has a concrete maintenance benefit.
