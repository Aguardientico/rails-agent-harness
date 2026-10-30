# frozen_string_literal: true

require "json"

RSpec.describe "bin/agent-check" do
  # Plain RuboCop defaults (single-quoted strings), minus noise for a tiny app.
  def rubocop_config
    <<~YAML
      AllCops:
        NewCops: disable
        SuggestExtensions: false
      Style/Documentation:
        Enabled: false
    YAML
  end

  def post_model(string)
    <<~RUBY
      # frozen_string_literal: true

      class Post < ApplicationRecord
        has_many :comments

        def label
          #{string}
        end
      end
    RUBY
  end

  # Installs the harness in a dummy copy (with a RuboCop config so RuboCop is detected) and
  # commits it, so only the example's own edits count as changes.
  def with_installed_app
    with_dummy_app_copy do |app_root|
      File.write(File.join(app_root, ".rubocop.yml"), rubocop_config)
      output, status = run_in(app_root, "bin/rails g agent_harness:install")
      raise "install failed:\n#{output}" unless status.success?

      run_in(app_root, "git add -A && git -c user.email=test@example.com -c user.name=Test commit -q -m install")
      yield app_root
    end
  end

  it "reports a RuboCop offense in a changed file, then passes once it's fixed" do
    with_installed_app do |app_root|
      File.write(File.join(app_root, "app/models/post.rb"), post_model('"post"'))

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = run_in(app_root, "bin/agent-check --only rubocop")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(status.exitstatus).to eq(1), output
      expect(output).to include("agent-check: FAIL (rubocop) - 1 file checked", "[rubocop] FAIL 1 offense")
      expect(output).to match(%r{^  app/models/post\.rb:7:5: C: \[Correctable\] Style/StringLiterals})
      expect(output).not_to match(/\e\[/)
      expect(elapsed).to be < 30

      File.write(File.join(app_root, "app/models/post.rb"), post_model("'post'"))
      output, status = run_in(app_root, "bin/agent-check --only rubocop")

      expect(status.exitstatus).to eq(0), output
      expect(output).to start_with("agent-check: PASS (rubocop) - 1 file checked")
    end
  end

  it "runs as Claude Code hooks" do
    with_installed_app do |app_root|
      post = File.join(app_root, "app/models/post.rb")
      File.write(post, post_model('"post"'))
      payload = JSON.generate("tool_name" => "Write", "tool_input" => {"file_path" => post})

      stdout, stderr, status = Open3.capture3(
        {"BUNDLE_GEMFILE" => DummyAppHelper::GEMFILE, "CLAUDE_PROJECT_DIR" => app_root},
        "bin/agent-check", "hook", "post-tool-use", stdin_data: payload, chdir: app_root
      )
      expect(status.exitstatus).to eq(2), stderr
      expect(stderr).to include("app/models/post.rb:7:5: C:")
      expect(stdout).to be_empty

      stdout, stderr, status = Open3.capture3(
        {"BUNDLE_GEMFILE" => DummyAppHelper::GEMFILE, "CLAUDE_PROJECT_DIR" => app_root},
        "bin/agent-check", "hook", "stop", stdin_data: JSON.generate("stop_hook_active" => true), chdir: app_root
      )
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout + stderr).to be_empty
    end
  end

  it "fails on a Brakeman SQL injection warning" do
    with_installed_app do |app_root|
      # The dummy app has no lockfile or bin/brakeman, so Brakeman needs a configured command.
      config = File.read(File.join(app_root, "config/agent_harness.yml"))
      File.write(File.join(app_root, "config/agent_harness.yml"),
        config.sub("brakeman:\n    enabled: false\n    command: null", "brakeman:\n    enabled: true\n    command: bundle exec brakeman"))
      File.write(File.join(app_root, "app/controllers/posts_controller.rb"), <<~RUBY)
        # frozen_string_literal: true

        class PostsController < ApplicationController
          def index
            @posts = Post.where("title = '\#{params[:q]}'")
          end
        end
      RUBY
      File.write(File.join(app_root, "config/routes.rb"), <<~RUBY)
        # frozen_string_literal: true

        Rails.application.routes.draw do
          resources :posts, only: :index
        end
      RUBY

      output, status = run_in(app_root, "bin/agent-check --only brakeman")

      expect(status.exitstatus).to eq(1), output
      expect(output).to match(%r{app/controllers/posts_controller\.rb:5 \[(High|Medium)\] SQL Injection})
    end
  end
end
