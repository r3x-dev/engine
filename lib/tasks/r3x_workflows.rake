namespace :r3x do
  namespace :workflows do
    desc "List all registered workflows with their triggers"
    task list: :environment do
      R3x::Workflow::PackLoader.load!

      workflows = R3x::Workflow::Registry.all

      if workflows.empty?
        puts "No workflows registered."
        next
      end

      puts "\nRegistered Workflows (#{workflows.size}):"
      puts "=" * 60

      workflows.each do |workflow_class|
        key = workflow_class.workflow_key
        puts "\n#{key}"
        puts "  Class: #{workflow_class.name}"

        triggers = workflow_class.triggers
        puts "  Triggers:"
        triggers.each do |trigger|
          puts "    - #{trigger.type}: #{trigger.unique_key}"
        end
      end

      puts "\n" + "=" * 60
      puts "Total: #{workflows.size} workflow(s)"
    end

    desc "Run a workflow by key (r3x:workflows:run[workflow_key])"
    task :run, [ :workflow_key ] => :environment do |_task, args|
      raise "Usage: rake r3x:workflows:run[workflow_key]" unless args[:workflow_key]

      key = args[:workflow_key].to_s
      puts "Running workflow: #{key}"

      begin
        result = R3x::Workflow::ManualRunner.run(key)
        puts "  Result: #{result.inspect}"
        puts "Done!"
      rescue => e
        puts "  Error: #{e.class.name}: #{e.message}"
        exit 1
      end
    end
  end
end
