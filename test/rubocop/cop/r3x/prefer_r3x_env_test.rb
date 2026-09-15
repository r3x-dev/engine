# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/prefer_r3x_env"

module RuboCop
  module Cop
    module R3x
      class PreferR3xEnvTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/PreferR3xEnv" => { "Enabled" => true })
        end

        def test_env_bracket_with_r3x_key
          assert_offense('ENV["R3X_FOO"]')
        end

        def test_env_fetch_with_r3x_key
          assert_offense('ENV.fetch("R3X_FOO")')
        end

        def test_env_fetch_with_default_and_r3x_key
          assert_offense('ENV.fetch("R3X_FOO", "default")')
        end

        def test_env_key_with_r3x_key
          assert_offense('ENV.key?("R3X_FOO")')
        end

        def test_env_present_with_r3x_key
          assert_offense('ENV.present?("R3X_FOO")')
        end

        def test_env_bracket_with_non_r3x_key
          refute_offense('ENV["PORT"]')
        end

        def test_env_fetch_with_non_r3x_key
          refute_offense('ENV.fetch("RAILS_ENV", "development")')
        end

        def test_env_assignment_with_r3x_key
          refute_offense('ENV["R3X_FOO"] = "bar"')
        end

        def test_r3x_env_fetch_is_allowed
          refute_offense('R3x::Env.fetch("R3X_FOO")')
        end

        def test_client_reads_include_provider_and_dynamic_keys
          ['ENV["APIFY_API_KEY"]', "::ENV.fetch(api_key_env)", "ENV.key?(name)"].each do |source|
            assert_equal 1, investigate(source, "app/lib/r3x/client/example.rb").size
          end
        end

        def test_client_writes_and_env_helpers_are_allowed
          ['ENV["APIFY_API_KEY"] = "value"', "R3x::Env.secure_fetch(api_key_env)", "Other::ENV.fetch(name)"].each do |source|
            assert_empty investigate(source, "app/lib/r3x/client/example.rb")
          end
        end

        def test_dynamic_keys_outside_clients_remain_allowed
          assert_empty investigate("ENV[name]", "lib/r3x/env.rb")
          assert_empty investigate("ENV[name]", "app/lib/r3x/client_examples/example.rb")
        end

        private

        def assert_offense(source)
          offenses = investigate(source)

          assert_equal 1, offenses.size, "Expected one offense for: #{source}"
        end

        def refute_offense(source)
          offenses = investigate(source)

          assert_empty offenses, "Expected no offenses for: #{source}"
        end

        def investigate(source, path = "app/models/example.rb")
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, Rails.root.join(path).to_s)
          cop = PreferR3xEnv.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])

          commissioner.investigate(processed_source).offenses
        end
      end
    end
  end
end
