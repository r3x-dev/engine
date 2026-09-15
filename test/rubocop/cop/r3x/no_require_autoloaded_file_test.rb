# frozen_string_literal: true

require "test_helper"
require "rubocop"
require "tmpdir"
require_relative "../../../../.rubocop/cop/r3x/no_require_autoloaded_file"

module RuboCop
  module Cop
    module R3x
      class NoRequireAutoloadedFileTest < ActiveSupport::TestCase
        def test_literal_autoloaded_targets
          ['require "r3x/env"', 'require "r3x/env.rb"', 'Kernel.require "r3x/env"',
            'require_relative "env"', 'require_relative "../r3x/env.rb"', 'require "./lib/r3x/env"'].each do |source|
            assert_equal 1, investigate(source).size, source
          end
        end

        def test_external_dynamic_and_non_autoloaded_targets
          ['require "logger"', 'require "fugit"', "require path", "require_relative path",
            'R3x::GemLoader.require "r3x/env"', 'require_relative "../../config/boot"',
            'require_relative "missing"', 'loader.require "r3x/env"'].each do |source|
            assert_empty investigate(source), source
          end
        end

        def test_ignored_targets
          assert_empty investigate('require "r3x/env"', ignored: ["lib/r3x"])
        end

        def test_application_autoload_root
          assert_equal 1, investigate('require "r3x/client/http"').size
        end

        def test_cache_changes_when_autoload_targets_are_added_or_removed
          Dir.mktmpdir do |directory|
            config = RuboCop::Config.new("R3x/NoRequireAutoloadedFile" => { "AutoloadPaths" => [directory] })
            cop = NoRequireAutoloadedFile.new(config)
            checksum = cop.external_dependency_checksum
            target = File.join(directory, "example.rb")
            File.write(target, "class Example; end")

            assert_not_equal checksum, cop.external_dependency_checksum

            File.delete(target)

            assert_equal checksum, cop.external_dependency_checksum
          end
        end

        private

        def investigate(source, ignored: ["lib/assets", "lib/tasks"])
          config = RuboCop::Config.new({
            "R3x/NoRequireAutoloadedFile" => {
              "Enabled" => true, "AutoloadPaths" => ["app/lib", "lib"], "IgnoredPaths" => ignored
            },
          }, Rails.root.join(".rubocop.yml").to_s)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, Rails.root.join("lib/r3x/example.rb").to_s)
          cop = NoRequireAutoloadedFile.new(config)
          RuboCop::Cop::Commissioner.new([cop]).investigate(processed_source).offenses
        end
      end
    end
  end
end
