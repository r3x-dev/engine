require "test_helper"
require_relative "../../../db/seeds/support/dashboard_demo_seeder"

module Seeds
  class DashboardDemoSeederTest < ActiveSupport::TestCase
    setup do
      TestDbCleanup.clear_runtime_tables!
    end

    teardown do
      TestDbCleanup.clear_runtime_tables!
    end

    test "seeds predictable demo workflows and runs" do
      stdout, = capture_io do
        @runs = DashboardDemoSeeder.new.seed!
      end

      assert_equal "", stdout
      assert_equal 5, @runs.size

      runs = R3x::Dashboard::Workflow::Runs.new.all.select { |run| run[:workflow_key].start_with?("demo_") }

      assert_equal [
        "demo_feed_watch",
        "demo_inventory_sync",
        "demo_invoice_dispatch",
        "demo_monitoring",
        "demo_retention_cleanup"
      ], R3x::Dashboard::Workflow::Catalog.new.workflow_keys

      assert_equal %w[failed finished finished running scheduled], runs.map { |run| run[:status] }.sort
      assert_equal 5, SolidQueue::RecurringTask.where("key LIKE ?", "workflow:demo_%").count
      assert_equal 5, R3x::TriggerState.where("workflow_key LIKE ?", "demo_%").count
    end

    test "re-seeding replaces demo records instead of duplicating them" do
      seeder = DashboardDemoSeeder.new

      seeder.seed!
      first_counts = runtime_counts

      seeder.seed!

      assert_equal first_counts, runtime_counts
    end

    test "prints summary when explicitly requested" do
      seeder = DashboardDemoSeeder.new
      runs = seeder.seed!

      stdout, = capture_io do
        seeder.print_summary(runs)
      end

      assert_includes stdout, "Seeded dashboard demo data for local UI review:"
      assert_includes stdout, "  /workflow-runs"
      assert_includes stdout, "Demo Feed Watch"
      assert_includes stdout, "Demo Inventory Sync"
      assert_includes stdout, "Demo Invoice Dispatch"
      assert_includes stdout, "Demo Monitoring"
      assert_includes stdout, "Demo Retention Cleanup"
    end

    private

    def runtime_counts
      {
        claimed: SolidQueue::ClaimedExecution.count,
        failed: SolidQueue::FailedExecution.count,
        jobs: SolidQueue::Job.count,
        processes: SolidQueue::Process.count,
        ready: SolidQueue::ReadyExecution.count,
        recurring_tasks: SolidQueue::RecurringTask.count,
        scheduled: SolidQueue::ScheduledExecution.count,
        trigger_states: R3x::TriggerState.count
      }
    end
  end
end
