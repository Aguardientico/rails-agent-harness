# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module DummyAppHelper
  GEM_ROOT = File.expand_path("../..", __dir__)
  DUMMY_APP = File.join(GEM_ROOT, "spec", "dummy")
  GEMFILE = File.join(GEM_ROOT, "Gemfile")
  EXCLUDED = %r{\A(log|tmp)(/|\z)|\.sqlite3}

  # Copies spec/dummy into a fresh tmp dir that is a git repo on branch `main`
  # with a single commit, yields its path, and removes it afterwards.
  def with_dummy_app_copy
    Dir.mktmpdir("agent_harness_dummy") do |dir|
      app_root = File.join(dir, "app")
      copy_dummy_app(app_root)
      git = "git -c user.email=test@example.com -c user.name=Test"
      ["git init -q -b main", "git add -A", "#{git} commit -q -m init"].each do |cmd|
        output, status = run_in(app_root, cmd)
        raise "#{cmd} failed:\n#{output}" unless status.success?
      end
      yield app_root
    end
  end

  def run_in(app_root, cmd, env: {})
    Open3.capture2e({"BUNDLE_GEMFILE" => GEMFILE}.merge(env), cmd, chdir: app_root)
  end

  private

  def copy_dummy_app(target)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: DUMMY_APP).sort.each do |relative|
      next if File.basename(relative) == "." || relative.match?(EXCLUDED)

      source = File.join(DUMMY_APP, relative)
      destination = File.join(target, relative)
      if File.directory?(source)
        FileUtils.mkdir_p(destination)
      else
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination, preserve: true)
      end
    end
  end
end
