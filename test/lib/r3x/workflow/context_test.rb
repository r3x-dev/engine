require "test_helper"

module R3x
  module Workflow
    class ExecutionTest < ActiveSupport::TestCase
      test "previous_run_at returns nil when no execution in solid_queue" do
        execution = Execution.new(workflow_key: "nonexistent_workflow")

        assert_nil execution.previous_run_at
      end

      test "previous_run_at is memoized" do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [ "test_memo" ]
        )
        SolidQueue::RecurringTask.create!(
          key: "test_memo",
          schedule: "0 * * * *",
          class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [],
          queue_name: "default"
        )
        SolidQueue::RecurringExecution.create!(
          task_key: "test_memo",
          run_at: 2.hours.ago,
          job_id: job.id
        )

        execution = Execution.new(workflow_key: "test_memo")

        t1 = execution.previous_run_at
        t2 = execution.previous_run_at

        assert_equal t1, t2
        assert_predicate t1, :present?
      ensure
        SolidQueue::RecurringExecution.where(task_key: "test_memo").delete_all
        SolidQueue::RecurringTask.where(key: "test_memo").delete_all
        SolidQueue::Job.where(class_name: R3x::TestSupport::DashboardWorkflowJob.name).delete_all
      end

      test "first_run? returns true when no previous_run_at" do
        execution = Execution.new(workflow_key: "new_workflow")

        assert_predicate execution, :first_run?
      end

      test "first_run? returns false when previous_run_at exists" do
        job = SolidQueue::Job.create!(
          queue_name: "default",
          class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [ "test_fr" ]
        )
        SolidQueue::RecurringTask.create!(
          key: "test_fr",
          schedule: "0 * * * *",
          class_name: R3x::TestSupport::DashboardWorkflowJob.name,
          arguments: [],
          queue_name: "default"
        )
        SolidQueue::RecurringExecution.create!(
          task_key: "test_fr",
          run_at: 2.hours.ago,
          job_id: job.id
        )

        execution = Execution.new(workflow_key: "test_fr")

        refute_predicate execution, :first_run?
      ensure
        SolidQueue::RecurringExecution.where(task_key: "test_fr").delete_all
        SolidQueue::RecurringTask.where(key: "test_fr").delete_all
        SolidQueue::Job.where(class_name: R3x::TestSupport::DashboardWorkflowJob.name).delete_all
      end
    end

    class ContextTest < ActiveSupport::TestCase
      test "has trigger and execution" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger:, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")

        assert_equal :schedule, ctx.trigger.type
        assert_predicate ctx.trigger, :schedule?
        assert_kind_of Execution, ctx.execution
      end

      test "client proxy builds gmail client from project" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger:, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")
        gmail = ctx.client.gmail(project: "MISSING")

        assert_instance_of R3x::Client::Google::Gmail, gmail
      end

      test "client proxy builds google translate client from project" do
        trigger = R3x::Triggers::Schedule.new(cron: "0 13 * * *")
        trigger_execution = R3x::TriggerManager::Execution.new(trigger:, workflow_key: "test")
        ctx = Context.new(trigger: trigger_execution, workflow_key: "test")
        translate = ctx.client.google_translate(project: "MISSING")

        assert_instance_of R3x::Client::Google::Translate, translate
      end

      test "client proxy builds discord webhook client" do
        with_env("DISCORD_WEBHOOK_URL_TEST" => "https://discord.test/webhook") do
          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          discord = ctx.client.discord(webhook_url_env: "DISCORD_WEBHOOK_URL_TEST")

          assert_instance_of R3x::Client::Discord, discord
        end
      end

      test "client proxy builds healthchecks client" do
        with_env("HEALTHCHECKS_IO_URL" => "https://hc-ping.test") do
          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          healthchecks = ctx.client.healthchecks_io("test-check")

          assert_instance_of R3x::Client::HealthchecksIO, healthchecks
        end
      end

      test "client proxy parses rss feed" do
        stub_request(:get, "https://news.test/feed.xml")
          .to_return(
            status: 200,
            body: <<~XML,
              <?xml version="1.0" encoding="UTF-8"?>
              <rss version="2.0">
                <channel>
                  <title>News</title>
                  <item>
                    <title>First item</title>
                    <link>https://news.test/first</link>
                  </item>
                </channel>
              </rss>
            XML
            headers: { "Content-Type" => "application/rss+xml" }
          )
        ctx = Context.new(
          trigger: R3x::TriggerManager::Execution.new(
            trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
            workflow_key: "test"
          ),
          workflow_key: "test"
        )

        feed = ctx.client.rss("https://news.test/feed.xml")

        assert_equal "First item", feed.items.first.title
      end

      test "client proxy yields persistent http client" do
        stub_request(:get, "https://api.test/one")
          .to_return(status: 200, body: "first")
        stub_request(:get, "https://api.test/two")
          .to_return(status: 200, body: "second")
        ctx = Context.new(
          trigger: R3x::TriggerManager::Execution.new(
            trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
            workflow_key: "test"
          ),
          workflow_key: "test"
        )

        bodies = ctx.client.persistent_http(timeout: 30) do |http|
          [
            http.get("https://api.test/one").body.to_s,
            http.get("https://api.test/two").body.to_s
          ]
        end

        assert_equal [ "first", "second" ], bodies
        assert_requested :get, "https://api.test/one"
        assert_requested :get, "https://api.test/two"
      end

      test "client proxy markdownify returns markdown string" do
        with_env("R3X_MARKDOWNIFY_DRY_RUN" => "false") do
          stub_request(:post, "https://markdown.new/")
            .to_return(
              status: 200,
              body: MultiJSON.generate({ "content" => "# Hello from markdown.new" }),
              headers: { "Content-Type" => "application/json" }
            )

          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          result = ctx.client.markdownify(url: "https://example.com")

          assert_equal "# Hello from markdown.new", result
        end
      end

      test "client proxy builds llm client for opencode provider with base env" do
        with_env("OPENCODE_GO_API_KEY" => "go-base-key") do
          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          llm = ctx.client.llm(api_key_env: "OPENCODE_GO_API_KEY")

          assert_instance_of R3x::Client::Llm, llm
          assert_equal({ provider: :opencode_go, assume_model_exists: true }, llm.instance_variable_get(:@chat_options))
          context = llm.instance_variable_get(:@llm_context)

          assert_equal "go-base-key", context.config.opencode_go_api_key
        end
      end

      test "client proxy builds llm client for opencode provider with suffixed env" do
        with_env("OPENCODE_GO_API_KEY_PROJECTA" => "go-test-key") do
          ctx = Context.new(
            trigger: R3x::TriggerManager::Execution.new(
              trigger: R3x::Triggers::Schedule.new(cron: "0 13 * * *"),
              workflow_key: "test"
            ),
            workflow_key: "test"
          )
          llm = ctx.client.llm(api_key_env: "OPENCODE_GO_API_KEY_PROJECTA")

          assert_instance_of R3x::Client::Llm, llm
          assert_equal({ provider: :opencode_go, assume_model_exists: true }, llm.instance_variable_get(:@chat_options))
          context = llm.instance_variable_get(:@llm_context)

          assert_equal "go-test-key", context.config.opencode_go_api_key
        end
      end



      private

      def with_env(hash)
        originals = hash.each_with_object({}) { |(k, _), memo| memo[k] = ENV[k] }
        hash.each { |k, v| ENV[k] = v }
        yield
      ensure
        originals.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      end
    end
  end
end
