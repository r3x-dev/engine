# Example Workflow: Multi-Step Integration

This file is a worked example for people who want to build workflows in `r3x`.
It is based on the real workflows in `workflows/` and shows the common pieces together:

- HTTP fetching and HTML parsing, like `porto_santo_news`
- Google Sheets and Gmail delivery
- Apify, OCR, LLM classification, and deduplication, like `camara_ps_events`
- resumable loops with `step`

The goal is to show the shape of a real workflow, not to provide production-ready secrets or URLs.
Replace the placeholder values before using any of it for real.

```ruby
module Workflows
  class ExampleIslandDigest < R3x::Workflow::Base
    SPREADSHEET_ID = "spreadsheet-id"
    GOOGLE_PROJECT = "EXAMPLE_PROJECT"
    DISCORD_WEBHOOK_ENV = "DISCORD_WEBHOOK_URL_EXAMPLE"
    GEMINI_API_KEY_ENV = "GEMINI_API_KEY_EXAMPLE"
    SENT_ITEMS_TTL = 30.days

    trigger :schedule, cron: "0 8 * * *", timezone: "Europe/Lisbon"

    DigestSchema = R3x::Workflow::LlmSchema.define do
      array :items do
        object :item do
          string :title
          string :summary
          string :url
        end
      end
    end

    def run
      logger.info("Starting example integration digest")

      rows = with_cache { read_source_rows }
      candidates = collect_candidates(rows)
      sent_items = ctx.durable_set(:sent, ttl: SENT_ITEMS_TTL)

      @delivered = []
      step :deliver_candidates, start: 0 do |step|
        cursor = step.cursor || 0

        candidates[cursor..].each_with_index do |candidate, offset|
          index = cursor + offset
          dedup_key = workflow_dedup_key(candidate.fetch("url"))

          if sent_items.include?(dedup_key)
            logger.debug { "Skipping already delivered item #{candidate.fetch('url')}" }
            step.advance! from: index + 1
            next
          end

          delivered_item = deliver_candidate(candidate)
          sent_items.add(dedup_key)
          @delivered << delivered_item

          step.advance! from: index + 1
        end
      end

      logger.info("Example integration digest delivered #{@delivered.size} items")
    end

    private

    def read_source_rows
      ctx.client
        .google_sheets(spreadsheet_id: SPREADSHEET_ID, project: GOOGLE_PROJECT)
        .read_rows(range: "Approved!A:Z")
        .map { |row| row.to_h.transform_keys(&:to_s) }
    end

    def collect_candidates(rows)
      sheet_items = rows.map do |row|
        {
          "title" => row.fetch("title"),
          "url" => row.fetch("url"),
          "body" => row.fetch("description")
        }
      end

      page_items = Nokogiri::HTML(ctx.client.http.get("https://example.com/news").body)
        .css("article")
        .filter_map do |node|
          url = node.at_css("a")&.[]("href")
          body = node.text.squish
          next if url.blank? || body.blank?

          { "title" => node.at_css("h2")&.text.to_s.squish, "url" => url, "body" => body }
        end

      sheet_items + page_items
    end

    def deliver_candidate(candidate)
      summary = summarize(candidate)
      translated = ctx.client.google_translate(project: GOOGLE_PROJECT)
        .translate(summary.fetch("summary"), from: "pt", to: "en")

      ctx.client
        .discord(webhook_url_env: DISCORD_WEBHOOK_ENV)
        .deliver(content: "#{translated}\n\n#{candidate.fetch('url')}")

      if important?(summary)
        ctx.client.gmail(project: GOOGLE_PROJECT).deliver(
          to: "team@example.com",
          subject: "Important island update: #{summary.fetch('title')}",
          body: "#{translated}\n\n#{candidate.fetch('url')}"
        )
      end

      summary.merge("translated_summary" => translated)
    end

    def summarize(candidate)
      response = ctx.client.llm(api_key_env: GEMINI_API_KEY_ENV).message(
        model: "gemini-flash-lite-latest",
        schema: DigestSchema,
        prompt: <<~PROMPT
          Summarize this item for an operational digest.
          Return one item only.

          Title: #{candidate.fetch("title")}
          URL: #{candidate.fetch("url")}
          Body: #{candidate.fetch("body")}
        PROMPT
      )

      response.content.fetch("items").first
    end

    def important?(summary)
      summary.fetch("summary").match?(/closure|warning|alert|emergency/i)
    end
  end
end
```

## Why This Shape Works

- `R3x::Workflow::Base` is an `ApplicationJob`, so you can use `ActiveJob::Continuable` and `step`
  directly in workflow code.
- `step` is the resumable boundary. In the example, the workflow can resume from the next item in
  the list instead of starting the whole digest again.
- `with_cache` sits around the slow read-only fetch, not around delivery. That keeps local iteration
  fast while leaving the side effects visible.
- `ctx.durable_set(:sent, ttl: ...)` is used for best-effort cross-run dedup. Add to it only after
  the delivery side effect succeeds.
- `ctx.client.*` is the normal boundary for integrations. That keeps workflow code readable and
  lets clients encapsulate auth, retries, and provider-specific details.
- `R3x::Workflow::LlmSchema.define` is the preferred way to get structured LLM output when the
  workflow needs fields instead of free-form text.
- If a workflow sends mail, posts messages, or creates external side effects, keep the dry-run path
  explicit at the boundary. Use `R3x::Policy.dry_run_for(...)` when the client supports it.

## Run It Locally

Save the workflow as `workflows/example_island_digest/workflow.rb`, then run it directly:

```bash
bin/workflow run --dry-run workflows/example_island_digest/workflow.rb
```

Use `--dry-run` first for workflows that send mail, post webhooks, upload files, or call other
side-effecting APIs. Add `--skip-cache` when you want to force fresh reads from upstream sources:

```bash
bin/workflow run --dry-run --skip-cache workflows/example_island_digest/workflow.rb
```

If the workflow pack is included in `R3X_WORKFLOW_PATHS`, you can also inspect it by key:

```bash
export R3X_WORKFLOW_PATHS="$PWD/workflows"
bin/workflow list
bin/workflow info example_island_digest
```

## Validate It Manually

Workflow packs stay as small scripts and are validated through the runtime rather than pack-local
test suites. Inspect registration first, then run with fresh provider reads and dry-run delivery:

```bash
bin/workflow info example_island_digest
bin/workflow run --dry-run --skip-cache workflows/example_island_digest/workflow.rb
```

## Vault Parity

When `R3X_VAULT_ADDR` and `R3X_VAULT_SECRETS_PATH` point at the same Vault setup used in
production, local runs can hydrate the same secret names and values that production uses. That gives
you a much tighter local feedback loop: the workflow, clients, env names, and credentials all match
the deployed runtime.

Keep using `--dry-run` for local workflow runs with side effects. Vault parity proves the workflow
can see the same configuration as production; dry run keeps local testing from sending real mail or
posting real webhooks unless you explicitly choose to do that.
