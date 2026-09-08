# Models and Ruby expression

## Find the natural receiver

Prefer `card.close`, `board.publish`, and `subscription.cancel` when the receiver owns that behavior. Name queries `closed?`, `published?`, and `cancelled?`; avoid indirect names such as `update_closed_status`.

Use a plain Ruby object for a distinct domain concept that needs no table, such as `Event::Description`. Namespace it under its owning concept when that clarifies the relationship. Keep multi-system orchestration in its natural application boundary; do not force it into Active Record merely to avoid a service object.

## Extract capabilities

Name concerns for cohesive behavior: `Closeable`, `Watchable`, `Publishable`. Keep the capability's associations, scopes, and methods together. Extract when the concept makes the model easier to understand or provides real reuse; avoid arbitrary size limits and generic `Helpers` modules.

## Choose a state representation

Use a closure record when closing has an actor, timestamp, or behavior of its own. Let the card expose the vocabulary:

```ruby
def closed?
  closure.present?
end

def close(creator:)
  create_closure!(creator: creator)
end

def reopen
  closure&.destroy!
end
```

Treat this as a naming sketch over an existing association. Define repeated-call behavior, uniqueness, and atomicity from the actual domain contract before implementing it. Keep simple flags such as `dark_mode_enabled` as booleans when a separate record adds no meaning.

## Name queries for their use

Prefer scopes such as `chronologically`, `alphabetically`, `unassigned`, and `published`. Use `preloaded` only when there is a clear common association set; name distinct loading shapes for their actual use.

Keep query composition in relations when possible. Introduce a local when it names a useful intermediate result or avoids repeating work.

## Make the main path obvious

Match the repository formatter. In a project using these conventions, prefer readable symbol arrays and private helper grouping:

```ruby
before_action :set_message, only: %i[ show edit update destroy ]

private
  def set_message
    @message = @room.messages.find(params[:id])
  end
```

Use guard clauses for exceptional exits, a ternary for a short choice, and `case` when several branches read more clearly together. Choose expression form for readability rather than to minimize lines.

Use bang persistence methods when failure should interrupt the operation. Use non-bang methods when validation failure is an expected branch, and handle it explicitly.

Keep lifecycle bookkeeping in small callbacks when it belongs to every persistence path. Put multi-step business operations in explicit methods. Use database constraints for invariants and model validations for useful feedback; they serve complementary purposes.
