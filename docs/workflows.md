# Workflows

R3x loads Ruby workflow packs into its Rails application. Each pack declares its
triggers, prepares data and delivers results using the engine's integration clients.
A catalog can live in a separate repository; `R3X_WORKFLOW_PATHS` selects it.

The maintained authoring guide is the
[R3x workflow skill](../.agents/skills/r3x-workflows/SKILL.md). Its entrypoint explains
the shared rules and selects task-specific references:

- [Runtime and structure](../.agents/skills/r3x-workflows/references/runtime.md)
- [State, resumptions and delivery](../.agents/skills/r3x-workflows/references/state-and-delivery.md)
- [Caching and retries](../.agents/skills/r3x-workflows/references/caching-and-retries.md)
- [Integrations and LLMs](../.agents/skills/r3x-workflows/references/integrations-and-llm.md)
- [Local verification](../.agents/skills/r3x-workflows/references/local-verification.md)

See the [worked digest](workflows/example_multi_step_digest.md) for a composed
example and its delivery limitations. Environment and deployment setup remain in
[environment.md](environment.md) and [deployment.md](deployment.md).
