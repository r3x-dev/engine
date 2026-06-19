# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/no_manual_method_patching_in_tests"

module RuboCop
  module Cop
    module R3x
      class NoManualMethodPatchingInTestsTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/NoManualMethodPatchingInTests" => { "Enabled" => true })
        end

        test "flags define_singleton_method on constants" do
          assert_offense("HighLine.define_singleton_method(:new) { fake }")
        end

        test "flags singleton_class define_method" do
          assert_offense("Signet::OAuth2::Client.singleton_class.define_method(:new) { fake }")
        end

        test "flags singleton_class alias_method" do
          assert_offense("SolidQueue::Job.singleton_class.alias_method(:original_enqueue, :enqueue)")
        end

        test "flags singleton_class remove_method" do
          assert_offense("SolidQueue::Job.singleton_class.remove_method(:original_enqueue)")
        end

        test "allows plain fake objects to define singleton methods" do
          refute_offense(<<~RUBY)
            fake = Object.new
            fake.define_singleton_method(:call) { :ok }
          RUBY
        end

        test "allows plain fake classes" do
          refute_offense(<<~RUBY)
            fake = Class.new do
              def call
                :ok
              end
            end.new
          RUBY
        end

        test "allows mocha stubs" do
          refute_offense("HighLine.stubs(:new).returns(fake)")
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

        def investigate(source)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
          cop = NoManualMethodPatchingInTests.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])

          commissioner.investigate(processed_source).offenses
        end
      end
    end
  end
end
