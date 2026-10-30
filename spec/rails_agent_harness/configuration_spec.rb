# frozen_string_literal: true

RSpec.describe RailsAgentHarness::Configuration do
  around do |example|
    Dir.mktmpdir("agent_harness_config") do |dir|
      @root = dir
      example.run
    end
  end

  attr_reader :root

  def write_config(contents)
    path = File.join(root, described_class::PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  let(:expected_defaults) do
    {
      "base_branch" => "main",
      "max_output_lines" => 40,
      "checks" => {
        "rubocop" => {"enabled" => true, "command" => nil},
        "brakeman" => {"enabled" => true, "command" => nil},
        "tests" => {"enabled" => true, "command" => nil}
      },
      "guards" => {
        "migrations" => {"enabled" => true},
        "schema" => {"enabled" => true}
      }
    }
  end

  describe "constants" do
    it "exposes the config path" do
      expect(described_class::PATH).to eq("config/agent_harness.yml")
    end

    it "exposes deeply frozen defaults matching the documented schema" do
      expect(described_class::DEFAULTS).to eq(expected_defaults)
      expect(described_class::DEFAULTS).to be_frozen
      expect(described_class::DEFAULTS["checks"]).to be_frozen
      expect(described_class::DEFAULTS["checks"]["rubocop"]).to be_frozen
      expect(described_class::DEFAULTS["guards"]["schema"]).to be_frozen
    end
  end

  describe ".load" do
    it "returns defaults when the file is missing" do
      config = described_class.load(root)

      expect(config.to_h).to eq(expected_defaults)
      expect(config.base_branch).to eq("main")
      expect(config.max_output_lines).to eq(40)
      expect(config.check_enabled?(:rubocop)).to be(true)
      expect(config.check_command(:tests)).to be_nil
      expect(config.guard_enabled?(:migrations)).to be(true)
    end

    it "returns defaults when the file is empty" do
      write_config("")

      expect(described_class.load(root).to_h).to eq(expected_defaults)
    end

    it "returns defaults when the file only has comments" do
      write_config("# nothing here\n")

      expect(described_class.load(root).to_h).to eq(expected_defaults)
    end

    it "defaults root to the current directory" do
      write_config("base_branch: develop\n")

      expect(Dir.chdir(root) { described_class.load.base_branch }).to eq("develop")
    end

    it "accepts a Pathname root" do
      write_config("base_branch: develop\n")

      expect(described_class.load(Pathname(root)).base_branch).to eq("develop")
    end

    it "deep-merges user values over the defaults" do
      write_config(<<~YAML)
        checks:
          brakeman:
            enabled: false
      YAML
      config = described_class.load(root)

      expect(config.check_enabled?(:brakeman)).to be(false)
      expect(config.check_enabled?(:rubocop)).to be(true)
      expect(config.check_enabled?(:tests)).to be(true)
      expect(config.check_command(:brakeman)).to be_nil
      expect(config.guard_enabled?(:schema)).to be(true)
      expect(config.base_branch).to eq("main")
      expect(config.to_h["checks"]["brakeman"]).to eq("enabled" => false, "command" => nil)
    end

    it "reads every documented setting" do
      write_config(<<~YAML)
        base_branch: develop
        max_output_lines: 10
        checks:
          rubocop:
            command: bin/rubocop
          tests:
            command: bin/rails test
        guards:
          migrations:
            enabled: false
          schema:
            enabled: false
      YAML
      config = described_class.load(root)

      expect(config.base_branch).to eq("develop")
      expect(config.max_output_lines).to eq(10)
      expect(config.check_command(:rubocop)).to eq("bin/rubocop")
      expect(config.check_command(:tests)).to eq("bin/rails test")
      expect(config.check_command("tests")).to eq("bin/rails test")
      expect(config.guard_enabled?(:migrations)).to be(false)
      expect(config.guard_enabled?(:schema)).to be(false)
    end

    it "treats empty sections and entries as absent" do
      write_config(<<~YAML)
        checks:
          rubocop:
        guards:
      YAML

      expect(described_class.load(root).to_h).to eq(expected_defaults)
    end

    it "does not evaluate ERB" do
      write_config(%(base_branch: "<%= 1 + 1 %>"\n))

      expect(described_class.load(root).base_branch).to eq("<%= 1 + 1 %>")
    end

    it "returns a copy from #to_h that does not affect the configuration" do
      config = described_class.load(root)
      config.to_h["checks"]["rubocop"]["enabled"] = false

      expect(config.check_enabled?(:rubocop)).to be(true)
      expect(described_class::DEFAULTS["checks"]["rubocop"]["enabled"]).to be(true)
    end

    it "isolates strings returned by #to_h from the configuration" do
      write_config(<<~YAML)
        base_branch: develop
        checks:
          tests:
            command: bin/rails test
      YAML
      config = described_class.load(root)
      copy = config.to_h
      copy["base_branch"].replace("changed")
      copy["checks"]["tests"]["command"] << " --fail-fast"

      expect(config.base_branch).to eq("develop")
      expect(config.check_command(:tests)).to eq("bin/rails test")
    end

    it "returns frozen values from the accessors" do
      write_config("base_branch: develop\nchecks:\n  tests:\n    command: bin/rails test\n")
      config = described_class.load(root)

      expect(config.base_branch).to be_frozen
      expect(config.check_command(:tests)).to be_frozen
      expect { config.base_branch << "x" }.to raise_error(FrozenError)
    end

    it "is only built through .load" do
      expect { described_class.new({}) }.to raise_error(NoMethodError)
    end

    context "with invalid files" do
      it "raises ConfigurationError with the path for invalid YAML" do
        path = write_config("checks: [unclosed\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}/)
      end

      it "raises ConfigurationError with the path for YAML aliases" do
        path = write_config(<<~YAML)
          base: &base
            enabled: false
          checks:
            rubocop: *base
        YAML

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}/)
      end

      it "raises ConfigurationError with the path for disallowed YAML types" do
        path = write_config("base_branch: !ruby/object:Object {}\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}/)
      end

      it "raises ConfigurationError with the path for a non-Hash top level" do
        path = write_config("- main\n- develop\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}.*mapping/)
      end

      it "raises ConfigurationError with the path for a scalar top level" do
        path = write_config("main\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}/)
      end

      it "raises ConfigurationError when a section is not a mapping" do
        path = write_config("checks: false\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}.*"checks"/)
      end

      {
        "base_branch: \"\"" => /"base_branch" must be a non-empty string, got ""/,
        "base_branch: 123" => /"base_branch" must be a non-empty string, got 123/,
        "base_branch:" => /"base_branch" must be a non-empty string, got nil/,
        "max_output_lines: lots" => /"max_output_lines" must be a positive integer, got "lots"/,
        "max_output_lines: 0" => /"max_output_lines" must be a positive integer, got 0/,
        "max_output_lines: -5" => /"max_output_lines" must be a positive integer, got -5/,
        "max_output_lines: 1.5" => /"max_output_lines" must be a positive integer, got 1.5/,
        "checks:\n  rubocop:\n    enabled: \"false\"" => /"checks.rubocop.enabled" must be true or false, got "false"/,
        "checks:\n  tests:\n    enabled:" => /"checks.tests.enabled" must be true or false, got nil/,
        "guards:\n  schema:\n    enabled: 1" => /"guards.schema.enabled" must be true or false, got 1/,
        "checks:\n  brakeman:\n    command: 123" => /"checks.brakeman.command" must be a string or null, got 123/,
        "checks:\n  tests:\n    command: [rspec]" => /"checks.tests.command" must be a string or null, got \["rspec"\]/
      }.each do |yaml, message|
        it "raises ConfigurationError with the key path for #{yaml.inspect}" do
          path = write_config("#{yaml}\n")

          expect { described_class.load(root) }
            .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}: #{message}/)
        end
      end

      it "raises ConfigurationError when a known entry is not a mapping" do
        path = write_config("guards:\n  schema: false\n")

        expect { described_class.load(root) }
          .to raise_error(RailsAgentHarness::ConfigurationError, /#{Regexp.escape(path)}.*"guards.schema"/)
      end
    end

    context "with unknown keys" do
      it "warns once per unknown key without raising" do
        write_config(<<~YAML)
          base_branch: develop
          colour: blue
          checks:
            foo:
              enabled: true
            rubocop:
              enabled: false
          guards:
            bar:
              enabled: false
        YAML
        config = nil

        expect { config = described_class.load(root) }.to output(<<~ERR).to_stderr
          agent_harness: unknown config key "colour" in config/agent_harness.yml
          agent_harness: unknown config key "checks.foo" in config/agent_harness.yml
          agent_harness: unknown config key "guards.bar" in config/agent_harness.yml
        ERR
        expect(config.base_branch).to eq("develop")
        expect(config.check_enabled?(:rubocop)).to be(false)
      end

      it "warns for unknown entries left empty" do
        write_config(<<~YAML)
          checks:
            rubcop:
          guards:
            migratons:
        YAML

        expect { described_class.load(root) }.to output(<<~ERR).to_stderr
          agent_harness: unknown config key "checks.rubcop" in config/agent_harness.yml
          agent_harness: unknown config key "guards.migratons" in config/agent_harness.yml
        ERR
      end

      it "warns for unknown keys inside a known entry" do
        write_config(<<~YAML)
          checks:
            rubocop:
              comand: bin/rubocop
          guards:
            schema:
              enabeld: false
        YAML
        config = nil

        expect { config = described_class.load(root) }.to output(<<~ERR).to_stderr
          agent_harness: unknown config key "checks.rubocop.comand" in config/agent_harness.yml
          agent_harness: unknown config key "guards.schema.enabeld" in config/agent_harness.yml
        ERR
        expect(config.check_command(:rubocop)).to be_nil
        expect(config.guard_enabled?(:schema)).to be(true)
      end

      it "drops unknown keys so #to_h only contains the documented schema" do
        write_config(<<~YAML)
          colour: blue
          checks:
            rubcop:
            foo:
              enabled: true
            rubocop:
              comand: bin/rubocop
              enabled: false
          guards:
            bar: 1
        YAML
        config = nil
        expect { config = described_class.load(root) }.to output.to_stderr

        expected = expected_defaults.merge(
          "checks" => expected_defaults["checks"].merge("rubocop" => {"enabled" => false, "command" => nil})
        )
        expect(config.to_h).to eq(expected)
      end

      it "warns about and drops non-string keys" do
        # Psych returns Integer/boolean keys for `1:` and YAML 1.1 booleans like `on:`.
        write_config("on: true\nchecks:\n  1:\n")
        config = nil

        expect { config = described_class.load(root) }.to output(<<~ERR).to_stderr
          agent_harness: unknown config key "true" in config/agent_harness.yml
          agent_harness: unknown config key "checks.1" in config/agent_harness.yml
        ERR
        expect(config.to_h).to eq(expected_defaults)
      end

      it "does not type-check unknown keys" do
        write_config("checks:\n  foo:\n    enabled: maybe\n")

        expect { described_class.load(root) }.to output(/checks\.foo/).to_stderr
      end

      it "does not warn for a valid file" do
        write_config("checks:\n  brakeman:\n    enabled: false\n")

        expect { described_class.load(root) }.not_to output.to_stderr
      end
    end
  end

  describe "querying unknown names" do
    let(:config) { described_class.load(root) }

    it "raises ArgumentError for an unknown check" do
      expect { config.check_enabled?(:nope) }.to raise_error(ArgumentError, /nope/)
      expect { config.check_command(:nope) }.to raise_error(ArgumentError, /nope/)
    end

    it "raises ArgumentError for an unknown guard" do
      expect { config.guard_enabled?(:nope) }.to raise_error(ArgumentError, /nope/)
    end

    it "raises ArgumentError for a check name used as a guard" do
      expect { config.guard_enabled?(:rubocop) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for an unknown key that only appears in the file" do
      write_config("checks:\n  foo:\n    enabled: true\n")
      config = nil
      expect { config = described_class.load(root) }.to output.to_stderr

      expect { config.check_enabled?(:foo) }.to raise_error(ArgumentError)
    end
  end
end
