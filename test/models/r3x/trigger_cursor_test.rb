# frozen_string_literal: true

require "test_helper"

class R3x::TriggerCursorTest < ActiveSupport::TestCase
  class ProbeJob < ApplicationJob
  end

  self.use_transactional_tests = false

  setup do
    R3x::TriggerCursor.seed!(workflow_key: "sample_workflow", trigger_key: "sample_trigger", message_id: "10")
  end

  teardown do
    jobs.delete_all
    R3x::TriggerCursor.delete_by(workflow_key: "sample_workflow", trigger_key: "sample_trigger")
  end

  test "a failed third enqueue rolls back the earlier jobs and the cursor" do
    cursor = find_cursor

    assert_raises(ActiveJob::SerializationError) do
      cursor.advance(from: "10", to: "20") do
        enqueue(1)
        enqueue(2)
        enqueue(Object.new)
      end
    end

    assert_empty jobs
    assert_equal "10", cursor.reload.message_id

    assert cursor.advance(from: "10", to: "20") { 3.times { |index| enqueue(index) } }
    assert_equal 3, jobs.count
    assert_equal "20", cursor.reload.message_id
  end

  test "overlapping schedulers enqueue once when both observe the same cursor" do
    observed = Queue.new
    start = Queue.new

    schedulers = 2.times.map do
      Thread.new do # rubocop:disable ThreadSafety/NewThread -- Use independent database connections for the scheduler race.
        R3x::TriggerCursor.with_connection do
          cursor = find_cursor
          observed << cursor.message_id
          start.pop(timeout: 5)
          cursor.advance(from: cursor.message_id, to: "20") { enqueue(1) }
        end
      end
    end

    assert_equal %w[10 10], 2.times.map { observed.pop(timeout: 5) }
    schedulers.size.times { start << true }

    assert_equal({ true => 1, false => 1 }, schedulers.map(&:value).tally)
    assert_equal 1, jobs.count
    assert_equal "20", find_cursor.message_id
  ensure
    schedulers&.each(&:join)
  end

  private

  def find_cursor
    R3x::TriggerCursor.find_by!(workflow_key: "sample_workflow", trigger_key: "sample_trigger")
  end

  def jobs
    SolidQueue::Job.where(class_name: ProbeJob.name)
  end

  def enqueue(argument)
    SolidQueue::Job.enqueue(ProbeJob.new(argument))
  end
end
