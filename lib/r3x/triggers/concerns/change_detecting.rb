module R3x
  module Triggers
    module Concerns
      module ChangeDetecting
        def change_detecting?
          true
        end

        def detect_changes(workflow_key:, state:)
          raise NotImplementedError, "#{self.class.name} must implement #detect_changes"
        end
      end
    end
  end
end
