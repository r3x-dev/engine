---
name: ce-dhh-rails-style
description: Apply DHH/37signals coding style to Rails implementation, refactoring, or review when the user asks for DHH, 37signals, Basecamp, HEY, Campfire, or vanilla Rails style, or repository instructions explicitly adopt it. Do not activate solely because code uses Ruby or Rails. Focus on domain naming, object design, REST resources, and readable Rails idioms, not infrastructure or stack migrations.
---

# DHH / 37signals Rails Style

Use this guide as a coding-style lens. Give explicit user instructions and repository conventions precedence over its preferences. Preserve established architecture and behavior unless the requested change includes redesigning them.

Infer the relevant area from the task and existing code. Read only the references needed for that area; for reviews, start with the diff. Apply preferences where they clarify the requested change, without introducing a category-selection or approval workflow.

## Core style

- Put behavior on the domain object that naturally owns it: `card.close`, `board.publish`, `subscription.cancel`.
- Name operations with domain verbs, predicates with `?`, and objects with meaningful nouns. Prefer `Card::Closure` to a generic `CardManager`.
- Express state transitions as REST resources when they have a useful identity or lifecycle: create a closure to close a card, destroy it to reopen.
- Keep controllers focused on scoped lookup, permission enforcement, invoking behavior, and the response.
- Group a cohesive model capability in a concern such as `Closeable` or `Watchable`. Keep small models direct; extraction needs a clearer concept, not a line-count target.
- Prefer familiar Ruby and Rails primitives before introducing another abstraction. Use plain Ruby domain objects for behavior that does not need persistence.
- Consider a state record when actor, timestamp, history, or lifecycle matters. Keep a boolean for a genuinely binary attribute.
- Make the main path easy to read. Use short methods, intention-revealing locals, and private helpers that name meaningful steps.

## References

- [Controllers](references/controllers.md): resource naming, thin actions, scoped concerns.
- [Models](references/models.md): domain receivers, capability concerns, state, scopes, Ruby expression style.
- [Frontend](references/frontend.md): partials, server-rendered HTML, small Stimulus behaviors, CSS.
- [Architecture](references/architecture.md): domain boundaries, shallow jobs, request context.
- [Testing](references/testing.md): readable behavior tests and meaningful fixture names.
- [Dependencies](references/gems.md): choosing the smallest adequate existing primitive.

## Applying the lens

Treat these patterns as preferences inspired by 37signals, not universal Rails correctness rules. Distinguish a style suggestion from a defect during review and explain the concrete benefit before proposing an extraction or a new record.

Use the project's installed versions and documentation for version-sensitive APIs. Keep authentication, authorization, tenancy, and other security mechanisms governed by the project's design and current framework guidance; this skill provides no replacement implementations.

Follow the project's testing workflow and existing test stack. Match verification to the changed behavior and risk; broaden it only for failures, unresolved concerns, or required project checks. Do not introduce tests that only mirror a cosmetic edit.

## Sources

Treat the [Unofficial 37signals/DHH Rails Style Guide](https://github.com/marckohlbrugge/unofficial-37signals-coding-style-guide) by Marc Köhlbrugge as inspiration, not an authoritative specification. Preserve its provenance: the original guide is LLM-generated, may contain inaccuracies, identifies Fizzy examples as O'Saasy-licensed, and is not endorsed by 37signals.

Refer to the [official GPT-6 Astra prompting guidance](https://developers.openai.com/api/docs/guides/latest-model?model=gpt-6-astra) for the instruction-design basis of this guide: explicit user priority, task follow-through, and proportionate verification.
