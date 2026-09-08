# Frontend

## Start with the rendered page

Prefer semantic HTML and standard Rails partials when they express the interface cleanly. Give a partial a meaningful piece of the page, with explicit locals. Extract helpers for reusable presentation logic rather than hiding the page structure behind wrappers.

In a Hotwire application, use Turbo for navigation and server-rendered updates; use Stimulus for small browser behaviors. Preserve the application's chosen frontend stack unless a migration is requested.

## Keep browser behavior local

Give a Stimulus controller one responsibility, such as submitting a form after a delay or opening a dialog. Use named targets and values to make its contract visible in the markup. Communicate through events when components should remain independent.

Clean up timers, listeners, and observers when the controller disconnects. Use native elements such as `button` and `dialog` before rebuilding their interaction model. Check installed Turbo and Stimulus APIs before adopting version-sensitive features.

## Keep shared fragments independent of the viewer

Cache the shared card body and render personalized controls outside that fragment:

```erb
<% cache card do %>
  <%= render "cards/body", card: card %>
<% end %>

<% if card.editable_by?(Current.user) %>
  <%= render "cards/actions", card: card %>
<% end %>
```

Keep `cards/body` viewer-independent and ensure any surrounding cache also respects this boundary. If personalized content must be cached, include all relevant rendering dependencies in its key. Enforce permissions on the server regardless of whether a control is visible.

## Let CSS express presentation

Prefer component names such as `.card` and `.card .title`, custom properties for shared values, and native layout primitives. Use cascade layers, nesting, and logical properties where they clarify the existing stylesheet. Keep the project's design tokens and browser support requirements; do not introduce a parallel CSS system for stylistic consistency.
