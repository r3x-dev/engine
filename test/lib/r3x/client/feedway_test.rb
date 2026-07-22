# frozen_string_literal: true

require "test_helper"

module R3x
  module Client
    class FeedwayTest < ActiveSupport::TestCase
      teardown do
        WebMock.reset!
      end

      test "raises when url env is missing" do
        with_env("FEEDWAY_URL" => nil, "FEEDWAY_API_TOKEN" => "token-123") do
          error = assert_raises(ArgumentError) do
            Feedway.new(url_env: "FEEDWAY_URL", api_token_env: "FEEDWAY_API_TOKEN")
          end

          assert_equal "Missing FEEDWAY_URL", error.message
        end
      end

      test "raises when api token env is missing" do
        with_env("FEEDWAY_URL" => "https://feedway.test", "FEEDWAY_API_TOKEN" => nil) do
          error = assert_raises(ArgumentError) do
            Feedway.new(url_env: "FEEDWAY_URL", api_token_env: "FEEDWAY_API_TOKEN")
          end

          assert_equal "Missing FEEDWAY_API_TOKEN", error.message
        end
      end

      test "rejects url env names outside feedway prefix" do
        with_env("OTHER_URL" => "https://feedway.test", "FEEDWAY_API_TOKEN" => "token-123") do
          error = assert_raises(ArgumentError) do
            Feedway.new(url_env: "OTHER_URL", api_token_env: "FEEDWAY_API_TOKEN")
          end

          assert_equal "Key 'OTHER_URL' must be 'FEEDWAY_URL' or start with 'FEEDWAY_URL_'", error.message
        end
      end

      test "rejects api token env names outside feedway prefix" do
        with_env("FEEDWAY_URL" => "https://feedway.test", "OTHER_TOKEN" => "token-123") do
          error = assert_raises(ArgumentError) do
            Feedway.new(url_env: "FEEDWAY_URL", api_token_env: "OTHER_TOKEN")
          end

          assert_equal "Key 'OTHER_TOKEN' must be 'FEEDWAY_API_TOKEN' or start with 'FEEDWAY_API_TOKEN_'", error.message
        end
      end

      test "publish sends POST request with correct payload and headers in real mode" do
        stub_request(:post, "https://feedway.test/api/v1/entries")
          .with(
            body: '{"content_html":"<p>hello</p>","title":"My Title"}',
            headers: {
              "Authorization" => "Bearer token-123",
            },
          )
          .to_return(
            status: 201,
            body: MultiJSON.generate({ "result" => "created", "id" => "sha256-v1:abc" }),
            headers: { "Content-Type" => "application/json" },
          )

        with_client_env do
          with_env("R3X_FEEDWAY_DRY_RUN" => "false") do
            client = Feedway.new
            result = client.publish(content_html: "<p>hello</p>", title: "My Title")

            assert_equal "created", result["result"]
            assert_equal "sha256-v1:abc", result["id"]
          end
        end
      end

      test "publish returns dry_run result and logs intent when dry run is active" do
        client = with_client_env { Feedway.new }

        result = nil
        output = capture_logged_output do
          result = client.publish(content_html: "<p>hello</p>", title: "My Title")
        end

        assert_equal({ "mode" => "dry_run", "result" => "dry_run", "id" => "dry-run-feedway-id" }, result)
        assert_includes output, "DRY-RUN"
        assert_includes output, "action=publish"
        assert_includes output, "content_length=12"
        assert_includes output, "title="
        assert_includes output, "My Title"
      end

      test "publish requires content_html" do
        client = with_client_env { Feedway.new }

        assert_raises(ArgumentError) do
          client.publish(content_html: "")
        end

        assert_raises(ArgumentError) do
          client.publish(content_html: nil)
        end
      end

      test "context client helper builds feedway client" do
        client = with_client_env do
          R3x::Workflow::Context::Client.feedway
        end

        assert_instance_of Feedway, client

        result = client.publish(content_html: "<p>hello</p>")

        assert_equal "dry_run", result["result"]
      end

      private

      def with_client_env(&)
        with_env(
          "FEEDWAY_URL"       => "https://feedway.test/",
          "FEEDWAY_API_TOKEN" => "token-123",
          &
        )
      end

      def with_env(hash)
        originals = hash.each_with_object({}) { |(key, _), memo| memo[key] = ENV[key] }
        hash.each { |key, value| ENV[key] = value }
        yield
      ensure
        originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
      end
    end
  end
end
