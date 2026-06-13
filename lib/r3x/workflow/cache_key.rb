require "digest"

module R3x
  module Workflow
    class CacheKey
      class << self
        def generate(workflow_key:, block:, method_name:)
          new(workflow_key: workflow_key, block: block, method_name: method_name).generate
        end
      end

      def initialize(workflow_key:, block:, method_name:)
        @workflow_key = workflow_key
        @block = block
        @method_name = method_name.to_s
      end

      def generate
        file, line = block.source_location

        unless file && line && File.file?(file)
          raise "#{method_name} requires a block backed by a readable Ruby source file"
        end

        path_digest = Digest::SHA256.hexdigest(File.expand_path(file))
        # RubyVM::InstructionSequence#to_a[4] is metadata, e.g.
        # { code_location: [1, 13, 1, 18], parser: :prism }.
        location_digest = Digest::SHA256.hexdigest(
          RubyVM::InstructionSequence.of(block).to_a.dig(4, :code_location).join(":")
        )
        file_digest = Digest::SHA256.file(file).hexdigest
        fingerprint = "#{path_digest}:#{location_digest}:#{file_digest}"

        "r3x:workflow:#{workflow_key}:#{Digest::SHA256.hexdigest(fingerprint)}"
      end

      private

      attr_reader :workflow_key, :block, :method_name
    end
  end
end
