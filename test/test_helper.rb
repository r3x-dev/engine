ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "support/dashboard_job_rows"
require_relative "support/dashboard_workflow_job"
require_relative "support/test_db_cleanup"

WebMock.disable_net_connect!

module ActiveSupport
  class TestCase
    # Add more helper methods to be used by all tests here...
  end
end
