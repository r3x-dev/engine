---
title: Consider Polymorphism for Existing Variants
tags: cond, polymorphism, case-when
---

## Consider Polymorphism for Existing Variants

Keep a straightforward case/when for a small closed set of behaviors. Introduce
polymorphism only when existing variants need independent state or behavior and
repeated dispatch sites make a real change difficult.

1. Inventory all supported variants and the fallback. For a notification
   dispatcher, preserve email, SMS, and push; do not omit push from the registry
   merely because its implementation resembles another branch.
2. Move the complete behavior and its dependencies. Keep validator ownership
   explicit; a newly extracted class cannot call a helper that exists only on
   the old service without receiving or moving that dependency.
3. Preserve validation order, payload fields, external calls, return values,
   and the original exception for an unknown type.
4. Keep the existing caller-facing entry point unless changing it is authorized.
5. Instantiate stateful handlers per operation or give them an explicit lifetime.
   Do not put shared mutable handler instances in a frozen registry and assume
   that freezing the Hash makes its values immutable.
6. Test every original branch with recording fakes before and after extraction,
   including invalid input and the unknown-type fallback.

Do not add a base class, factory, and registry merely to replace one short case.
Prefer a local method extraction when it provides the same clarity with fewer
objects and fewer dependencies.
