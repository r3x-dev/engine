# Keep seeds as a no-op in production.
#
# Why: production startup uses `db:prepare` (see bin/docker-entrypoint), and on a
# fresh database that task may run `db:seed`. Raising here would break first boot.
if Rails.env.production?
  puts "[db:seed] Skipping dashboard demo seeds in production." # rubocop:disable Rails/Output
else
  load Rails.root.join("db/seeds/development/dashboard_demo.rb")
end
