module R3x
  module Workflow
    class Validator
      class ForbiddenAccessError < StandardError; end

      def self.scan_file(file_path, policy: :strict)
        new(file_path, policy: policy).scan
      end

      def initialize(file_path, policy:)
        @file_path = file_path
        @policy = policy
        @violations = []
      end

      def scan
        return if @policy == :permissive

        source = File.read(@file_path)
        ast = RubyVM::AbstractSyntaxTree.parse(source)
        walk(ast)
        raise_on_violations
      end

      private

      def walk(node)
        return if node.nil?
        return unless node.is_a?(RubyVM::AbstractSyntaxTree::Node)

        check_node(node)
        node.children.each { |child| walk(child) if child.is_a?(RubyVM::AbstractSyntaxTree::Node) }
      end

      def check_node(node)
        case node.type
        when :CONST
          check_forbidden_constant(node.children[0])
        when :COLON3
          check_forbidden_constant(node.children[0])
        when :COLON2
          check_forbidden_prefix(node)
        when :FCALL
          check_forbidden_method(node.children[0])
        when :CALL
          check_forbidden_method(node.children[1])
        when :XSTR
          @violations << "Backtick shell execution is forbidden (use declared capabilities instead)"
        end
      end

      def check_forbidden_constant(name)
        return unless Policy::STRICT_FORBIDDEN_CONSTANTS.include?(name.to_s)

        @violations << "Direct ENV access is forbidden (use declared capabilities instead)"
      end

      def check_forbidden_method(name)
        return unless Policy::STRICT_FORBIDDEN_METHODS.include?(name)

        @violations << "Calling #{name} is forbidden (use declared capabilities instead)"
      end

      def check_forbidden_prefix(node)
        constant_path = resolve_constant_path(node)
        return if constant_path.nil?

        if Policy::STRICT_FORBIDDEN_MODULE_PREFIXES.any? { |prefix| constant_path == prefix }
          @violations << "Direct #{constant_path} access is forbidden (use declared capabilities instead)"
        end
      end

      def resolve_constant_path(node)
        return nil unless node.is_a?(RubyVM::AbstractSyntaxTree::Node) && node.type == :COLON2

        child = node.children[0]
        name = node.children[1]

        if child.nil?
          name.to_s
        elsif child.is_a?(RubyVM::AbstractSyntaxTree::Node) && child.type == :CONST
          "#{child.children[0]}::#{name}"
        elsif child.is_a?(RubyVM::AbstractSyntaxTree::Node) && child.type == :COLON3
          "::#{child.children[0]}::#{name}"
        end
      end

      def raise_on_violations
        return if @violations.empty?

        unique = @violations.uniq
        message = "Workflow policy violation in #{@file_path}:\n#{unique.map { |v| "  - #{v}" }.join("\n")}"
        raise ForbiddenAccessError, message
      end
    end
  end
end
