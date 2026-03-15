# Instructions

This Rails app uses a small set of preferred libraries for common integration work. Follow these defaults for new code and agent-authored changes unless an existing subsystem already requires a different interface.

## JSON

- Prefer `MultiJson` for JSON parsing and serialization work.
- Reasoning: it gives the app one consistent JSON abstraction instead of scattering direct `JSON` stdlib usage across the codebase, which makes adapter swaps and shared conventions easier later.

## HTTP

- Prefer `Faraday` for outbound HTTP and API integrations.
- Reasoning: it is already a direct project dependency and gives us a standard place for middleware, retries, authentication, adapters, and test stubbing instead of ad hoc HTTP clients.

## Scope

- Apply these as defaults for new work.
- Do not rewrite existing code only to satisfy these preferences unless the task explicitly calls for that refactor.
