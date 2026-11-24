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

## Discord messages

```ruby
trigger :discord_message, key: :posters, channel_id: "123456789012345678", attachments: :images, run_per: :message
```

The scheduler polls subscribed channels every 60 seconds. A new subscription starts
at the current end of the channel. Restarting with the same workflow and trigger
keys resumes from the saved message ID. Give a different channel a new trigger key.

Choose `run_per: :message` for one run with all matching images, or
`run_per: :attachment` for a separate run per image. Each run receives
`channel_id`, `message_id`, `content` and an ordered `attachments` array in
`ctx.trigger.payload`. Each attachment carries its original Discord ID. The workflow
uses those IDs to retrieve the images. Only messages from allowed human authors
with image attachments on the message itself qualify.

Enable Read Message History and Message Content before the first poll. Discord
can return an empty history or omit attachment data when these permissions are
missing. Restoring access can expose older messages after an empty initial read,
and messages already passed by the cursor will not be revisited.
