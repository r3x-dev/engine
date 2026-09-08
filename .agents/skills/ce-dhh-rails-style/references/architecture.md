# Domain boundaries

## Put behavior where its vocabulary belongs

Start with the existing domain objects. Move an operation onto its natural receiver when that reduces indirection. Introduce a new object when it represents a distinct concept with its own responsibilities, not merely because each action needs a class.

Keep persistence optional for domain objects. Use ordinary Ruby objects for descriptions, calculations, and explicit workflows spanning several collaborators. Choose a name that explains the job instead of a generic `Manager` or `Processor`.

## Make jobs read like delegation

Keep a job shallow when its role is scheduling domain behavior:

```ruby
class NotifyWatchersJob < ApplicationJob
  def perform(card)
    card.notify_watchers
  end
end
```

Use a `_later` method when it provides a useful domain-facing enqueue operation. Add a `_now` variant only when callers need that distinction. Avoid layers of forwarding methods with no separate purpose.

Keep orchestration on the job when execution state, resumable steps, or queue semantics are its responsibility. Preserve transaction, retry, and delivery guarantees rather than extracting behavior for appearance alone. Determine those guarantees from the configured backend and database connections.

## Keep request context intentional

Use an established `Current` object for request-scoped identity or context. Pass arguments explicitly when they make ownership clearer or when code runs outside that scope. Derive background-job context from persisted input rather than assuming an HTTP request remains available.

Keep deployment, database topology, authentication, tenancy, and event retention as project decisions. Apply the naming and object-design lens within those boundaries.
