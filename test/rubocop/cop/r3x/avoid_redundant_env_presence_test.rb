# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/avoid_redundant_env_presence"

module RuboCop
  module Cop
    module R3x
      class AvoidRedundantEnvPresenceTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/AvoidRedundantEnvPresence" => { "Enabled" => true })
        end

        def test_fetch_with_presence
          assert_offense('R3x::Env.fetch("R3X_FOO").presence')
        end

        def test_fetch_bang_with_presence
          assert_offense('R3x::Env.fetch!("R3X_FOO").presence')
        end

        def test_secure_fetch_with_presence
          assert_offense('R3x::Env.secure_fetch("R3X_FOO", prefix: "R3X_").presence')
        end

        def test_fetch_without_presence
          refute_offense('R3x::Env.fetch("R3X_FOO")')
        end

        def test_fetch_bang_without_presence
          refute_offense('R3x::Env.fetch!("R3X_FOO")')
        end

        def test_secure_fetch_without_presence
          refute_offense('R3x::Env.secure_fetch("R3X_FOO", prefix: "R3X_")')
        end

        def test_other_presence_is_allowed
          refute_offense("some_other_value.presence")
        end

        def test_autocorrect_fetch_presence
          assert_autocorrect('R3x::Env.fetch("R3X_FOO").presence', 'R3x::Env.fetch("R3X_FOO")')
        end

        def test_autocorrect_fetch_bang_presence
          assert_autocorrect('R3x::Env.fetch!("R3X_FOO").presence', 'R3x::Env.fetch!("R3X_FOO")')
        end

        def test_autocorrect_secure_fetch_presence
          assert_autocorrect('R3x::Env.secure_fetch("R3X_FOO", prefix: "R3X_").presence', 'R3x::Env.secure_fetch("R3X_FOO", prefix: "R3X_")')
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

        def assert_autocorrect(source, expected)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
          cop = AvoidRedundantEnvPresence.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])
          offenses = commissioner.investigate(processed_source).offenses

          flunk "Expected offenses to autocorrect for: #{source}" if offenses.empty?

          corrected_source = offenses.first.corrector.process

          assert_equal expected, corrected_source
        end

        def investigate(source)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
          cop = AvoidRedundantEnvPresence.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])

          commissioner.investigate(processed_source).offenses
        end
      end
    end
  end
end
