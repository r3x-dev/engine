require "test_helper"

module R3x
  module Validators
    class CronTest < ActiveSupport::TestCase
      class DummyModel
        include ActiveModel::Validations

        attr_reader :cron

        validates_with R3x::Validators::Cron, attributes: [ :cron ], allow_blank: true

        def initialize(cron:)
          @cron = cron
        end
      end

      test "accepts standard cron expression" do
        model = DummyModel.new(cron: "0 13 * * *")

        assert_predicate model, :valid?
      end

      test "accepts human readable cron via fugit" do
        model = DummyModel.new(cron: "every day at 13:00")

        assert_predicate model, :valid?
      end

      test "accepts various human readable formats" do
        assert_predicate DummyModel.new(cron: "every hour"), :valid?
        assert_predicate DummyModel.new(cron: "every 15 minutes"), :valid?
        assert_predicate DummyModel.new(cron: "every weekday at 9am"), :valid?
      end

      test "rejects invalid cron" do
        model = DummyModel.new(cron: "invalid cron")

        assert_not model.valid?
        assert_includes model.errors[:cron], "is not a valid cron expression"
      end

      test "allows blank when allow_blank is set" do
        model = DummyModel.new(cron: "")

        assert_predicate model, :valid?
        model = DummyModel.new(cron: nil)

        assert_predicate model, :valid?
      end
    end
  end
end
