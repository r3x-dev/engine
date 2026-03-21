module R3x
  module Workflow
    module Policy
      STRICT_FORBIDDEN_CONSTANTS = %w[ENV].freeze
      STRICT_FORBIDDEN_MODULE_PREFIXES = %w[R3x::Env ::R3x::Env].freeze
      STRICT_FORBIDDEN_METHODS = %i[eval system exec spawn send __send__ instance_eval class_eval const_get].freeze
    end
  end
end
