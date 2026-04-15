module R3x
  module Dashboard
    class ApplicationController < R3x::WebController
      layout "r3x/dashboard"

      helper_method :finished_runs_retention_label, :logs_configured?, :logs_requested?, :mission_control_path

      rescue_from KeyError, with: :render_not_found

      private
        def finished_runs_retention_label
          duration = Rails.configuration.solid_queue.clear_finished_jobs_after
          return "unknown" unless duration.respond_to?(:parts)

          parts = duration.parts
          return "unknown" if parts.blank?

          parts.map do |unit, value|
            "#{value} #{unit.to_s.pluralize(value)}"
          end.to_sentence
        end

        def mission_control_path
          "/ops/jobs"
        end

        def logs_configured?
          Logs.configured?
        end

        def logs_requested?
          logs_configured? && params[:logs] == "1"
        end

        def render_not_found
          head :not_found
        end
    end
  end
end
