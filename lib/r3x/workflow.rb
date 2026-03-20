module R3x
  module Workflow
    KNOWN_CAPABILITIES = Set.new(%i[networking filesystem shell]).freeze

    module Dsl
      extend ActiveSupport::Concern

      class_methods do
        def inherited(subclass)
          super
          subclass._triggers = TriggerManager::Collection.new
          subclass._capabilities = Set.new
        end

        def workflow_key
          name.demodulize.underscore
        end

        def trigger(type, **options)
          trigger_instance = Triggers.resolve(type).new(**options)
          trigger_instance.validate!(message_prefix: "Invalid trigger :#{type} for #{name}")
          _triggers.add(trigger_instance)
        end

        def uses(*capabilities)
          incoming = Set.new(capabilities.flatten.compact.map(&:to_sym))
          unknown = incoming - KNOWN_CAPABILITIES
          raise ArgumentError, "Unknown capabilities: #{unknown.to_a.join(', ')}. Known: #{KNOWN_CAPABILITIES.to_a.join(', ')}" if unknown.any?

          duplicates = incoming & _capabilities
          raise ArgumentError, "Capability already declared: #{duplicates.to_a.join(', ')}" if duplicates.any?

          _capabilities.merge(incoming)
        end

        def capabilities
          _capabilities.dup
        end

        def uses?(capability)
          _capabilities.include?(capability.to_sym)
        end

        def triggers
          _triggers.to_a
        end

        def schedulable_triggers
          _triggers.select(&:cron_schedulable?)
        end

        def triggers_by_key
          _triggers.by_key
        end

        attr_accessor :_triggers
        attr_accessor :_capabilities
      end
    end
  end
end
