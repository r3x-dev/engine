# frozen_string_literal: true

require "digest"

module RuboCop
  module Cop
    module R3x
      # Check literal targets against the project's configured autoload roots.
      # Dynamic pack loading and external libraries are not inferred from names.
      class NoRequireAutoloadedFile < Base
        MSG = "Reference the constant instead of requiring a file managed by Rails autoloading."
        RESTRICT_ON_SEND = %i[require require_relative].freeze

        # A newly added or removed target can change offenses in an unchanged caller.
        def external_dependency_checksum
          Digest::SHA256.hexdigest(autoload_roots.flat_map { Dir.glob(File.join(it, "**/*.rb")) }.sort.join("\n"))
        end

        def on_send(node)
          return unless node.receiver.nil? || node.receiver.const_name == "Kernel"

          argument = node.first_argument
          return unless argument&.str_type?

          roots = autoload_roots
          bases = if node.method?(:require_relative)
            [File.dirname(processed_source.file_path)]
          elsif argument.value.start_with?(".")
            [config.base_dir_for_path_parameters]
          else
            roots
          end
          paths = bases.map { File.expand_path(argument.value.delete_suffix(".rb") + ".rb", it) }
          return unless paths.any? { autoloaded_file?(it, roots) }

          add_offense(node)
        end

        private

        def autoload_roots
          cop_config.fetch("AutoloadPaths").map { File.expand_path(it, config.base_dir_for_path_parameters) }
        end

        def autoloaded_file?(path, roots)
          return false unless File.file?(path)
          return false unless roots.any? { path.start_with?(it + File::SEPARATOR) }

          cop_config.fetch("IgnoredPaths", []).none? do |ignored|
            directory = File.expand_path(ignored, config.base_dir_for_path_parameters)
            path == directory || path.start_with?(directory + File::SEPARATOR)
          end
        end
      end
    end
  end
end
