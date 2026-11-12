# frozen_string_literal: true

module Workflows
  class CallbackWorkflow < R3x::Workflow::Base
    EVENTS = Concurrent::Array.new

    self.resume_options = { wait: 0 }

    class << self
      def abort_execution? = false
      def abort_resume? = false
      def discard_resume? = false
      def fail_after_progress? = false
      def mutate_after_enqueue? = false
      def enqueue_separate_run? = false
    end

    before_perform do
      EVENTS << "before"
      throw :abort if self.class.abort_execution?
    end

    around_perform do |_job, execution|
      EVENTS << "around"
      execution.call
    end

    after_perform { EVENTS << "after" }
    before_enqueue do
      raise ActiveJob::EnqueueError, "continuation is no longer relevant" if self.class.discard_resume?

      throw :abort if self.class.abort_resume?
    end
    discard_on ActiveJob::EnqueueError do |job, error|
      raise error unless job.class.discard_resume?

      EVENTS << "discarded"
    end
    after_enqueue do
      EVENTS << "enqueued"
      @snapshot["value"] = "changed after enqueue" if self.class.mutate_after_enqueue?
    end

    def serialize
      super.merge("snapshot" => @snapshot)
    end

    def deserialize(job_data)
      super
      @snapshot = job_data.fetch("snapshot")
    end

    def run
      @snapshot ||= { "value" => "original" }

      step :first do
        EVENTS << "first"
        self.class.perform_later if self.class.enqueue_separate_run?
      end

      raise Timeout::Error, "failed after progress" if self.class.fail_after_progress? && executions == 1

      step :second, isolated: true do
        EVENTS << "second"
      end

      { "executions" => executions, "resumptions" => resumptions, "snapshot" => @snapshot.fetch("value") }
    end
  end
end
