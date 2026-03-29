require "test_helper"
require_relative "../../support/fake_change_detecting_trigger"

module R3x
  class ChangeDetectionJobTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @original_workflow_paths = ENV["R3X_WORKFLOW_PATHS"]
      ENV["R3X_WORKFLOW_PATHS"] = Rails.root.join("test/fixtures/workflows").to_s
      clear_enqueued_jobs
      R3x::TriggerState.delete_all
    end

    teardown do
      clear_enqueued_jobs
      R3x::TriggerState.delete_all
      ENV["R3X_WORKFLOW_PATHS"] = @original_workflow_paths
      Workflow::Registry.reset!
    end

    test "creates trigger state and does not enqueue workflow when unchanged" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(
        identity: "feed",
        detector: ->(workflow_key:, state:) do
          assert_equal "test_change_detecting_feed", workflow_key
          assert_equal({}, state)
          { changed: false, state: { cursor: "v1" }, payload: nil }
        end
      )

      register_change_detecting_workflow(fake_trigger)

      assert_no_enqueued_jobs do
        ChangeDetectionJob.perform_now("test_change_detecting_feed", { "trigger_key" => fake_trigger.unique_key })
      end

      state = R3x::TriggerState.find_by!(workflow_key: "test_change_detecting_feed", trigger_key: fake_trigger.unique_key)
      assert_equal "fake_change_detecting", state.trigger_type
      assert_equal({ "cursor" => "v1" }, state.state)
      assert state.last_checked_at.present?
      assert_nil state.last_triggered_at
      assert_nil state.last_error_at
    end

    test "enqueues workflow and records last_triggered_at when changed" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(
        identity: "feed",
        detector: ->(workflow_key:, state:) do
          { changed: true, state: state.merge(cursor: "v2"), payload: { "entries" => [ { "title" => "Hello" } ] } }
        end
      )

      workflow_class = register_change_detecting_workflow(fake_trigger)

      assert_enqueued_jobs 1, only: workflow_class do
        ChangeDetectionJob.perform_now("test_change_detecting_feed", { "trigger_key" => fake_trigger.unique_key })
      end

      enqueued_job = enqueued_jobs.last
      assert_equal workflow_class, enqueued_job[:job]
      assert_equal fake_trigger.unique_key, enqueued_job[:args][0]
      payload = enqueued_job[:args][1]["trigger_payload"]
      assert_equal 1, payload["entries"].length
      assert_equal "Hello", payload["entries"].first["title"]

      state = R3x::TriggerState.find_by!(workflow_key: "test_change_detecting_feed", trigger_key: fake_trigger.unique_key)
      assert_equal({ "cursor" => "v2" }, state.state)
      assert state.last_triggered_at.present?
    end

    test "does not advance trigger state when enqueue fails" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(
        identity: "feed",
        detector: ->(workflow_key:, state:) do
          { changed: true, state: state.merge(cursor: "v2"), payload: { "entries" => [ { "title" => "Hello" } ] } }
        end
      )

      workflow_class = register_change_detecting_workflow(fake_trigger)

      original_perform_later = workflow_class.method(:perform_later)
      workflow_class.singleton_class.send(:define_method, :perform_later) do |*|
        raise ActiveJob::EnqueueError, "enqueue failed"
      end

      error = assert_raises(ActiveJob::EnqueueError) do
        ChangeDetectionJob.perform_now("test_change_detecting_feed", { "trigger_key" => fake_trigger.unique_key })
      ensure
        workflow_class.singleton_class.send(:define_method, :perform_later, original_perform_later)
      end

      assert_equal "enqueue failed", error.message

      state = R3x::TriggerState.find_by!(workflow_key: "test_change_detecting_feed", trigger_key: fake_trigger.unique_key)

      assert_equal({}, state.state)
      assert_nil state.last_checked_at
      assert_nil state.last_triggered_at
      assert state.last_error_at.present?
      assert_equal "enqueue failed", state.last_error_message
    end

    test "persists last error details when detection fails" do
      fake_trigger = R3x::TestSupport::FakeChangeDetectingTrigger.new(
        identity: "feed",
        detector: ->(workflow_key:, state:) do
          raise ArgumentError, "detection failed"
        end
      )

      register_change_detecting_workflow(fake_trigger)

      error = assert_raises(ArgumentError) do
        ChangeDetectionJob.perform_now("test_change_detecting_feed", trigger_key: fake_trigger.unique_key)
      end

      assert_equal "detection failed", error.message

      state = R3x::TriggerState.find_by!(workflow_key: "test_change_detecting_feed", trigger_key: fake_trigger.unique_key)
      assert state.last_error_at.present?
      assert_equal "detection failed", state.last_error_message
    end

    private

    def register_change_detecting_workflow(fake_trigger)
      workflow_class = Class.new(R3x::Workflow::Base) do
        def self.name
          "TestChangeDetectingFeed"
        end

        define_singleton_method(:triggers_by_key) { { fake_trigger.unique_key => fake_trigger } }

        def run
          ctx.trigger.payload
        end
      end

      Workflow::Registry.register(workflow_class)
      workflow_class
    end
  end
end
