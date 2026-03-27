require "test_helper"

module R3x
  module Client
    module Google
      class CredentialsTest < ActiveSupport::TestCase
        test "loads credentials from env" do
          ENV["GOOGLE_CREDENTIALS_TEST_APP"] = MultiJson.dump(
            client_id: "client-id",
            client_secret: "client-secret",
            refresh_token: "refresh-token"
          )

          assert_equal(
            {
              "client_id" => "client-id",
              "client_secret" => "client-secret",
              "refresh_token" => "refresh-token"
            },
            Credentials.from_env("GOOGLE_CREDENTIALS_TEST_APP")
          )
        ensure
          ENV.delete("GOOGLE_CREDENTIALS_TEST_APP")
        end
      end
    end
  end
end
