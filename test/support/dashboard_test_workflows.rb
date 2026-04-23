module Workflows
  module Test
  end
end

module DashboardTestWorkflows
  extend self

  def ensure_class(name)
    return "Workflows::Test::#{name}" if Workflows::Test.const_defined?(name, false)

    Workflows::Test.const_set(name, Class.new(R3x::TestSupport::DashboardWorkflowJob))
    "Workflows::Test::#{name}"
  end
end
