---
name: r3x-workflows
description: Write, refactor, review or diagnose R3x workflow packs in this Rails application. Covers resumable state, caching, delivery, integrations and local verification. Use for framework changes that alter those workflow contracts too.
---

# R3x Workflows

Workflows execute inside the booted R3x Rails application. They can depend on its
Rails version, Active Support, Action View and available gems; standalone Ruby
execution and portability to other runtimes are not requirements.

Read the repository's [AGENTS.md](../../../AGENTS.md) and the affected pack's
instructions before changing code. Preserve unrelated catalog changes: the engine
and a mounted workflow catalog can be separate Git repositories.

## Choose the relevant reference

Read these before designing or changing the corresponding behavior; do not load all
references for every task.

| Task | Read |
| --- | --- |
| Add a pack, change triggers, steps, guards, callbacks or catalog loading | [Runtime and structure](references/runtime.md) |
| Resume work, save input, deduplicate items, reserve processing or deliver to multiple destinations | [State and delivery](references/state-and-delivery.md) |
| Cache expensive calls or change request/queue retries | [Caching and retries](references/caching-and-retries.md) |
| Use HTTP, MCP, Sheets or LLMs, including structured output and typed decisions | [Integrations and LLMs](references/integrations-and-llm.md) |
| Run locally, configure dry run/Vault, inspect logs or verify a workflow | [Local verification](references/local-verification.md) |

For framework implementation, read the owning source linked from the reference.
Those links identify the contract owner; they are not instructions to read every
client or duplicate its implementation.

## Prefer existing Rails and gem code

- Before custom parsing, collection handling, HTML generation or integration code,
  look for an existing stdlib, Rails helper, gem API or R3x client that fits the
  required behavior. Prefer maintained, tested implementations when clearer.
  Preserve validation, escaping and meaningful nil/false values.
- Check [Gemfile](../../../Gemfile), [Gemfile.lock](../../../Gemfile.lock) and the
  [runtime profile](../../../config/runtime_profile.rb) for production availability.
  Headless workers skip web-only gems and helper loading. Explicitly load/include
  needed Action View helpers in a rendering component without depending on a request
  or controller. Use `tag`, `link_to` and `safe_join` when appropriate; never mark
  model/source text `html_safe` just to make it render.
- Follow the repository's lazy-loading policy for optional/heavy gems. Verify
  version-sensitive APIs against the installed version; adding wrappers or new gems
  is justified only by a current requirement.
- Keep small parsing close to its source. For an explicitly allowed fallback among
  equivalent fields, `value.presence || other.presence` can express the rule clearly;
  do not introduce fallback behavior for missing required data.
- Keep `run` and steps focused on collecting, preparing and delivering results.
  Extract formatting/parsing when it becomes a distinct responsibility, using a
  small pack-owned component. Avoid portability and compatibility layers.

## Preserve these boundaries

- Implement `run` on `R3x::Workflow::Base`; use `ctx` during execution.
  `step` is a resumable boundary, not a block-result helper.
- Give every declared trigger a stable semantic `key:`. Preserve it when changing
  schedules or declaration order; see [runtime and structure](references/runtime.md#scheduling)
  before changing existing trigger identities.
- Save run input and required intermediate results across resumptions. TTL cache
  cannot establish stable input, permanent deduplication or exactly-once delivery.
- Establish required delivery and provider success before marking completion.
  Unknown external outcomes require reconciliation, not blind retries.
- Keep new side effects dry by default. A global dry run does not imply that reads,
  paid generation or every client become no-ops; inspect the affected boundary.
- Let unexpected errors and invalid states propagate. Rescue only at an intentional
  recovery/cleanup boundary or to translate a known error without hiding failure.
- Keep concrete provider payloads, retry budgets, prompts, recovery notes and
  verification evidence in the owning pack. Shared instructions and examples use
  fictional workflows and placeholder configuration.
- Follow the repository's validation and Git authorization policy. Normally verify
  user packs manually; add pack-owned tests only when explicitly requested. Report
  local, CI, deployed and live evidence separately.

For a composed example, read
[the worked digest](../../../docs/workflows/example_multi_step_digest.md).
It documents its deliberately simplified delivery behavior; review those limitations
before using it as a production template.
