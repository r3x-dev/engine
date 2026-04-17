# frozen_string_literal: true

module R3x
  module Workflow
    module DedupKey
      extend self

      def build(workflow_key:, value: nil, candidates: nil)
        candidate = first_present(candidates || [ value ])
        raise ArgumentError, "dedup key value can't be blank" if candidate.blank?

        [ "wf", normalize(workflow_key, label: "workflow_key"), candidate ].join(":")
      end

      private

      def first_present(values)
        Array(values).filter_map do |value|
          normalized = value.to_s.strip
          normalized if normalized.present?
        end.first
      end

      def normalize(value, label:)
        normalized = value.to_s.strip
        return normalized if normalized.present?

        raise ArgumentError, "#{label} can't be blank"
      end
    end
  end
end
