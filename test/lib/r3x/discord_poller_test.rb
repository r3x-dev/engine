# frozen_string_literal: true

require "test_helper"

module R3x
  class DiscordPollerTest < ActiveSupport::TestCase
    class MessageWorkflow < Workflow::Base
      self.queue_adapter = :solid_queue
      trigger :discord_message, key: :inbox, channel_id: "42", attachments: :images, run_per: :message
    end

    class ImageWorkflow < Workflow::Base
      self.queue_adapter = :solid_queue
      trigger :discord_message, key: :inbox, channel_id: "42", attachments: :images, run_per: :attachment

      before_enqueue do |job|
        id = job.arguments.last.fetch(:trigger_payload).fetch("attachments").first.fetch("id")
        throw :abort if id == "99"
        raise ActiveRecord::Rollback if id == "98"
      end
    end

    class DiscardWorkflow < Workflow::Base
      self.queue_adapter = :solid_queue
      trigger :discord_message, key: :inbox, channel_id: "42", attachments: :images, run_per: :attachment
      limits_concurrency to: 1, key: "one", on_conflict: :discard
    end

    CHANNEL_URL = "https://discord.com/api/v10/channels/42/messages"

    setup do
      R3x::Env.stubs(:fetch!).with("DISCORD_BOT_TOKEN").returns("test-token")
      R3x::Env.stubs(:fetch!).with("R3X_DISCORD_ALLOWED_AUTHOR_IDS").returns("1, 2")
      Workflow::Registry.stubs(:all).returns([MessageWorkflow, ImageWorkflow])
    end

    test "shares reads and catches up past a full page while new messages arrive" do
      head = stub_page({ limit: 1 }, [discord_message(100)])
      assert_no_difference("SolidQueue::Job.count") { DiscordPoller.from_registry.poll }
      assert_equal %w[100 100], TriggerCursor.order(:message_id).pluck(:message_id)
      assert_requested head, times: 1

      stub_page({ limit: 1 }, [discord_message(202)])
      attachments = %w[20 21 22].map { |id| { "id" => id, "content_type" => "image/png" } }
      history = 200.downto(102).map { |id| discord_message(id) } << discord_message(101, attachments:)
      first_page = stub_page({ limit: 100, after: "100" }, history)
      second_page = stub_page({ limit: 100, after: "200" }, [discord_message(203, attachments:), discord_message(202, attachments:), discord_message(201)])

      assert_difference("SolidQueue::Job.count", 8) { DiscordPoller.from_registry.poll }

      assert_requested first_page, times: 1
      assert_requested second_page, times: 1
      assert_equal %w[202 202], TriggerCursor.order(:message_id).pluck(:message_id)
      assert_equal [["101", %w[20 21 22]], ["202", %w[20 21 22]]], admitted(MessageWorkflow)
      assert_equal [["101", ["20"]], ["101", ["21"]], ["101", ["22"]], ["202", ["20"]], ["202", ["21"]], ["202", ["22"]]], admitted(ImageWorkflow)

      stub_page({ limit: 100, after: "202" }, [discord_message(203, attachments:)])

      assert_difference("SolidQueue::Job.count", 4) { DiscordPoller.from_registry.poll }
      assert_equal %w[203 203], TriggerCursor.order(:message_id).pluck(:message_id)
    end

    { "aborts" => "99", "rolls back" => "98" }.each do |action, last_id|
      test "propagates the failure and rolls back earlier attachments when the third enqueue #{action}" do
        stub_page({ limit: 1 }, [])
        assert_no_difference("SolidQueue::Job.count") { DiscordPoller.from_registry.poll }

        ids = ["20", "21", last_id]
        attachments = ids.map { |id| { "id" => id, "content_type" => "image/png" } }
        stub_page({ limit: 100, after: "0" }, [discord_message(100, attachments:)])

        assert_raises(ActiveJob::EnqueueError) { DiscordPoller.from_registry.poll }
        assert_empty admitted(ImageWorkflow)
        assert_equal "0", TriggerCursor.find_by!(workflow_key: ImageWorkflow.workflow_key).message_id
        assert_equal [["100", ids]], admitted(MessageWorkflow)
      end
    end

    test "a concurrency discard rolls back the entire message" do
      Workflow::Registry.stubs(:all).returns([DiscardWorkflow])
      stub_page({ limit: 1 }, [])
      poller = DiscordPoller.from_registry
      poller.poll
      images = %w[20 21].map { |id| { "id" => id, "content_type" => "image/png" } }
      stub_page({ limit: 100, after: "0" }, [discord_message(100, attachments: images)])

      assert_raises(ActiveJob::EnqueueError) { poller.poll }
      assert_empty admitted(DiscardWorkflow)
      assert_equal "0", TriggerCursor.find_by!(workflow_key: DiscardWorkflow.workflow_key).message_id
    end

    test "a transient Discord outage leaves the cursor for the next poll" do
      poller = DiscordPoller.from_registry
      stub_request(:get, CHANNEL_URL).with(query: { limit: 1 }).to_return(status: 503)

      assert_includes capture_logged_output { poller.poll }, "503"
      assert_empty TriggerCursor.all

      stub_request(:get, CHANNEL_URL).with(query: { limit: 1 }).to_raise(EOFError.new("descriptor closed"))

      assert_includes capture_logged_output { poller.poll }, "descriptor closed"
      assert_empty TriggerCursor.all

      stub_page({ limit: 1 }, [discord_message(100)])
      poller.poll

      assert_equal %w[100 100], TriggerCursor.pluck(:message_id)
    end

    private

    def stub_page(query, messages)
      stub_request(:get, CHANNEL_URL).with(query:).to_return(
        status: 200, body: MultiJSON.generate(messages), headers: { "Content-Type" => "application/json" },
      )
    end

    def discord_message(id, attachments: [])
      { "id" => id.to_s, "channel_id" => "42", "author" => { "id" => "1" }, "content" => "Poster", "attachments" => attachments }
    end

    def admitted(workflow_class)
      SolidQueue::Job.where(class_name: workflow_class.name).order(:id).map do |job|
        payload = job.arguments.fetch("arguments").last.fetch("trigger_payload")
        [payload.fetch("message_id"), payload.fetch("attachments").pluck("id")]
      end
    end
  end
end
