require "test_helper"
require "tmpdir"

module R3x
  module Workflow
    class ValidatorTest < ActiveSupport::TestCase
      def scan_with(code, policy: :strict)
        Dir.mktmpdir do |dir|
          file = File.join(dir, "test_workflow.rb")
          File.write(file, code)
          Validator.scan_file(file, policy: policy)
        end
      end

      def assert_forbidden(code, message: nil)
        error = assert_raises(Validator::ForbiddenAccessError) { scan_with(code) }
        assert_match(/forbidden/i, error.message) if message.nil?
      end

      # --- Allowed patterns ---

      test "allows clean workflow code" do
        code = <<~RUBY
          module Workflows
            class Clean < R3x::Workflow::Base
              def run(ctx)
                { ok: true }
              end
            end
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows ctx.client.http usage" do
        code = <<~RUBY
          def run(ctx)
            ctx.client.http.get("https://example.com")
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows ctx.client.llm usage" do
        code = <<~RUBY
          def run(ctx)
            ctx.client.llm.message(model: "gemini-2.0-flash", prompt: "hi")
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows ctx.client.prometheus usage" do
        code = <<~RUBY
          def run(ctx)
            ctx.client.prometheus.query("up")
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows usages of R3x modules in class inheritance" do
        code = <<~RUBY
          module Workflows
            class MyWf < R3x::Workflow::Base
            end
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows api_key_env option string" do
        code = <<~RUBY
          module Workflows
            class LlmWf < R3x::Workflow::Base
              uses :llm, api_key_env: "GEMINI_API_KEY_MICHAL"
              def run(ctx); end
            end
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      test "allows local variables and method calls" do
        code = <<~RUBY
          def run(ctx)
            url = "https://example.com"
            response = ctx.client.http.get(url)
            response.body
          end
        RUBY
        assert_nothing_raised { scan_with(code) }
      end

      # --- Forbidden: ENV ---

      test "forbids ENV subscript access" do
        assert_forbidden 'ENV["FOO"]'
      end

      test "forbids ENV.fetch" do
        assert_forbidden 'ENV.fetch("FOO")'
      end

      test "forbids ENV.fetch with default" do
        assert_forbidden 'ENV.fetch("FOO", "default")'
      end

      test "forbids ENV assignment" do
        assert_forbidden 'ENV["FOO"] = "bar"'
      end

      test "forbids ENV.each" do
        assert_forbidden "ENV.each { |k, v| puts k }"
      end

      test "forbids ENV.key?" do
        assert_forbidden 'ENV.key?("FOO")'
      end

      test "forbids top-level ::ENV" do
        assert_forbidden '::ENV["FOO"]'
      end

      test "forbids ENV as value" do
        assert_forbidden "config = ENV"
      end

      test "forbids ENV.to_h" do
        assert_forbidden "ENV.to_h"
      end

      test "forbids ENV in assignment" do
        assert_forbidden 'my_var = ENV["FOO"]'
      end

      # --- Forbidden: R3x::Env ---

      test "forbids R3x::Env.fetch!" do
        assert_forbidden 'R3x::Env.fetch!("MY_KEY")'
      end

      test "forbids R3x::Env.fetch" do
        assert_forbidden 'R3x::Env.fetch("MY_KEY")'
      end

      test "forbids R3x::Env.present?" do
        assert_forbidden 'R3x::Env.present?("MY_KEY")'
      end

      test "forbids R3x::Env.load_from_vault" do
        assert_forbidden 'R3x::Env.load_from_vault("secret/foo")'
      end

      # --- Forbidden: ::R3x::Env (top-level constant path) ---

      test "forbids ::R3x::Env.fetch" do
        assert_forbidden '::R3x::Env.fetch("MY_KEY")'
      end

      test "forbids ::R3x::Env.fetch!" do
        assert_forbidden '::R3x::Env.fetch!("MY_KEY")'
      end

      # --- Forbidden: dangerous methods ---

      test "forbids eval" do
        assert_forbidden 'eval("ENV[\"SECRET\"]")'
      end

      test "forbids system" do
        assert_forbidden 'system("ls")'
      end

      test "forbids exec" do
        assert_forbidden 'exec("ls")'
      end

      test "forbids spawn" do
        assert_forbidden 'spawn("ls")'
      end

      test "forbids backtick execution" do
        assert_forbidden "`ls`"
      end

      test "forbids send" do
        assert_forbidden "obj.send(:dangerous_method)"
      end

      test "forbids __send__" do
        assert_forbidden "obj.__send__(:dangerous_method)"
      end

      test "forbids instance_eval" do
        assert_forbidden 'obj.instance_eval("code")'
      end

      test "forbids class_eval" do
        assert_forbidden 'Klass.class_eval("code")'
      end

      test "forbids const_get" do
        assert_forbidden "Module.const_get(name)"
      end

      # --- permissive policy ---

      test "allows ENV under permissive policy" do
        code = <<~RUBY
          def run(ctx)
            ENV["FOO"]
          end
        RUBY
        assert_nothing_raised { scan_with(code, policy: :permissive) }
      end

      test "allows R3x::Env under permissive policy" do
        code = <<~RUBY
          def run(ctx)
            R3x::Env.fetch!("KEY")
          end
        RUBY
        assert_nothing_raised { scan_with(code, policy: :permissive) }
      end

      # --- error messages ---

      test "error message includes file path" do
        Dir.mktmpdir do |dir|
          file = File.join(dir, "bad_workflow.rb")
          File.write(file, 'ENV["X"]')
          error = assert_raises(Validator::ForbiddenAccessError) do
            Validator.scan_file(file)
          end
          assert_includes error.message, file
        end
      end

      test "error message deduplicates violations" do
        code = <<~RUBY
          a = ENV["X"]
          b = ENV["Y"]
          c = ENV["Z"]
        RUBY
        Dir.mktmpdir do |dir|
          file = File.join(dir, "multi.rb")
          File.write(file, code)
          error = assert_raises(Validator::ForbiddenAccessError) do
            Validator.scan_file(file)
          end
          assert_equal 1, error.message.scan("ENV").size
        end
      end
    end
  end
end
