require_relative "../support/dashboard_demo_seeder"

seeder = Seeds::DashboardDemoSeeder.new
seeder.print_summary(seeder.seed!)
