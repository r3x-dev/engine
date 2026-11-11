# Integrations and LLMs

Read before choosing tools, provider payloads, structured generation or typed decisions.
Sources: [client factory](../../../../lib/r3x/workflow/context/client.rb),
[clients](../../../../app/lib/r3x/client),
[environment contract](../../../../docs/environment.md).

## Boundary ownership

Use `ctx.client.*` for existing integrations. Shared clients own protocol, transport,
authentication and provider errors; packs own tool choices, payload schemas and
interpretation. Resolve credentials through env-name references, not raw secret
objects. Keep heavy integrations lazy using the existing GemLoader policy.

For HTTP, reuse one `ctx.client.http` outside a loop; the factory returns a fresh
client each time. Use `ctx.client.persistent_http(...) { |http| ... }` only for a
controlled scope with a measured connection-reuse benefit. Do not add persistence
options to thin clients speculatively. [HTTP client](../../../../app/lib/r3x/client/http.rb)
redirects follow HTTPX policy: at most three hops, no HTTPS-to-HTTP downgrade, and no
forwarding Authorization to another origin. Use `json:` / `response.json` at
the HTTPX boundary and MultiJSON for other JSON work; propagate transport failures.
For URL parsing, normalization, or query parameter and anchor cleaning on external
links, prefer `Addressable::URI` (`uri.query_values`, `uri.normalize`) over stdlib `URI`.

## MCP and Sourcetap

The generic [MCP client](../../../../app/lib/r3x/client/mcp.rb) is stateless HTTP/JSON.
It initializes protocol for each `call_tool(name, arguments: {})` and returns the
complete successful result. HTTP, JSON-RPC and tool errors propagate. It does not
read provider env, infer auth or side effects, discover tools, support stateful/SSE/
stdio sessions, or retry automatically. Protocol version and timeout defaults live
in the client source.

[Sourcetap](../../../../app/lib/r3x/client/sourcetap.rb) composes MCP with env-based
endpoint/token and Bearer authentication. Read its MCP API before selecting a tool,
arguments or response fields, then call
`ctx.client.sourcetap.call_tool(name, arguments: {})`.
Interpret `content`, `structuredContent` and tool-specific fields in the pack;
there is no common item schema. Source sessions belong to the server.

Sourcetap reads are real even in workflow dry run and have no dry-run switch.
The generic protocol does not impose this read-only contract on other providers;
a provider exposing writes needs its own delivery policy.

## Google Sheets rows

`read_rows(range:)` returns raw arrays including the first row. Use
`as_hashes: true` explicitly for header-based hashes. Headers must be nonblank
and unique, and rows cannot exceed header width; invalid sheets raise instead of
renaming columns or dropping values. Short rows are padded with nil, names remain
unchanged, and an empty sheet yields an empty array.

Raw `as_hashes: false` preserves irregular rows and duplicate/blank headers.
The former `headers:` option and automatic duplicate suffixes are removed;
repair old sheets/callers instead of adding compatibility fallbacks.

## Generative structured output

Use [LlmSchema.define](../../../../lib/r3x/workflow/llm_schema.rb) close to the prompt
when a workflow needs structured data. This keeps Schematist off unrelated workflow
boot paths. Use nested `array` / `object` blocks, pass the schema to `message`,
and read `response.parsed` instead of parsing free-form text. Keep provider-specific
schema constants out of packs.

`message`, `analyze_image` and `classify` accept per-call `thinking_effort:`.
Choose a level supported by the selected model; omission/nil uses the provider default.
It does not leak to later calls/clients. Model aliases can change their target; verify
supported behavior rather than assuming a universal effort scale. Save model, effort,
prompt and necessary input when unfinished generation must preserve configuration.

The [LLM client](../../../../app/lib/r3x/client/llm.rb) lazily loads RubyLLM and uses
isolated per-client context. Before changing retry behavior, read
[caching and retries](caching-and-retries.md).

Credentials use `<PROVIDER>_API_KEY` or `<PROVIDER>_API_TOKEN`, optionally with an
underscore suffix. The exact selected env name is read, with no key/token fallback.
The prefix selects a supported provider; unknown providers fail. Custom compatible
providers use their registered protocol/model-assumption hook, so provider-specific
model IDs do not require a hand-maintained workflow model registry. For example,
OpenCode Go uses its registered Chat Completions adapter. See
[provider configuration](../../../../app/lib/r3x/client/llm/provider_configuration.rb)
and [registry](../../../../app/lib/r3x/client/llm/provider_registry.rb).

## Typed decisions

Use `judge(input, model:, questions:, with: nil)` for fixed typed choices,
probabilities or ordered scores. Use generative structured output for arbitrary field
extraction. Answers are native RubyLLM judgment objects; do not silently substitute
a category when a provider refuses or returns malformed data.

`judge` has no thinking-effort option and performs real model requests in every
environment: dry run does not disable it. It shares LLM retry/error translation.
Provider attachment support differs:

- OpenAI uses the Decisions API. Pass images using `with:`, including ordered
  arrays. Use `RubyLLM::Attachment.new(source, resolution: :high)` when small text
  needs high detail.
- Cloudflare Clef uses the lazy System One adapter for text/JSON input without image
  attachments. Use `judge`; `message` / `classify` remain generative APIs.

For Cloudflare, configure the account explicitly in the client's SDK context block:

```ruby
llm = ctx.client.llm(api_key_env: "CLOUDFLARE_API_TOKEN_PROJECTA", max_retries: 0) do |config|
  config.cloudflare_account_id = R3x::Env.fetch!("CLOUDFLARE_ACCOUNT_ID_PROJECTA")
end
decision = llm.judge(
  "Please refund the duplicate charge.",
  model: "clef-flash",
  questions: {
    team: {
      type: :choice,
      instructions: "Which team should handle this request?",
      options: { billing: "Payments and refunds", technical: "Errors and configuration" }
    }
  }
)
decision.team.choice
```

The config block runs after credentials and retry override are applied. Account
env name/suffix is not inferred; choose it explicitly. The account ID must be 32
hexadecimal characters. Native answers expose probabilities/confidence and token
metadata. Use `type: :probability` with instructions or `type: :score` with
instructions and ordered `levels:` for those question types.
