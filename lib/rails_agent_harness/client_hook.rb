# frozen_string_literal: true

require "json"
require "stringio"
require "rails_agent_harness/guards/migration_guard"

module RailsAgentHarness
  class ClientHook
    CLIENTS = %w[codex copilot cursor gemini].freeze
    PHASES = %w[pre post stop].freeze

    def initialize(root:, stdout:, stderr:)
      @root = root
      @stdout = stdout
      @stderr = stderr
    end

    def call(client, phase, input)
      raise ArgumentError, "unknown client hook" unless CLIENTS.include?(client) && PHASES.include?(phase)

      payload = JSON.parse(RailsAgentHarness.utf8(input.to_s))
      raise ArgumentError, "hook input must be an object" unless payload.is_a?(Hash)
      return allow_response(client, phase) if phase == "stop" && (payload["stop_hook_active"] == true || payload.fetch("loop_count", 0).to_i > 0)
      return allow_response(client, phase) if client == "cursor" && phase == "stop" && payload["status"] != "completed"

      message = if phase == "pre"
        guard_message(client, payload)
      else
        check_message(phase, client, payload)
      end
      return allow_response(client, phase) if message.nil? || message.empty?

      @stdout.puts JSON.generate(response(client, phase, message))
      0
    rescue JSON::ParserError, ArgumentError
      @stderr.puts "agent-check: invalid client hook or input"
      1
    end

    private

    def allow_response(client, phase)
      if client == "cursor" && phase == "pre"
        @stdout.puts JSON.generate("permission" => "allow")
      elsif client == "codex" && phase == "stop"
        @stdout.puts JSON.generate({})
      end
      0
    end

    def edits(client, payload)
      tool = payload["tool_name"] || payload["toolName"]
      tools = {"write_file" => "Write", "replace" => "Edit", "create" => "Write", "edit" => "Edit",
               "str_replace_editor" => "Edit", "Write" => "Write", "Edit" => "Edit", "Delete" => "Edit"}
      return [] unless tools.key?(tool) || tool == "apply_patch"

      input = payload["tool_input"] || payload["toolArgs"] || {}
      if tool == "apply_patch" && input.is_a?(String) && input.lstrip.start_with?("*** Begin Patch")
        input = {"command" => input}
      elsif input.is_a?(String)
        input = JSON.parse(input)
      end
      raise ArgumentError unless input.is_a?(Hash)
      return [] if tool == "str_replace_editor" && input["command"] == "view"

      if tool == "apply_patch"
        patch = input["command"] || input["input"] || input["patch"]
        raise ArgumentError unless patch.is_a?(String)

        changes = patch.scan(/^[ \t]*\*\*\* (Add|Update|Delete) File: (.+)$/).map do |action, path|
          [(action == "Add") ? "Write" : "Edit", path.strip]
        end + patch.scan(/^[ \t]*\*\*\* Move to: (.+)$/).map { |path| ["Write", path.first.strip] }
        return changes.map { |action, path| [action, edit_path(client, payload, path)] }
      end
      normalized = tools.fetch(tool)
      path = input["file_path"] || input["path"] || input["filePath"]
      raise ArgumentError unless path.is_a?(String) && !path.empty?

      path = edit_path(client, payload, path)
      normalized = "Write" unless File.exist?(File.expand_path(path, @root))
      [[normalized, path]]
    end

    def edit_path(client, payload, path)
      return path unless client == "codex" && payload["cwd"].is_a?(String)

      File.expand_path(path, payload["cwd"])
    end

    def guard_message(client, payload)
      guard = Guards::MigrationGuard.new(root: @root, config: Configuration.load(@root))
      edits(client, payload).filter_map do |tool, path|
        decision = guard.pre_tool_use({"tool_name" => tool, "tool_input" => {"file_path" => path}})
        decision.message unless decision.allowed?
      end.join("\n")
    end

    def check_message(phase, client, payload)
      args = []
      if phase == "post"
        paths = if client == "cursor"
          [payload["file_path"]].compact
        else
          edits(client, payload).map(&:last)
        end
        return if paths.empty?

        args = ["--only", "rubocop", "--files", paths.join(",")]
      end
      output = StringIO.new
      status = CLI.start(args, root: @root, stdin: StringIO.new, stdout: output, stderr: output)
      output.string unless status.zero?
    end

    def response(client, phase, message)
      case client
      when "gemini"
        if phase == "post"
          {"hookSpecificOutput" => {"additionalContext" => message}}
        else
          {"decision" => "deny", "reason" => message}
        end
      when "cursor"
        if phase == "pre"
          {"permission" => "deny", "user_message" => message, "agent_message" => message}
        elsif phase == "stop"
          {"followup_message" => message}
        else
          @stderr.puts message
          {}
        end
      when "copilot"
        if phase == "pre"
          {"permissionDecision" => "deny", "permissionDecisionReason" => message}
        elsif phase == "post"
          {"additionalContext" => message}
        else
          {"decision" => "block", "reason" => message}
        end
      when "codex"
        if phase == "pre"
          {"hookSpecificOutput" => {"hookEventName" => "PreToolUse", "permissionDecision" => "deny", "permissionDecisionReason" => message}}
        else
          {"decision" => "block", "reason" => message}
        end
      end
    end
  end
end
