module R3x
  module GemLoader
    extend self

    MUTEX = Mutex.new
    LOADED_FEATURES = Concurrent::Map.new

    def require(feature)
      return false if LOADED_FEATURES[feature]

      MUTEX.synchronize do
        return false if LOADED_FEATURES[feature]

        Kernel.require(feature)
        LOADED_FEATURES[feature] = true
      end
    end
  end
end
