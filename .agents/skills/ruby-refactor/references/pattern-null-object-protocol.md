---
title: Implement Null Object with Full Protocol
tags: pattern, null-object, protocol, duck-typing
---

## Implement Null Object with Full Protocol

Use a local guest presentation object only for the explicitly defined display protocol. Keep authentication state separate: do not replace a nil-returning `current_user` with a truthy object globally. Preserve fallbacks for real users whose optional permissions or avatar are nil, and keep guards when they express intent more simply.

**Before (nil checks scattered across the entire call chain):**

```ruby
class ApplicationController < ActionController::Base
  def dashboard
    if current_user
      @name = current_user.name
      @permissions = current_user.permissions
    else
      @name = "Guest"
      @permissions = []
    end

    @display_name = if current_user
      current_user.to_s  # repeated nil checks in every action
    else
      "Anonymous Visitor"
    end

    @can_edit = current_user&.permissions&.include?("edit") || false
    @avatar_url = current_user&.avatar_url || "/images/default_avatar.png"
  end
end
```

**Alternative (GuestUser responds to full User protocol with safe defaults):**

```ruby
class GuestUser
  def name
    "Guest"
  end

  def to_s
    "Anonymous Visitor"
  end

  def permissions
    []  # Preserve an independently mutable display value.
  end

  def avatar_url
    "/images/default_avatar.png"
  end

  def authenticated?
    false
  end

  def admin?
    false
  end
end

class ApplicationController < ActionController::Base
  def dashboard
    user = current_user || GuestUser.new
    @name = user.name
    @permissions = user.permissions
    @display_name = user.to_s
    @can_edit = user.permissions&.include?("edit") || false
    @avatar_url = user.avatar_url || "/images/default_avatar.png"
  end
end
```

**See also:** [`cond-null-object`](cond-null-object.md) for a simpler single-attribute null object introduction.
