require "digest"
require "ripper"

module R3x
  module Workflow
    class CacheKey
      class << self
        def generate(workflow_key:, block:, method_name:, key: nil)
          new(workflow_key:, block:, method_name:, key:).generate
        end
      end

      def initialize(workflow_key:, block:, method_name:, key:)
        @workflow_key = workflow_key
        @block = block
        @method_name = method_name.to_s
        @key = key
      end

      def generate
        file, line = block.source_location

        unless file && line && File.file?(file)
          raise "#{method_name} requires a block backed by a readable Ruby source file"
        end

        if key.nil? && ambiguous_source_line?(file, line)
          raise "#{method_name} cannot infer a unique cache key when multiple #{method_name} calls share line #{line}; " \
            "move them to separate lines or pass key:"
        end

        path_digest = Digest::SHA256.hexdigest(File.expand_path(file))
        location_digest = Digest::SHA256.hexdigest(line.to_s)
        key_digest = Digest::SHA256.hexdigest(key.to_s) unless key.nil?
        file_digest = Digest::SHA256.file(file).hexdigest
        fingerprint = [ path_digest, location_digest, key_digest, file_digest ].compact.join(":")

        "r3x:workflow:#{workflow_key}:#{Digest::SHA256.hexdigest(fingerprint)}"
      end

      private

      attr_reader :workflow_key, :block, :method_name, :key

      def ambiguous_source_line?(file, line)
        source_line = File.readlines(file)[line - 1].to_s

        Ripper.lex(source_line).count { |(_, type, token, _)| type == :on_ident && token == method_name } > 1
      end
    end
  end
end
