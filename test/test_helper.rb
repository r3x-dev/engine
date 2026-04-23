ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "support/dashboard_job_rows"
require_relative "support/dashboard_workflow_job"
require_relative "support/vault_test_helpers"
require_relative "support/test_db_cleanup"

WebMock.disable_net_connect!

module ActiveSupport
  class TestCase
    # Add more helper methods to be used by all tests here...
    # The suite stays serial on purpose: SQLite plus shared Solid Queue tables
    # produce more lock contention and hangs than speedup under Minitest processes.

    def capture_logged_output
      io = StringIO.new
      original_logger = Rails.logger
      original_active_job_logger = ActiveJob::Base.logger
      test_logger = build_test_logger(io)

      Rails.logger = test_logger
      ActiveJob::Base.logger = test_logger
      yield
      io.string
    ensure
      Rails.logger = original_logger
      ActiveJob::Base.logger = original_active_job_logger
    end

    def build_test_logger(output)
      ActiveSupport::TaggedLogging.new(
        ActiveSupport::Logger.new(output).tap do |logger|
          logger.formatter = Rails.application.config.log_formatter
        end
      )
    end
  end
end
