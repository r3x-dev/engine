require "test_helper"

module R3x
  module Client
    module Google
      class TranslateTest < ActiveSupport::TestCase
        test "translate posts to the translation api and returns cleaned text" do
          delivered = nil
          captured = {}
          authorization = FakeAuthorization.new(access_token: "access-token")

          stub_request(:post, "https://translation.googleapis.com/language/translate/v2")
            .with(headers: { "Authorization" => "Bearer access-token" }) do |req|
              delivered = MultiJson.load(req.body)
            end
            .to_return(
              status: 200,
              body: MultiJson.dump(
                "data" => {
                  "translations" => [
                    { "translatedText" => "<p>Hello <strong>world</strong></p>" }
                  ]
                }
              ),
              headers: { "Content-Type" => "application/json" }
            )

          with_stubbed_google_auth(authorization, captured) do
            result = Translate.new(project: "TEST_APP")
              .translate(" Ola mundo ", to: "en", from: "pt")

            assert_equal(
              {
                "q" => " Ola mundo ",
                "target" => "en",
                "source" => "pt",
                "format" => "text"
              },
              delivered
            )
            assert_equal "https://www.googleapis.com/auth/cloud-translation", captured[:scope]
            assert_equal "<p>Hello <strong>world</strong></p>", result
          end
        end

        private

        def with_stubbed_google_auth(result, captured)
          singleton_class = R3x::Client::GoogleAuth.singleton_class
          original_method = R3x::Client::GoogleAuth.method(:from_env)

          singleton_class.define_method(:from_env) do |project:, scope:|
            captured[:scope] = scope
            result
          end

          yield
        ensure
          singleton_class.define_method(:from_env, original_method)
        end

        class FakeAuthorization
          attr_reader :access_token

          def initialize(access_token:)
            @access_token = access_token
          end

          def expires_within?(_seconds)
            false
          end

          def fetch_access_token!
            access_token
          end
        end
      end
    end
  end
end
