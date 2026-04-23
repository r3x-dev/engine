require "fileutils"
require "logger"

module R3x
  module WorkflowLog
    DEFAULT_PATH_ENV = "R3X_WORKFLOW_LOG_PATH"
    ROTATION_COUNT_ENV = "R3X_WORKFLOW_LOG_ROTATION_COUNT"
    ROTATION_SIZE_BYTES_ENV = "R3X_WORKFLOW_LOG_ROTATION_SIZE_BYTES"
    DEFAULT_ROTATION_COUNT = 10
    DEFAULT_ROTATION_SIZE_BYTES = 50 * 1024 * 1024

    class Logger
      def initialize(stdout_logger:, file_logger:)
        @stdout_logger = stdout_logger
        @file_logger = file_logger
        @broadcast_logger = ActiveSupport::BroadcastLogger.new(stdout_logger, file_logger)
      end

      def formatter
        stdout_logger.formatter
      end

      def tagged(*tags)
        if block_given?
          stdout_logger.tagged(*tags) do
            file_logger.tagged(*tags) do
              yield self
            end
          end
        else
          self.class.new(
            stdout_logger: stdout_logger.tagged(*tags),
            file_logger: file_logger.tagged(*tags)
          )
        end
      end

      def respond_to_missing?(name, include_private = false)
        broadcast_logger.respond_to?(name, include_private) || super
      end

      private
        attr_reader :broadcast_logger, :file_logger, :stdout_logger

        def method_missing(name, *args, **kwargs, &block)
          return super unless broadcast_logger.respond_to?(name)

          broadcast_logger.public_send(name, *args, **kwargs, &block)
        end
    end

    class << self
      def build_logger(stdout: STDOUT, path: nil, env: Rails.env)
        workflow_log_path = path_for(path:, env:)
        FileUtils.mkdir_p(workflow_log_path.dirname)
        level = configured_log_level

        Logger.new(
          stdout_logger: build_stdout_logger(stdout, env: env, level: level),
          file_logger: build_file_logger(workflow_log_path, level: level)
        )
      end

      def path_for(path: nil, env: Rails.env)
        resolved_path =
          present_value(path) ||
          env_value(DEFAULT_PATH_ENV) ||
          Rails.root.join("log", "workflow_runs.#{env}.jsonl")

        resolved_path.is_a?(Pathname) ? resolved_path : Pathname.new(resolved_path.to_s)
      end

      private

      def build_stdout_logger(stdout, env:, level:)
        ActiveSupport::TaggedLogging.new(
          ActiveSupport::Logger.new(stdout).tap do |logger|
            logger.formatter = Rails.application.config.log_formatter if env.to_s == "production"
            logger.level = level
          end
        )
      end

      def build_file_logger(path, level:)
        ActiveSupport::TaggedLogging.new(
          ::Logger.new(path.to_s, rotation_count, rotation_size_bytes).tap do |logger|
            logger.formatter = R3x::LogFormatter.new
            logger.level = level
          end
        )
      end

      def configured_log_level
        value = Rails.application.config.log_level
        return value if value.is_a?(Integer)

        ::Logger::Severity.const_get(value.to_s.upcase)
      rescue NameError
        raise ArgumentError, "Unsupported log level: #{value.inspect}"
      end

      def rotation_count
        integer_env(ROTATION_COUNT_ENV) || DEFAULT_ROTATION_COUNT
      end

      def rotation_size_bytes
        integer_env(ROTATION_SIZE_BYTES_ENV) || DEFAULT_ROTATION_SIZE_BYTES
      end

      def env_value(key)
        present_value(ENV[key])
      end

      def integer_env(key)
        value = env_value(key)
        return if value.nil?

        parsed = Integer(value)
        raise ArgumentError, "#{key} must be positive" unless parsed.positive?

        parsed
      end

      def present_value(value)
        return if value.nil?
        return if value.respond_to?(:empty?) && value.empty?

        value
      end
    end
  end
end
