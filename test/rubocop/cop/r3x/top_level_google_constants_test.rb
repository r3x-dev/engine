# frozen_string_literal: true

require "test_helper"
require "rubocop"
require_relative "../../../../.rubocop/cop/r3x/top_level_google_constants"

module RuboCop
  module Cop
    module R3x
      class TopLevelGoogleConstantsTest < ActiveSupport::TestCase
        def setup
          @config = RuboCop::Config.new("R3x/TopLevelGoogleConstants" => { "Enabled" => true })
        end

        def test_flags_unqualified_google_apis_reference
          assert_offense("Google::Apis::SheetsV4::SheetsService.new")
        end

        def test_flags_unqualified_google_auth_reference
          assert_offense("Google::Auth::Credentials.new")
        end

        def test_flags_unqualified_google_cloud_reference
          assert_offense("Google::Cloud::Translate.new")
        end

        def test_allows_top_level_google_apis_reference
          refute_offense("::Google::Apis::SheetsV4::SheetsService.new")
        end

        def test_allows_local_google_gmail_reference
          refute_offense("Google::Gmail::Thing.new")
        end

        def test_allows_explicit_project_google_reference
          refute_offense("R3x::Client::Google::Gmail.new")
        end

        def test_allows_google_module_definition
          refute_offense("module Google; end")
        end

        def test_allows_google_namespace_definition
          refute_offense("module Google::Apis; end")
        end

        def test_allows_bare_google_reference
          refute_offense("Google")
        end

        def test_allows_unknown_google_namespace
          refute_offense("Google::FutureNamespace.new")
        end

        def test_namespace_spacing_does_not_bypass_check
          assert_autocorrect("Google::\nApis::SheetsV4.new", "::Google::\nApis::SheetsV4.new")
        end

        def test_google_sdk_superclass_is_checked
          assert_offense("class Example < Google::Auth::Credentials; end")
        end

        def test_nested_google_definition_is_allowed
          refute_offense("module R3x; module Client; module Google; end; end; end")
        end

        def test_autocorrects_unqualified_google_reference
          assert_autocorrect(
            "Google::Apis::SheetsV4::SheetsService.new",
            "::Google::Apis::SheetsV4::SheetsService.new",
          )
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
          cop = TopLevelGoogleConstants.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])
          offenses = commissioner.investigate(processed_source).offenses

          flunk "Expected offenses to autocorrect for: #{source}" if offenses.empty?

          corrected_source = offenses.first.corrector.process

          assert_equal expected, corrected_source
        end

        def investigate(source)
          processed_source = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f)
          cop = TopLevelGoogleConstants.new(@config)
          commissioner = RuboCop::Cop::Commissioner.new([cop])

          commissioner.investigate(processed_source).offenses
        end
      end
    end
  end
end
