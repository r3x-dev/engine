module R3x
  class Logger
    def initialize(logger = Rails.logger, tag: nil)
      @logger = logger
      @tag = tag || self.class.name
    end

    def info(message)
      @logger.tagged(@tag) { @logger.info(message) }
    end

    def debug(message)
      @logger.tagged(@tag) { @logger.debug(message) }
    end

    def warn(message)
      @logger.tagged(@tag) { @logger.warn(message) }
    end

    def error(message)
      @logger.tagged(@tag) { @logger.error(message) }
    end
  end
end
