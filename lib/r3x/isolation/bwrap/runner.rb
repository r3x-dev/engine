# frozen_string_literal: true

module R3x
  module Isolation
    class Bwrap
      class Runner
        def self.run(state_file, env_path:)
          state = MultiJson.load(File.read(state_file))
          require env_path

          workflow_class = R3x::Workflow::Registry.fetch(state["workflow_key"])
          workflow_class.perform_now(state["trigger_key"], trigger_payload: state["trigger_payload"])
        end
      end
    end
  end
end
