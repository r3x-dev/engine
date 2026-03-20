module R3x
  module Env
    def self.fetch(key)
      ENV[key].presence || raise(ArgumentError, "Missing #{key}")
    end
  end
end
