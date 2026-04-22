module R3x
  module Dashboard
    class WorkflowRunCounts
      LEGACY_CANDIDATE_MULTIPLIER = 5

      def running_count
        running_jobs_scope(non_legacy_jobs_scope).count + visible_legacy_job_ids(running_jobs_scope(legacy_jobs_scope)).size
      end

      def recent_activity_count(window:)
        time_range = window.ago..Time.current

        recent_non_legacy_count(time_range:) + recent_legacy_count(time_range:)
      end

      def recent_run_ids(limit:)
        (
          recent_status_job_ids(non_legacy_jobs_scope, limit:) +
          recent_legacy_job_ids(limit:)
        ).uniq
      end

      private
        def recent_non_legacy_count(time_range:)
          recent_scopes(non_legacy_jobs_scope, time_range:).sum(&:count)
        end

        def recent_legacy_count(time_range:)
          recent_scopes(legacy_jobs_scope, time_range:).sum do |scope|
            visible_legacy_job_ids(scope).size
          end
        end

        def recent_status_job_ids(base_scope, limit:)
          [
            failed_jobs_scope(base_scope).order("solid_queue_failed_executions.created_at DESC").limit(limit).pluck(:id),
            finished_jobs_scope(base_scope).order(finished_at: :desc).limit(limit).pluck(:id),
            running_jobs_scope(base_scope).order("solid_queue_claimed_executions.created_at DESC").limit(limit).pluck(:id),
            queued_jobs_scope(base_scope).order("solid_queue_ready_executions.created_at DESC").limit(limit).pluck(:id),
            fallback_queued_jobs_scope(base_scope).order(created_at: :desc).limit(limit).pluck(:id),
            blocked_jobs_scope(base_scope).order("solid_queue_blocked_executions.created_at DESC").limit(limit).pluck(:id),
            scheduled_jobs_scope(base_scope).order("solid_queue_scheduled_executions.scheduled_at DESC").limit(limit).pluck(:id)
          ].flatten
        end

        def recent_legacy_job_ids(limit:)
          fetch_limit = limit * LEGACY_CANDIDATE_MULTIPLIER

          [
            visible_legacy_job_ids(failed_jobs_scope(legacy_jobs_scope).order("solid_queue_failed_executions.created_at DESC").limit(fetch_limit)),
            visible_legacy_job_ids(finished_jobs_scope(legacy_jobs_scope).order(finished_at: :desc).limit(fetch_limit)),
            visible_legacy_job_ids(running_jobs_scope(legacy_jobs_scope).order("solid_queue_claimed_executions.created_at DESC").limit(fetch_limit)),
            visible_legacy_job_ids(queued_jobs_scope(legacy_jobs_scope).order("solid_queue_ready_executions.created_at DESC").limit(fetch_limit)),
            visible_legacy_job_ids(fallback_queued_jobs_scope(legacy_jobs_scope).order(created_at: :desc).limit(fetch_limit)),
            visible_legacy_job_ids(blocked_jobs_scope(legacy_jobs_scope).order("solid_queue_blocked_executions.created_at DESC").limit(fetch_limit)),
            visible_legacy_job_ids(scheduled_jobs_scope(legacy_jobs_scope).order("solid_queue_scheduled_executions.scheduled_at DESC").limit(fetch_limit))
          ].flatten
        end

        def recent_scopes(base_scope, time_range:)
          [
            failed_jobs_scope(base_scope).where(solid_queue_failed_executions: { created_at: time_range }),
            finished_jobs_scope(base_scope).where(finished_at: time_range),
            running_jobs_scope(base_scope).where(solid_queue_claimed_executions: { created_at: time_range }),
            queued_jobs_scope(base_scope).where(solid_queue_ready_executions: { created_at: time_range }),
            fallback_queued_jobs_scope(base_scope).where(created_at: time_range),
            blocked_jobs_scope(base_scope).where(solid_queue_blocked_executions: { created_at: time_range }),
            scheduled_jobs_scope(base_scope).where(solid_queue_scheduled_executions: { scheduled_at: time_range })
          ]
        end

        def visible_legacy_job_ids(scope)
          scope
            .select(:id, :arguments)
            .to_a
            .filter_map do |job|
              job.id if JobPayload.new(job.arguments).legacy_workflow_key.present?
            end
        end

        def non_legacy_jobs_scope
          @non_legacy_jobs_scope ||= SolidQueue::Job.where(class_name: non_legacy_class_names)
        end

        def legacy_jobs_scope
          @legacy_jobs_scope ||= SolidQueue::Job.where(class_name: WorkflowRuns::LEGACY_CLASS_NAME)
        end

        def failed_jobs_scope(base_scope)
          base_scope.joins(:failed_execution)
        end

        def finished_jobs_scope(base_scope)
          base_scope.where.not(finished_at: nil).where.missing(:failed_execution)
        end

        def running_jobs_scope(base_scope)
          base_scope.joins(:claimed_execution)
        end

        def queued_jobs_scope(base_scope)
          base_scope.joins(:ready_execution)
        end

        def fallback_queued_jobs_scope(base_scope)
          base_scope
            .where(finished_at: nil)
            .where.missing(:failed_execution)
            .where.missing(:claimed_execution)
            .where.missing(:ready_execution)
            .where.missing(:blocked_execution)
            .where.missing(:scheduled_execution)
        end

        def blocked_jobs_scope(base_scope)
          base_scope.joins(:blocked_execution)
        end

        def scheduled_jobs_scope(base_scope)
          base_scope.joins(:scheduled_execution)
        end

        def non_legacy_class_names
          @non_legacy_class_names ||= catalog.class_names_to_keys.keys
        end

        def catalog
          @catalog ||= WorkflowCatalog.new
        end
    end
  end
end
