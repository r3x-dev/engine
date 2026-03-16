namespace :r3x do
  namespace :workflows do
    desc "List all registered workflows with their triggers"
    task list: :environment do
      R3x::WorkflowPackLoader.load!

      workflows = R3x::WorkflowRegistry.all

      if workflows.empty?
        puts "No workflows registered."
        next
      end

      puts "\nRegistered Workflows (#{workflows.size}):"
      puts "=" * 60

      workflows.each do |workflow_class|
        key = workflow_class.workflow_key
        class_name = workflow_class.name

        puts "\n#{key}"
        puts "  Class: #{class_name}"

        triggers = workflow_class.triggers
        if triggers.empty?
          puts "  Triggers: none"
        else
          puts "  Triggers:"
          triggers.each do |trigger|
            puts "    - #{trigger.type}: #{trigger.to_h}"
          end
        end
      end

      puts "\n" + "=" * 60
      puts "Total: #{workflows.size} workflow(s)"
    end

    desc "Run all workflows or a specific one (r3x:workflows:run[workflow_key])"
    task :run, [ :workflow_key ] => :environment do |_task, args|
      R3x::WorkflowPackLoader.load!

      workflow_keys = if args[:workflow_key].present?
        [ args[:workflow_key].to_s ]
      else
        R3x::WorkflowRegistry.all.map do |workflow_class|
          workflow_class.respond_to?(:workflow_key) ? workflow_class.workflow_key : workflow_class.name.demodulize.underscore
        end
      end

      workflow_keys.each do |key|
        puts "Running workflow: #{key}"
        begin
          workflow_class = R3x::WorkflowRegistry.fetch(key)
          result = workflow_class.new.run(R3x::WorkflowContext.new)
          puts "  ✓ Success: #{result.inspect}"
        rescue => e
          puts "  ✗ Error: #{e.message}"
          raise e if args[:workflow_key].present? # Re-raise if specific workflow failed
        end
      end

      puts "\nDone! #{workflow_keys.size} workflow(s) executed."
    end
  end
end
