# Dependencies

## Prefer the smallest adequate existing tool

Check whether an existing Rails primitive expresses the requirement: a model method for domain behavior, a partial for a view fragment, a helper for formatting, or Active Job for queued execution.

Before adding a generic service framework or wrapper, name the concept it introduces and the complexity it removes. Prefer a direct implementation when it is small, understandable, and has a clear owner.

Evaluate dependency cost through maintenance, correctness, and operational needs, not a comparison between a short custom implementation and the gem's total line count. Use a maintained library when the problem warrants it; authentication and security are not code-golf exercises.

Treat Minitest, fixtures, Hotwire, and the Solid stack as examples of the 37signals preference for integrated Rails tools. Preserve existing dependencies unless changing them is part of the task. Avoid brand-based allowlists, denylists, and automatic stack substitutions.
