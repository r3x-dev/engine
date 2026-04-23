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

          R3x::Client::GoogleAuth.stubs(:from_env).with { |**kwargs|
            kwargs[:project] == "TEST_APP" && kwargs[:scope] == "https://www.googleapis.com/auth/cloud-translation"
          }.returns(authorization)

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
          assert_equal "<p>Hello <strong>world</strong></p>", result
        end

        private

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
