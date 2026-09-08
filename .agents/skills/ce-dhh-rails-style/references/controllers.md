# Controllers

## Give an operation a resource

Prefer a noun that describes the domain change when a controller accumulates custom actions:

```text
POST   /cards/:card_id/closure    -> create a closure
DELETE /cards/:card_id/closure    -> remove the closure
POST   /boards/:board_id/watching -> start watching
```

Use a singular resource for one relationship per parent and plural resources for collections. Keep nesting shallow enough to make the resource clear. Preserve existing public routes unless changing them is part of the task.

## Keep actions readable

Let an action read as lookup, permission check, domain operation, response. Put the meaning of closing a card on the card; keep HTTP details in the controller. Render validation failures through the project's normal form or API response path.

Extract a shared lookup concern when several controllers operate on the same parent:

```ruby
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find(params[:card_id])
    end
end
```

Adapt `accessible_cards` to the application's existing authorized scope; it is an application method, not a Rails API. Preserve action-specific authorization as well as record visibility.

Use concerns for a named shared responsibility. Avoid assembling a base controller from unrelated one-method modules.

## Let the response follow the application

Use redirects and HTML, Turbo templates, or JSON according to the existing interface. Keep response composition close to its view. Extract a rendering helper when several actions share a meaningful response, rather than wrapping every Rails call.
