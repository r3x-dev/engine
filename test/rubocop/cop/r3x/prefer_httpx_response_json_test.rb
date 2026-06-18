# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/prefer_httpx_response_json"

module RuboCop
  module Cop
    module R3x
      class PreferHttpxResponseJsonTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/PreferHttpxResponseJson" => { "Enabled" => true })
        end

        test "flags MultiJSON.parse on response.body" do
          assert_offense("MultiJSON.parse(response.body)")
        end

        test "flags MultiJSON.parse on response.body.to_s" do
          assert_offense("MultiJSON.parse(response.body.to_s)")
        end

        test "flags MultiJSON.load on res.body" do
          assert_offense("MultiJSON.load(res.body)")
        end

        test "flags MultiJSON.parse on HTTPX.get.body" do
          assert_offense('MultiJSON.parse(HTTPX.get("url").body)')
        end

        test "flags MultiJSON.parse on @response.body.to_s" do
          assert_offense("MultiJSON.parse(@response.body.to_s)")
        end

        test "flags MultiJSON.parse on http_response.body" do
          assert_offense("MultiJSON.parse(http_response.body)")
        end

        test "does not flag direct call to response.json" do
          refute_offense("response.json")
        end

        test "does not flag MultiJSON.parse on post.body" do
          refute_offense("MultiJSON.parse(post.body)")
        end

        test "does not flag MultiJSON.parse on message.body.to_s" do
          refute_offense("MultiJSON.parse(message.body.to_s)")
        end

        test "does not flag MultiJSON.generate" do
          refute_offense("MultiJSON.generate(data)")
        end

        test "autocorrects MultiJSON.parse(response.body) to response.json" do
          assert_autocorrect("MultiJSON.parse(response.body)", "response.json")
        end

        test "autocorrects MultiJSON.parse(response.body.to_s) to response.json" do
          assert_autocorrect("MultiJSON.parse(response.body.to_s)", "response.json")
        end

        test "autocorrects MultiJSON.load(res.body) to res.json" do
          assert_autocorrect("MultiJSON.load(res.body)", "res.json")
        end

        test "autocorrects MultiJSON.parse(HTTPX.get('url').body) to HTTPX.get('url').json" do
          assert_autocorrect("MultiJSON.parse(HTTPX.get('url').body)", "HTTPX.get('url').json")
        end

        test "autocorrects MultiJSON.parse(@response.body.to_s) to @response.json" do
          assert_autocorrect("MultiJSON.parse(@response.body.to_s)", "@response.json")
        end

        private

        def investigate(source)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
          cop = PreferHttpxResponseJson.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([ cop ])

          commissioner.investigate(processed_source).offenses
        end

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
          cop = PreferHttpxResponseJson.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([ cop ])
          offenses = commissioner.investigate(processed_source).offenses

          flunk "Expected offenses to autocorrect for: #{source}" if offenses.empty?

          corrected_source = offenses.first.corrector.process

          assert_equal expected, corrected_source
        end
      end
    end
  end
end
