# frozen_string_literal: true

module Dashboard
  class EnqueueRequest < Run
    scope :for_workflow, ->(class_names) do
      where(class_name: R3x::Workflow::EnqueueJob.name).where(Arel.sql(target_class_sql).in(class_names))
    end

    def self.target_class_sql
      case connection.adapter_name
      when /sqlite/i
        "json_extract(arguments, '$.arguments[0]')"
      when /postgres/i
        "arguments::jsonb -> 'arguments' ->> 0"
      else
        raise NotImplementedError, "Unsupported database adapter for workflow enqueue requests: #{connection.adapter_name}"
      end
    end
  end
end
