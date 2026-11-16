# frozen_string_literal: true

require "json"
require "digest"

module RailsAgentHarness
  module Installation
    PATH = "config/agent_harness_clients.json"

    def self.instruction_digest(text)
      Digest::SHA256.hexdigest(text.scan(/<!-- BEGIN rails_agent_harness -->.*?<!-- END rails_agent_harness -->/m).join("\n"))
    end

    def self.commands(group)
      return [] unless group.is_a?(Hash)

      Array(group.fetch("hooks", [group])).filter_map { |hook| hook["command"] || hook["bash"] if hook.is_a?(Hash) }
    end

    def self.verify(root)
      path = File.join(root, PATH)
      return ["#{PATH}: missing; re-run the installer"] unless File.file?(path)

      expected = JSON.parse(File.read(path, encoding: "UTF-8"))
      unless expected.is_a?(Hash) && expected["version"] == 1 &&
          %w[files instructions hooks].all? { |key| expected[key].is_a?(Hash) } && expected["required"].is_a?(Array)
        return ["#{PATH}: invalid installation manifest"]
      end

      problems = expected.fetch("required").filter_map do |relative|
        "#{relative}: missing installed file" unless installed_file?(root, relative)
      end
      %w[files instructions].each do |kind|
        expected.fetch(kind).each do |relative, digest|
          unless installed_file?(root, relative)
            problems << "#{relative}: missing installed file"
            next
          end
          full_path = File.join(root, relative)
          actual = (kind == "files") ? Digest::SHA256.file(full_path).hexdigest : instruction_digest(File.read(full_path, encoding: "UTF-8"))
          problems << "#{relative}: managed content differs from installation; reconcile it or re-run with --force-client-files for skills/Aider" if actual != digest
          problems << "#{relative}: not executable" if relative == "bin/agent-check" && !File.executable?(full_path)
        end
      end
      expected.fetch("hooks").each do |relative, events|
        unless installed_file?(root, relative)
          problems << "#{relative}: missing installed file"
          next
        end
        begin
          settings = JSON.parse(File.read(File.join(root, relative), encoding: "UTF-8"))
          hooks = settings.is_a?(Hash) ? settings["hooks"] : nil
          events.each do |event, signatures|
            groups = (hooks.is_a?(Hash) && hooks[event].is_a?(Array)) ? hooks[event] : []
            available = groups.flat_map { |group| commands(group) }
            unless signatures.all? { |signature| available.any? { |command| command.is_a?(String) && command.include?(signature) } }
              problems << "#{relative}: missing managed #{event} hook"
            end
          end
        rescue JSON::ParserError
          problems << "#{relative}: invalid JSON"
        end
      end
      problems
    rescue JSON::ParserError, TypeError, NoMethodError
      ["#{PATH}: invalid installation manifest"]
    end

    def self.installed_file?(root, relative)
      return false unless relative.is_a?(String)

      full_path = File.expand_path(relative, root)
      full_path.start_with?(File.expand_path(root) + File::SEPARATOR) && File.file?(full_path)
    end
  end
end
