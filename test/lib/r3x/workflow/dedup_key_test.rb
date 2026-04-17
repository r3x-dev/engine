# frozen_string_literal: true

require "test_helper"

module R3x
  module Workflow
    class DedupKeyTest < ActiveSupport::TestCase
      test "build uses workflow key and first present candidate" do
        key = DedupKey.build(workflow_key: "porto_santo_news", candidates: [ nil, "", "https://example.test/story" ])

        assert_equal "wf:porto_santo_news:https://example.test/story", key
      end

      test "build rejects blank values" do
        error = assert_raises(ArgumentError) do
          DedupKey.build(workflow_key: "porto_santo_news", candidates: [ nil, "  " ])
        end

        assert_equal "dedup key value can't be blank", error.message
      end
    end
  end
end
