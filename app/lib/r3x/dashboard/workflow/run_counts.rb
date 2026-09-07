# frozen_string_literal: true

module R3x
  module Dashboard
    module Workflow
      class RunCounts
        def running_count
          direct_runs.for_status("running").logical_count
        end

        def recent_activity_count(window:)
          return 0 if direct_class_names.empty?

          time_range = window.ago..Time.current
          recent_jobs = recent_scopes(time_range:).map { |scope| scope.select(:id) }
          recent_activity_ids = ::Dashboard::Run.from("recent_activity").select(:id)

          direct_runs.with(recent_activity: recent_jobs)
            .where(id: recent_activity_ids)
            .logical_count
        end

        private

        def recent_scopes(time_range:)
          [
            direct_runs.for_status("failed").where(solid_queue_failed_executions: { created_at: time_range }),
            direct_runs.for_status("finished").where(finished_at: time_range),
            direct_runs.for_status("running").where(solid_queue_claimed_executions: { created_at: time_range }),
            direct_runs.for_status("sleeping").where(created_at: time_range),
            direct_runs.for_status("queued").joins(:ready_execution).where(solid_queue_ready_executions: { created_at: time_range }),
            direct_runs.for_status("queued").where.missing(:ready_execution).where(created_at: time_range),
            direct_runs.for_status("blocked").where(solid_queue_blocked_executions: { created_at: time_range }),
            direct_runs.for_status("scheduled").where(solid_queue_scheduled_executions: { scheduled_at: time_range }),
          ]
        end

        def direct_runs
          @direct_runs ||= ::Dashboard::Run.dashboard_visible(direct_class_names)
        end

        def direct_class_names
          @direct_class_names ||= catalog.class_names_to_keys.keys
        end

        def catalog
          @catalog ||= Workflow::Catalog.new
        end
      end
    end
  end
end
