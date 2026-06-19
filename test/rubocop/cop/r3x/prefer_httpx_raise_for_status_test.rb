# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/prefer_httpx_raise_for_status"

module RuboCop
  module Cop
    module R3x
      class PreferHttpxRaiseForStatusTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/PreferHttpxRaiseForStatus" => { "Enabled" => true })
        end

        test "flags manual 2xx check on response status" do
          assert_offense("response.status >= 200 && response.status < 300")
        end

        test "flags manual 2xx check on res status" do
          assert_offense("res.status >= 200 && res.status < 300")
        end

        test "flags manual 2xx check on http_response status" do
          assert_offense("http_response.status >= 200 && http_response.status < 300")
        end

        test "flags manual 2xx check on HTTPX call status" do
          assert_offense('HTTPX.get("https://example.test").status >= 200 && HTTPX.get("https://example.test").status < 300')
        end

        test "does not flag response raise_for_status" do
          refute_offense("response.raise_for_status")
        end

        test "does not flag local status wrapper checks" do
          refute_offense("status >= 200 && status < 300")
        end

        test "does not flag unrelated object status checks" do
          refute_offense("job.status >= 200 && job.status < 300")
        end

        test "does not flag mismatched response objects" do
          refute_offense("response.status >= 200 && other_response.status < 300")
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
          cop = PreferHttpxRaiseForStatus.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])

          commissioner.investigate(processed_source).offenses
        end
      end
    end
  end
end
